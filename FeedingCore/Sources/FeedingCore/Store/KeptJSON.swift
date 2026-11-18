import Foundation

// Step 0 of the milestones journal (CEO review D18, 18 Nov 2026): a phone put back on an older
// build reads the household file a newer build wrote. What it doesn't know (a field name, a kind of
// record, a whole entry, a new part of the file) is skipped and kept exactly as it was, so the
// newer build gets it back. Before this, one unknown value made the whole file unreadable: the
// phone started empty and cancelled its alarms.

/// A piece of the household file this build couldn't read, kept as plain JSON and written back
/// unchanged.
public enum KeptJSON: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    /// Whole numbers stay whole, so a date in milliseconds comes back exactly.
    case integer(Int64)
    /// A whole number above `Int64.max`.
    case unsigned(UInt64)
    /// A number with a fraction, kept to its written digits (up to 38 of them).
    case decimal(Decimal)
    /// Any other number: one too big or too small for `Decimal`.
    case number(Double)
    case string(String)
    case array([KeptJSON])
    case object([String: KeptJSON])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsigned(value)
        } else if let value = try? container.decode(Decimal.self), value.isFinite {
            self = .decimal(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([KeptJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: KeptJSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .unsigned(let value): try container.encode(value)
        case .decimal(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// One entry of the file: read if this build can, otherwise kept as it was.
enum Lenient<Value: Codable>: Codable {
    case read(Value)
    case kept(KeptJSON)

    init(from decoder: any Decoder) throws {
        do {
            self = .read(try Value(from: decoder))
        } catch {
            self = .kept(try KeptJSON(from: decoder))
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .read(let value): try value.encode(to: encoder)
        case .kept(let json): try json.encode(to: encoder)
        }
    }
}

/// A coding key for any name, for the parts of the file a newer build added.
struct AnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
