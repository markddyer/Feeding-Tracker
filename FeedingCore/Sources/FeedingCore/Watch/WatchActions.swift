import Foundation

// Step 1 of the watch parity work (`docs/planning/11-watch-parity.md`, with the outside review's
// changes): the watch's new taps. They travel in their own message (`WatchMessage.action`,
// `WatchKey.action`), which an older phone simply ignores, and the watch shows a button only once
// the phone says it understands its tap (`WatchState.capabilities`). The phone answers each tap
// (`WatchState.results`), so the watch's Logged card says "Waiting for iPhone" until it is saved.
// As before, the watch picks the ID of anything it creates, so a tap that arrives twice changes
// nothing the second time, and the phone applies each tap as the same tap in the app would.

/// A new tap from the watch.
public enum WatchAction: Codable, Hashable, Sendable {
    /// A bath, now.
    case bath(id: String)
    /// A medicine from the household's list, given now.
    case medicine(id: String, name: String)
    /// Pumping just done: from 30 to 10 minutes before the tap, as the phone's Pumping starts. An
    /// amount may be left out.
    case pump(id: String, side: PumpSide, leftML: Int?, rightML: Int?)
    /// A poo's colour and consistency, after Poo or Both. Only what is given is set.
    case pooDetails(nappyID: String, colour: PooColour?, consistency: PooConsistency?)
    /// "Earlier" on the Logged card: moves an entry the watch just logged back by `minutes`, only
    /// while its start is still `expected` (what the tap wrote), so a newer change is never undone.
    /// Never a feed: moving a feed moves the alarms (`11-watch-parity.md`, step 3).
    case earlier(id: String, minutes: Int, expected: Date)
    /// "Done by" on the Logged card.
    case doneBy(id: String, member: MemberID)
    /// Undo on the Logged card: removes an entry the watch just logged (not a feed: its Stop ·
    /// discard does that, and step 3 adds the rest).
    case undo(id: String)

    // Step 2, the feed extras (W-D1). The watch picks each new ID, and names the tap about the
    // same feed that must come first (`WatchActionRequest.after`), so they arrive in order.

    /// A bottle: during this parent's feed while it has none (the phone's Bottle), or after it
    /// finished, of a kind not logged yet ("Add to this feed"), with its amount when one was chosen.
    case addBottle(feedID: String, bottleID: String, milk: MilkKind, ml: Int?)
    /// A side not logged yet, after the feed finished.
    case addSide(feedID: String, side: BreastSide)
    /// A bottle's amount.
    case amount(feedID: String, bottleID: String, ml: Int)
    /// "Just finished": a feed from `minutesAgo` before the tap until the tap.
    case justFinished(feedID: String, minutesAgo: Int)
    /// "Earlier": a feed from `start`, for 20 minutes or until the tap (the phone's default).
    case earlierFeed(feedID: String, start: Date)
}

/// A new tap, with when it was made and the tap it depends on.
public struct WatchActionRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var action: WatchAction
    public var at: Date
    /// A tap the phone must have handled first: the nappy for its details, the entry for Earlier,
    /// Done by or Undo. Until then the phone answers `waiting`, and the watch sends it again.
    public var after: String?

    public init(id: String = UUID().uuidString, action: WatchAction, at: Date, after: String? = nil) {
        self.id = id
        self.action = action
        self.at = at
        self.after = after
    }

    /// The entry this tap is about.
    public var entryID: String {
        switch action {
        case .bath(let id), .medicine(let id, _), .pump(let id, _, _, _), .earlier(let id, _, _),
             .doneBy(let id, _), .undo(let id):
            id
        case .pooDetails(let id, _, _):
            id
        case .addBottle(let id, _, _, _), .addSide(let id, _), .amount(let id, _, _), .justFinished(let id, _),
             .earlierFeed(let id, _):
            id
        }
    }
}

/// What the phone did with a tap.
public enum WatchOutcome: String, Codable, Hashable, Sendable {
    /// Saved.
    case applied
    /// Nothing to change: it was already so (a tap that arrived twice).
    case unchanged
    /// Not done: the entry changed since, was removed, is too old, or isn't this parent's.
    case refused
    /// The tap it depends on hasn't reached the phone yet: send it again later.
    case waiting
}

/// The phone's answer to one tap.
public struct WatchResult: Codable, Hashable, Sendable {
    public var id: String
    public var outcome: WatchOutcome

    public init(id: String, outcome: WatchOutcome) {
        self.id = id
        self.outcome = outcome
    }
}

/// A medicine on the household's list, as page 3 shows it.
public struct WatchMedicine: Codable, Hashable, Sendable {
    public var name: String
    public var lastGiven: Date?

    public init(name: String, lastGiven: Date?) {
        self.name = name
        self.lastGiven = lastGiven
    }
}

/// A parent, for "Done by".
public struct WatchMember: Codable, Hashable, Sendable {
    public var id: MemberID
    public var name: String
    /// Their colour's name ("teal").
    public var colour: String

    public init(id: MemberID, name: String, colour: String) {
        self.id = id
        self.name = name
        self.colour = colour
    }
}

/// The new taps a phone understands, named in `WatchState.capabilities`.
public enum WatchCapability {
    public static let bath = "bath"
    public static let medicine = "medicine"
    public static let pump = "pump"
    public static let pooDetails = "pooDetails"
    public static let earlier = "earlier"
    public static let doneBy = "doneBy"
    public static let undo = "undo"
    /// The phone answers each tap (`WatchState.results`).
    public static let results = "results"
    /// Step 2: a bottle or side added, an amount, Just finished and Earlier feed.
    public static let feedExtras = "feedExtras"

    /// Everything this version understands.
    public static let all = [bath, medicine, pump, pooDetails, earlier, doneBy, undo, results, feedExtras]
}

extension WatchActionRequest {
    /// The capability a phone needs to understand this tap.
    public var capability: String {
        switch action {
        case .bath: WatchCapability.bath
        case .medicine: WatchCapability.medicine
        case .pump: WatchCapability.pump
        case .pooDetails: WatchCapability.pooDetails
        case .earlier: WatchCapability.earlier
        case .doneBy: WatchCapability.doneBy
        case .undo: WatchCapability.undo
        case .addBottle, .addSide, .amount, .justFinished, .earlierFeed: WatchCapability.feedExtras
        }
    }
}

/// How old a tap may be when it reaches the phone. The watch forgets its own after a day
/// (`WatchSaved.dropStale`); one the system was still carrying is turned down here.
public let watchTapLifetime: TimeInterval = 25 * 3600

/// How long after its tap an entry may be undone from the watch: the Logged card shows Undo for a
/// few seconds, and a tap kept while the phone was out of reach mustn't remove an entry the other
/// parent may have corrected since (outside review of `11-watch-parity.md`).
public let watchUndoWindow: TimeInterval = 10 * 60

/// How far back the watch's Earlier feed goes: 12 hours, in 5-minute steps.
public let watchEarliestFeed: TimeInterval = 12 * 3600

/// The kinds the watch's Earlier and Undo work on in step 1: not feeds.
let watchCareKinds: Set<EventKind> = [.nappy, .bath, .medicine, .pump, .sleep]

extension HouseholdData {
    /// Applies a new tap from the watch, as the same tap in the app would, and sends it at once.
    /// The caller has checked that its `after` tap was handled.
    public mutating func applyWatchAction(_ request: WatchActionRequest, babyID: String, by me: MemberID,
                                          timeZoneID: String, now: Date) -> WatchOutcome {
        let at = request.at
        guard now.timeIntervalSince(at) <= watchTapLifetime else { return .refused }
        let outcome: WatchOutcome
        switch request.action {
        case .bath(let id):
            guard events[id] == nil else { return .unchanged }
            add(id: id, kind: .bath, babyID: babyID, startedAt: at, payload: EventPayload(), by: me, timeZoneID: timeZoneID, now: at)
            outcome = .applied
        case .medicine(let id, let name):
            guard events[id] == nil else { return .unchanged }
            addMedicine(id: id, babyID: babyID, MedicineDetails(name: name), at: at, by: me, timeZoneID: timeZoneID, now: at)
            outcome = .applied
        case .pump(let id, let side, let leftML, let rightML):
            guard events[id] == nil else { return .unchanged }
            add(id: id, kind: .pump, babyID: babyID, startedAt: at.addingTimeInterval(-30 * 60),
                endedAt: at.addingTimeInterval(-10 * 60),
                payload: EventPayload(pump: PumpDetails(side: side, leftML: leftML, rightML: rightML)),
                by: me, timeZoneID: timeZoneID, now: at)
            outcome = .applied
        case .pooDetails(let id, let colour, let consistency):
            guard let snapshot = events[id]?.snapshot, snapshot.event.kind == .nappy, snapshot.event.deletedAt == nil,
                  let nappy = snapshot.payload?.nappy, nappy.poo else { return .refused }
            let wanted = (colour ?? nappy.colour, consistency ?? nappy.consistency)
            guard wanted != (nappy.colour, nappy.consistency) else { return .unchanged }
            let changed = edit(id, by: me, now: max(at, snapshot.event.startedAt)) { snapshot in
                if let colour { snapshot.payload?.nappy?.colour = colour }
                if let consistency { snapshot.payload?.nappy?.consistency = consistency }
            }
            outcome = changed ? .applied : .refused
        case .earlier(let id, let minutes, let expected):
            guard minutes > 0, minutes <= 60, let event = events[id]?.event, event.deletedAt == nil,
                  event.loggedBy == me, watchCareKinds.contains(event.kind),
                  abs(event.startedAt.timeIntervalSince(expected)) < 1 else { return .refused }
            let shift = -Double(minutes) * 60
            let changed = edit(id, by: me, now: max(at, event.startedAt)) { snapshot in
                snapshot.event.startedAt = expected.addingTimeInterval(shift)
                // Pumping moves as a whole; a sleep's start never goes after its end.
                if snapshot.event.kind == .pump, let end = snapshot.event.endedAt {
                    snapshot.event.endedAt = end.addingTimeInterval(shift)
                }
            }
            outcome = changed ? .applied : .refused
        case .doneBy(let id, let member):
            guard let event = events[id]?.event, event.deletedAt == nil else { return .refused }
            guard event.doneBy != member else { return .unchanged }
            outcome = setDoneBy(id, to: member, by: me, now: max(at, event.startedAt)) ? .applied : .refused
        case .undo(let id):
            guard let event = events[id]?.event else { return .unchanged }
            guard event.deletedAt == nil else { return .unchanged }
            // Only an entry this parent logged a moment ago, and a sleep still running (Undo of
            // Woke up is step 3).
            guard event.loggedBy == me, watchCareKinds.contains(event.kind),
                  now.timeIntervalSince(event.createdAt) <= watchUndoWindow,
                  event.kind != .sleep || event.endedAt == nil else { return .refused }
            if !undoAdd(id, now: now) { delete(id, by: me, now: max(now, event.startedAt)) }
            outcome = .applied
        case .addBottle(let id, let bottleID, let milk, let ml):
            guard let feed = events[id]?.snapshot, feed.event.isLiveFeed else { return .refused }
            let details = feed.payload?.feed ?? FeedDetails()
            guard !details.bottles.contains(where: { $0.id == bottleID }) else { return .unchanged }
            // As the phone: while the feed runs, only the parent who started it adds its one
            // bottle; afterwards, a kind not logged yet (`DetailChoices`).
            if feed.event.endedAt == nil {
                guard feed.event.loggedBy == me, details.bottles.isEmpty else { return .refused }
            } else {
                guard !details.bottles.contains(where: { $0.milk == milk }) else { return .refused }
            }
            outcome = editFeedDetails(id, by: me, now: max(at, feed.event.startedAt)) {
                $0.bottles.append(Bottle(id: bottleID, milk: milk, ml: ml.map { min(300, max(5, $0)) }))
            }
        case .addSide(let id, let side):
            guard let feed = events[id]?.snapshot, feed.event.isLiveFeed, feed.event.endedAt != nil else { return .refused }
            guard !(feed.payload?.feed?.breast ?? []).contains(where: { $0.side == side }) else { return .unchanged }
            outcome = editFeedDetails(id, by: me, now: max(at, feed.event.startedAt)) {
                $0.breast.append(BreastSegment(side: side))
            }
        case .amount(let id, let bottleID, let ml):
            guard let feed = events[id]?.snapshot, feed.event.isLiveFeed,
                  let bottle = feed.payload?.feed?.bottles.first(where: { $0.id == bottleID }) else { return .refused }
            let ml = min(300, max(5, ml))
            guard bottle.ml != ml else { return .unchanged }
            outcome = editFeedDetails(id, by: me, now: max(at, feed.event.startedAt)) { details in
                if let index = details.bottles.firstIndex(where: { $0.id == bottleID }) { details.bottles[index].ml = ml }
            }
        case .justFinished(let id, let minutesAgo):
            guard events[id] == nil else { return .unchanged }
            guard (1...180).contains(minutesAgo) else { return .refused }
            outcome = addPastFeed(id, babyID: babyID, from: at.addingTimeInterval(-Double(minutesAgo) * 60), to: at, by: me,
                                  timeZoneID: timeZoneID, now: at)
        case .earlierFeed(let id, let start):
            guard events[id] == nil else { return .unchanged }
            // Back to 12 hours, as the watch's Digital Crown offers; never after the tap.
            guard start <= at, at.timeIntervalSince(start) <= watchEarliestFeed + 60 else { return .refused }
            outcome = addPastFeed(id, babyID: babyID, from: start, to: min(start.addingTimeInterval(20 * 60), at), by: me,
                                  timeZoneID: timeZoneID, now: at)
        }
        if outcome == .applied { events[request.entryID]?.uploadNotBefore = nil }
        return outcome
    }

    /// Changes a feed's sides and bottles, as the phone's details panel does.
    private mutating func editFeedDetails(_ id: String, by me: MemberID, now: Date,
                                          _ change: (inout FeedDetails) -> Void) -> WatchOutcome {
        let changed = edit(id, by: me, now: now) { snapshot in
            var details = snapshot.payload?.feed ?? FeedDetails()
            change(&details)
            snapshot.payload?.feed = details
        }
        return changed ? .applied : .refused
    }

    /// A finished feed logged afterwards, as the phone's Just finished and Earlier. Turned down
    /// when a feed is already logged in its span (one running counts until now), so a tap that
    /// arrives late, or twice from two watches, can't log the same feed twice (outside review of
    /// `11-watch-parity.md`).
    private mutating func addPastFeed(_ id: String, babyID: String, from start: Date, to end: Date, by me: MemberID,
                                      timeZoneID: String, now: Date) -> WatchOutcome {
        let clash = allEvents.contains {
            $0.isLiveFeed && $0.babyID == babyID && $0.startedAt < end && ($0.endedAt ?? max(now, end)) > start
        }
        guard !clash else { return .refused }
        add(id: id, kind: .feed, babyID: babyID, startedAt: start, endedAt: end, payload: EventPayload(feed: FeedDetails()),
            by: me, timeZoneID: timeZoneID, now: now)
        return .applied
    }

    /// The household's medicines, with when each was last given, for page 3.
    public func watchMedicines(babyID: String, now: Date) -> [WatchMedicine] {
        medicines.map { WatchMedicine(name: $0, lastGiven: lastGiven($0, babyID: babyID, now: now)) }
    }

    /// When the last bath was, for page 3.
    public func lastBath(babyID: String, now: Date) -> Date? {
        allEvents.filter { $0.kind == .bath && $0.deletedAt == nil && $0.babyID == babyID && $0.startedAt <= now }
            .map(\.startedAt).max()
    }
}

extension WatchState {
    /// A feed logged afterwards, shown at once. Only while no feed runs (the phone turns it down
    /// otherwise); the window moves only if it is the latest.
    mutating func showPastFeed(_ id: String, from start: Date, to end: Date) {
        guard running == nil, lastFeed?.id != id else { return }
        lastFeed = WatchLastFeed(id: id, start: start, end: end, details: FeedDetails(), mine: true)
        let latest = max(start, lastFeedStart ?? start)
        lastFeedStart = latest
        previousFeedStart = latest
    }

    /// True when the phone understands this new tap.
    public func understands(_ capability: String) -> Bool {
        capabilities?.contains(capability) ?? false
    }

    /// The phone's answer to a tap, if it has given one (or, for the first eight kinds of tap from
    /// a phone that doesn't answer, that it handled it).
    public func result(of requestID: String) -> WatchOutcome? {
        if let result = results?.last(where: { $0.id == requestID }) { return result.outcome }
        return handled.contains(requestID) ? .applied : nil
    }

    /// The state as it will be once the phone has applied a new tap, so the watch shows it at once.
    public func applying(_ request: WatchActionRequest) -> WatchState {
        var state = self
        switch request.action {
        case .bath:
            state.lastBath = max(request.at, state.lastBath ?? request.at)
        case .medicine(_, let name):
            if var medicines = state.medicines, let index = medicines.firstIndex(where: { $0.name == name }) {
                medicines[index].lastGiven = max(request.at, medicines[index].lastGiven ?? request.at)
                state.medicines = medicines
            }
        case .pooDetails(let id, let colour, let consistency):
            guard state.lastNappy?.id == id else { break }
            if let colour { state.lastNappy?.colour = colour }
            if let consistency { state.lastNappy?.consistency = consistency }
        case .earlier(let id, let minutes, let expected):
            let moved = expected.addingTimeInterval(-Double(minutes) * 60)
            if state.lastNappy?.id == id { state.lastNappy?.at = moved }
            if state.sleep?.id == id, state.sleep?.asleep == true { state.sleep?.start = moved }
            // A bath or medicine shows only its time: it moves while that is still the tap's, so
            // a newer one is never replaced (outside review of step 1, P3).
            func isTap(_ date: Date?) -> Bool { date.map { abs($0.timeIntervalSince(expected)) < 1 } ?? false }
            if isTap(state.lastBath) { state.lastBath = moved }
            if var medicines = state.medicines {
                for index in medicines.indices where isTap(medicines[index].lastGiven) { medicines[index].lastGiven = moved }
                state.medicines = medicines
            }
        case .doneBy(let id, let member):
            if state.lastNappy?.id == id { state.lastNappy?.doneBy = member }
        case .pump, .undo:
            // Nothing on the watch's pages shows pumping; an Undo shows once the phone answers.
            break
        case .addBottle(let id, let bottleID, let milk, let ml):
            let bottle = Bottle(id: bottleID, milk: milk, ml: ml)
            if state.running?.id == id, state.running?.bottles.contains(where: { $0.id == bottleID }) == false {
                state.running?.bottles.append(bottle)
            }
            if state.lastFeed?.id == id, state.lastFeed?.details.bottles.contains(where: { $0.id == bottleID }) == false {
                state.lastFeed?.details.bottles.append(bottle)
            }
            state.lastMilk = milk
        case .addSide(let id, let side):
            if state.lastFeed?.id == id, state.lastFeed?.details.breast.contains(where: { $0.side == side }) == false {
                state.lastFeed?.details.breast.append(BreastSegment(side: side))
            }
        case .amount(let id, let bottleID, let ml):
            if state.running?.id == id, let index = state.running?.bottles.firstIndex(where: { $0.id == bottleID }) {
                state.running?.bottles[index].ml = ml
            }
            if state.lastFeed?.id == id, let index = state.lastFeed?.details.bottles.firstIndex(where: { $0.id == bottleID }) {
                state.lastFeed?.details.bottles[index].ml = ml
            }
        case .justFinished(let id, let minutesAgo):
            state.showPastFeed(id, from: request.at.addingTimeInterval(-Double(minutesAgo) * 60), to: request.at)
        case .earlierFeed(let id, let start):
            state.showPastFeed(id, from: start, to: min(start.addingTimeInterval(20 * 60), request.at))
        }
        return state
    }
}
