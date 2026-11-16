import Foundation

// The Apple Watch app (plan v1, Phase 2; the user's choices of 16 Nov 2026). The watch never
// syncs on its own: it talks to its own iPhone over WatchConnectivity (plan v1, "watchOS app";
// review round 2). The phone sends a `WatchState`; the watch sends `WatchRequest`s, which the
// phone applies to its household as a tap in the app would, so the alarms, the other phone and
// the widgets all follow.
//
// The watch picks the IDs of anything it creates (a feed, its bottle), so a tap kept while the
// phone was out of reach can still be finished and given an amount, and a request that arrives
// twice changes nothing the second time.

/// A feed running now, as the watch shows it.
public struct WatchFeed: Codable, Hashable, Sendable {
    public var id: String
    public var startedAt: Date
    /// Started by this watch's parent. Only they choose the sides while it runs.
    public var mine: Bool
    /// The parent who started it: "Sam". Not used when `mine`.
    public var byName: String
    /// Their colour's name ("teal"), for the label.
    public var byColour: String
    /// The side being fed now, if any.
    public var side: BreastSide?
    public var bottles: [Bottle]

    public init(id: String, startedAt: Date, mine: Bool, byName: String, byColour: String, side: BreastSide?,
                bottles: [Bottle]) {
        self.id = id
        self.startedAt = startedAt
        self.mine = mine
        self.byName = byName
        self.byColour = byColour
        self.side = side
        self.bottles = bottles
    }
}

/// Everything the watch shows, made by the phone.
public struct WatchState: Codable, Hashable, Sendable {
    /// Raised when a field the watch must understand is added.
    public static let currentVersion = 1
    public var version: Int
    /// When the phone made it.
    public var madeAt: Date
    /// False until the phone has a household and a baby: the watch then asks to set up the phone.
    public var setUp: Bool
    /// The start of the latest feed, running or not, and of the latest one before the feed running
    /// now (shown again if the running feed is discarded before the phone hears).
    public var lastFeedStart: Date?
    public var previousFeedStart: Date?
    public var window: FeedWindowSettings
    public var timeZoneID: String
    public var dayHours: DayHours
    public var lookSetting: LookSetting
    public var running: WatchFeed?
    /// This parent's "How you feed" is Bottle only: Formula and Expressed instead of Start feed.
    public var bottleOnly: Bool
    public var nextSide: BreastSide?
    /// Where the Digital Crown starts for each milk: the last bottle's amount.
    public var lastFormulaML: Int?
    public var lastExpressedML: Int?
    /// The milk of the latest bottle: the button a double tap presses on a bottle-only watch.
    public var lastMilk: MilkKind?
    /// This parent's colour's name, for a feed the watch starts before the phone replies.
    public var myColour: String
    /// The IDs of the watch's latest taps that the phone has applied (or found had nothing to
    /// change), newest last, so the watch stops showing them as waiting.
    public var handled: [String]

    public init(version: Int = WatchState.currentVersion, madeAt: Date, setUp: Bool, lastFeedStart: Date? = nil,
                previousFeedStart: Date? = nil, window: FeedWindowSettings = .init(), timeZoneID: String = "Europe/London",
                dayHours: DayHours = .standard, lookSetting: LookSetting = .automatic, running: WatchFeed? = nil,
                bottleOnly: Bool = false, nextSide: BreastSide? = nil, lastFormulaML: Int? = nil,
                lastExpressedML: Int? = nil, lastMilk: MilkKind? = nil, myColour: String = "sunflower",
                handled: [String] = []) {
        self.version = version
        self.madeAt = madeAt
        self.setUp = setUp
        self.lastFeedStart = lastFeedStart
        self.previousFeedStart = previousFeedStart
        self.window = window
        self.timeZoneID = timeZoneID
        self.dayHours = dayHours
        self.lookSetting = lookSetting
        self.running = running
        self.bottleOnly = bottleOnly
        self.nextSide = nextSide
        self.lastFormulaML = lastFormulaML
        self.lastExpressedML = lastExpressedML
        self.lastMilk = lastMilk
        self.myColour = myColour
        self.handled = handled
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
    }

    /// The feeding window from the last feed's start, as on the phone.
    public var feedWindow: FeedWindow? {
        lastFeedStart.map { FeedWindow(lastFeedStart: $0, settings: window) }
    }

    /// The same facts as the Lock Screen widget, for the watch face.
    public var glance: FeedGlance? {
        guard setUp else { return nil }
        let window = feedWindow
        return FeedGlance(lastFeedStart: lastFeedStart, runningSince: running?.startedAt, windowOpens: window?.opensAt,
                          windowCloses: window?.closesAt, timeZoneID: timeZoneID)
    }

    /// The look on the watch at `now`. The watch has no Dark Mode of its own, so "Match iPhone"
    /// follows the household's hours, as Automatic does.
    public func look(at now: Date) -> Look {
        let setting: LookSetting = lookSetting == .matchPhone ? .automatic : lookSetting
        return setting.resolve(dayHours: dayHours, timeZone: timeZone, phoneIsDark: false, now: now).look
    }

    /// Where the Digital Crown starts for a bottle of `milk`.
    public func startAmount(for milk: MilkKind) -> Int? {
        switch milk {
        case .formula: lastFormulaML ?? lastExpressedML
        case .expressed: lastExpressedML ?? lastFormulaML
        }
    }

    /// The same state, ignoring when it was made: the phone sends a new one only when this differs.
    public var content: WatchState {
        var copy = self
        copy.madeAt = .distantPast
        return copy
    }
}

/// What a tap on the watch face's Start feed does.
public enum WatchFaceStart: Hashable, Sendable {
    /// The watch hasn't heard from a set-up phone: it shows why.
    case notReady
    /// A feed is running: the watch shows it, and starts nothing.
    case showRunning
    /// A bottle-only watch asks "Formula or expressed?", then starts the feed from the tap.
    case askMilk
    /// Starts a feed at once, with nothing chosen, as Start feed in the app does.
    case startNow

    /// How long the question waits for an answer. Unanswered, it goes and no feed is logged: a
    /// feed nobody confirmed would move the alarms later.
    public static let questionLifetime: TimeInterval = 10 * 60
}

/// What a tap on the watch asks the phone to do.
public enum WatchCommand: Codable, Hashable, Sendable {
    /// Start feed, with the bottle on a bottle-only watch. The watch picks both IDs.
    case start(feedID: String, bottle: MilkKind?, bottleID: String)
    case switchSide(feedID: String, side: BreastSide)
    /// Finish, or "Finish for Sam".
    case finish(feedID: String)
    /// The amount from the Digital Crown, after Finish.
    case setAmount(feedID: String, bottleID: String, ml: Int)
    /// "Stop · discard": removes a feed started by mistake.
    case discard(feedID: String)
}

/// A tap, with when it was made: a request kept while the phone was out of reach still starts
/// or finishes the feed at the moment of the tap.
public struct WatchRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var command: WatchCommand
    public var at: Date

    public init(id: String = UUID().uuidString, command: WatchCommand, at: Date) {
        self.id = id
        self.command = command
        self.at = at
    }
}

/// A message from the watch: a tap, or no tap to ask for the state (when the watch app opens).
/// The phone replies with its state.
public struct WatchMessage: Codable, Hashable, Sendable {
    public var request: WatchRequest?

    public init(request: WatchRequest?) {
        self.request = request
    }
}

/// What the watch keeps, on the watch: the phone's latest state, and the taps the phone hasn't
/// applied yet. The watch app saves it for the watch face too.
public struct WatchSaved: Codable, Hashable, Sendable {
    public var phone: WatchState?
    public var pending: [WatchRequest]

    public init(phone: WatchState? = nil, pending: [WatchRequest] = []) {
        self.phone = phone
        self.pending = pending
    }

    /// What the watch shows: the phone's state with the waiting taps on top.
    public var shown: WatchState? {
        pending.reduce(phone) { state, request in state?.applying(request) }
    }

    /// Takes a state from the phone, unless it is older than the one already held (messages can
    /// arrive out of order), and stops holding the taps the phone has handled. Returns false when
    /// the state was older.
    public mutating func receive(_ state: WatchState) -> Bool {
        if let phone, state.madeAt < phone.madeAt { return false }
        phone = state
        pending.removeAll { state.handled.contains($0.id) }
        return true
    }

    /// Forgets taps more than a day old that never reached the phone: the phone would drop them
    /// anyway, as newer feeds have been logged since.
    public mutating func dropStale(now: Date) {
        pending.removeAll { now.timeIntervalSince($0.at) > 24 * 3600 }
    }
}

/// The keys in WatchConnectivity's dictionaries.
public enum WatchKey {
    /// A `WatchState`, in the application context or a watch face transfer.
    public static let state = "state"
    /// A `WatchRequest`, in a transfer kept while the phone was out of reach.
    public static let request = "request"
}

/// What travels between the phone and the watch, as JSON.
public enum WatchCoding {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }
}

// MARK: - On the phone

extension HouseholdData {
    /// The watch's state. `names` and `colours` are by member; `colours` holds colour names.
    public func watchState(me: MemberID, names: [MemberID: String], colours: [MemberID: String], bottleOnly: Bool,
                           lookSetting: LookSetting, handled: [String] = [], now: Date) -> WatchState {
        let settings = householdSettings
        var state = WatchState(madeAt: now, setUp: false, window: settings.window, timeZoneID: settings.timeZoneID,
                               dayHours: settings.dayHours, lookSetting: lookSetting, bottleOnly: bottleOnly,
                               myColour: colours[me] ?? "sunflower", handled: handled)
        guard let babyID = currentBaby?.name else { return state }
        state.setUp = true
        let feeds = allEvents.filter { $0.isLiveFeed && $0.babyID == babyID }
        state.lastFeedStart = feeds.latestFeedStart(babyID: babyID, now: now)
        if let running = feedInProgress(babyID: babyID) {
            state.previousFeedStart = feeds.filter { $0.id != running.id }.latestFeedStart(babyID: babyID, now: now)
            let details = running.payload?.feed ?? FeedDetails()
            let by = running.event.loggedBy
            state.running = WatchFeed(id: running.id, startedAt: running.event.startedAt, mine: by == me,
                                      byName: names[by] ?? "Other parent", byColour: colours[by] ?? "teal",
                                      side: details.breast.last.flatMap { $0.durationSeconds == nil ? $0.side : nil },
                                      bottles: details.bottles)
        } else {
            state.previousFeedStart = state.lastFeedStart
        }
        let visible = visibleSnapshots(babyID: babyID)
        state.nextSide = suggestedNextSide(visible, babyID: babyID, now: now)
        state.lastFormulaML = lastBottleAmount(visible, babyID: babyID, milk: .formula)
        state.lastExpressedML = lastBottleAmount(visible, babyID: babyID, milk: .expressed)
        state.lastMilk = visible.filter { $0.event.isLiveFeed && $0.event.babyID == babyID }
            .sorted { ($0.event.startedAt, $0.event.id) > ($1.event.startedAt, $1.event.id) }
            .lazy.compactMap { $0.payload?.feed?.bottles.last?.milk }.first
        return state
    }

    /// Applies a tap from the watch, as the same tap in the app would, and sends it at once (there
    /// is no Undo bar on the watch). Returns false when it changes nothing: a request seen before,
    /// a feed that has already finished, or a start while a feed runs.
    @discardableResult
    public mutating func applyWatch(_ request: WatchRequest, babyID: String, by me: MemberID, timeZoneID: String) -> Bool {
        let at = request.at
        let changed: Bool
        let id: String
        switch request.command {
        case .start(let feedID, let bottle, let bottleID):
            id = feedID
            guard events[feedID] == nil, feedInProgress(babyID: babyID) == nil else { return false }
            // A start kept while the phone was out of reach, from before a feed logged since:
            // starting it now would show a feed running for hours.
            let later = allEvents.contains { $0.isLiveFeed && $0.babyID == babyID && $0.startedAt > at }
            guard !later else { return false }
            add(id: feedID, kind: .feed, babyID: babyID, startedAt: at,
                payload: EventPayload(feed: FeedDetails(bottles: bottle.map { [Bottle(id: bottleID, milk: $0)] } ?? [])),
                by: me, timeZoneID: timeZoneID, now: at)
            changed = true
        case .switchSide(let feedID, let side):
            id = feedID
            guard let feed = runningFeed(feedID), feed.event.loggedBy == me else { return false }
            let current = feed.payload?.feed?.breast.last.flatMap { $0.durationSeconds == nil ? $0.side : nil }
            guard current != side else { return false }
            changed = switchSide(feedID, to: side, by: me, now: max(at, feed.event.startedAt))
        case .finish(let feedID):
            id = feedID
            guard let feed = runningFeed(feedID) else { return false }
            changed = finishFeed(feedID, by: me, now: max(at, feed.event.startedAt))
        case .setAmount(let feedID, let bottleID, let ml):
            id = feedID
            guard let feed = events[feedID]?.snapshot, feed.event.deletedAt == nil,
                  feed.payload?.feed?.bottles.contains(where: { $0.id == bottleID && $0.ml != ml }) == true
            else { return false }
            changed = edit(feedID, by: me, now: at) { snapshot in
                var details = snapshot.payload?.feed ?? FeedDetails()
                if let index = details.bottles.firstIndex(where: { $0.id == bottleID }) { details.bottles[index].ml = ml }
                snapshot.payload?.feed = details
            }
        case .discard(let feedID):
            id = feedID
            guard let feed = events[feedID]?.snapshot, feed.event.deletedAt == nil, feed.event.loggedBy == me
            else { return false }
            changed = delete(feedID, by: me, now: max(at, feed.event.startedAt))
        }
        if changed { events[id]?.uploadNotBefore = nil }
        return changed
    }

    /// A feed that is still running and not removed.
    private func runningFeed(_ id: String) -> EventSnapshot? {
        guard let feed = events[id]?.snapshot, feed.event.isLiveFeed, feed.event.endedAt == nil else { return nil }
        return feed
    }
}

// MARK: - On the watch

extension WatchState {
    /// The state as it will be once the phone has applied `request`, so the watch shows the tap at
    /// once, and still shows it when an older state arrives from the phone before the request.
    public func applying(_ request: WatchRequest) -> WatchState {
        var state = self
        switch request.command {
        case .start(let feedID, let bottle, let bottleID):
            guard state.setUp, state.running == nil else { break }
            state.previousFeedStart = state.lastFeedStart
            state.running = WatchFeed(id: feedID, startedAt: request.at, mine: true, byName: "", byColour: myColour,
                                      side: nil, bottles: bottle.map { [Bottle(id: bottleID, milk: $0)] } ?? [])
            state.lastFeedStart = max(request.at, state.lastFeedStart ?? request.at)
            if let bottle { state.lastMilk = bottle }
        case .switchSide(let feedID, let side):
            guard state.running?.id == feedID, state.running?.mine == true else { break }
            state.running?.side = side
            state.nextSide = side.other
        case .finish(let feedID):
            guard state.running?.id == feedID else { break }
            if let side = state.running?.side { state.nextSide = side.other }
            state.running = nil
            state.previousFeedStart = state.lastFeedStart
        case .setAmount:
            // Nothing on the watch's screens changes. The screen that asked remembers the amount
            // for the crown next time (`rememberAmount`).
            break
        case .discard(let feedID):
            guard state.running?.id == feedID else { break }
            state.running = nil
            state.lastFeedStart = state.previousFeedStart
        }
        return state
    }

    /// What a tap on the watch face's Start feed does (the user's choice of 16 Nov 2026): the same
    /// as Start feed in the app. A bottle-only watch asks "Formula or expressed?" first; the feed
    /// then starts from the moment of the tap.
    public var faceStart: WatchFaceStart {
        guard setUp else { return .notReady }
        if running != nil { return .showRunning }
        return bottleOnly ? .askMilk : .startNow
    }

    /// Remembers an amount the watch saved, so the crown starts there next time.
    public mutating func rememberAmount(_ ml: Int, milk: MilkKind) {
        switch milk {
        case .formula: lastFormulaML = ml
        case .expressed: lastExpressedML = ml
        }
        lastMilk = milk
    }
}
