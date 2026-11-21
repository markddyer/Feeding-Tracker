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
    /// A bath given, at `startedAt`, with no details (`docs/planning/09-who-does-what.md`, X5).
    /// Never in the alerts, and it never ends a running sleep.
    public static let bath: EventKind = "bath"

    /// The kinds that are a parent's work in "who does what" (R2): each has a "done by", counts on
    /// the shared screen, and gets the swap on its Undo bar. Growth and firsts are not work. The
    /// one list every part reads (engineering review, A4), so they can't disagree.
    public var countsAsWork: Bool { Self.work.contains(self) }

    private static let work: Set<EventKind> = [.feed, .pump, .sleep, .nappy, .medicine, .bath]
}
