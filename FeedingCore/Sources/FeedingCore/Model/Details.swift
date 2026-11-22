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

/// What was in a nappy (`docs/planning/06-more-than-feeds.md`, Q2: one tap, wee, poo or both).
/// Both may be true. Both false is a dry nappy: it counts as a change, but as neither.
///
/// A poo's colour and consistency are optional and added after the tap (the nappy is saved at
/// once). They mean something only with `poo`; a wee-only nappy has neither. Each merges as a
/// field of its own, so one phone adding the colour while the other adds the consistency keeps
/// both.
public struct NappyDetails: Hashable, Sendable, Codable {
    public var wee: Bool
    public var poo: Bool
    /// Nil when not given.
    public var colour: PooColour?
    /// Nil when not given.
    public var consistency: PooConsistency?

    public init(wee: Bool, poo: Bool, colour: PooColour? = nil, consistency: PooConsistency? = nil) {
        self.wee = wee
        self.poo = poo
        self.colour = colour
        self.consistency = consistency
    }
}

/// A poo's colour. Open, like `EventKind`: a value from a newer app version is kept as it is,
/// and saved back unchanged.
public struct PooColour: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let brown: PooColour = "brown"
    public static let yellow: PooColour = "yellow"
    public static let green: PooColour = "green"
    /// Pale or white (R9 of `12-ai-insights-gauntlet.md`, 22 Nov 2026): the NHS asks parents to
    /// mention pale poo to a health visitor or GP. A fact, like the others; never a verdict.
    public static let pale: PooColour = "pale"
    public static let other: PooColour = "other"
    /// The colours this app version offers, in the order it shows them.
    public static let known: [PooColour] = [.brown, .yellow, .green, .pale, .other]
}

/// A poo's consistency. Open, like `PooColour`.
public struct PooConsistency: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let liquid: PooConsistency = "liquid"
    public static let loose: PooConsistency = "loose"
    public static let firm: PooConsistency = "firm"
    /// The consistencies this app version offers, in the order it shows them.
    public static let known: [PooConsistency] = [.liquid, .loose, .firm]
}

/// One growth measurement. Any of the three, in whole grams and millimetres, so the numbers are
/// exact on both phones; the screens show kilograms, pounds and ounces, or centimetres.
public struct GrowthDetails: Hashable, Sendable, Codable {
    public var weightGrams: Int?
    public var lengthMM: Int?
    public var headMM: Int?

    public init(weightGrams: Int? = nil, lengthMM: Int? = nil, headMM: Int? = nil) {
        self.weightGrams = weightGrams
        self.lengthMM = lengthMM
        self.headMM = headMM
    }

    /// No measurement at all. The app saves a growth entry only with at least one.
    public var isEmpty: Bool { weightGrams == nil && lengthMM == nil && headMM == nil }
}

/// A medicine or vitamin given. `name` comes from the household's own short list, such as
/// "Vitamin D". `amount` is the parents' own words ("1 drop", "2.5 ml"), never worked out by the
/// app: facts only, no doses.
public struct MedicineDetails: Hashable, Sendable, Codable {
    public var name: String
    public var amount: String?

    public init(name: String, amount: String? = nil) {
        self.name = name
        self.amount = amount
    }
}
