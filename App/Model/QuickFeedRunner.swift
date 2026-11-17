import FeedingCore
import Foundation

/// Runs "Start feed" and "Finish feed" from outside the app (`FeedIntents.swift`), in the app's
/// process, often just woken in the background. It makes the change as a tap in the app does,
/// then sets this phone's alarms and sends the change before the app goes back to sleep.
@MainActor
enum QuickFeedRunner {
    /// This phone's "How you feed" is Bottle only: Start feed then names a bottle.
    nonisolated static var isBottleOnly: Bool {
        UserDefaults.standard.string(forKey: FeedingStyle.storageKey) == FeedingStyle.bottleOnly.rawValue
    }

    static func start(bottle: MilkKind?, now: Date = Date()) async -> String {
        let model = AppModel.shared
        guard let me = model.me, let baby = model.baby else { return GlanceText.notSetUp }
        let result = model.store.change {
            $0.quickStartFeed(babyID: baby.name, bottle: bottle, by: me, timeZoneID: TimeZone.current.identifier, now: now)
        }
        await settle()
        return said(result, me: me, now: now)
    }

    static func finish(now: Date = Date()) async -> String {
        let model = AppModel.shared
        guard let me = model.me, let baby = model.baby else { return GlanceText.notSetUp }
        var result = model.store.change { $0.quickFinishFeed(babyID: baby.name, by: me, now: now) }
        if result == .nothingRunning {
            // The other parent may have started one this phone hasn't heard about yet.
            await waitAtMost(seconds: 3) { await model.sync.fetchNow() }
            result = model.store.change { $0.quickFinishFeed(babyID: baby.name, by: me, now: Date()) }
        }
        if case .finished(let feed) = result, feed.event.loggedBy == me {
            // The details panel opens on Home next time, as after Finish in the app.
            UserDefaults.standard.set(feed.id, forKey: FeedControls.detailsKey)
        }
        await settle()
        return said(result, me: me, now: now)
    }

    // MARK: Sleep, nappies and medicine (`CareIntents.swift`)

    static func fellAsleep(now: Date = Date()) async -> String {
        await care { data, me, baby in
            data.quickFellAsleep(babyID: baby, by: me, timeZoneID: TimeZone.current.identifier, now: now)
        }
    }

    static func wokeUp(now: Date = Date()) async -> String {
        let model = AppModel.shared
        guard let me = model.me, let baby = model.baby else { return GlanceText.notSetUp }
        var result = model.store.change { $0.quickWokeUp(babyID: baby.name, by: me, now: now) }
        if result == .notAsleep {
            // The other parent may have logged a sleep this phone hasn't heard about yet.
            await waitAtMost(seconds: 3) { await model.sync.fetchNow() }
            result = model.store.change { $0.quickWokeUp(babyID: baby.name, by: me, now: Date()) }
        }
        await settle()
        return GlanceText.said(result, timeZoneID: model.store.data.householdSettings.timeZoneID)
    }

    static func nappy(wee: Bool, poo: Bool, now: Date = Date()) async -> String {
        await care { data, me, baby in
            data.quickNappy(babyID: baby, wee: wee, poo: poo, by: me, timeZoneID: TimeZone.current.identifier, now: now)
        }
    }

    static func medicine(_ name: String, now: Date = Date()) async -> String {
        await care { data, me, baby in
            data.quickMedicine(babyID: baby, name: name, by: me, timeZoneID: TimeZone.current.identifier, now: now)
        }
    }

    /// Makes a sleep, nappy or medicine change as a tap in the app does, then saves and sends it
    /// the same way as a feed (`settle`). These never move a feed alarm: `reconcile` counts feeds
    /// only.
    private static func care(_ body: (inout HouseholdData, MemberID, String) -> QuickCareResult) async -> String {
        let model = AppModel.shared
        guard let me = model.me, let baby = model.baby else { return GlanceText.notSetUp }
        let result = model.store.change { body(&$0, me, baby.name) }
        await settle()
        return GlanceText.said(result, timeZoneID: model.store.data.householdSettings.timeZoneID)
    }

    private static func said(_ result: QuickFeedResult, me: MemberID, now: Date) -> String {
        let model = AppModel.shared
        return GlanceText.said(result, me: me, names: model.memberNames,
                               timeZoneID: model.store.data.householdSettings.timeZoneID, now: now)
    }

    /// Sets this phone's alarms, then sends the change, waiting a few seconds at most, so the
    /// other phone hears about it before this app goes back to sleep. If the send can't finish,
    /// it goes the next time the app runs; the alarms are already set. Also used for the watch's
    /// taps (`WatchRelay`).
    static func settle() async {
        let model = AppModel.shared
        await model.reconciler.run()
        model.sync.scheduleUploads()
        await waitAtMost(seconds: 8) { await model.sync.sendNow() }
    }

    /// Runs `work`, but returns after `seconds` even if it hasn't finished (it then carries on).
    private static func waitAtMost(seconds: Double, _ work: @escaping @MainActor () async -> Void) async {
        let gate = Gate()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gate.continuation = continuation
            Task { @MainActor in
                await work()
                gate.open()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                gate.open()
            }
        }
    }

    /// Resumes the waiting call once, whichever finishes first.
    @MainActor
    private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?

        func open() {
            continuation?.resume()
            continuation = nil
        }
    }
}
