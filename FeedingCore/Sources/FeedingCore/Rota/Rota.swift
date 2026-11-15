import Foundation

/// The night rota: the parents alternate nightly from a shared start date.
///
/// Each phone works the rota out for itself, so both agree even while sync is down.
public struct Rota: Hashable, Sendable, Codable {
    /// The first night of the rota, stored as a plain date.
    public var startDate: PlainDate
    /// On duty on the start night and every second night after it.
    public var firstOnDuty: MemberID
    public var secondOnDuty: MemberID

    public init(startDate: PlainDate, firstOnDuty: MemberID, secondOnDuty: MemberID) {
        self.startDate = startDate
        self.firstOnDuty = firstOnDuty
        self.secondOnDuty = secondOnDuty
    }

    /// Who the rota puts on duty for `night`, before any claims. Works for nights before the
    /// start date too, by alternating backwards.
    public func scheduledOnDuty(night: PlainDate) -> MemberID {
        night.days(since: startDate).isMultiple(of: 2) ? firstOnDuty : secondOnDuty
    }
}

/// "I'll take tonight". Stored as one record per night.
public struct NightClaim: Hashable, Sendable, Codable {
    public var night: PlainDate
    public var member: MemberID
    public var claimedAt: Date

    public init(night: PlainDate, member: MemberID, claimedAt: Date) {
        self.night = night
        self.member = member
        self.claimedAt = claimedAt
    }

    /// The CloudKit record name, such as "night-2026-11-13".
    public var recordName: String { "night-\(night)" }
}

/// The rota plus the claims: who is on duty each night.
public struct DutyRoster: Hashable, Sendable {
    public var rota: Rota
    private var claimsByNight: [PlainDate: NightClaim]

    /// When two claims name the same night, the later one wins; on a tie, the lower member ID,
    /// so both phones always pick the same one.
    public init(rota: Rota, claims: [NightClaim] = []) {
        self.rota = rota
        var byNight: [PlainDate: NightClaim] = [:]
        for claim in claims {
            if let existing = byNight[claim.night] {
                let later = (claim.claimedAt, existing.member) > (existing.claimedAt, claim.member)
                if later { byNight[claim.night] = claim }
            } else {
                byNight[claim.night] = claim
            }
        }
        claimsByNight = byNight
    }

    public func onDuty(night: PlainDate) -> MemberID {
        claimsByNight[night]?.member ?? rota.scheduledOnDuty(night: night)
    }

    /// The claim that decides `night`, if any ("I'll take tonight").
    public func claim(for night: PlainDate) -> NightClaim? {
        claimsByNight[night]
    }
}
