import Charts
import FeedingCore
import SwiftUI

// The daily rhythm report and growth on the Graphs tab (`06-more-than-feeds.md`; the users'
// choices D and K, 17 Nov 2026). Facts only: how long, how many, when. No targets, no "normal"
// ranges, no red-book curves, no red or green.

/// The rhythm report, then "Asleep per day" and "Nappies per day", each only when it has
/// something to show. A tap on a day's row or bar opens that graph's page on that day.
struct RhythmTiles: View {
    let days: [RhythmDay]
    let zone: TimeZone
    let dayHours: DayHours
    let open: (GraphKind, PlainDate?) -> Void

    private var isWeek: Bool { days.count <= 7 }

    var body: some View {
        if days.contains(where: { !$0.sleeps.isEmpty || !$0.nappies.isEmpty }) {
            rhythm
        }
        if days.contains(where: { $0.sleepSeconds > 0 }) {
            GraphTile(kind: .asleep, dayHours: dayHours, open: open) {
                RhythmGraphChart(kind: .asleep, days: days, zone: zone) { open(.asleep, $0) }
            }
        }
        if days.contains(where: { !$0.nappies.isEmpty }) {
            GraphTile(kind: .nappies, open: open) {
                RhythmGraphChart(kind: .nappies, days: days, zone: zone) { open(.nappies, $0) }
            }
        }
    }

    // MARK: The report: one row per day, midnight to midnight

    private var rhythm: some View {
        GraphTile(kind: .rhythm, open: open) {
            VStack(spacing: 0) {
                RhythmHourLabels()
                ForEach(days) { day in
                    RhythmRow(day: day, zone: zone, label: RhythmText.rowLabel(day, in: zone, week: isWeek))
                        .contentShape(Rectangle())
                        .onTapGesture { open(.rhythm, day.date) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(RhythmText.spokenDay(day, in: zone))
                        .accessibilityValue(RhythmText.spokenRhythm(day))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { open(.rhythm, day.date) }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }
}

/// "00 06 12 18 24" over the rhythm rows.
struct RhythmHourLabels: View {
    var body: some View {
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
/// ounces beside (N). Never a centile curve or a "normal" band. A tap opens the weight page, on
/// the weight tapped.
struct GrowthTile: View {
    let weights: [WeightEntry]
    /// Every growth entry, oldest first, for the latest length and head.
    let entries: [EventSnapshot]
    let zone: TimeZone
    let add: () -> Void
    let open: (String?) -> Void

    var body: some View {
        let addButton = PillButton("Add", action: add).accessibilityLabel("Add a measurement")
        Tile(label: GraphText.tileLabel(.weight), accessory: AnyView(HStack(spacing: 8) {
            addButton
            if !entries.isEmpty {
                GraphOpenButton(kind: .weight) { open(nil) }
            }
        })) {
            if let last = weights.last {
                Text(CareText.weight(last.grams)).feedText(.total).lineLimit(1).minimumScaleFactor(0.7)
                Text("on \(RhythmText.date(last.at, in: zone))").feedText(.small).foregroundStyle(Theme.textMuted)
                if weights.count > 1 {
                    WeightChart(weights: weights, zone: zone) { open($0) }
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
        .contentShape(Rectangle())
        .onTapGesture { if !entries.isEmpty { open(nil) } }
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

/// The weight line, on its tile and on its page. A tap picks the nearest weight; on the page the
/// picked one is drawn bigger and the others fade.
struct WeightChart: View {
    let weights: [WeightEntry]
    let zone: TimeZone
    var selected: String?
    var height: CGFloat = 140
    let pick: (String) -> Void

    var body: some View {
        let kgs = weights.map { Double($0.grams) / 1000 }
        let low = ((kgs.min() ?? 3) - 0.2).rounded(.down)
        let high = ((kgs.max() ?? 4) + 0.2).rounded(.up)
        Chart(weights) { weight in
            LineMark(x: .value("Date", weight.at), y: .value("kg", Double(weight.grams) / 1000))
                .foregroundStyle(Theme.primary)
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineJoin: .round))
            PointMark(x: .value("Date", weight.at), y: .value("kg", Double(weight.grams) / 1000))
                .foregroundStyle(Theme.primary)
                .symbolSize(weight.id == selected ? 120 : 40)
                .opacity(selected == nil || weight.id == selected ? 1 : 0.45)
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
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geometry[plot].origin.x
                        guard let date: Date = proxy.value(atX: x),
                              let nearest = weights.min(by: { abs($0.at.timeIntervalSince(date)) < abs($1.at.timeIntervalSince(date)) })
                        else { return }
                        pick(nearest.id)
                    }
            }
        }
        .frame(height: height)
        .padding(.top, 4)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityRepresentation {
            VStack {
                ForEach(weights) { weight in
                    Button("\(RhythmText.date(weight.at, in: zone)): \(CareText.weight(weight.grams))") { pick(weight.id) }
                        .accessibilityAddTraits(weight.id == selected ? .isSelected : [])
                }
            }
        }
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

    /// One day of a rhythm graph for VoiceOver: "Tuesday 17 November: 7 wees, 3 poos".
    static func spoken(_ kind: GraphKind, _ day: RhythmDay, in zone: TimeZone) -> String {
        let facts = switch kind {
        case .nappies: spokenNappies(day)
        case .asleep: spokenSleep(day)
        default: spokenRhythm(day)
        }
        return "\(spokenDay(day, in: zone)): \(facts)"
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
