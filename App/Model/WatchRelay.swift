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
    /// The watch's taps handled here, newest last: none is applied twice, and the watch stops
    /// showing them as waiting. Kept, as the app may be woken for each tap separately.
    private var handled: WatchTapLog {
        get { WatchTapLog(ids: UserDefaults.standard.stringArray(forKey: "watch.handled") ?? []) }
        set { UserDefaults.standard.set(newValue.ids, forKey: "watch.handled") }
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
        return model.store.data.watchState(me: me, names: model.memberNames, colours: model.memberColours.mapValues(\.rawValue),
                                           bottleOnly: QuickFeedRunner.isBottleOnly, lookSetting: look ?? .automatic,
                                           handled: handled.latest, now: now)
    }

    /// Sends the watch its state, when something it shows has changed.
    func update(_ model: AppModel) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let state = state(of: model)
        guard sent != state.content, let data = try? WatchCoding.encode(state) else { return }
        do {
            try session.updateApplicationContext([WatchKey.state: data])
            sent = state.content
        } catch {
            return
        }
        // A feed started or finished, the baby fell asleep or woke, or a nappy was logged: the
        // watch face hears at once, if Feeding is on it.
        let face = FaceFacts(glance: state.glance, sleep: state.sleep, nappy: state.lastNappy)
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
        // A tap seen before (the watch's kept copy, after the message) is never applied again: a
        // Start turned down while a feed ran would start a feed at the old tap.
        var log = handled
        guard log.firstSight(of: request.id) else {
            update(model)
            return state(of: model)
        }
        handled = log
        let changed = model.store.change {
            $0.applyWatch(request, babyID: baby.name, by: me, timeZoneID: TimeZone.current.identifier)
        }
        // Nothing changed (a feed already finished, or a start while a feed runs): the watch still
        // needs to hear that the tap was handled.
        if !changed { update(model) }
        if changed, case .finish(let id) = request.command, model.store.data.events[id]?.event.loggedBy == me {
            // The details panel opens on Home next time, as after Finish in the app. It closes by
            // itself once nothing is left to add (the watch may have saved the amount already).
            UserDefaults.standard.set(id, forKey: FeedControls.detailsKey)
        }
        if changed {
            let application = UIApplication.shared
            let task = application.beginBackgroundTask(withName: "Watch tap")
            Task { @MainActor in
                await QuickFeedRunner.settle()
                application.endBackgroundTask(task)
            }
        }
        return state(of: model)
    }

    fileprivate func sessionChanged() {
        sent = nil
        faceSent = nil
        update(AppModel.shared)
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
        let request = WatchCoding.decode(WatchMessage.self, from: messageData)?.request
        Task { @MainActor in
            let state = self.handle(request)
            reply.send((try? WatchCoding.encode(state)) ?? Data())
        }
    }

    /// A tap kept while this phone was out of reach.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchKey.request] as? Data,
              let request = WatchCoding.decode(WatchRequest.self, from: data) else { return }
        Task { @MainActor in _ = self.handle(request) }
    }
}

/// WatchConnectivity's reply handler, carried to the main actor. It may be called from any thread.
private struct Reply: @unchecked Sendable {
    let send: (Data) -> Void
}
