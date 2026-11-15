import Foundation

// "Both phones tonight" (the user's choice of 15 Nov 2026, after the first phone test of the
// night ask showed no way to give a taken night back): either parent can tap it, and both phones
// alert that night.
//
// It only adds alerting. The phone that had the night stays on, and the other phone comes on as
// soon as it hears. So, unlike taking a claim back, it is safe at once and needs no
// acknowledgement (plan v1, "The acknowledgement rule"; review round 2, S3). A claim made after it
// decides the night again.
//
// It is its own record, not a change to the claim's: an app version that can't read it still
// sees the claim, so the claimer's phone stays on.

/// "Both phones tonight". One record per night.
public struct BothPhonesNight: Hashable, Sendable, Codable {
    public var night: PlainDate
    public var by: MemberID
    public var at: Date

    public init(night: PlainDate, by: MemberID, at: Date) {
        self.night = night
        self.by = by
        self.at = at
    }
}

extension HouseholdState {
    /// The claim for `night`, whether or not "Both phones tonight" came after it.
    func latestClaim(for night: PlainDate) -> NightClaim? {
        DutyRoster(rota: Rota(startDate: night, firstOnDuty: "", secondOnDuty: ""), claims: claims).claim(for: night)
    }

    /// "Both phones tonight" for `night`, when no claim came after it. On a tie, both phones:
    /// that alerts more.
    public func bothPhonesInForce(night: PlainDate) -> BothPhonesNight? {
        guard let both = bothPhones.filter({ $0.night == night }).max(by: { $0.at < $1.at }) else { return nil }
        if let claim = latestClaim(for: night), claim.claimedAt > both.at { return nil }
        return both
    }

    /// When `night` was last decided by a tap: the claim, or "Both phones tonight". Nil when the
    /// rota decides it, or nothing does (no rota).
    public func decidedAt(night: PlainDate) -> Date? {
        claim(for: night)?.claimedAt ?? bothPhonesInForce(night: night)?.at
    }
}

extension HouseholdData {
    public var bothPhonesNights: [BothPhonesNight] {
        plainRecords(of: .setting).filter { $0.name.hasPrefix("both-") }.compactMap {
            PayloadCoder.decode(SettingPayload<BothPhonesNight>.self, from: $0.payload)?.value
        }
    }

    /// "Both phones tonight". Only adds alerting, so it isn't pending.
    public mutating func setBothPhones(_ night: PlainDate, by member: MemberID, now: Date) {
        putSetting(BothPhonesNight(night: night, by: member, at: now), key: SettingKey.bothPhones(night), now: now)
    }

    /// Undo for "I'll take it". Before the claim has left this phone, it goes. After that, taking
    /// it back could leave neither phone alerting while the other phone catches up, so both
    /// phones alert that night instead. Does nothing once someone else has taken the night.
    public mutating func undoTake(_ night: PlainDate, by member: MemberID, now: Date) {
        guard householdState.claim(for: night)?.member == member else { return }
        if !undoClaim(night, by: member) {
            setBothPhones(night, by: member, now: now)
        }
    }
}
