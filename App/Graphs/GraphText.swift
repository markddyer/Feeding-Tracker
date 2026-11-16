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
}
