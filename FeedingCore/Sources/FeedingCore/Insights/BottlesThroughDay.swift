import Foundation

// "Bottles through the day" (Parent A, 26 Nov 2026, `docs/planning/14-bottles-through-the-day.md`):
// the bottles logged from midnight to now, beside the day before by the same clock time and the
// average of the 7 days before by the same clock time. Facts only: amounts and times, no targets,
// no "too much", no verdicts. A breastfeed has no amount, so only bottles add up; breastfeeds and
// bottles with no amount are counted beside it, so the page can say so.

/// One feed with a bottle in a day's running total, at the feed's start: the same feeds as "Bottles
/// each day"'s list (`GraphDayDetails.bottleFeeds`), so a bottle saved with no amount is a row too.
public struct BottleStep: Hashable, Sendable, Identifiable {
    /// The feed's ID.
    public var id: String
    public var at: Date
    /// Where the bottle sits on the day's clock, in seconds after midnight: the clock's own reading,
    /// so 15:20 is 15:20 on a day the clocks change. Only in the hour the clocks go back, which
    /// happens twice, is a bottle from the first time round put at the earliest later reading, so
    /// the day's bottles stay in the order they happened and today's never sit after now.
    public var clockSecond: Int
    /// The feed's bottle amounts, formula and expressed milk together; 0 when none has an amount.
    public var ml: Int
    /// From midnight to this bottle, this one included, in the order they happened.
    public var total: Int
}

/// One calendar day's bottles, midnight to midnight in the household's time zone.
public struct BottleDay: Hashable, Sendable {
    public var date: PlainDate
    /// In clock order (then start, then ID).
    public var steps: [BottleStep] = []

    /// The day's bottles up to and including `clockSecond` on its clock.
    public func total(by clockSecond: Int) -> Int {
        steps.lazy.filter { $0.clockSecond <= clockSecond }.map(\.ml).reduce(0, +)
    }

    /// Every bottle the day has.
    public var whole: Int { steps.last?.total ?? 0 }
}

/// A point on the average's line: from `clockSecond` on, the average total from midnight.
public struct AverageStep: Hashable, Sendable {
    public var clockSecond: Int
    public var ml: Double
}

/// What "Bottles through the day" shows for one day.
public struct BottlesThroughDay: Hashable, Sendable {
    public static let secondsInClockDay = 24 * 3600

    public var date: PlainDate
    public var isToday: Bool
    /// The clock time the day before and the average are read at: now on the household's clock
    /// for today, the end of the day for a day that is over.
    public var cutOff: Int
    public var day: BottleDay
    /// The day before, unless it is before the first feed or pump logged.
    public var dayBefore: BottleDay?
    /// Up to 7 whole days before `date`, the day before first. Days before the first feed or pump
    /// logged are left out, so a new household's average isn't pulled down by days it didn't log.
    public var week: [BottleDay]
    /// Feeds at the breast on the day (by now, today): they have no amount.
    public var breastFeeds = 0
    /// The breast sides' logged lengths on those feeds. A side still running adds nothing yet.
    public var breastSeconds = 0
    /// Bottles on the day logged with no amount.
    public var bottlesWithNoAmount = 0

    /// The day's total so far: today, every bottle logged by now (a bottle from the first 01:30 on
    /// the day the clocks go back is in it at 01:10, the second time round, and on the line by
    /// then too); a day that is over, the whole day.
    public var soFar: Int { day.whole }

    /// The day before at `cutOff` on its clock.
    public var dayBeforeByCutOff: Int? { dayBefore?.total(by: cutOff) }

    /// The 7 days' average at `clockSecond`, or nil with no days before this one.
    public func average(by clockSecond: Int) -> Double? {
        guard !week.isEmpty else { return nil }
        return Double(week.map { $0.total(by: clockSecond) }.reduce(0, +)) / Double(week.count)
    }

    /// The average at `cutOff`.
    public var averageByCutOff: Double? { average(by: cutOff) }

    /// The average as a step line from midnight: a point at midnight, then one at each clock time a
    /// bottle was given on one of the week's days. Empty with no days before this one.
    public var averageSteps: [AverageStep] {
        guard !week.isEmpty else { return [] }
        let times = Set(week.flatMap { $0.steps.map(\.clockSecond) }).sorted()
        return [AverageStep(clockSecond: 0, ml: 0)]
            + times.map { AverageStep(clockSecond: $0, ml: average(by: $0) ?? 0) }
    }

    /// Whether any of these days has a bottle, with an amount or not: with none, Home and Graphs
    /// leave it out.
    public var hasBottles: Bool {
        !day.steps.isEmpty || dayBefore.map { !$0.steps.isEmpty } == true || week.contains { !$0.steps.isEmpty }
    }

    /// The days the page can step through: the first day with a feed or pump logged up to today.
    public var firstDate: PlainDate
    public var today: PlainDate
}

/// "Bottles through the day" for `date` (today when nil), or nil when nothing is logged yet or the
/// day is outside the first feed or pump's day to today. Days run midnight to midnight in
/// `timeZone` (the household's), as on the Graphs tab, whatever the phone's own clock says. Pass
/// `visibleSnapshots`, so a feed logged on both phones counts once; deleted feeds, other babies and
/// anything that starts after `now` (a clock set back) are left out, as in `graphDays`.
public func bottlesThroughDay(_ snapshots: [EventSnapshot], babyID: String, timeZone: TimeZone,
                              date wanted: PlainDate? = nil, now: Date) -> BottlesThroughDay? {
    let live = graphSnapshots(snapshots, babyID: babyID, now: now)
    guard let first = live.map(\.event.startedAt).min() else { return nil }
    let today = PlainDate(now, in: timeZone)
    let firstDate = PlainDate(first, in: timeZone)
    let date = wanted ?? today
    guard date >= firstDate, date <= today else { return nil }

    let calendar = WallClock.calendar(timeZone)
    func clockSecond(_ instant: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: instant)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    // Every feed, by its day.
    var feedsByDay: [PlainDate: [EventSnapshot]] = [:]
    for snapshot in live where snapshot.event.kind == .feed {
        feedsByDay[PlainDate(snapshot.event.startedAt, in: timeZone), default: []].append(snapshot)
    }

    let isToday = date == today
    let cutOff = isToday ? clockSecond(now) : BottlesThroughDay.secondsInClockDay - 1

    func bottleDay(_ day: PlainDate) -> BottleDay {
        var steps: [BottleStep] = []
        for snapshot in feedsByDay[day] ?? [] {
            guard let feed = snapshot.payload?.feed, !feed.bottles.isEmpty else { continue }
            steps.append(BottleStep(id: snapshot.id, at: snapshot.event.startedAt,
                                    clockSecond: clockSecond(snapshot.event.startedAt),
                                    ml: feed.ml(of: .formula) + feed.ml(of: .expressed), total: 0))
        }
        // In the order they happened, each no later on the clock than the ones after it (only the
        // hour the clocks go back reads out of order) and, today, than now.
        steps.sort { ($0.at, $0.id) < ($1.at, $1.id) }
        var latest = day == today ? cutOff : Int.max
        for i in steps.indices.reversed() {
            steps[i].clockSecond = min(steps[i].clockSecond, latest)
            latest = steps[i].clockSecond
        }
        var total = 0
        for i in steps.indices {
            total += steps[i].ml
            steps[i].total = total
        }
        return BottleDay(date: day, steps: steps)
    }

    var result = BottlesThroughDay(
        date: date, isToday: isToday,
        cutOff: cutOff,
        day: bottleDay(date),
        dayBefore: date > firstDate ? bottleDay(date.adding(days: -1)) : nil,
        week: (1...7).map { date.adding(days: -$0) }.filter { $0 >= firstDate }.map(bottleDay),
        firstDate: firstDate, today: today)

    for snapshot in feedsByDay[date] ?? [] {
        guard let feed = snapshot.payload?.feed else { continue }
        if !feed.breast.isEmpty {
            result.breastFeeds += 1
            result.breastSeconds += feed.breast.map { max(0, $0.durationSeconds ?? 0) }.reduce(0, +)
        }
        result.bottlesWithNoAmount += feed.bottles.filter { $0.ml == nil }.count
    }
    return result
}
