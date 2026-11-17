import Charts
import FeedingCore
import SwiftUI

// The daily rhythm report and growth on the Graphs tab (`06-more-than-feeds.md`; the users'
// choices D and K, 17 Nov 2026). Facts only: how long, how many, when. No targets, no "normal"
// ranges, no red-book curves, no red or green.

/// The rhythm report, then "Asleep per day" and "Nappies per day", each only when it has
/// something to show.
struct RhythmTiles: View {
    let days: [RhythmDay]
    let zone: TimeZone
    let dayHours: DayHours

    private var isWeek: Bool { days.count <= 7 }
    private var keys: [String] { days.map(\.date.description) }

    var body: some View {
        if days.contains(where: { !$0.sleeps.isEmpty || !$0.nappies.isEmpty }) {
            rhythm
        }
        if days.contains(where: { $0.sleepSeconds > 0 }) { asleep }
        if days.contains(where: { !$0.nappies.isEmpty }) { nappies }
    }

    // MARK: The report: one row per day, midnight to midnight

    private var rhythm: some View {
        Tile(label: "Daily rhythm") {
            rhythmKey
            VStack(spacing: 0) {
                hourLabels
                ForEach(days) { day in
                    RhythmRow(day: day, zone: zone, label: RhythmText.rowLabel(day, in: zone, week: isWeek))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(RhythmText.spokenDay(day, in: zone))
                        .accessibilityValue(RhythmText.spokenRhythm(day))
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }

    private var hourLabels: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: RhythmRow.labelWidth, height: 1)
            HStack {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { hour in
                    Text(hour)
                    if hour != "24" { Spacer(minLength: 0) }
                }
            }
        }
        .feedText(.small)
        .foregroundStyle(Theme.textMuted)
        .padding(.bottom, 3)
        .accessibilityHidden(true)
    }

    private var rhythmKey: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.sleepMark).frame(width: 12, height: 9)
                Text("Asleep")
            }
            HStack(spacing: 4) {
                Capsule().fill(Theme.breastMark).frame(width: 3, height: 11)
                Text("Feed")
            }
            HStack(spacing: 4) {
                Circle().fill(Theme.weeMark).frame(width: 7, height: 7)
                Text("Wee")
            }
            HStack(spacing: 4) {
                Circle().fill(Theme.pooMark).frame(width: 7, height: 7)
                Text("Poo")
            }
        }
        .modifier(RhythmKeyStyle())
    }

    // MARK: Asleep per day: night and day, stacked

    private var asleep: some View {
        Tile(label: "Asleep per day · hours") {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.sleepMark).frame(width: 10, height: 10)
                    Text("Night \(RhythmText.hours(dayHours))")
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.sleepSoft).frame(width: 10, height: 10)
                    Text("Day")
                }
            }
            .modifier(RhythmKeyStyle())
            let top = max(4, ((days.map(\.sleepSeconds).max() ?? 0) / 3600 / 4).rounded(.up) * 4)
            Chart(days) { day in
                BarMark(x: .value("Day", day.date.description), y: .value("Hours", day.nightSleepSeconds / 3600),
                        width: .ratio(isWeek ? 0.55 : 0.7))
                    .foregroundStyle(by: .value("When", "Night"))
                    .cornerRadius(3)
                    .opacity(day.isToday ? 0.45 : 1)
                    .accessibilityLabel(RhythmText.spokenDay(day, in: zone))
                    .accessibilityValue(RhythmText.spokenSleep(day))
                BarMark(x: .value("Day", day.date.description), y: .value("Hours", day.daySleepSeconds / 3600),
                        width: .ratio(isWeek ? 0.55 : 0.7))
                    .foregroundStyle(by: .value("When", "Day"))
                    .cornerRadius(3)
                    .opacity(day.isToday ? 0.45 : 1)
                    .annotation(position: .top, spacing: 2) {
                        if isWeek, day.sleepSeconds > 0 {
                            Text(RhythmText.shortHours(day.sleepSeconds)).feedText(.small).foregroundStyle(Theme.textMuted)
                        }
                    }
                    .accessibilityHidden(true)
            }
            .chartForegroundStyleScale(["Night": Theme.sleepMark, "Day": Theme.sleepSoft])
            .chartLegend(.hidden)
            .chartYScale(domain: 0...(top * (isWeek ? 1.15 : 1)))
            .modifier(RhythmAxes(keys: keys, labels: labels, unit: "h", step: 4))
        }
    }

    // MARK: Nappies per day: wees and poos side by side

    private var nappies: some View {
        let top = Double(max(4, days.map { max($0.wees, $0.poos) }.max() ?? 0))
        return Tile(label: "Nappies per day") {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    FeedMarkView(.wee, size: 12, relativeTo: .caption2)
                    Text("Wee")
                }
                HStack(spacing: 4) {
                    FeedMarkView(.poo, size: 12, relativeTo: .caption2)
                    Text("Poo")
                }
            }
            .modifier(RhythmKeyStyle())
            Chart(days) { day in
                BarMark(x: .value("Day", day.date.description), y: .value("Count", day.wees), width: .ratio(0.85))
                    .foregroundStyle(by: .value("Kind", "Wee"))
                    .position(by: .value("Kind", "Wee"), axis: .horizontal, span: .ratio(isWeek ? 0.62 : 0.8))
                    .cornerRadius(3)
                    .opacity(day.isToday ? 0.45 : 1)
                    .annotation(position: .top, spacing: 2) { count(day.wees) }
                    .accessibilityLabel(RhythmText.spokenDay(day, in: zone))
                    .accessibilityValue(RhythmText.spokenNappies(day))
                BarMark(x: .value("Day", day.date.description), y: .value("Count", day.poos), width: .ratio(0.85))
                    .foregroundStyle(by: .value("Kind", "Poo"))
                    .position(by: .value("Kind", "Poo"), axis: .horizontal, span: .ratio(isWeek ? 0.62 : 0.8))
                    .cornerRadius(3)
                    .opacity(day.isToday ? 0.45 : 1)
                    .annotation(position: .top, spacing: 2) { count(day.poos) }
                    .accessibilityHidden(true)
            }
            .chartForegroundStyleScale(["Wee": Theme.weeMark, "Poo": Theme.pooMark])
            .chartLegend(.hidden)
            .chartYScale(domain: 0...(top * (isWeek ? 1.2 : 1.05)))
            .modifier(RhythmAxes(keys: keys, labels: labels, unit: "", step: nil, showsY: !isWeek))
        }
    }

    @ViewBuilder
    private func count(_ value: Int) -> some View {
        if isWeek, value > 0 {
            Text("\(value)").feedText(.small).foregroundStyle(Theme.textMuted)
        }
    }

    private var labels: [String: String] {
        let step = isWeek ? 1 : max(7, Int((Double(days.count) / 5 / 7).rounded(.up)) * 7)
        return Dictionary(uniqueKeysWithValues: days.enumerated()
            .filter { (days.count - 1 - $0.offset) % step == 0 }
            .map { ($0.element.date.description, RhythmText.rowLabel($0.element, in: zone, week: isWeek)) })
    }
}

/// One day's row: the day's name, then midnight to midnight with the sleeps as bars, each feed
/// as a thin tick, and the wees and poos as dots under it. Today is paler, as it isn't over.
struct RhythmRow: View {
    let day: RhythmDay
    let zone: TimeZone
    let label: String

    static let labelWidth: CGFloat = 46
    private let barHeight: CGFloat = 15

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .feedText(.small)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.labelWidth, height: barHeight, alignment: .leading)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.chartStrip).frame(height: barHeight)
                    ForEach(day.sleeps) { sleep in
                        let from = x(sleep.start, width), to = x(sleep.end, width)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.sleepMark)
                            .frame(width: max(2, to - from), height: barHeight)
                            .offset(x: from)
                    }
                    ForEach(day.feeds) { feed in
                        Capsule()
                            .fill(feed.bottle && !feed.breast ? Theme.bottleMark : feed.breast ? Theme.breastMark : Theme.textMuted)
                            .frame(width: 2.5, height: barHeight + 4)
                            .offset(x: min(max(0, x(feed.startedAt, width) - 1.25), width - 2.5), y: -2)
                    }
                    ForEach(day.nappies) { nappy in
                        let at = min(max(0, x(nappy.at, width) - 3), width - 6)
                        HStack(spacing: 1) {
                            if nappy.wee { Circle().fill(Theme.weeMark).frame(width: 6, height: 6) }
                            if nappy.poo { Circle().fill(Theme.pooMark).frame(width: 6, height: 6) }
                            if !nappy.wee && !nappy.poo { Circle().strokeBorder(Theme.textMuted, lineWidth: 1).frame(width: 6, height: 6) }
                        }
                        .offset(x: at, y: barHeight + 3)
                    }
                }
            }
            .frame(height: barHeight + 11)
            .opacity(day.isToday ? 0.6 : 1)
        }
        .padding(.vertical, 2)
    }

    /// Where a moment sits on the row: by the clock in the household's time zone, so it lines up
    /// with the 00 / 06 / 12 / 18 / 24 labels even on the days the clocks change (a 23 or 25 hour
    /// day). The hour the clocks go back is drawn twice over the same place.
    private func x(_ date: Date, _ width: CGFloat) -> CGFloat {
        CGFloat(Self.clockShare(date, dayStart: day.start, dayEnd: day.end, zone: zone)) * width
    }

    /// The share of the day's clock face, from 0 at midnight to 1 at the next midnight.
    static func clockShare(_ date: Date, dayStart: Date, dayEnd: Date, zone: TimeZone) -> Double {
        if date >= dayEnd { return 1 }
        if date <= dayStart { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hours = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
        return min(1, max(0, hours / 24))
    }
}

/// The baby's own weights over time, with Add (the users' choice K). Kilograms, with pounds and
/// ounces beside (N). Never a centile curve or a "normal" band.
struct GrowthTile: View {
    let entries: [EventSnapshot]
    let zone: TimeZone
    let add: () -> Void

    var body: some View {
        let weights = entries.compactMap { entry in entry.payload?.growth?.weightGrams.map { (entry.event.startedAt, $0) } }
        Tile(label: "Weight", accessory: AnyView(PillButton("Add", action: add).accessibilityLabel("Add a measurement"))) {
            if let last = weights.last {
                Text(CareText.weight(last.1)).feedText(.total).lineLimit(1).minimumScaleFactor(0.7)
                Text("on \(RhythmText.date(last.0, in: zone))").feedText(.small).foregroundStyle(Theme.textMuted)
                if weights.count > 1 {
                    chart(weights)
                }
            } else {
                Text("No weight logged yet.")
                    .feedText(.body)
                    .foregroundStyle(Theme.textMuted)
            }
            if let latest = latestLengthAndHead {
                Text(latest).feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func chart(_ weights: [(Date, Int)]) -> some View {
        let kgs = weights.map { Double($0.1) / 1000 }
        let low = ((kgs.min() ?? 3) - 0.2).rounded(.down)
        let high = ((kgs.max() ?? 4) + 0.2).rounded(.up)
        return Chart(Array(weights.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Date", point.0), y: .value("kg", Double(point.1) / 1000))
                .foregroundStyle(Theme.primary)
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineJoin: .round))
            PointMark(x: .value("Date", point.0), y: .value("kg", Double(point.1) / 1000))
                .foregroundStyle(Theme.primary)
                .symbolSize(40)
                .accessibilityLabel(RhythmText.date(point.0, in: zone))
                .accessibilityValue(CareText.weight(point.1))
        }
        .chartYScale(domain: low...high)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated)))
                            .feedText(.small).foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text(String(format: "%.1f kg", kg)).feedText(.small).foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
        .frame(height: 140)
        .padding(.top, 4)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// "Length 52.5 cm · head 36.0 cm, on 14 Nov": the latest of each.
    private var latestLengthAndHead: String? {
        let length = entries.last { $0.payload?.growth?.lengthMM != nil }
        let head = entries.last { $0.payload?.growth?.headMM != nil }
        var parts: [String] = []
        if let length, let mm = length.payload?.growth?.lengthMM {
            parts.append("Length \(CareText.centimetres(mm)), \(RhythmText.date(length.event.startedAt, in: zone))")
        }
        if let head, let mm = head.payload?.growth?.headMM {
            parts.append("Head \(CareText.centimetres(mm)), \(RhythmText.date(head.event.startedAt, in: zone))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The words on the rhythm and growth tiles, and what VoiceOver reads.
enum RhythmText {
    static func rowLabel(_ day: RhythmDay, in zone: TimeZone, week: Bool) -> String {
        if day.isToday { return "Today" }
        var style = Date.FormatStyle(timeZone: zone)
        style = week ? style.weekday(.abbreviated) : style.day().month(.abbreviated)
        return GraphText.midday(day.date, in: zone).formatted(style)
    }

    static func spokenDay(_ day: RhythmDay, in zone: TimeZone) -> String {
        if day.isToday { return "Today" }
        return GraphText.midday(day.date, in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.wide))
    }

    static func spokenSleep(_ day: RhythmDay) -> String {
        "Asleep \(HomeText.spokenElapsed(day.sleepSeconds)): \(HomeText.spokenElapsed(day.nightSleepSeconds)) at night, \(HomeText.spokenElapsed(day.daySleepSeconds)) in the day"
    }

    static func spokenNappies(_ day: RhythmDay) -> String {
        "\(day.wees) \(day.wees == 1 ? "wee" : "wees"), \(day.poos) \(day.poos == 1 ? "poo" : "poos")"
    }

    static func spokenRhythm(_ day: RhythmDay) -> String {
        "\(spokenSleep(day)). \(GraphText.feeds(day.feeds.count)). \(spokenNappies(day))."
    }

    /// "13h", "13.5h": a day's sleep over its bar.
    static func shortHours(_ seconds: TimeInterval) -> String {
        let hours = (seconds / 1800).rounded() / 2
        return hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }

    /// "21:00 to 07:00": the household's night hours.
    static func hours(_ dayHours: DayHours) -> String {
        "\(dayHours.nightStart) to \(dayHours.dayStart)"
    }

    /// "Saturday 14 Nov", or "today".
    static func date(_ date: Date, in zone: TimeZone) -> String {
        if PlainDate(date, in: zone) == PlainDate(Date(), in: zone) { return "today" }
        return date.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.abbreviated))
    }
}

private struct RhythmKeyStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .feedText(.small)
            .foregroundStyle(Theme.textMuted)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// The axes for the two per-day charts, as on the other graphs.
private struct RhythmAxes: ViewModifier {
    let keys: [String]
    let labels: [String: String]
    let unit: String
    let step: Double?
    var showsY = true

    func body(content: Content) -> some View {
        content
            .chartXScale(domain: keys)
            .chartXAxis {
                AxisMarks(values: keys.filter { labels[$0] != nil }) { value in
                    AxisValueLabel {
                        if let key = value.as(String.self), let label = labels[key] {
                            Text(label).feedText(.small).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis(showsY ? .visible : .hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: step.map { .stride(by: $0) } ?? .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number))\(unit)").feedText(.small).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .frame(height: 140)
            .padding(.top, 4)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}
