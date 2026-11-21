import FeedingCore
import Foundation

/// The words on the Graphs tab: the days under the bars and the sentences VoiceOver reads. Facts
/// only, as on Home (no "due", "missed", targets or verdicts).
enum GraphText {
    /// Midday on `day` in `zone`, only to write the day's name (never to decide anything).
    static func midday(_ day: PlainDate, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? Date()
    }

    /// Under a bar: "Tue" for a week, "10 Nov" for longer; "Today" for today.
    static func axisLabel(_ day: GraphDay, in zone: TimeZone, week: Bool) -> String {
        if day.isToday { return "Today" }
        var style = Date.FormatStyle(timeZone: zone)
        style = week ? style.weekday(.abbreviated) : style.day().month(.abbreviated)
        return midday(day.date, in: zone).formatted(style)
    }

    /// The days that get a label: every day in a week; otherwise today and every `step` days back,
    /// about five labels across.
    static func labelled(_ days: [GraphDay]) -> [GraphDay] {
        guard days.count > 7 else { return days }
        let step = max(7, Int((Double(days.count) / 5 / 7).rounded(.up)) * 7)
        return days.enumerated().filter { (days.count - 1 - $0.offset) % step == 0 }.map(\.element)
    }

    /// "Tuesday 10 November", or "Today".
    static func spokenDay(_ day: GraphDay, in zone: TimeZone) -> String {
        if day.isToday { return "Today" }
        let style = Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.wide)
        return midday(day.date, in: zone).formatted(style)
    }

    static func feeds(_ count: Int) -> String { count == 1 ? "1 feed" : "\(count) feeds" }

    static func bottles(_ day: GraphDay) -> String {
        "\(day.bottleML) ml: \(day.formulaML) ml formula, \(day.expressedML) ml expressed milk"
    }

    /// "2 hours, 5 minutes", as VoiceOver reads it on Home.
    static func duration(_ seconds: TimeInterval) -> String { HomeText.spokenElapsed(seconds) }

    static func gaps(_ day: GraphDay) -> String {
        guard let shortest = day.shortestGap, let longest = day.longestGap, let middle = day.middleGap else {
            return "No time between feeds"
        }
        if day.gaps.count == 1 { return "One gap of \(duration(shortest))" }
        return "Shortest \(duration(shortest)); longest \(duration(longest)); middle \(duration(middle))"
    }

    static func sides(_ day: GraphDay) -> String {
        "Left \(minutes(day.leftSeconds)), right \(minutes(day.rightSeconds))"
    }

    static func minutes(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60).rounded())
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    static func pumped(_ day: GraphDay) -> String {
        day.pumpSessions == 1 ? "\(day.pumpedML) ml pumped, 1 session" : "\(day.pumpedML) ml pumped, \(day.pumpSessions) sessions"
    }

    // MARK: Each graph's own page (`docs/planning/10-graph-pages.md`)

    /// A tile's label, with its unit.
    static func tileLabel(_ kind: GraphKind) -> String {
        switch kind {
        case .rhythm: "Daily rhythm"
        case .asleep: "Asleep per day · hours"
        case .nappies: "Nappies per day"
        case .weight: "Weight"
        case .feeds: "Feeds each day"
        case .bottles: "Bottles each day · ml"
        case .gaps: "Time between feeds"
        case .breast: "Breast each day · minutes"
        case .pumped: "Pumped each day · ml"
        }
    }

    /// The page's title.
    static func title(_ kind: GraphKind) -> String {
        switch kind {
        case .asleep: "Asleep per day"
        case .bottles: "Bottles each day"
        case .breast: "Breast each day"
        case .pumped: "Pumped each day"
        default: tileLabel(kind)
        }
    }

    /// Which days get a label under the bars: every day in a week; otherwise today and every
    /// `step` days back, about five labels across. "Tue" for a week, "10 Nov" for longer.
    static func axisLabels(_ days: [(date: PlainDate, isToday: Bool)], in zone: TimeZone) -> [String: String] {
        let week = days.count <= 7
        let step = week ? 1 : max(7, Int((Double(days.count) / 5 / 7).rounded(.up)) * 7)
        var labels: [String: String] = [:]
        for (offset, day) in days.enumerated() where (days.count - 1 - offset) % step == 0 {
            var style = Date.FormatStyle(timeZone: zone)
            style = week ? style.weekday(.abbreviated) : style.day().month(.abbreviated)
            labels[day.date.description] = day.isToday ? "Today" : midday(day.date, in: zone).formatted(style)
        }
        return labels
    }

    /// One day of a feed graph for VoiceOver: "Tuesday 17 November: 8 feeds".
    static func spoken(_ kind: GraphKind, _ day: GraphDay, in zone: TimeZone) -> String {
        let facts = switch kind {
        case .bottles: bottles(day)
        case .gaps: gaps(day)
        case .breast: sides(day)
        case .pumped: pumped(day)
        default: feeds(day.feeds)
        }
        return "\(spokenDay(day, in: zone)): \(facts)"
    }

    /// The page's day: "Today", "Yesterday", "Tuesday 17 Nov".
    static func dayName(_ day: PlainDate, today: PlainDate, in zone: TimeZone) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: -1) { return "Yesterday" }
        return midday(day, in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.abbreviated))
    }

    /// The weekday alone, for "3h 10m of it on Tuesday".
    static func weekday(_ day: PlainDate, in zone: TimeZone) -> String {
        midday(day, in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide))
    }

    static let nothingThatDay = "Nothing logged on this day."
    static let gapsExplained = "From each feed's start to the next feed's start."
    static let longest = "Longest"
    static let running = "Still running"
    static let showEntries = "Show the entries"

    /// "From 22:05 to 00:40", for a gap; "Mon 22:05" when it began on another day.
    static func clock(_ date: Date, on day: PlainDate, in zone: TimeZone) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
        guard PlainDate(date, in: zone) != day else { return time }
        return midday(PlainDate(date, in: zone), in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)) + " " + time
    }

    /// Under a feed or pumping row: "To 01:03 · 23m", or "Still running".
    static func feedTiming(_ snapshot: EventSnapshot, on day: PlainDate, in zone: TimeZone) -> String {
        guard let end = snapshot.event.endedAt else { return running }
        return "To \(clock(end, on: day, in: zone)) · \(elapsed(end.timeIntervalSince(snapshot.event.startedAt)))"
    }

    /// "23m", "2h 35m".
    static func elapsed(_ seconds: TimeInterval) -> String { HomeText.elapsed(max(0, seconds)) }

    /// "3h 10m of it on Tuesday", under a sleep that runs over midnight.
    static func partOfSleep(_ seconds: TimeInterval, on day: PlainDate, in zone: TimeZone) -> String {
        "\(elapsed(seconds)) of it on \(weekday(day, in: zone))"
    }

    /// "+ 140 g since 12 Nov", under a weight. A plain difference: no "gain" or "loss" words.
    static func weightChange(_ grams: Int, since date: Date, in zone: TimeZone) -> String {
        let sign = grams > 0 ? "+ " : grams < 0 ? "− " : ""
        return "\(sign)\(abs(grams)) g since \(date.formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated)))"
    }

    /// "Thu 19 Nov", on the left of a weight row.
    static func shortDate(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).day().month(.abbreviated))
    }

    static func count(_ number: Int, _ one: String, _ many: String) -> String {
        "\(number) \(number == 1 ? one : many)"
    }
}
