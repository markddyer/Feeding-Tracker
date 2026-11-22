import Foundation

// Step 3 of `docs/planning/11-watch-parity.md` (W-D3): tonight's rota on the watch's page 3. The
// watch offers what the phone's Nights tile and ask card offer, and the phone applies each tap with
// its own rota calls (`claimNight`, `askNight`, `declineAsk`, `withdrawAsk`, `setBothPhones`,
// `undoTake`), so the acknowledgement rule and every alarm rule stay as they are.

/// Tonight's rota, as the watch shows it.
public struct WatchTonight: Codable, Hashable, Sendable {
    /// Where an ask for tonight stands for this parent (`NightAskStatus`).
    public enum Ask: String, Codable, Hashable, Sendable {
        case none
        /// The other parent asks this parent to take tonight.
        case askedOfMe
        /// This parent asked, and waits for the answer.
        case waiting
        /// This parent asked; the other parent said not tonight.
        case declined
    }

    public var night: PlainDate
    /// Who is on duty tonight; nil when both phones alert.
    public var onDuty: MemberID?
    /// No rota, and nobody has taken a night.
    public var noRota: Bool
    /// Someone took tonight: "Both phones tonight" gives it back.
    public var taken: Bool
    public var ask: Ask
    /// The other parent, if there is one.
    public var other: MemberID?

    public init(night: PlainDate, onDuty: MemberID?, noRota: Bool, taken: Bool, ask: Ask, other: MemberID?) {
        self.night = night
        self.onDuty = onDuty
        self.noRota = noRota
        self.taken = taken
        self.ask = ask
        self.other = other
    }

    /// What the watch offers, as the phone's Nights tile and ask card do.
    public enum Choice: Hashable, Sendable {
        case take
        case ask
        case decline
        case bothPhones
    }

    public func choices(me: MemberID) -> [Choice] {
        if ask == .askedOfMe { return [.take, .decline] }
        if onDuty == me {
            return (ask == .none && other != nil ? [.ask] : []) + (taken ? [.bothPhones] : [])
        }
        if taken { return [.take, .bothPhones] }
        if onDuty == nil, ask == .none, other != nil { return [.take, .ask] }
        return [.take]
    }
}

extension HouseholdData {
    /// Tonight's rota for the watch, for `me`; `other` is the other parent.
    public func watchTonight(me: MemberID, other: MemberID?, now: Date) -> WatchTonight {
        let night = householdSettings.tonight(at: now)
        let state = householdState
        let onDuty = state.onDuty(night: night)
        let nights = state.nights(around: night, before: 5, after: 1)
        let ask: WatchTonight.Ask = switch nightAskStatus(night: night, me: me) {
        case .askedOfMe?: .askedOfMe
        case .waiting?: .waiting
        case .declined?: .declined
        case .taken?, nil: .none
        }
        return WatchTonight(night: night, onDuty: onDuty, noRota: state.rota == nil && nights.allSatisfy { $0.onDuty == nil },
                            taken: state.claim(for: night) != nil && other != nil, ask: ask, other: other)
    }

    /// Applies a rota tap from the watch. A night already past is turned down.
    mutating func applyWatchNight(_ action: WatchAction, by me: MemberID, now: Date) -> WatchOutcome {
        let tonight = householdSettings.tonight(at: now)
        switch action {
        case .claimNight(let night):
            guard night >= tonight else { return .refused }
            guard householdState.claim(for: night)?.member != me else { return .unchanged }
            claimNight(night, by: me, now: now)
            return .applied
        case .askNight(let night):
            guard night >= tonight else { return .refused }
            if case .waiting? = nightAskStatus(night: night, me: me) { return .unchanged }
            return askNight(night, by: me, now: now) ? .applied : .refused
        case .declineAsk(let night):
            guard case .askedOfMe? = nightAskStatus(night: night, me: me) else { return .refused }
            declineAsk(night, by: me, now: now)
            return .applied
        case .withdrawAsk(let night):
            guard let ask = nightAsk(for: night), ask.askedBy == me else { return .refused }
            guard !ask.withdrawn else { return .unchanged }
            withdrawAsk(night, by: me, now: now)
            return .applied
        case .bothPhones(let night):
            guard night >= tonight else { return .refused }
            guard householdState.bothPhonesInForce(night: night) == nil else { return .unchanged }
            setBothPhones(night, by: me, now: now)
            return .applied
        case .undoTake(let night):
            // Only a claim made a moment ago, as the Logged card's Undo; once sent, both phones
            // alert instead (`undoTake`), so nothing goes quiet.
            guard let claim = householdState.claim(for: night), claim.member == me,
                  now.timeIntervalSince(claim.claimedAt) <= watchUndoWindow else { return .refused }
            undoTake(night, by: me, now: now)
            return .applied
        default:
            return .refused
        }
    }
}

extension WatchState {
    /// A rota tap, shown at once.
    mutating func showNight(_ action: WatchAction) {
        guard var tonight else { return }
        switch action {
        case .claimNight(let night) where night == tonight.night:
            tonight.onDuty = me
            tonight.taken = tonight.other != nil
            tonight.ask = .none
        case .askNight(let night) where night == tonight.night:
            tonight.ask = .waiting
        case .declineAsk(let night) where night == tonight.night, .withdrawAsk(let night) where night == tonight.night:
            tonight.ask = .none
        case .bothPhones(let night) where night == tonight.night:
            tonight.onDuty = nil
            tonight.taken = false
        default:
            return
        }
        self.tonight = tonight
    }
}
