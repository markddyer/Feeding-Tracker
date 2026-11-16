import FeedingCore
import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// The watch's end of the link to its own iPhone (plan v1: WatchConnectivity, no sync of its
/// own). It keeps the phone's latest state and this watch's taps until the phone has handled them,
/// and shows each tap at once.
///
/// A tap goes as a message when the phone is in reach (the phone app is woken for it and replies
/// with its new state), and otherwise as a transfer that the system delivers when the phone is
/// near again. Either way it carries the moment of the tap, and sending it twice is harmless.
@MainActor
@Observable
final class PhoneLink {
    static let shared = PhoneLink()

    private(set) var saved: WatchSaved
    /// The phone can be reached now.
    private(set) var reachable = false
    @ObservationIgnored private let delegate = SessionDelegate()
    @ObservationIgnored private var activated = false

    /// What the watch shows.
    var shown: WatchState? { saved.shown }

    /// Taps are waiting and the phone is out of reach.
    var waitingForPhone: Bool { !saved.pending.isEmpty && !reachable }

    private init() {
        saved = WatchFile.load()
        saved.dropStale(now: Date())
    }

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// At launch, also when the system wakes the app to deliver the phone's news.
    func activate() {
        #if FEEDING_DEV
        if let sample = WatchSamples.fromLaunchArguments() {
            // "waiting": a tap that changes nothing on screen, held with the phone out of reach.
            let held = WatchSamples.showsWaiting ? [WatchRequest(command: .finish(feedID: "none"), at: Date())] : []
            saved = WatchSaved(phone: sample, pending: held)
            return
        }
        #endif
        guard !activated, let session else { return }
        activated = true
        delegate.link = self
        session.delegate = delegate
        session.activate()
    }

    // MARK: Taps

    /// Sends a tap to the phone and shows it at once.
    func send(_ command: WatchCommand, now: Date = Date()) {
        let request = WatchRequest(command: command, at: now)
        change { $0.pending.append(request) }
        deliver(request)
    }

    /// Remembers an amount saved here, so the crown starts there next time.
    func rememberAmount(_ ml: Int, milk: MilkKind) {
        change { $0.phone?.rememberAmount(ml, milk: milk) }
    }

    // WatchConnectivity calls the reply and error handlers on its own queue, so each is marked
    // @Sendable (not tied to the main actor) and hops to the main actor itself.
    private func deliver(_ request: WatchRequest) {
        guard let session, session.activationState == .activated else { return }
        guard session.isReachable, let data = try? WatchCoding.encode(WatchMessage(request: request)) else {
            transfer(request)
            return
        }
        session.sendMessageData(data, replyHandler: { @Sendable reply in
            let state = WatchCoding.decode(WatchState.self, from: reply)
            Task { @MainActor in if let state { self.receive(state) } }
        }, errorHandler: { @Sendable _ in
            Task { @MainActor in self.transfer(request) }
        })
    }

    /// Kept by the system until the phone is near.
    private func transfer(_ request: WatchRequest) {
        guard let session, session.activationState == .activated,
              !queuedIDs(session).contains(request.id), let data = try? WatchCoding.encode(request) else { return }
        session.transferUserInfo([WatchKey.request: data])
    }

    private func queuedIDs(_ session: WCSession) -> Set<String> {
        Set(session.outstandingUserInfoTransfers.compactMap { transfer in
            (transfer.userInfo[WatchKey.request] as? Data).flatMap { WatchCoding.decode(WatchRequest.self, from: $0)?.id }
        })
    }

    /// Sends again any tap the phone hasn't handled and the system isn't already carrying (after
    /// a restart, or when the phone comes back in reach).
    private func deliverWaiting() {
        guard let session, session.activationState == .activated else { return }
        let queued = queuedIDs(session)
        for request in saved.pending where !queued.contains(request.id) || session.isReachable {
            deliver(request)
        }
    }

    // MARK: News from the phone

    /// Asks the phone for its state, as the app opens.
    func refresh() {
        guard let session, session.activationState == .activated, session.isReachable,
              let data = try? WatchCoding.encode(WatchMessage(request: nil)) else { return }
        session.sendMessageData(data, replyHandler: { @Sendable reply in
            let state = WatchCoding.decode(WatchState.self, from: reply)
            Task { @MainActor in if let state { self.receive(state) } }
        }, errorHandler: nil)
    }

    fileprivate func receive(_ state: WatchState) {
        change { _ = $0.receive(state) }
    }

    fileprivate func activationDone() {
        guard let session else { return }
        reachable = session.isReachable
        if let data = session.receivedApplicationContext[WatchKey.state] as? Data,
           let state = WatchCoding.decode(WatchState.self, from: data) {
            receive(state)
        }
        deliverWaiting()
        refresh()
        #if FEEDING_DEV
        WatchSamples.runSendTest(self)
        #endif
    }

    fileprivate func reachabilityChanged() {
        guard let session else { return }
        reachable = session.isReachable
        if reachable {
            deliverWaiting()
            refresh()
        }
    }

    /// Saves every change, for the next launch and the watch face, and reloads the watch face
    /// when what it shows has changed.
    private func change(_ body: (inout WatchSaved) -> Void) {
        let before = saved.shown?.glance
        var copy = saved
        body(&copy)
        copy.dropStale(now: Date())
        guard copy != saved else { return }
        saved = copy
        WatchFile.save(copy)
        if copy.shown?.glance != before {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Keeps the app awake in the background until the system has handed over the phone's news.
    func finishBackgroundDelivery() async {
        activate()
        for _ in 0..<50 {
            guard let session, session.activationState != .activated || session.hasContentPending else { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}

/// WatchConnectivity calls these on its own queue; each hops to the main actor.
private final class SessionDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    /// Set once, before the session is activated.
    weak var link: PhoneLink?

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: (any Error)?) {
        Task { @MainActor in self.link?.activationDone() }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.link?.reachabilityChanged() }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext[WatchKey.state] as? Data)
    }

    /// The phone's instant update for the watch face.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(userInfo[WatchKey.state] as? Data)
    }

    private func deliver(_ data: Data?) {
        guard let data, let state = WatchCoding.decode(WatchState.self, from: data) else { return }
        Task { @MainActor in self.link?.receive(state) }
    }
}
