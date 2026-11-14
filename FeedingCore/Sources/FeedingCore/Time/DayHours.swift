import Foundation

/// Whether an instant is in the day or in a night.
public enum Period: Hashable, Sendable {
    /// Daytime on this local date.
    case day(PlainDate)
    /// A night, named by the local date it starts on.
    case night(PlainDate)
}

/// The shared daytime hours. Everything outside them is night.
public struct DayHours: Hashable, Sendable, Codable {
    public var dayStart: TimeOfDay
    public var nightStart: TimeOfDay

    public init(dayStart: TimeOfDay, nightStart: TimeOfDay) {
        self.dayStart = dayStart
        self.nightStart = nightStart
    }

    /// 07:00 to 21:00.
    public static let standard = DayHours(dayStart: TimeOfDay(hour: 7)!, nightStart: TimeOfDay(hour: 21)!)

    /// True when the night runs past midnight (the usual case, such as 21:00 to 07:00).
    var nightCrossesMidnight: Bool { nightStart > dayStart }

    /// Day or night at `date`, read on the household's wall clock.
    ///
    /// When `dayStart` equals `nightStart` there is no night, so both phones alert all the time.
    public func period(at date: Date, in timeZone: TimeZone) -> Period {
        let (day, time) = WallClock.reading(date, in: timeZone)
        if nightStart == dayStart { return .day(day) }
        if nightCrossesMidnight {
            if time >= nightStart { return .night(day) }
            if time < dayStart { return .night(day.adding(days: -1)) }
            return .day(day)
        }
        if time >= nightStart && time < dayStart { return .night(day) }
        return .day(day)
    }

    /// The night that ends when the day starts on `date`.
    public func nightEnding(on date: PlainDate) -> PlainDate {
        nightCrossesMidnight ? date.adding(days: -1) : date
    }
}
