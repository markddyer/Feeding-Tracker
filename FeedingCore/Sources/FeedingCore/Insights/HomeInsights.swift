import Foundation

// The facts behind the home screen's pictures (`docs/planning/05-visual-redesign.md`): the
// greeting, the baby's age, the 24-hour chart and the row of nights. None of it affects alerts.

/// The part of the day, for the greeting at the top of the home screen.
public enum PartOfDay: Hashable, Sendable, CaseIterable {
    case morning
    case afternoon
    case evening
    /// The household's night hours (the rota's), so the greeting and the night look agree.
    case night
}

extension DayHours {
    /// Night during the night hours. Otherwise morning until 12:00, afternoon until 17:00, then
    /// evening, on the household's wall clock.
    public func partOfDay(at date: Date, in timeZone: TimeZone) -> PartOfDay {
        if case .night = period(at: date, in: timeZone) { return .night }
        let time = WallClock.reading(date, in: timeZone).time
        if time.hour < 12 { return .morning }
        if time.hour < 17 { return .afternoon }
        return .evening
    }
}

extension BabyPayload {
    /// Whole days since the birth date, on the household's calendar: 0 on the day of birth. Nil
    /// with no birth date, or with one after `date` (a phone clock set back).
    public func ageInDays(at date: Date, in timeZone: TimeZone) -> Int? {
        guard let birthDate else { return nil }
        let days = PlainDate(date, in: timeZone).days(since: birthDate)
        return days >= 0 ? days : nil
    }
}

extension PlainDate {
    /// The day of the week, 1 for Monday to 7 for Sunday (ISO 8601).
    public var weekday: Int {
        // Julian day 0 was a Monday.
        ((julianDay % 7) + 7) % 7 + 1
    }
}

/// One feed on the 24-hour chart.
public struct DayChartFeed: Hashable, Sendable, Identifiable {
    public var id: String
    public var startedAt: Date
    /// From start to end, or to now while the feed runs.
    public var duration: TimeInterval
    /// At least one breast segment.
    public var breast: Bool
    /// At least one bottle.
    public var bottle: Bool
    /// The feed is still running.
    public var running: Bool
}

/// The feeds of `babyID` that started in the `hours` up to `now`, both ends included (the same
/// stretch as `summarise`), oldest first. Deleted feeds and pumping sessions are left out. A feed
/// whose details this app version can't read shows with neither breast nor bottle set.
public func dayChart(_ snapshots: [EventSnapshot], babyID: String, now: Date, hours: Double = 24) -> [DayChartFeed] {
    let start = now.addingTimeInterval(-hours * 3600)
    return snapshots.compactMap { snapshot -> DayChartFeed? in
        let event = snapshot.event
        guard event.isLiveFeed, event.babyID == babyID, event.startedAt >= start, event.startedAt <= now else { return nil }
        let feed = snapshot.payload?.feed
        let end = event.endedAt ?? now
        return DayChartFeed(id: event.id, startedAt: event.startedAt, duration: max(0, end.timeIntervalSince(event.startedAt)),
                            breast: !(feed?.breast.isEmpty ?? true), bottle: !(feed?.bottles.isEmpty ?? true),
                            running: event.endedAt == nil)
    }
    .sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
}

/// Who is on duty one night, for the row of nights.
public struct NightDuty: Hashable, Sendable {
    public var night: PlainDate
    /// Nil when there is no rota yet and no one has taken the night.
    public var onDuty: MemberID?
}

extension HouseholdState {
    /// Who is on duty from `before` nights before `tonight` to `after` nights after it, oldest
    /// first. For the screen only: with no rota, a night nobody took shows as nobody, while
    /// `roster(for:)` counts this phone as on duty so that nothing goes quiet.
    public func nights(around tonight: PlainDate, before: Int, after: Int) -> [NightDuty] {
        (-before...after).map { offset in
            let night = tonight.adding(days: offset)
            return NightDuty(night: night, onDuty: onDuty(night: night))
        }
    }
}
