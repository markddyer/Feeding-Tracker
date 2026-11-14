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
}
