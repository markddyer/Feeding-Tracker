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

    init(store: HouseholdStore, sync: HouseholdSync, defaults: UserDefaults) {
        self.store = store
        self.sync = sync
        self.defaults = defaults
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
            await self?.run()
        }
    }

    func run() async {
        if isRunning {
            runAgain = true
            return
        }
        isRunning = true
        defer { isRunning = false }
        repeat {
            runAgain = false
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
            let desired = reconcile(events: store.data.allEvents, settings: state.settings, roster: roster,
                                    pendingChanges: state.pendingChanges, me: me, now: now)
            let events = store.data.allEvents
            let babies = Set(events.filter(\.isLiveFeed).map(\.babyID))
            let latest = Dictionary(uniqueKeysWithValues: babies.compactMap { baby in
                events.latestFeedStart(babyID: baby, now: now).map { (baby, $0) }
            })
            await scheduler.apply(desired, latestFeedStarts: latest, now: now, timeZone: state.settings.timeZone)
            alerts = desired
            lastRunAt = Date()
        } while runAgain
    }
}
