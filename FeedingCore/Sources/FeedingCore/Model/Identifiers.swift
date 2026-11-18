import Foundation

/// Identifies a parent in the household.
public struct MemberID: RawRepresentable, Hashable, Comparable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public static func < (lhs: MemberID, rhs: MemberID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}

/// The kind of an event. Unknown kinds from a newer app version are kept and ignored.
public struct EventKind: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let feed: EventKind = "feed"
    public static let pump: EventKind = "pump"
    /// A sleep: `startedAt` is when the baby fell asleep, `endedAt` when they woke up (nil while
    /// asleep). It never touches the alerts: `reconcile` counts feeds only.
    public static let sleep: EventKind = "sleep"
    /// A nappy change, at `startedAt`, with what was in it (`NappyDetails`).
    public static let nappy: EventKind = "nappy"
    /// A weight, length or head measurement, at `startedAt` (`GrowthDetails`).
    public static let growth: EventKind = "growth"
    /// A medicine or vitamin given, at `startedAt` (`MedicineDetails`).
    public static let medicine: EventKind = "medicine"
    /// One of the baby's firsts, at `startedAt` (`MilestoneDetails`). Parents read "first"; the
    /// code says "milestone" (`docs/planning/07-milestones-journal.md`). Never in the alerts.
    public static let milestone: EventKind = "milestone"
}
