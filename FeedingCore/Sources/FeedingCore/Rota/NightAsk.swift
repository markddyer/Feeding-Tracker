import Foundation

// "Ask the other parent to take a night" (plan v1, "Who gets alerted"; the user's choice of
// 15 Nov 2026: a card on the other parent's Home, plus an ordinary notification).
//
// An ask is a request, not a hand-off. The parent who asks stays on duty until the other parent
// takes the night with "I'll take it", which is an ordinary `NightClaim`. So an ask never changes
// who alerts, and `reconcile` never reads it.
//
// Each record has one writer at a time, so the two phones don't write the same record at once:
// the ask is written by the parent on duty, and "Not tonight" by the parent who was asked.

/// "Can you take tonight?" One record per night.
public struct NightAsk: Hashable, Sendable, Codable {
    public var night: PlainDate
    public var askedBy: MemberID
    public var askedAt: Date
    /// Set when the asker taps Undo. The record stays, so the other phone hears about it.
    public var withdrawn: Bool

    public init(night: PlainDate, askedBy: MemberID, askedAt: Date, withdrawn: Bool = false) {
        self.night = night
        self.askedBy = askedBy
        self.askedAt = askedAt
        self.withdrawn = withdrawn
    }
}

/// "Not tonight": the asked parent's answer. One record per night.
public struct NightAskReply: Hashable, Sendable, Codable {
    public var night: PlainDate
    /// The ask this answers, by when it was made: a reply never answers a later ask.
    public var askedAt: Date
    public var by: MemberID
    public var repliedAt: Date

    public init(night: PlainDate, askedAt: Date, by: MemberID, repliedAt: Date) {
        self.night = night
        self.askedAt = askedAt
        self.by = by
        self.repliedAt = repliedAt
    }
}

/// Where an ask stands, as one parent's phone sees it.
public enum NightAskStatus: Hashable, Sendable {
    /// The other parent asks this parent to take the night: the card with two answers.
    case askedOfMe(NightAsk)
    /// This parent asked and is still on duty, waiting for an answer.
    case waiting(NightAsk)
    /// This parent asked; the other parent said "Not tonight".
    case declined(NightAsk, by: MemberID)
    /// This parent asked; the other parent is now on duty.
    case taken(NightAsk, by: MemberID)
}

/// Something about an ask that this phone tells its parent with an ordinary notification.
public enum NightAskNews: Hashable, Sendable {
    case asked(NightAsk)
    case taken(NightAsk, by: MemberID)
    case declined(NightAsk, by: MemberID)

    public var ask: NightAsk {
        switch self {
        case .asked(let ask), .taken(let ask, _), .declined(let ask, _): ask
        }
    }

    /// Stable for one ask and one outcome, so each is told once. Also the notification's ID.
    public var id: String {
        let base = "nightAsk-\(ask.night)-\(ask.askedAt.wholeMilliseconds)"
        switch self {
        case .asked: return "\(base)-asked"
        case .taken: return "\(base)-taken"
        case .declined: return "\(base)-declined"
        }
    }
}

private extension Date {
    /// Records keep times in milliseconds, and a time read back and saved again can move by a
    /// tiny fraction. Asks are matched on whole milliseconds, so that never matters.
    var wholeMilliseconds: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}

extension HouseholdSettings {
    /// The night that is on now, or, by day, the one coming tonight.
    public func tonight(at now: Date) -> PlainDate {
        switch dayHours.period(at: now, in: timeZone) {
        case .night(let night): night
        case .day(let day): day
        }
    }
}

extension HouseholdState {
    /// The claim that decides `night`, if any.
    public func claim(for night: PlainDate) -> NightClaim? {
        DutyRoster(rota: Rota(startDate: night, firstOnDuty: "", secondOnDuty: ""), claims: claims).claim(for: night)
    }

    /// Who is on duty on `night`, for the screens. Nil when there is no rota and nobody took the
    /// night (`roster(for:)` counts this phone as on duty then, so that nothing goes quiet).
    public func onDuty(night: PlainDate) -> MemberID? {
        claim(for: night)?.member ?? rota?.scheduledOnDuty(night: night)
    }
}

extension HouseholdData {
    // MARK: Reading

    public func nightAsk(for night: PlainDate) -> NightAsk? {
        setting(NightAsk.self, SettingKey.ask(night))
    }

    /// Every ask this app version can read.
    public var nightAsks: [NightAsk] {
        plainRecords(of: .setting).filter { $0.name.hasPrefix("ask-") }.compactMap {
            PayloadCoder.decode(SettingPayload<NightAsk>.self, from: $0.payload)?.value
        }
    }

    /// Where the ask for `night` stands, for `me`. Nil when there is no open ask: none was made,
    /// it was withdrawn, or a claim made after it settled the night.
    public func nightAskStatus(night: PlainDate, me: MemberID) -> NightAskStatus? {
        guard let ask = nightAsk(for: night), !ask.withdrawn else { return nil }
        let state = householdState
        let onDuty = state.onDuty(night: night)
        // A claim made after the ask answers it: the other parent took the night, or the asker
        // took it back after that.
        let claimedSince = state.claim(for: night).map { $0.claimedAt > ask.askedAt } ?? false
        let reply = setting(NightAskReply.self, SettingKey.askReply(night))
            .flatMap { $0.askedAt.wholeMilliseconds == ask.askedAt.wholeMilliseconds && $0.by != ask.askedBy ? $0 : nil }
        if ask.askedBy == me {
            if let onDuty, onDuty != me { return .taken(ask, by: onDuty) }
            if claimedSince { return nil }
            if let reply { return .declined(ask, by: reply.by) }
            return .waiting(ask)
        }
        // With no rota and no claim, nobody is on (both phones alert), so the ask still stands.
        guard onDuty == ask.askedBy || onDuty == nil, !claimedSince, reply == nil else { return nil }
        return .askedOfMe(ask)
    }

    /// What this phone should tell its parent about asks for tonight and later nights. The phone
    /// keeps a note of what it told, so each one is told once.
    public func nightAskNews(me: MemberID, now: Date) -> [NightAskNews] {
        let tonight = householdSettings.tonight(at: now)
        return nightAsks.filter { $0.night >= tonight }.sorted { $0.night < $1.night }.compactMap { ask in
            switch nightAskStatus(night: ask.night, me: me) {
            case .askedOfMe(let ask): .asked(ask)
            case .taken(let ask, let by): .taken(ask, by: by)
            case .declined(let ask, let by): .declined(ask, by: by)
            case .waiting, nil: nil
            }
        }
    }

    // MARK: Changing

    /// "Ask Sam to take it". The parent on duty that night can ask. So can either parent when
    /// nobody is on (no rota and no claim: both phones alert), which is when asking helps most
    /// (the user's choice, 15 Nov 2026). Changes nothing about who alerts. Returns false when it
    /// can't ask.
    @discardableResult
    public mutating func askNight(_ night: PlainDate, by member: MemberID, now: Date) -> Bool {
        let onDuty = householdState.onDuty(night: night)
        guard onDuty == member || onDuty == nil, nightAskStatus(night: night, me: member) == nil
        else { return false }
        putSetting(NightAsk(night: night, askedBy: member, askedAt: now), key: SettingKey.ask(night), now: now)
        return true
    }

    /// Undo for an ask. It works after the ask has reached the other phone too: its card goes.
    public mutating func withdrawAsk(_ night: PlainDate, by member: MemberID, now: Date) {
        guard var ask = nightAsk(for: night), ask.askedBy == member, !ask.withdrawn else { return }
        ask.withdrawn = true
        putSetting(ask, key: SettingKey.ask(night), now: now)
    }

    /// "Not tonight". The asker stays on duty.
    public mutating func declineAsk(_ night: PlainDate, by member: MemberID, now: Date) {
        guard case .askedOfMe(let ask) = nightAskStatus(night: night, me: member) else { return }
        putSetting(NightAskReply(night: night, askedAt: ask.askedAt, by: member, repliedAt: now),
                   key: SettingKey.askReply(night), now: now)
    }
}
