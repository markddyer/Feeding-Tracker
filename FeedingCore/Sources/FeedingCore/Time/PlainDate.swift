import Foundation

/// A calendar date with no time of day and no time zone, such as the date a night starts on.
///
/// Day arithmetic uses Julian day numbers, so it never meets a clock change or a time zone.
public struct PlainDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns nil for a date that doesn't exist, such as 2026-02-30.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), (1...31).contains(day), (1...9999).contains(year) else { return nil }
        let candidate = PlainDate(julianDay: PlainDate.julianDay(year: year, month: month, day: day))
        guard candidate.year == year, candidate.month == month, candidate.day == day else { return nil }
        self = candidate
    }

    /// Parses "YYYY-MM-DD".
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The local calendar date of `date` in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone) {
        let parts = WallClock.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(julianDay: PlainDate.julianDay(year: parts.year!, month: parts.month!, day: parts.day!))
    }

    init(julianDay j: Int) {
        let a = j + 32044
        let b = (4 * a + 3) / 146_097
        let c = a - 146_097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        day = e - (153 * m + 2) / 5 + 1
        month = m + 3 - 12 * (m / 10)
        year = 100 * b + d - 4800 + m / 10
    }

    var julianDay: Int { PlainDate.julianDay(year: year, month: month, day: day) }

    static func julianDay(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    public func adding(days: Int) -> PlainDate { PlainDate(julianDay: julianDay + days) }

    /// Whole days from `other` to `self`; negative when `self` is earlier.
    public func days(since other: PlainDate) -> Int { julianDay - other.julianDay }

    public static func < (lhs: PlainDate, rhs: PlainDate) -> Bool { lhs.julianDay < rhs.julianDay }

    /// "YYYY-MM-DD".
    public var description: String {
        func pad(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }
}

extension PlainDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = PlainDate(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a YYYY-MM-DD date: \(string)")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
