import Foundation

/// A breast. Used for feeds and for pumping.
public enum BreastSide: String, Hashable, Sendable, Codable, CaseIterable {
    case left
    case right

    public var other: BreastSide { self == .left ? .right : .left }
}

/// One stretch of breastfeeding on one side. Switching sides adds a segment.
public struct BreastSegment: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var side: BreastSide
    /// When this side started. Set while a feed is timed live; nil when logged afterwards.
    public var startedAt: Date?
    /// How long this side lasted, in seconds. Nil when not known.
    public var durationSeconds: Int?

    public init(id: String = UUID().uuidString, side: BreastSide, startedAt: Date? = nil, durationSeconds: Int? = nil) {
        self.id = id
        self.side = side
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
    }
}

/// What is in a bottle.
public enum MilkKind: String, Hashable, Sendable, Codable, CaseIterable {
    case expressed
    case formula
}

/// One bottle in a feed.
public struct Bottle: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var milk: MilkKind
    /// Nil when the amount was skipped.
    public var ml: Int?

    public init(id: String = UUID().uuidString, milk: MilkKind, ml: Int? = nil) {
        self.id = id
        self.milk = milk
        self.ml = ml
    }
}

/// The details of a feed: any mix of breast segments and bottles.
public struct FeedDetails: Hashable, Sendable, Codable {
    public var breast: [BreastSegment]
    public var bottles: [Bottle]

    public init(breast: [BreastSegment] = [], bottles: [Bottle] = []) {
        self.breast = breast
        self.bottles = bottles
    }

    public func ml(of milk: MilkKind) -> Int {
        bottles.lazy.filter { $0.milk == milk }.compactMap(\.ml).reduce(0, +)
    }
}

/// Which side a pumping session used.
public enum PumpSide: String, Hashable, Sendable, Codable, CaseIterable {
    case left
    case right
    case both
}

/// The details of a pumping (expressing) session.
public struct PumpDetails: Hashable, Sendable, Codable {
    public var side: PumpSide
    public var leftML: Int?
    public var rightML: Int?

    public init(side: PumpSide, leftML: Int? = nil, rightML: Int? = nil) {
        self.side = side
        self.leftML = leftML
        self.rightML = rightML
    }

    public var totalML: Int { (leftML ?? 0) + (rightML ?? 0) }
}
