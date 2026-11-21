import Charts
import FeedingCore
import SwiftUI

// The charts of the Graphs tab, drawn on their tiles and, bigger, on each graph's own page (the
// users' choice C, 21 Nov 2026, `docs/planning/10-graph-pages.md`). A tap on a day's bar calls
// `pick` with that day. On a page the picked day stays full colour and the others fade.

/// How strong a day's bar is: today paler, as it isn't over; on a page, the picked day full and
/// the rest faded.
enum GraphShade {
    static func opacity(_ date: PlainDate, isToday: Bool, selected: PlainDate?) -> Double {
        guard let selected else { return isToday ? 0.45 : 1 }
        return date == selected ? 1 : 0.3
    }
}

/// One of the five feed graphs (`graphDays`).
struct FeedGraphChart: View {
    let kind: GraphKind
    let days: [GraphDay]
    let zone: TimeZone
    var selected: PlainDate?
    var height: CGFloat = 140
    let pick: (PlainDate) -> Void

    private var keys: [String] { days.map(\.date.description) }
    private var isWeek: Bool { days.count <= 7 }
    /// Numbers on the bars only when there is room for them.
    private var showsValues: Bool { isWeek }
    private var bar: MarkDimension { .ratio(isWeek ? 0.55 : 0.7) }

    /// The amount axis, with room above the tallest bar for its number.
    private func scale(_ largest: Int) -> ClosedRange<Double> {
        0...max(1, Double(largest) * (showsValues ? 1.22 : 1.05))
    }

    private func shade(_ day: GraphDay) -> Double { GraphShade.opacity(day.date, isToday: day.isToday, selected: selected) }

    var body: some View {
        switch kind {
        case .bottles: bottles
        case .gaps: gaps
        case .breast: sides
        case .pumped: pumped
        default: feeds
        }
    }

    private var feeds: some View {
        finish(Chart(days) { day in
            BarMark(x: .value("Day", day.date.description), y: .value("Feeds", day.feeds), width: bar)
                .cornerRadius(5)
                .foregroundStyle(Theme.chart)
                .opacity(shade(day))
                .annotation(position: .top, spacing: 2) { value("\(day.feeds)", day.feeds > 0) }
        }
        .chartYScale(domain: scale(days.map(\.feeds).max() ?? 0)), yAxis: showsValues ? .hidden : .visible, unit: "")
    }

    private var bottles: some View {
        finish(Chart(days) { day in
            // Formula at the bottom, expressed milk on top; the total over the bar.
            BarMark(x: .value("Day", day.date.description), y: .value("ml", day.formulaML), width: bar)
                .foregroundStyle(by: .value("Milk", "Formula"))
                .cornerRadius(3)
                .opacity(shade(day))
                .annotation(position: .top, spacing: 2) { value("\(day.bottleML)", day.expressedML == 0 && day.bottleML > 0) }
            BarMark(x: .value("Day", day.date.description), y: .value("ml", day.expressedML), width: bar)
                .foregroundStyle(by: .value("Milk", "Expressed"))
                .cornerRadius(3)
                .opacity(shade(day))
                .annotation(position: .top, spacing: 2) { value("\(day.bottleML)", day.expressedML > 0) }
        }
        .chartForegroundStyleScale(["Formula": Theme.bottleMark, "Expressed": Theme.bottleSoft])
        .chartLegend(.hidden)
        .chartYScale(domain: scale(days.map(\.bottleML).max() ?? 0)), yAxis: showsValues ? .hidden : .visible, unit: "")
    }

    /// Each day: a soft bar from the shortest gap to the longest, and a dot for the middle one.
    private var gaps: some View {
        let longest = days.compactMap(\.longestGap).max() ?? 0
        let top = max(4, (longest / 3600 / 2).rounded(.up) * 2)
        return finish(Chart {
            ForEach(days) { day in
                if let shortest = day.shortestGap, let longest = day.longestGap, let middle = day.middleGap {
                    BarMark(x: .value("Day", day.date.description),
                            yStart: .value("Shortest", shortest / 3600), yEnd: .value("Longest", longest / 3600),
                            width: .ratio(isWeek ? 0.3 : 0.6))
                        .cornerRadius(7)
                        .foregroundStyle(Theme.chart.opacity(0.3))
                        .opacity(shade(day))
                    PointMark(x: .value("Day", day.date.description), y: .value("Middle", middle / 3600))
                        .symbolSize(isWeek ? 70 : 24)
                        .foregroundStyle(Theme.chart)
                        .opacity(shade(day))
                }
            }
        }
        .chartYScale(domain: 0...top), yAxis: .visible, unit: "h", step: 2)
    }

    private var sides: some View {
        finish(Chart(days) { day in
            BarMark(x: .value("Day", day.date.description), y: .value("Minutes", Double(day.leftSeconds) / 60),
                    width: .ratio(0.85))
                .foregroundStyle(by: .value("Side", "Left"))
                .position(by: .value("Side", "Left"), axis: .horizontal, span: .ratio(isWeek ? 0.62 : 0.8))
                .cornerRadius(3)
                .opacity(shade(day))
            BarMark(x: .value("Day", day.date.description), y: .value("Minutes", Double(day.rightSeconds) / 60),
                    width: .ratio(0.85))
                .foregroundStyle(by: .value("Side", "Right"))
                .position(by: .value("Side", "Right"), axis: .horizontal, span: .ratio(isWeek ? 0.62 : 0.8))
                .cornerRadius(3)
                .opacity(shade(day))
        }
        .chartForegroundStyleScale(["Left": Theme.breastMark, "Right": Theme.breastSoft])
        .chartLegend(.hidden), yAxis: .visible, unit: "m")
    }

    private var pumped: some View {
        finish(Chart(days) { day in
            BarMark(x: .value("Day", day.date.description), y: .value("ml", day.pumpedML), width: bar)
                .cornerRadius(5)
                .foregroundStyle(Theme.pumpMark)
                .opacity(shade(day))
                .annotation(position: .top, spacing: 2) { value("\(day.pumpedML)", day.pumpedML > 0) }
        }
        .chartYScale(domain: scale(days.map(\.pumpedML).max() ?? 0)), yAxis: showsValues ? .hidden : .visible, unit: "")
    }

    /// The axes, the tap, and VoiceOver's list of days, the same on every feed graph.
    private func finish(_ chart: some View, yAxis: Visibility, unit: String, step: Double? = nil) -> some View {
        chart
            .modifier(ChartDayTap(dates: days.map(\.date), pick: pick))
            .modifier(GraphAxes(keys: keys, labels: GraphText.axisLabels(days.map { ($0.date, $0.isToday) }, in: zone),
                                yAxis: yAxis, unit: unit, step: step, height: height))
            .accessibilityRepresentation {
                GraphDayButtons(days: days.map { ($0.date, GraphText.spoken(kind, $0, in: zone)) }, selected: selected, pick: pick)
            }
    }

    @ViewBuilder
    private func value(_ text: String, _ shows: Bool) -> some View {
        if shows && showsValues {
            Text(text).feedText(.small).foregroundStyle(Theme.textMuted)
        }
    }
}

/// "Asleep per day" and "Nappies per day" (`rhythmDays`).
struct RhythmGraphChart: View {
    let kind: GraphKind
    let days: [RhythmDay]
    let zone: TimeZone
    var selected: PlainDate?
    var height: CGFloat = 140
    let pick: (PlainDate) -> Void

    private var isWeek: Bool { days.count <= 7 }
    private var keys: [String] { days.map(\.date.description) }
    private func shade(_ day: RhythmDay) -> Double { GraphShade.opacity(day.date, isToday: day.isToday, selected: selected) }

    var body: some View {
        if kind == .nappies { nappies } else { asleep }
    }

    // Night and day, stacked.
    private var asleep: some View {
        let top = max(4, ((days.map(\.sleepSeconds).max() ?? 0) / 3600 / 4).rounded(.up) * 4)
        return finish(Chart(days) { day in
            BarMark(x: .value("Day", day.date.description), y: .value("Hours", day.nightSleepSeconds / 3600),
                    width: .ratio(isWeek ? 0.55 : 0.7))
                .foregroundStyle(by: .value("When", "Night"))
                .cornerRadius(3)
                .opacity(shade(day))
            BarMark(x: .value("Day", day.date.description), y: .value("Hours", day.daySleepSeconds / 3600),
                    width: .ratio(isWeek ? 0.55 : 0.7))
                .foregroundStyle(by: .value("When", "Day"))
                .cornerRadius(3)
                .opacity(shade(day))
                .annotation(position: .top, spacing: 2) {
                    if isWeek, day.sleepSeconds > 0 {
                        Text(RhythmText.shortHours(day.sleepSeconds)).feedText(.small).foregroundStyle(Theme.textMuted)
                    }
                }
        }
        .chartForegroundStyleScale(["Night": Theme.sleepMark, "Day": Theme.sleepSoft])
        .chartLegend(.hidden)
        .chartYScale(domain: 0...(top * (isWeek ? 1.15 : 1))), yAxis: .visible, unit: "h", step: 4)
    }

    // Wees and poos side by side.
    private var nappies: some View {
        let top = Double(max(4, days.map { max($0.wees, $0.poos) }.max() ?? 0))
        return finish(Chart(days) { day in
            BarMark(x: .value("Day", day.date.description), y: .value("Count", day.wees), width: .ratio(0.85))
                .foregroundStyle(by: .value("Kind", "Wee"))
                .position(by: .value("Kind", "Wee"), axis: .horizontal, span: .ratio(isWeek ? 0.62 : 0.8))
                .cornerRadius(3)
                .opacity(shade(day))
                .annotation(position: .top, spacing: 2) { count(day.wees) }
            BarMark(x: .value("Day", day.date.description), y: .value("Count", day.poos), width: .ratio(0.85))
                .foregroundStyle(by: .value("Kind", "Poo"))
                .position(by: .value("Kind", "Poo"), axis: .horizontal, span: .ratio(isWeek ? 0.62 : 0.8))
                .cornerRadius(3)
                .opacity(shade(day))
                .annotation(position: .top, spacing: 2) { count(day.poos) }
        }
        .chartForegroundStyleScale(["Wee": Theme.weeMark, "Poo": Theme.pooMark])
        .chartLegend(.hidden)
        .chartYScale(domain: 0...(top * (isWeek ? 1.2 : 1.05))), yAxis: isWeek ? .hidden : .visible, unit: "")
    }

    @ViewBuilder
    private func count(_ value: Int) -> some View {
        if isWeek, value > 0 {
            Text("\(value)").feedText(.small).foregroundStyle(Theme.textMuted)
        }
    }

    private func finish(_ chart: some View, yAxis: Visibility, unit: String, step: Double? = nil) -> some View {
        chart
            .modifier(ChartDayTap(dates: days.map(\.date), pick: pick))
            .modifier(GraphAxes(keys: keys, labels: GraphText.axisLabels(days.map { ($0.date, $0.isToday) }, in: zone),
                                yAxis: yAxis, unit: unit, step: step, height: height))
            .accessibilityRepresentation {
                GraphDayButtons(days: days.map { ($0.date, RhythmText.spoken(kind, $0, in: zone)) }, selected: selected, pick: pick)
            }
    }
}

/// A tap anywhere over a day's slot (bar, gap or label) picks that day. A plain tap, so the page
/// still scrolls when a finger starts on a graph.
struct ChartDayTap: ViewModifier {
    let dates: [PlainDate]
    let pick: (PlainDate) -> Void

    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geometry[plot].origin.x
                        guard let key: String = proxy.value(atX: x),
                              let date = dates.first(where: { $0.description == key }) else { return }
                        pick(date)
                    }
            }
        }
    }
}

/// What VoiceOver finds in a graph: one button per day ("Tuesday 17 November, 8 feeds"), which
/// does what a tap on that day's bar does.
struct GraphDayButtons: View {
    let days: [(PlainDate, String)]
    let selected: PlainDate?
    let pick: (PlainDate) -> Void

    var body: some View {
        VStack {
            ForEach(days, id: \.0) { date, label in
                Button(label) { pick(date) }
                    .accessibilityAddTraits(date == selected ? .isSelected : [])
            }
        }
    }
}

/// A graph's key, on its own line under the tile's label (as in the mockup), so a long label is
/// never squeezed; its sizes stop growing where Home's key does. Nil for a graph with no key.
struct GraphKey: View {
    let kind: GraphKind
    var dayHours: DayHours = .standard

    var body: some View {
        HStack(spacing: 10) {
            switch kind {
            case .bottles:
                item(Theme.bottleMark, "Formula")
                item(Theme.bottleSoft, "Expressed")
            case .breast:
                shape(.side(.left), Theme.breastMark, "Left")
                shape(.side(.right), Theme.breastSoft, "Right")
            case .gaps:
                item(Theme.chart.opacity(0.3), "Shortest to longest")
                HStack(spacing: 4) {
                    Circle().fill(Theme.chart).frame(width: 8, height: 8)
                    Text("Middle")
                }
            case .asleep:
                item(Theme.sleepMark, "Night \(RhythmText.hours(dayHours))")
                item(Theme.sleepSoft, "Day")
            case .nappies:
                shape(.wee, nil, "Wee")
                shape(.poo, nil, "Poo")
            case .rhythm:
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
            default:
                EmptyView()
            }
        }
        .feedText(.small)
        .foregroundStyle(Theme.textMuted)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    static func shows(_ kind: GraphKind) -> Bool {
        [.bottles, .breast, .gaps, .asleep, .nappies, .rhythm].contains(kind)
    }

    private func item(_ colour: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(colour).frame(width: 10, height: 10)
            Text(title)
        }
    }

    private func shape(_ mark: FeedMark, _ colour: Color?, _ title: String) -> some View {
        HStack(spacing: 4) {
            if let colour {
                FeedMarkView(mark, size: 12, relativeTo: .caption2, colour: colour)
            } else {
                FeedMarkView(mark, size: 12, relativeTo: .caption2)
            }
            Text(title)
        }
    }
}

/// Every graph's axes: every day on the bottom (only some labelled), and the amounts up the right
/// side when the bars carry no numbers. Applied to the chart only, so the tile's label still grows.
struct GraphAxes: ViewModifier {
    let keys: [String]
    let labels: [String: String]
    let yAxis: Visibility
    let unit: String
    var step: Double? = nil
    var height: CGFloat = 140

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
            .chartYAxis(yAxis)
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
            .frame(height: height)
            .padding(.top, 4)
            // Day names and numbers stop growing where seven of them still fit across the tile
            // (as in Apple's Health app); each day is read out by VoiceOver.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}
