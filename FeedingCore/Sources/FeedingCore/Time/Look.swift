import Foundation

/// The app's two looks (DESIGN.md, "Day and night"): warm and bright by day, dim at night.
public enum Look: String, Hashable, Sendable {
    case day
    case night
}

/// Each phone's own choice of look, in Settings. Kept on the phone; the other phone has its own.
public enum LookSetting: String, Hashable, Sendable, CaseIterable, Codable {
    /// The night look during the household's night hours (the same hours as the night rota), and
    /// the day look the rest of the time. The default.
    case automatic
    /// The day look all the time, at night too (the user's choice, 16 Nov 2026).
    case alwaysDay
    case alwaysNight
    /// Follows the phone's own Dark Mode.
    case matchPhone
}

/// The look to show now, and when it next changes by itself.
public struct LookResolution: Hashable, Sendable {
    public var look: Look
    /// The next moment the look changes by itself. Nil when only the setting, the household's
    /// hours or the phone's own Dark Mode can change it.
    public var nextChange: Date?

    public init(look: Look, nextChange: Date?) {
        self.look = look
        self.nextChange = nextChange
    }
}

extension LookSetting {
    /// The look at `now`. Pure: the same inputs always give the same answer, so a clock that is
    /// set back simply gives the look for the new time.
    public func resolve(dayHours: DayHours, timeZone: TimeZone, phoneIsDark: Bool, now: Date) -> LookResolution {
        switch self {
        case .alwaysDay:
            LookResolution(look: .day, nextChange: nil)
        case .alwaysNight:
            LookResolution(look: .night, nextChange: nil)
        case .matchPhone:
            LookResolution(look: phoneIsDark ? .night : .day, nextChange: nil)
        case .automatic:
            LookResolution(look: dayHours.look(at: now, in: timeZone),
                           nextChange: dayHours.nextLookChange(after: now, in: timeZone))
        }
    }
}

extension DayHours {
    /// The night look during the night hours, read on the household's wall clock.
    public func look(at date: Date, in timeZone: TimeZone) -> Look {
        if case .night = period(at: date, in: timeZone) { return .night }
        return .day
    }

    /// The first moment after `date` when `look(at:in:)` changes. Nil when there is no night.
    ///
    /// Between two clock changes the wall clock moves in step with real time, so the next
    /// boundary is a sum. A clock change can move the wall clock past a boundary, or back before
    /// one, so the look is checked at each clock change on the way.
    public func nextLookChange(after date: Date, in timeZone: TimeZone) -> Date? {
        guard dayStart != nightStart else { return nil }
        let current = look(at: date, in: timeZone)
        let boundary = current == .night ? dayStart : nightStart
        // Whole seconds, so the answer reads exactly on the boundary on any platform.
        var from = date.timeIntervalSince1970.rounded(.down)
        // Each pass either answers or moves past one clock change. Two years of changes is more
        // than enough for any time zone.
        for _ in 0..<8 {
            let fromDate = Date(timeIntervalSince1970: from)
            let wallSeconds = Int(from) + timeZone.secondsFromGMT(for: fromDate)
            let secondOfDay = ((wallSeconds % 86_400) + 86_400) % 86_400
            var wait = (boundary.minutesSinceMidnight * 60 - secondOfDay + 86_400) % 86_400
            if wait == 0 { wait = 86_400 }
            let candidate = Date(timeIntervalSince1970: from + Double(wait))
            guard let clockChange = timeZone.nextDaylightSavingTimeTransition(after: fromDate),
                  clockChange <= candidate
            else { return candidate }
            if look(at: clockChange, in: timeZone) != current { return clockChange }
            from = clockChange.timeIntervalSince1970.rounded(.down)
        }
        return nil
    }
}
