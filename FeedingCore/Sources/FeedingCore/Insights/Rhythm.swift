import Foundation

// Sleep and nappies (`docs/planning/06-more-than-feeds.md`): the facts behind Home's Sleep and
// Nappy tiles and the daily rhythm report on the Graphs tab. Facts only: how long, how many and
// when. No targets and no verdicts. None of it affects the alerts: `reconcile` counts feeds only.

// MARK: - Home's tiles

/// Asleep or awake, for Home's Sleep tile.
public enum SleepState: Hashable, Sendable {
    /// No sleep logged yet.
    case notLogged
    /// Asleep since `since`. `id` is the running sleep, which "Woke up" ends.
    case asleep(id: String, since: Date)
    /// Awake since the last sleep ended.
    case awake(since: Date)
}

/// The sleep that started last decides: running (no end yet, or an end after `now`, as when the
/// clock was set back) means asleep, otherwise awake since it ended. Deleted sleeps, other babies
/// and sleeps that start after `now` are left out.
public func sleepState(_ snapshots: [EventSnapshot], babyID: String, now: Date) -> SleepState {
    let sleeps = liveSleeps(snapshots.map(\.event), babyID: babyID, now: now)
    guard let last = sleeps.last else { return .notLogged }
    if let end = last.endedAt, end <= now { return .awake(since: end) }
    return .asleep(id: last.id, since: last.startedAt)
}

/// One nappy change, for Home's Nappy tile and the report.
public struct NappyChange: Hashable, Sendable, Identifiable {
    public var id: String
    public var at: Date
    /// Nil when a newer app version wrote the details: it still counts as a change.
    public var details: NappyDetails?

    public var wee: Bool { details?.wee ?? false }
    public var poo: Bool { details?.poo ?? false }
}

/// The latest nappy change of `babyID` up to `now`, or nil when none is logged.
public func lastNappy(_ snapshots: [EventSnapshot], babyID: String, now: Date) -> NappyChange? {
    nappyChanges(snapshots, babyID: babyID, from: .distantPast, to: now).last
}

/// The nappy changes of `babyID` from `start` up to (not including) `end`, oldest first. Deleted
/// ones and other babies are left out. A dry nappy counts as a change but as neither wee nor poo.
public func nappyChanges(_ snapshots: [EventSnapshot], babyID: String, from start: Date, to end: Date) -> [NappyChange] {
    snapshots.compactMap { snapshot -> NappyChange? in
        let event = snapshot.event
        guard event.kind == .nappy, event.deletedAt == nil, event.babyID == babyID,
              event.startedAt >= start, event.startedAt <= end else { return nil }
        return NappyChange(id: event.id, at: event.startedAt, details: snapshot.payload?.nappy)
    }
    .sorted { ($0.at, $0.id) < ($1.at, $1.id) }
}

// MARK: - The daily rhythm report

/// One sleep on one day's row: cut to the day, and to `now`.
public struct RhythmSleep: Hashable, Sendable, Identifiable {
    public var id: String
    public var start: Date
    public var end: Date
    /// Began on an earlier day, so the bar runs on from the left edge.
    public var fromDayBefore: Bool
    /// Goes on into the next day, so the bar runs off the right edge.
    public var intoNextDay: Bool
    /// Still asleep now.
    public var running: Bool
    /// The whole sleep, from when it started to when it ended (or now, or the next sleep's
    /// start), for a graph's page: "22:30 Mon, to 03:10".
    public var spanStart: Date
    public var spanEnd: Date
}

/// One calendar day of the daily rhythm report (the users' choice D, 17 Nov 2026): midnight to
/// midnight in the household's time zone, like the other graphs, so a night is split across two
/// rows.
public struct RhythmDay: Hashable, Sendable, Identifiable {
    public var date: PlainDate
    /// Today is not over, so the screen draws it lighter.
    public var isToday: Bool
    /// This day's first moment, and the next day's. 23 or 25 hours apart when the clocks change.
    public var start: Date
    public var end: Date
    public var sleeps: [RhythmSleep] = []
    /// The feeds that started on this day (a tick at each start).
    public var feeds: [DayChartFeed] = []
    public var nappies: [NappyChange] = []
    /// Time asleep in the household's night hours (21:00 to 07:00 by default), and in the day.
    /// Sleeps logged on both phones at once overlap; the overlap counts once.
    public var nightSleepSeconds: TimeInterval = 0
    public var daySleepSeconds: TimeInterval = 0

    public init(date: PlainDate, isToday: Bool, start: Date, end: Date) {
        self.date = date
        self.isToday = isToday
        self.start = start
        self.end = end
    }

    public var id: PlainDate { date }
    public var sleepSeconds: TimeInterval { nightSleepSeconds + daySleepSeconds }
    /// A nappy with both counts once in each.
    public var wees: Int { nappies.filter(\.wee).count }
    public var poos: Int { nappies.filter(\.poo).count }
}

/// The rows of the daily rhythm report, oldest first, ending today. A day is the household's
/// calendar day in `timeZone`, wherever the phone was. The rows start no earlier than the first
/// feed, sleep or nappy. Deleted events, other babies and anything that starts after `now` are
/// left out; pass `visibleSnapshots`, so a feed logged on both phones counts once.
///
/// A sleep with no end runs to `now`, unless a later sleep started (a "Woke up" that never came,
/// such as two phones that each tapped "Fell asleep"): then it runs to that later start.
public func rhythmDays(_ snapshots: [EventSnapshot], babyID: String, timeZone: TimeZone, dayHours: DayHours,
                       range: GraphRange, now: Date) -> [RhythmDay] {
    let live = snapshots.filter {
        $0.event.deletedAt == nil && $0.event.babyID == babyID && $0.event.startedAt <= now
            && [EventKind.feed, .sleep, .nappy].contains($0.event.kind)
    }
    guard let first = live.map(\.event.startedAt).min() else { return [] }
    let today = PlainDate(now, in: timeZone)
    let firstDay = PlainDate(first, in: timeZone)
    let startDay = max(firstDay, range.days.map { today.adding(days: 1 - $0) } ?? firstDay)
    let count = today.days(since: startDay) + 1
    guard count > 0 else { return [] }

    let sleeps = sleepSpans(live.map(\.event), babyID: babyID, now: now)
    let feeds = dayChart(live, babyID: babyID, now: now, hours: now.timeIntervalSince(first) / 3600)
    let nappies = nappyChanges(live, babyID: babyID, from: .distantPast, to: now)

    return (0..<count).map { offset in
        let date = startDay.adding(days: offset)
        var day = RhythmDay(date: date, isToday: offset == count - 1,
                            start: date.firstMoment(in: timeZone), end: date.adding(days: 1).firstMoment(in: timeZone))
        let to = min(day.end, now)
        var pieces: [(Date, Date)] = []
        for span in sleeps where span.start < to && span.end > day.start {
            let piece = (max(span.start, day.start), min(span.end, to))
            guard piece.1 > piece.0 else { continue }
            pieces.append(piece)
            day.sleeps.append(RhythmSleep(id: span.id, start: piece.0, end: piece.1, fromDayBefore: span.start < day.start,
                                          intoNextDay: span.end > day.end, running: span.running,
                                          spanStart: span.start, spanEnd: span.end))
        }
        for (from, upTo) in union(pieces) {
            let split = dayHours.nightAndDaySeconds(from: from, to: upTo, in: timeZone)
            day.nightSleepSeconds += split.night
            day.daySleepSeconds += split.day
        }
        day.feeds = feeds.filter { $0.startedAt >= day.start && $0.startedAt < day.end }
        day.nappies = nappies.filter { $0.at >= day.start && $0.at < day.end }
        return day
    }
}

/// A sleep from its start to where it ends on the report.
struct SleepSpan: Hashable, Sendable {
    var id: String
    var start: Date
    var end: Date
    var running: Bool
}

/// The live sleeps of `babyID` that started by `now`, in the order they started.
func liveSleeps(_ events: [Event], babyID: String, now: Date) -> [Event] {
    events.filter { $0.kind == .sleep && $0.deletedAt == nil && $0.babyID == babyID && $0.startedAt <= now }
        .sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
}

/// Each live sleep's span. An end after `now` (a clock set back) is cut to `now`. A sleep with no
/// end runs to `now`, or to the start of the next sleep when one started later.
func sleepSpans(_ events: [Event], babyID: String, now: Date) -> [SleepSpan] {
    let sleeps = liveSleeps(events, babyID: babyID, now: now)
    return sleeps.enumerated().map { index, sleep in
        let next = sleeps[(index + 1)...].first { $0.startedAt > sleep.startedAt }?.startedAt
        let end = sleep.endedAt ?? next ?? now
        return SleepSpan(id: sleep.id, start: sleep.startedAt, end: max(sleep.startedAt, min(end, now)),
                         running: sleep.endedAt == nil && next == nil)
    }
}

/// Overlapping stretches joined into one, oldest first.
func union(_ pieces: [(Date, Date)]) -> [(Date, Date)] {
    var joined: [(Date, Date)] = []
    for piece in pieces.sorted(by: { $0.0 < $1.0 }) {
        if let last = joined.last, piece.0 <= last.1 {
            joined[joined.count - 1].1 = max(last.1, piece.1)
        } else {
            joined.append(piece)
        }
    }
    return joined
}

extension DayHours {
    /// The time from `start` to `end` that falls in the night hours, and in the day, on the
    /// household's wall clock. Split at each change of look, which already allows for clock
    /// changes, so the two always add up to the real time.
    public func nightAndDaySeconds(from start: Date, to end: Date, in timeZone: TimeZone) -> (night: TimeInterval, day: TimeInterval) {
        var night: TimeInterval = 0
        var day: TimeInterval = 0
        var from = start
        while from < end {
            var next = nextLookChange(after: from, in: timeZone) ?? end
            if next <= from { next = end }
            let upTo = min(next, end)
            if look(at: from, in: timeZone) == .night {
                night += upTo.timeIntervalSince(from)
            } else {
                day += upTo.timeIntervalSince(from)
            }
            from = upTo
        }
        return (night, day)
    }
}

extension PlainDate {
    /// The first moment of this date in `timeZone`: midnight, or the first moment after it where a
    /// clock change skips midnight. Found from noon, which every date has.
    public func firstMoment(in timeZone: TimeZone) -> Date {
        let calendar = WallClock.calendar(timeZone)
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
            ?? Date(timeIntervalSince1970: Double(julianDay - 2_440_588) * 86_400 + 43_200 - Double(timeZone.secondsFromGMT()))
        return calendar.startOfDay(for: noon)
    }
}
