import FeedingCore
import Foundation

/// Runs "Start feed" and "Finish feed" from outside the app (`FeedIntents.swift`), in the app's
/// process, often just woken in the background. It makes the change as a tap in the app does,
/// then sets this phone's alarms and sends the change before the app goes back to sleep.
@MainActor
enum QuickFeedRunner {
    static func start(now: Date = Date()) async -> String {
        let model = AppModel.shared
        guard let me = model.me, let baby = model.baby else { return GlanceText.notSetUp }
        let result = model.store.change {
            $0.quickStartFeed(babyID: baby.name, by: me, timeZoneID: TimeZone.current.identifier, now: now)
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

    private static func said(_ result: QuickFeedResult, me: MemberID, now: Date) -> String {
        let model = AppModel.shared
        return GlanceText.said(result, me: me, names: model.memberNames,
                               timeZoneID: model.store.data.householdSettings.timeZoneID, now: now)
    }

    /// Sets this phone's alarms, then sends the change, waiting a few seconds at most, so the
    /// other phone hears about it before this app goes back to sleep. If the send can't finish,
    /// it goes the next time the app runs; the alarms are already set.
    private static func settle() async {
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
