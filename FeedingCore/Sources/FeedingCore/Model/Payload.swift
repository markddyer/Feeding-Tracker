import Foundation

/// When a field was last changed, and by whom. Orders two phones' edits of the same field: the
/// later time wins, and the member ID breaks a tie, so both phones pick the same winner.
public struct FieldStamp: Hashable, Sendable, Codable, Comparable {
    public var at: Date
    public var by: MemberID

    public init(at: Date, by: MemberID) {
        self.at = at
        self.by = by
    }

    public static func < (lhs: FieldStamp, rhs: FieldStamp) -> Bool {
        (lhs.at, lhs.by) < (rhs.at, rhs.by)
    }
}

/// The parts of an event that the two phones can change separately. The first three are
/// top-level record fields; the rest live in the encrypted payload.
public enum EventField: String, Hashable, Sendable, Codable, CaseIterable {
    case startedAt
    case endedAt
    case deletedAt
    case breast
    case bottles
    case pump
    case note
    /// A nappy's wee and poo, as one choice.
    case nappy
    /// A poo's colour and its consistency, each on its own: both are added after the tap, perhaps
    /// one on each phone.
    case pooColour
    case pooConsistency
    /// A growth entry's three measurements, each on its own, so one parent can add the head while
    /// the other corrects the weight.
    case weight
    case length
    case head
    /// A medicine's name and amount, as one.
    case medicine
    /// A first's title.
    case title
    /// A first's ordered list of photos and videos, as one: the later change wins.
    case media
    /// A first's removed photos and videos. Merged by joining both phones' lists, never by the
    /// later change (eng D10), so a removed item can't come back.
    case removedMedia

    /// The fields an event of `kind` has: the top-level ones, the note, and its own details. A new
    /// event is stamped with these only, so a feed's record holds no field an older app version
    /// can't name. Every field for a kind this app doesn't know.
    public static func fields(for kind: EventKind) -> Set<EventField> {
        let shared: Set<EventField> = [.startedAt, .endedAt, .deletedAt, .note]
        switch kind {
        case .feed: return shared.union([.breast, .bottles])
        case .pump: return shared.union([.pump])
        case .sleep: return shared
        case .nappy: return shared.union([.nappy, .pooColour, .pooConsistency])
        case .growth: return shared.union([.weight, .length, .head])
        case .medicine: return shared.union([.medicine])
        case .milestone: return shared.union([.title, .media, .removedMedia])
        default: return Set(allCases)
        }
    }
}

/// A payload with a format version. A phone never reads, and so never edits, a payload whose
/// version is higher than its own.
///
/// **Rule for later versions:** adding a field that matters means raising `currentVersion`.
/// An older app that decoded the payload and saved it again would drop the field it doesn't know.
public protocol VersionedPayload: Codable, Sendable {
    static var currentVersion: Int { get }
    var v: Int { get }
}

/// The encrypted details of an `Event`.
///
/// A payload is written with the lowest version that holds its fields (`neededVersion`), not
/// always with `currentVersion`. So a feed saved by this app is still version 1, and a phone on an
/// older build still reads its sides and bottles; only a nappy, growth or medicine entry is
/// version 2, and a first version 3, which an older build leaves unread and so can never save back
/// without its details.
public struct EventPayload: VersionedPayload, Hashable {
    /// 1: feeds and pumping. 2 (17 Nov 2026): adds `nappy`, `growth` and `medicine`. 3 (18 Nov
    /// 2026): adds `milestone`.
    public static let currentVersion = 3

    public var v: Int
    /// Set for feeds.
    public var feed: FeedDetails?
    /// Set for pumping sessions.
    public var pump: PumpDetails?
    /// Set for nappy changes. Version 2.
    public var nappy: NappyDetails? { didSet { raiseVersion() } }
    /// Set for growth entries. Version 2.
    public var growth: GrowthDetails? { didSet { raiseVersion() } }
    /// Set for medicines. Version 2.
    public var medicine: MedicineDetails? { didSet { raiseVersion() } }
    /// Set for firsts. Version 3.
    public var milestone: MilestoneDetails? { didSet { raiseVersion() } }
    public var note: String?
    /// The stamp of each field's last change, keyed by `EventField` raw value. String keys, so a
    /// field added by a newer app doesn't stop an older one from decoding the rest.
    public var stamps: [String: FieldStamp]

    public init(feed: FeedDetails? = nil, pump: PumpDetails? = nil, nappy: NappyDetails? = nil,
                growth: GrowthDetails? = nil, medicine: MedicineDetails? = nil, milestone: MilestoneDetails? = nil,
                note: String? = nil, stamps: [String: FieldStamp] = [:]) {
        v = 1
        self.feed = feed
        self.pump = pump
        self.nappy = nappy
        self.growth = growth
        self.medicine = medicine
        self.milestone = milestone
        self.note = note
        self.stamps = stamps
        v = neededVersion
    }

    /// The lowest version that knows every detail set here: 3 with a first, 2 with a nappy,
    /// growth or medicine, otherwise 1.
    public var neededVersion: Int {
        if milestone != nil { return 3 }
        return nappy == nil && growth == nil && medicine == nil ? 1 : 2
    }

    /// Setting a version 2 detail on a version 1 payload raises it. It never goes down.
    private mutating func raiseVersion() { v = max(v, neededVersion) }

    public func stamp(_ field: EventField) -> FieldStamp? { stamps[field.rawValue] }

    public mutating func setStamp(_ field: EventField, _ stamp: FieldStamp) { stamps[field.rawValue] = stamp }
}

/// The encrypted details of a `Baby` record.
public struct BabyPayload: VersionedPayload, Hashable {
    public static let currentVersion = 1

    public var v: Int
    public var name: String
    public var birthDate: PlainDate?

    public init(name: String, birthDate: PlainDate? = nil) {
        v = Self.currentVersion
        self.name = name
        self.birthDate = birthDate
    }
}

/// The encrypted details of a `Member` record: how a parent appears in the app.
public struct MemberPayload: VersionedPayload, Hashable {
    public static let currentVersion = 1

    public var v: Int
    public var displayName: String
    /// A named colour from the app's palette, such as "sunflower" (`ParentColour` in the app).
    public var colour: String

    public init(displayName: String, colour: String) {
        v = Self.currentVersion
        self.displayName = displayName
        self.colour = colour
    }
}

/// Encodes payloads as JSON with sorted keys and millisecond dates, so both phones and both
/// platforms produce the same bytes for the same value.
public enum PayloadCoder {
    public static func encode<T: VersionedPayload>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    /// Nil when there is no payload, it can't be read, or a newer app version wrote it.
    public static func decode<T: VersionedPayload>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let probe = try? decoder.decode(VersionProbe.self, from: data), probe.v <= T.currentVersion else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private struct VersionProbe: Decodable {
        var v: Int
    }
}
