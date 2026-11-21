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
    /// A breastfeed: it has a side, or counts for the parent who breastfeeds with no bottle. A
    /// bottle-only watch then shows Left and Right too (design DD15, Codex 7). Nil from an older
    /// phone: no.
    public var breastfeed: Bool?

    public init(id: String, startedAt: Date, mine: Bool, byName: String, byColour: String, side: BreastSide?,
                bottles: [Bottle], breastfeed: Bool? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.mine = mine
        self.byName = byName
        self.byColour = byColour
        self.side = side
        self.bottles = bottles
        self.breastfeed = breastfeed
    }
}

/// The baby's latest sleep, as the watch shows it (`06-more-than-feeds.md`, pick I): the one
/// running, or the one that ended last.
public struct WatchSleep: Codable, Hashable, Sendable {
    public var id: String
    public var start: Date
    /// Nil while asleep.
    public var end: Date?

    public init(id: String, start: Date, end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }

    public var asleep: Bool { end == nil }
    /// Asleep since the start, or awake since the end.
    public var since: Date { end ?? start }
}

/// The last nappy change, as the watch shows it.
public struct WatchNappy: Codable, Hashable, Sendable {
    public var id: String
    public var at: Date
    public var wee: Bool
    public var poo: Bool

    public init(id: String, at: Date, wee: Bool, poo: Bool) {
        self.id = id
        self.at = at
        self.wee = wee
        self.poo = poo
    }
}

/// Everything the watch shows, made by the phone.
public struct WatchState: Codable, Hashable, Sendable {
    /// Raised when a field the watch must understand is added. 2 (17 Nov 2026): the sleep and the
    /// last nappy. Both are optional, so a state from either version still reads.
    public static let currentVersion = 2
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
    /// The latest sleep, running or ended. Nil before the first sleep is logged.
    public var sleep: WatchSleep?
    /// The last nappy change. Nil before the first.
    public var lastNappy: WatchNappy?
    /// On a bottle-only watch, the other parent named in "Who breastfeeds?" (design DD15, 4B):
    /// Start feed then offers "Breastfeed (Sam)", sent with their ID. Nil otherwise, and from an
    /// older phone.
    public var breastfeeder: MemberID?
    public var breastfeederName: String?

    public init(version: Int = WatchState.currentVersion, madeAt: Date, setUp: Bool, lastFeedStart: Date? = nil,
                previousFeedStart: Date? = nil, window: FeedWindowSettings = .init(), timeZoneID: String = "Europe/London",
                dayHours: DayHours = .standard, lookSetting: LookSetting = .automatic, running: WatchFeed? = nil,
                bottleOnly: Bool = false, nextSide: BreastSide? = nil, lastFormulaML: Int? = nil,
                lastExpressedML: Int? = nil, lastMilk: MilkKind? = nil, myColour: String = "sunflower",
                handled: [String] = [], sleep: WatchSleep? = nil, lastNappy: WatchNappy? = nil,
                breastfeeder: MemberID? = nil, breastfeederName: String? = nil) {
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
        self.sleep = sleep
        self.lastNappy = lastNappy
        self.breastfeeder = breastfeeder
        self.breastfeederName = breastfeederName
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
/// The watch face's Start feed piece (the user's choices of 16 Nov 2026). With no feed running it
/// is Start feed. While this parent's feed runs it shows a stopwatch and the feed's timer, and a
/// tap finishes the feed, then the watch asks for each bottle's amount. While the other parent's
/// feed runs it shows their timer, and a tap only opens the app on "Finish for Sam", so ending
/// their feed takes a second, deliberate tap.
public enum WatchFaceButton: Hashable, Sendable {
    case notReady
    case start
    case finish(feedID: String, since: Date)
    case others(feedID: String, since: Date, name: String)
}

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
    /// Start feed, with the bottle on a bottle-only watch. The watch picks both IDs. `doneBy`:
    /// "Breastfeed (Sam)" on a bottle-only watch, a breastfeed saved as Sam's at once (4B); an
    /// older phone ignores it and starts a feed with nothing chosen.
    case start(feedID: String, bottle: MilkKind?, bottleID: String, doneBy: MemberID? = nil)
    case switchSide(feedID: String, side: BreastSide)
    /// Finish, or "Finish for Sam".
    case finish(feedID: String)
    /// The amount from the Digital Crown, after Finish.
    case setAmount(feedID: String, bottleID: String, ml: Int)
    /// "Stop · discard": removes a feed started by mistake.
    case discard(feedID: String)
    /// "Fell asleep". The watch picks the sleep's ID, so a tap that arrives twice adds one sleep.
    case fellAsleep(sleepID: String)
    /// "Woke up", for the sleep the watch shows running.
    case wokeUp(sleepID: String)
    /// A nappy change: wee, poo or both. The watch picks the ID. No colour or consistency: those
    /// are added on the phone ("Add details").
    case nappy(nappyID: String, wee: Bool, poo: Bool)
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
    ///
    /// A held state made later than `now` means the clock has gone back since (the watch takes its
    /// time from the phone), so the new state is taken: otherwise the watch would turn down every
    /// state, and every acknowledgement, until the clock caught up again.
    public mutating func receive(_ state: WatchState, now: Date) -> Bool {
        if let phone, state.madeAt < phone.madeAt, phone.madeAt <= now { return false }
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

/// The phone's record of the watch's taps it has handled, newest last. One tap can arrive twice:
/// as a message, and again as the transfer the watch kept for when the phone was out of reach.
/// Only the first is applied, so a Start turned down while another feed ran can't start a feed
/// later (which would move the alarms later), and an old side can't undo a newer one.
public struct WatchTapLog: Hashable, Sendable {
    /// How many taps the phone remembers.
    public static let kept = 200
    /// How many the watch is told about, in each state.
    public static let told = 30

    public private(set) var ids: [String]

    public init(ids: [String] = []) {
        self.ids = Array(ids.suffix(Self.kept))
    }

    /// Records the tap. False when it was seen before: it must not be applied again.
    public mutating func firstSight(of id: String) -> Bool {
        guard !ids.contains(id) else { return false }
        ids = Array((ids + [id]).suffix(Self.kept))
        return true
    }

    /// The latest taps, for the watch's `handled`.
    public var latest: [String] { Array(ids.suffix(Self.told)) }
}

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
                                      bottles: details.bottles,
                                      breastfeed: isBreastfeed(running) ? true : nil)
        } else {
            state.previousFeedStart = state.lastFeedStart
        }
        // "Breastfeed (Sam)" on a bottle-only watch (DD15): only when the other parent is named.
        if bottleOnly, let other = breastfeeder?.member, other != me, let name = names[other] {
            state.breastfeeder = other
            state.breastfeederName = name
        }
        let visible = visibleSnapshots(babyID: babyID)
        state.nextSide = suggestedNextSide(visible, babyID: babyID, now: now)
        state.lastFormulaML = lastBottleAmount(visible, babyID: babyID, milk: .formula)
        state.lastExpressedML = lastBottleAmount(visible, babyID: babyID, milk: .expressed)
        state.lastMilk = visible.filter { $0.event.isLiveFeed && $0.event.babyID == babyID }
            .sorted { ($0.event.startedAt, $0.event.id) > ($1.event.startedAt, $1.event.id) }
            .lazy.compactMap { $0.payload?.feed?.bottles.last?.milk }.first
        // The sleep that started last decides, as on Home (`sleepState`): an end after `now` (a
        // clock set back) still counts as asleep.
        if let last = liveSleeps(allEvents, babyID: babyID, now: now).last {
            state.sleep = WatchSleep(id: last.id, start: last.startedAt, end: last.endedAt.flatMap { $0 <= now ? $0 : nil })
        }
        state.lastNappy = lastNappy(snapshots, babyID: babyID, now: now)
            .map { WatchNappy(id: $0.id, at: $0.at, wee: $0.wee, poo: $0.poo) }
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
        /// Other records the tap changed, sent at once too.
        var alsoChanged: [String] = []
        switch request.command {
        case .start(let feedID, let bottle, let bottleID, let doneBy):
            id = feedID
            guard events[feedID] == nil, feedInProgress(babyID: babyID) == nil else { return false }
            // A start kept while the phone was out of reach, from before a feed logged since:
            // starting it now would show a feed running for hours.
            let later = allEvents.contains { $0.isLiveFeed && $0.babyID == babyID && $0.startedAt > at }
            guard !later else { return false }
            add(id: feedID, kind: .feed, babyID: babyID, startedAt: at,
                payload: EventPayload(feed: FeedDetails(bottles: bottle.map { [Bottle(id: bottleID, milk: $0)] } ?? [])),
                by: me, doneBy: bottle == nil ? doneBy : nil, timeZoneID: timeZoneID, now: at)
            // Start feed ends a running sleep, as in the app (the users' choice O).
            alsoChanged = endSleepForFeed(babyID: babyID, start: at, feedID: feedID, by: me, now: at)
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
            if changed {
                alsoChanged = reopenSleepEnded(byFeed: feed.event, by: me, now: max(at, feed.event.startedAt))
            }
        case .fellAsleep(let sleepID):
            id = sleepID
            // One sleep at a time. A tap kept while the phone was out of reach, from before a sleep
            // logged since, would make a second sleep over the first.
            guard events[sleepID] == nil, sleepInProgress(babyID: babyID, now: at) == nil else { return false }
            let later = allEvents.contains { $0.kind == .sleep && $0.deletedAt == nil && $0.babyID == babyID && $0.startedAt > at }
            guard !later else { return false }
            startSleep(id: sleepID, babyID: babyID, startedAt: at, by: me, timeZoneID: timeZoneID, now: at)
            changed = true
        case .wokeUp(let sleepID):
            id = sleepID
            // Only while the sleep the watch showed still runs: a late tap must not end a sleep
            // that began after it.
            guard let sleep = events[sleepID]?.event, sleep.kind == .sleep, sleep.deletedAt == nil, sleep.endedAt == nil
            else { return false }
            let ended = endSleep(babyID: babyID, at: max(at, sleep.startedAt), by: me, now: max(at, sleep.startedAt))
            alsoChanged = ended
            changed = !ended.isEmpty
        case .nappy(let nappyID, let wee, let poo):
            id = nappyID
            guard events[nappyID] == nil else { return false }
            addNappy(id: nappyID, babyID: babyID, wee: wee, poo: poo, at: at, by: me, timeZoneID: timeZoneID, now: at)
            changed = true
        }
        if changed {
            for changedID in [id] + alsoChanged { events[changedID]?.uploadNotBefore = nil }
        }
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
        case .start(let feedID, let bottle, let bottleID, let doneBy):
            guard state.setUp, state.running == nil else { break }
            // Start feed ends a running sleep, as on the phone (the users' choice O).
            if let sleep = state.sleep, sleep.asleep, sleep.start < request.at { state.sleep?.end = request.at }
            state.previousFeedStart = state.lastFeedStart
            state.running = WatchFeed(id: feedID, startedAt: request.at, mine: true, byName: "", byColour: myColour,
                                      side: nil, bottles: bottle.map { [Bottle(id: bottleID, milk: $0)] } ?? [],
                                      breastfeed: bottle == nil && doneBy != nil ? true : nil)
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
            guard let running = state.running, running.id == feedID else { break }
            // The sleep this feed's start ended runs again, as on the phone (`reopenSleepEnded`).
            if let end = state.sleep?.end, abs(end.timeIntervalSince(running.startedAt)) < 1 { state.sleep?.end = nil }
            state.running = nil
            state.lastFeedStart = state.previousFeedStart
        case .fellAsleep(let sleepID):
            guard state.setUp, state.sleep?.asleep != true, (state.sleep?.since).map({ $0 <= request.at }) ?? true
            else { break }
            state.sleep = WatchSleep(id: sleepID, start: request.at)
        case .wokeUp(let sleepID):
            guard let sleep = state.sleep, sleep.id == sleepID, sleep.asleep else { break }
            state.sleep?.end = max(request.at, sleep.start)
        case .nappy(let nappyID, let wee, let poo):
            guard state.setUp, (state.lastNappy?.at).map({ $0 <= request.at }) ?? true else { break }
            state.lastNappy = WatchNappy(id: nappyID, at: request.at, wee: wee, poo: poo)
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

    /// What the watch face's Start feed piece shows, and what a tap on it does.
    public var faceButton: WatchFaceButton {
        guard setUp else { return .notReady }
        guard let running else { return .start }
        return running.mine
            ? .finish(feedID: running.id, since: running.startedAt)
            : .others(feedID: running.id, since: running.startedAt, name: running.byName)
    }

    /// A tap on the watch face's Finish, checked against what the watch knows now (the face can be
    /// a little behind): only this parent's feed, and only while it is still the one running.
    public func finishFromFace(feedID: String) -> WatchFeed? {
        guard let running, running.mine, running.id == feedID else { return nil }
        return running
    }

    /// What a tap on Fell asleep or Woke up sends: Woke up for the sleep shown running, otherwise
    /// Fell asleep with a new ID. Nil before the phone is set up.
    public func sleepTap(newID: String = UUID().uuidString) -> WatchCommand? {
        guard setUp else { return nil }
        if let sleep, sleep.asleep { return .wokeUp(sleepID: sleep.id) }
        return .fellAsleep(sleepID: newID)
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
