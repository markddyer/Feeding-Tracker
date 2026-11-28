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
/// near again. Either way it carries the moment of the tap. The same tap may arrive twice (as a
/// message and as its kept transfer): the phone applies it only once (`WatchReceipts`).
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

    /// The "Last night" card the phone last sent (AI insights step 4). Kept in the watch app's own
    /// settings, never in the file the watch face reads (Y6).
    private(set) var card: WatchCard?
    /// Where page 4's check with the phone stands (step 4 D11 A, design D9 A).
    enum CardCheck: Equatable {
        /// Asking the phone: "Checking with iPhone…".
        case checking
        /// The phone said the card (or its facts) is current.
        case current
        /// No answer: "The card is on your iPhone".
        case unreachable
        /// The phone took the card back while the page showed: "No card today.", and the page goes
        /// the next time the app opens.
        case takenBack
    }
    private(set) var cardCheck: CardCheck = .checking
    private static let cardKey = "watch.lastNightCard"
    private static let revisionKey = "watch.lastNightRevision"
    /// The phone's number for the card kept here (`WatchKey.cardRevision`).
    private var cardRevision: Int64 = 0
    /// Each check's own number: only the newest check's timer and errors count.
    private var checkNumber = 0

    /// Page 4 shows: on days with a card the phone hasn't taken back, before the card's day ends.
    func showsLastNight(at now: Date) -> Bool {
        if cardCheck == .takenBack { return true }
        return card?.isCurrent(at: now) ?? false
    }

    /// Taps are waiting and the phone is out of reach.
    var waitingForPhone: Bool { (!saved.pending.isEmpty || !saved.actions.isEmpty) && !reachable }

    private init() {
        saved = WatchFile.load()
        saved.dropStale(now: Date())
        card = UserDefaults.standard.data(forKey: Self.cardKey).flatMap { WatchCoding.decode(WatchCard.self, from: $0) }
        cardRevision = (UserDefaults.standard.object(forKey: Self.revisionKey) as? NSNumber)?.int64Value ?? 0
    }

    /// True when the phone's word is newer than what is kept, or the same; false for an older one,
    /// which is ignored. With no number (never from a build that sends cards), it counts.
    private func takes(_ revision: Int64?) -> Bool {
        guard let revision else { return true }
        guard revision >= cardRevision else { return false }
        cardRevision = revision
        UserDefaults.standard.set(NSNumber(value: revision), forKey: Self.revisionKey)
        return true
    }

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// At launch, also when the system wakes the app to deliver the phone's news.
    func activate() {
        #if FEEDING_DEV
        if let sample = WatchSamples.fromLaunchArguments() {
            card = WatchSamples.lastNightCard()
            cardCheck = WatchSamples.lastNightCheck()
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

    /// Sends a tap to the phone and shows it at once. Any earlier tap the phone hasn't handled goes
    /// again first, in order, so a Finish can't overtake its Start (one kept as a transfer while
    /// the phone was out of reach, the next sent as a message). The phone applies each tap once.
    /// Returns the tap's ID, for the Logged card to follow the phone's answer.
    @discardableResult
    func send(_ command: WatchCommand, now: Date = Date()) -> String {
        let request = WatchRequest(command: command, at: now)
        change { $0.pending.append(request) }
        deliverWaiting()
        return request.id
    }

    /// Sends a new tap (`WatchAction`, `11-watch-parity.md` step 1), after `after` if it depends on
    /// one, and shows it at once. Only sent once the phone has said it understands it.
    @discardableResult
    func send(_ action: WatchAction, after: String? = nil, now: Date = Date()) -> String {
        let request = WatchActionRequest(action: action, at: now, after: after)
        change { $0.actions.append(request) }
        deliverWaiting()
        return request.id
    }

    /// Finish, or Finish again after an Undo of Finish the phone hasn't answered: sent after it, so
    /// they arrive in order (outside review of step 3). The watch's Finish button and Siri's Finish
    /// both send it this way (Codex review of doc 15, 3).
    @discardableResult
    func sendFinish(feedID: String, now: Date = Date()) -> String {
        if let undo = saved.actions.last(where: {
            if case .undoFinish(let id, _) = $0.action { return id == feedID }
            return false
        }) {
            return send(.refinish(feedID: feedID), after: undo.id, now: now)
        }
        return send(.finish(feedID: feedID), now: now)
    }

    /// The latest tap about this feed the phone hasn't answered yet. A feed extra names it
    /// (`after`), so the phone applies them in order: a side after its Finish, an amount after its
    /// bottle (step 2 of `11-watch-parity.md`).
    func unansweredTap(about feedID: String) -> String? {
        let first = saved.pending.filter { request in
            switch request.command {
            case .start(let id, _, _, _), .switchSide(let id, _), .finish(let id), .setAmount(let id, _, _), .discard(let id):
                id == feedID
            default:
                false
            }
        }.map { ($0.at, $0.id) }
        let new = saved.actions.filter { $0.entryID == feedID }.map { ($0.at, $0.id) }
        return (first + new).max { $0.0 < $1.0 }?.1
    }

    /// Sends a feed extra after the tap about the same feed that must come first. An amount waits
    /// for the tap that made its bottle, if the phone hasn't answered it, whichever queue it is in
    /// (outside review of step 2).
    @discardableResult
    func sendFeedExtra(_ action: WatchAction, feedID: String, now: Date = Date()) -> String {
        if case .amount(_, let bottleID, _) = action, let made = unansweredTap(making: bottleID) {
            return send(action, after: made, now: now)
        }
        return send(action, after: unansweredTap(about: feedID), now: now)
    }

    /// The unanswered tap that made this bottle: a bottle-only Start, or a bottle added here.
    private func unansweredTap(making bottleID: String) -> String? {
        if let start = saved.pending.last(where: {
            if case .start(_, let milk, let id, _) = $0.command { return milk != nil && id == bottleID }
            return false
        }) { return start.id }
        return saved.actions.last { request in
            if case .addBottle(_, let id, _, _) = request.action { return id == bottleID }
            return false
        }?.id
    }

    /// The phone's answer to a tap, once it has given one.
    func result(of id: String) -> WatchOutcome? {
        saved.phone?.result(of: id)
    }

    /// True while a tap is still on its way, or the phone asked for it again later.
    func isWaiting(_ id: String) -> Bool {
        saved.pending.contains { $0.id == id } || saved.actions.contains { $0.id == id }
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

    private func deliver(_ request: WatchActionRequest) {
        guard let session, session.activationState == .activated else { return }
        guard session.isReachable, let data = try? WatchCoding.encode(WatchMessage(request: nil, action: request)) else {
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

    private func transfer(_ request: WatchActionRequest) {
        guard let session, session.activationState == .activated,
              !queuedIDs(session).contains(request.id), let data = try? WatchCoding.encode(request) else { return }
        session.transferUserInfo([WatchKey.action: data])
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
                ?? (transfer.userInfo[WatchKey.action] as? Data).flatMap { WatchCoding.decode(WatchActionRequest.self, from: $0)?.id }
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
        // The new taps after the first kind, oldest first: one that depends on another names it,
        // and the phone holds it ("waiting") until that one is handled.
        for request in saved.actions where !queued.contains(request.id) || session.isReachable {
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
        var taken = false
        let medicines = saved.phone?.medicines?.map(\.name)
        change { taken = $0.receive(state, now: Date()) }
        guard taken else { return }
        // "Log Vitamin D in Little Log": Siri's phrases follow the household's list (doc 15).
        if state.medicines?.map(\.name) != medicines { WatchShortcuts.updateAppShortcutParameters() }
        // A tap the phone held ("waiting") for one it hadn't handled goes again once it has, so it
        // isn't left until the next tap or a change of reach (outside review of step 1, P2). The
        // phone stops saying "waiting" once it tries the tap, so this can't repeat.
        let ready = saved.actions.filter { action in
            guard let after = action.after, state.result(of: action.id) == .waiting,
                  let first = state.result(of: after) else { return false }
            return first != .waiting
        }
        for action in ready { deliver(action) }
    }

    fileprivate func activationDone() {
        guard let session else { return }
        reachable = session.isReachable
        if let data = session.receivedApplicationContext[WatchKey.state] as? Data,
           let state = WatchCoding.decode(WatchState.self, from: data) {
            receive(state)
            receiveCard(session.receivedApplicationContext[WatchKey.card] as? Data,
                        revision: (session.receivedApplicationContext[WatchKey.cardRevision] as? NSNumber)?.int64Value)
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

    // MARK: The "Last night" card (AI insights step 4)

    /// The card that came with the phone's state; none means the phone has none now.
    fileprivate func receiveCard(_ data: Data?, revision: Int64?) {
        guard takes(revision) else { return }
        let new = data.flatMap { WatchCoding.decode(WatchCard.self, from: $0) }
        guard new != card else { return }
        // A card taken back while page 4 shows: the page says so, and goes next time (design D9 A).
        if card != nil, new == nil, cardCheck == .current { cardCheck = .takenBack }
        keep(new)
    }

    private func keep(_ new: WatchCard?) {
        card = new
        if let new, let data = try? WatchCoding.encode(new) {
            UserDefaults.standard.set(data, forKey: Self.cardKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.cardKey)
        }
    }

    /// As page 4 opens: asks the phone whether the card is still current (step 4 D11 A). The card's
    /// words show only once the phone has said so; with no answer in about 2 seconds, "The card is
    /// on your iPhone".
    func checkCard() {
        #if FEEDING_DEV
        if WatchSamples.fromLaunchArguments() != nil { return }
        #endif
        if cardCheck == .takenBack { return }
        cardCheck = .checking
        checkNumber += 1
        let number = checkNumber
        guard let session, session.activationState == .activated, session.isReachable else {
            cardCheck = .unreachable
            return
        }
        session.sendMessage([WatchKey.cardCheck: true], replyHandler: { @Sendable reply in
            let data = reply[WatchKey.card] as? Data
            let revision = (reply[WatchKey.cardRevision] as? NSNumber)?.int64Value
            Task { @MainActor in self.cardAnswered(data, revision: revision) }
        }, errorHandler: { @Sendable _ in
            Task { @MainActor in if self.checkNumber == number, self.cardCheck == .checking { self.cardCheck = .unreachable } }
        })
        Task {
            try? await Task.sleep(for: .seconds(2))
            if checkNumber == number, cardCheck == .checking { cardCheck = .unreachable }
        }
    }

    private func cardAnswered(_ data: Data?, revision: Int64?) {
        // An answer after the 2 seconds still counts, unless the phone has said something newer
        // since (a card taken back in the context): it is the phone's word now.
        guard takes(revision) else { return }
        let new = data.flatMap { WatchCoding.decode(WatchCard.self, from: $0) }
        if new == nil, card != nil {
            cardCheck = .takenBack
            keep(nil)
        } else {
            keep(new)
            cardCheck = .current
        }
    }

    /// The app opened again: a card taken back is gone now.
    func appOpened() {
        #if FEEDING_DEV
        if WatchSamples.fromLaunchArguments() != nil { return }
        #endif
        if cardCheck == .takenBack { cardCheck = .checking }
    }

    /// Saves every change, for the next launch and the watch face, and reloads the watch face
    /// when what it shows has changed: the times, the feed running, or its side.
    private func change(_ body: (inout WatchSaved) -> Void) {
        let before = Self.faceFacts(saved.shown)
        var copy = saved
        body(&copy)
        copy.dropStale(now: Date())
        guard copy != saved else { return }
        saved = copy
        WatchFile.save(copy)
        if Self.faceFacts(copy.shown) != before {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// What the watch face pieces draw: the wide one shows the side being fed, which the times
    /// don't change with; the Sleep and Nappy pieces show the sleep and the last nappy.
    private static func faceFacts(_ state: WatchState?) -> FaceFacts {
        FaceFacts(glance: state?.glance, feedID: state?.running?.id, mine: state?.running?.mine, side: state?.running?.side,
                  sleep: state?.sleep, nappy: state?.lastNappy?.onFace)
    }

    private struct FaceFacts: Equatable {
        var glance: FeedGlance?
        var feedID: String?
        var mine: Bool?
        var side: BreastSide?
        var sleep: WatchSleep?
        var nappy: WatchNappy?
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
        // The "Last night" card comes beside the state, never in the watch face's transfer (Y6).
        let card = applicationContext[WatchKey.card] as? Data
        let revision = (applicationContext[WatchKey.cardRevision] as? NSNumber)?.int64Value
        Task { @MainActor in self.link?.receiveCard(card, revision: revision) }
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
