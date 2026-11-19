import FeedingCore
import Foundation
import Observation
import UIKit

/// Runs `reconcile` and applies its output, at the moments plan v1 lists: launch, coming to the
/// foreground, any change to the data (from this phone or the other), and a clock or time zone
/// change. Only one run happens at a time; a request during a run starts one more after it.
@MainActor
@Observable
final class Reconciler {
    private(set) var lastRunAt: Date?
    /// The alerts from the last run, for the screens.
    private(set) var alerts: [DesiredAlert] = []

    private let store: HouseholdStore
    private let sync: HouseholdSync
    private let scheduler: AlertScheduler
    private let defaults: UserDefaults
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private var debounce: Task<Void, Never>?
    /// Callers waiting for the pass that starts after their call (a push, whose data must be in
    /// the alerts before the app sleeps again).
    @ObservationIgnored private var waitingForNextPass: [CheckedContinuation<Void, Never>] = []
    /// Called once a run is over and every alert is set, with the data the last pass planned them
    /// from: the notice of a new first from the other phone starts then, on its own (outside review
    /// O8). It is never awaited here, so nothing it does can hold up an alarm.
    @ObservationIgnored var onRunFinished: (@MainActor (HouseholdData) -> Void)?
    /// Sets the alerts: the scheduler, or a stand-in in tests.
    typealias ApplyAlerts = @MainActor (_ desired: [DesiredAlert], _ latestFeedStarts: [String: Date], _ now: Date,
                                        _ timeZone: TimeZone, _ keepExisting: Bool) async -> Void
    @ObservationIgnored private let applyAlerts: ApplyAlerts?

    init(store: HouseholdStore, sync: HouseholdSync, defaults: UserDefaults, applyAlerts: ApplyAlerts? = nil) {
        self.store = store
        self.sync = sync
        self.defaults = defaults
        self.applyAlerts = applyAlerts
        scheduler = AlertScheduler(defaults: defaults)
        store.onDataChange = { [weak self] in self?.runSoon() }
        for name in [UIApplication.significantTimeChangeNotification, Notification.Name.NSSystemTimeZoneDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runSoon() }
            }
        }
    }

    var lastError: String? { scheduler.lastError }
    var alarmsAllowed: Bool { scheduler.alarmsAllowed }

    /// This parent's own alert choices. Stored on this phone only.
    var preferences: MemberPreferences {
        get {
            defaults.data(forKey: "memberPreferences")
                .flatMap { try? JSONDecoder().decode(MemberPreferences.self, from: $0) } ?? MemberPreferences()
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "memberPreferences")
            runSoon()
        }
    }

    /// The app came to the foreground: this ends a lie-in (plan v1, "Morning").
    func appCameToForeground() {
        defaults.set(Date(), forKey: "lastForegroundAt")
        runSoon()
    }

    func requestPermissions() async {
        await scheduler.requestPermissions()
        runSoon()
    }

    /// Many changes can arrive at once from a fetch: run once, just after them.
    func runSoon() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            // Only the wait is cancelled by a later request, never a run under way (Codex review
            // of X1): the run goes in a task of its own.
            Task { [weak self] in await self?.run() }
        }
    }

    /// Runs `reconcile` and sets the alerts. A call during a run waits for the next pass, which
    /// starts after it, so the caller's data is in the alerts when it returns.
    func run() async {
        if isRunning {
            runAgain = true
            await withCheckedContinuation { waitingForNextPass.append($0) }
            return
        }
        isRunning = true
        var planned = store.data
        repeat {
            runAgain = false
            let waiters = waitingForNextPass
            waitingForNextPass = []
            let now = Date()
            if let me = sync.memberID, !store.data.pendingChanges.filter({ $0.madeBy != me }).isEmpty {
                // Tell the other phone this one has its changes ("seen by Parent B ✓").
                store.change { $0.acknowledgeChanges(by: me, now: now) }
            }
            var state = store.data.householdState
            if sync.memberID == nil {
                // This parent isn't known yet (no iCloud): alert as if on duty every night.
                state.rota = nil
                state.claims = []
            }
            let me = Me(id: sync.memberID ?? "this-phone", preferences: preferences,
                        lastForegroundAt: defaults.object(forKey: "lastForegroundAt") as? Date)
            let roster = state.roster(for: me.id)
            planned = store.data
            let desired = reconcile(events: planned.allEvents, settings: state.settings, roster: roster,
                                    pendingChanges: state.pendingChanges, me: me, now: now)
            let events = planned.allEvents
            let babies = Set(events.filter(\.isLiveFeed).map(\.babyID))
            let latest = Dictionary(uniqueKeysWithValues: babies.compactMap { baby in
                events.latestFeedStart(babyID: baby, now: now).map { (baby, $0) }
            })
            // While the file is being filled again from iCloud, no alert already set is cancelled
            // (CEO review D18). Otherwise the feeds the alerts come from are noted outside the
            // file, so after a lost file the wait ends only once those feeds are back.
            let waiting = store.data.isWaitingForICloud(now: now)
            if !waiting { defaults.plannedFeedStarts = latest }
            if let applyAlerts {
                await applyAlerts(desired, latest, now, state.settings.timeZone, waiting)
            } else {
                await scheduler.apply(desired, latestFeedStarts: latest, now: now, timeZone: state.settings.timeZone,
                                      keepExisting: waiting)
            }
            alerts = desired
            lastRunAt = Date()
            for waiter in waiters { waiter.resume() }
        } while runAgain
        isRunning = false
        onRunFinished?(planned)
    }
}

extension UserDefaults {
    /// Each baby's latest feed start that the alerts were last planned from. Kept here, outside
    /// the household file, so it outlives a file that is lost (`HouseholdData.hasFeedsBack`).
    /// Nil when never noted (a build from before 18 Nov 2026).
    var plannedFeedStarts: [String: Date]? {
        get { data(forKey: "plannedFeedStarts").flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } }
        set { set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "plannedFeedStarts") }
    }
}
