import FeedingCore
import Foundation
import UIKit
import WatchConnectivity

/// The phone's end of the watch app (plan v1, Phase 2; the user's choices of 16 Nov 2026). The
/// watch never syncs on its own: this sends it what it shows, and applies its taps here as the same
/// taps in the app would, so this phone's alarms, the other phone and the widgets all follow.
@MainActor
final class WatchRelay: NSObject {
    /// What the watch was last sent, without its time, so an unchanged state isn't sent again.
    private var sent: WatchState?
    /// What the watch face was last sent: it has a small daily allowance of instant updates.
    private var faceSent: FaceFacts?
    /// The "Last night" card last sent (AI insights step 4).
    private var sentCard: WatchCard?
    /// The card `cardRevision` names, once one has been given in this run.
    private var revisionCard: WatchCard??
    private static let revisionKey = "watch.lastNightRevision"

    /// The number for `card`: the same while the card is the same, higher for each change, and
    /// never lower than one given before (kept across launches; the clock in milliseconds when
    /// that is higher).
    private func revision(for card: WatchCard?) -> Int64 {
        let defaults = UserDefaults.standard
        var revision = (defaults.object(forKey: Self.revisionKey) as? NSNumber)?.int64Value ?? 0
        if revisionCard != .some(card) {
            revision = max(revision + 1, Int64(Date().timeIntervalSince1970 * 1000))
            defaults.set(NSNumber(value: revision), forKey: Self.revisionKey)
            revisionCard = .some(card)
        }
        return revision
    }
    /// Answers given again in this run, newest last: to a tap that arrived twice after its answer
    /// left the latest 30, and `waiting` for one that depends on a tap not handled yet (outside
    /// review of step 1, P2). Not kept: the watch sends such a tap again.
    private var extra: [WatchResult] = []

    /// The answers to the watch's taps (`HouseholdData.watchReceipts`). Until the first tap after
    /// the update, the list an earlier build kept outside the file.
    private func receipts(_ model: AppModel) -> WatchReceipts {
        let saved = model.store.data.watchReceipts
        guard saved.results.isEmpty, let earlier = Self.earlierReceipts() else { return saved }
        return earlier
    }

    private static func earlierReceipts() -> WatchReceipts? {
        let defaults = UserDefaults.standard
        guard let handled = defaults.stringArray(forKey: "watch.handled") else { return nil }
        let results = defaults.data(forKey: "watch.results").flatMap { WatchCoding.decode([WatchResult].self, from: $0) }
        return .earlier(handled: handled, results: results ?? [])
    }

    private func tell(_ id: String, _ outcome: WatchOutcome) {
        extra = Array((extra.filter { $0.id != id } + [WatchResult(id: id, outcome: outcome)]).suffix(WatchReceipts.told))
    }

    /// Applies a tap and notes its answer in the same checked save (outside review of step 1, P1).
    /// Not saved: no answer, so the watch keeps the tap and sends it again. Returns the answer.
    private func apply(_ id: String, _ model: AppModel, _ body: (inout HouseholdData) -> WatchOutcome) -> WatchOutcome? {
        extra.removeAll { $0.id == id }
        let earlier = Self.earlierReceipts()
        let (outcome, saved) = model.store.changeChecked { data -> WatchOutcome in
            if let earlier, data.watchReceipts.results.isEmpty { data.watchReceipts = earlier }
            let outcome = body(&data)
            data.watchReceipts.record(id, outcome, at: Date())
            return outcome
        }
        guard saved else {
            SyncLog.add("watch: a tap couldn't be saved on this phone; the watch will send it again")
            return nil
        }
        if earlier != nil {
            UserDefaults.standard.removeObject(forKey: "watch.handled")
            UserDefaults.standard.removeObject(forKey: "watch.results")
        }
        return outcome
    }

    /// Keeps the app awake while a tap's change is sent and its alarms are set.
    private func settleInBackground() {
        let application = UIApplication.shared
        let task = application.beginBackgroundTask(withName: "Watch tap")
        Task { @MainActor in
            await QuickFeedRunner.settle()
            application.endBackgroundTask(task)
        }
    }

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// At launch, also when the watch wakes the app in the background with a tap.
    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// The watch's state now.
    func state(of model: AppModel, now: Date = Date()) -> WatchState {
        guard let me = model.me else { return WatchState(madeAt: now, setUp: false) }
        let look = UserDefaults.standard.string(forKey: LookSetting.storageKey).flatMap(LookSetting.init(rawValue:))
        let told = receipts(model).told(extra)
        return model.store.data.watchState(me: me, names: model.memberNames, colours: model.memberColours.mapValues(\.rawValue),
                                           bottleOnly: QuickFeedRunner.isBottleOnly, lookSetting: look ?? .automatic,
                                           handled: told.handled, results: told.results, now: now)
    }

    /// Sends the watch its state, when something it shows has changed, and the "Last night" card
    /// beside it under its own key (AI insights step 4, Y6).
    func update(_ model: AppModel) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let state = state(of: model)
        let card = WatchCardMaker.card(model: model)
        guard sent != state.content || sentCard != card, let data = try? WatchCoding.encode(state) else { return }
        var context: [String: Any] = [WatchKey.state: data, WatchKey.cardRevision: NSNumber(value: revision(for: card))]
        if let card, let cardData = try? WatchCoding.encode(card) { context[WatchKey.card] = cardData }
        do {
            try session.updateApplicationContext(context)
            sent = state.content
            sentCard = card
        } catch {
            return
        }
        // A feed started or finished, the baby fell asleep or woke, or a nappy was logged: the
        // watch face hears at once, if Feeding is on it.
        let face = FaceFacts(glance: state.glance, sleep: state.sleep, nappy: state.lastNappy?.onFace)
        if face != faceSent, session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo([WatchKey.state: data])
            faceSent = face
        }
    }

    /// What the watch face pieces show: the feed times, the sleep and the last nappy.
    private struct FaceFacts: Equatable {
        var glance: FeedGlance?
        var sleep: WatchSleep?
        var nappy: WatchNappy?
    }

    /// Applies a tap from the watch, then sets the alarms and sends it to the other phone, as
    /// "Start feed" from the Lock Screen does. Returns the state for the watch at once; the
    /// sending carries on in the background.
    fileprivate func handle(_ request: WatchRequest?) -> WatchState {
        let model = AppModel.shared
        guard let request, let me = model.me, let baby = model.baby else { return state(of: model) }
        if let outcome = receipts(model).outcome(of: request.id) {
            // A tap seen before (the watch's kept copy, after the message) is never applied again:
            // a Start turned down while a feed ran would start a feed at the old tap. Its answer is
            // given again, as the watch may have missed it (P2).
            tell(request.id, outcome)
        } else {
            // One the system carried for longer than the watch keeps its own is turned down.
            let tooOld = Date().timeIntervalSince(request.at) > watchTapLifetime
            let outcome = apply(request.id, model) { data in
                tooOld ? .refused
                    : data.applyWatchRequest(request, babyID: baby.name, by: me, timeZoneID: TimeZone.current.identifier)
            }
            if outcome == .applied, case .finish(let id) = request.command, model.store.data.events[id]?.event.loggedBy == me {
                // The details panel opens on Home next time, as after Finish in the app. It closes
                // by itself once nothing is left to add (the watch may have saved the amount already).
                UserDefaults.standard.set(id, forKey: FeedControls.detailsKey)
            }
            if outcome == .applied { settleInBackground() }
        }
        // The watch hears the answer also when the tap came as a transfer, with no reply (P2).
        update(model)
        return state(of: model)
    }

    /// Applies a new tap from the watch (`WatchAction`, `11-watch-parity.md` step 1) and answers
    /// it. One that depends on a tap not handled yet waits: the watch sends it again.
    fileprivate func handle(_ request: WatchActionRequest) -> WatchState {
        let model = AppModel.shared
        guard let me = model.me, let baby = model.baby else { return state(of: model) }
        let receipts = receipts(model)
        if let outcome = receipts.outcome(of: request.id) {
            tell(request.id, outcome)
        } else if let after = request.after, receipts.outcome(of: after) == nil {
            tell(request.id, .waiting)
        } else {
            let outcome = apply(request.id, model) { data in
                data.applyWatchAction(request, babyID: baby.name, by: me, timeZoneID: TimeZone.current.identifier, now: Date())
            }
            if outcome == .applied { settleInBackground() }
        }
        update(model)
        return state(of: model)
    }

    fileprivate func sessionChanged() {
        sent = nil
        faceSent = nil
        sentCard = nil
        update(AppModel.shared)
    }

    /// The watch's check as page 4 opens (step 4 D11 A): the card as Home shows it now, or none.
    fileprivate func cardNow() -> [String: Any] {
        let card = WatchCardMaker.card(model: AppModel.shared)
        let revision = NSNumber(value: revision(for: card))
        guard let card, let data = try? WatchCoding.encode(card) else {
            return [WatchKey.cardCheck: "none", WatchKey.cardRevision: revision]
        }
        return [WatchKey.card: data, WatchKey.cardRevision: revision]
    }
}

/// WatchConnectivity calls these on its own queue; each hops to the main actor.
extension WatchRelay: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor in self.sessionChanged() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The parent switched to another watch: start again with the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The watch app was installed, or Feeding was added to the watch face.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sessionChanged() }
    }

    /// A tap, or the watch app asking for the state as it opens. The reply is the new state.
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data,
                             replyHandler: @escaping (Data) -> Void) {
        let reply = Reply(send: replyHandler)
        let message = WatchCoding.decode(WatchMessage.self, from: messageData)
        Task { @MainActor in
            let state = if let action = message?.action { self.handle(action) } else { self.handle(message?.request) }
            reply.send((try? WatchCoding.encode(state)) ?? Data())
        }
    }

    /// The watch asking whether the "Last night" card is still current (AI insights step 4, D11 A).
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = DictionaryReply(send: replyHandler)
        guard message[WatchKey.cardCheck] != nil else {
            reply.send([:])
            return
        }
        Task { @MainActor in reply.send(self.cardNow()) }
    }

    /// A tap kept while this phone was out of reach.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[WatchKey.action] as? Data, let action = WatchCoding.decode(WatchActionRequest.self, from: data) {
            Task { @MainActor in _ = self.handle(action) }
            return
        }
        guard let data = userInfo[WatchKey.request] as? Data,
              let request = WatchCoding.decode(WatchRequest.self, from: data) else { return }
        Task { @MainActor in _ = self.handle(request) }
    }
}

/// WatchConnectivity's reply handler, carried to the main actor. It may be called from any thread.
private struct Reply: @unchecked Sendable {
    let send: (Data) -> Void
}

private struct DictionaryReply: @unchecked Sendable {
    let send: ([String: Any]) -> Void
}
