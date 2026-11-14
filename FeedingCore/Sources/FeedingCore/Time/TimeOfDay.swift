import Foundation

/// A wall-clock time of day, such as 21:00, with minute precision.
public struct TimeOfDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// 0 ..< 1440.
    public let minutesSinceMidnight: Int

    /// Returns nil outside 00:00 ... 23:59.
    public init?(hour: Int, minute: Int = 0) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        minutesSinceMidnight = hour * 60 + minute
    }

    /// Parses "HH:mm".
    public init?(_ string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1])
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var hour: Int { minutesSinceMidnight / 60 }
    public var minute: Int { minutesSinceMidnight % 60 }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    /// "HH:mm".
    public var description: String {
        let h = hour < 10 ? "0\(hour)" : "\(hour)"
        let m = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(h):\(m)"
    }
}

extension TimeOfDay: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let time = TimeOfDay(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an HH:mm time: \(string)")
        }
        self = time
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Reads the local date and time of an instant in a given time zone.
///
/// Going from an instant to a wall-clock reading is always well defined, even when the clocks
/// change. Going the other way is not (02:30 may not exist, 01:30 may happen twice), so day and
/// night are always decided by reading the clock at an instant, never by building an instant from
/// a wall-clock time.
enum WallClock {
    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func reading(_ date: Date, in timeZone: TimeZone) -> (date: PlainDate, time: TimeOfDay) {
        let parts = calendar(timeZone).dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = PlainDate(julianDay: PlainDate.julianDay(year: parts.year!, month: parts.month!, day: parts.day!))
        return (day, TimeOfDay(hour: parts.hour!, minute: parts.minute!)!)
    }
}
