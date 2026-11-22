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

    /// Everything this version understands.
    public static let all = [bath, medicine, pump, pooDetails, earlier, doneBy, undo, results]
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
        }
        if outcome == .applied { events[request.entryID]?.uploadNotBefore = nil }
        return outcome
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
        }
        return state
    }
}
