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
public struct EventPayload: VersionedPayload, Hashable {
    public static let currentVersion = 1

    public var v: Int
    /// Set for feeds.
    public var feed: FeedDetails?
    /// Set for pumping sessions.
    public var pump: PumpDetails?
    public var note: String?
    /// The stamp of each field's last change, keyed by `EventField` raw value. String keys, so a
    /// field added by a newer app doesn't stop an older one from decoding the rest.
    public var stamps: [String: FieldStamp]

    public init(feed: FeedDetails? = nil, pump: PumpDetails? = nil, note: String? = nil, stamps: [String: FieldStamp] = [:]) {
        v = Self.currentVersion
        self.feed = feed
        self.pump = pump
        self.note = note
        self.stamps = stamps
    }

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
    /// A named colour from the app's palette, such as "amber".
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
