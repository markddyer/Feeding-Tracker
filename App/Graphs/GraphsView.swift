import Charts
import FeedingCore
import SwiftUI

/// The Graphs tab (plan v1, Phase 2; the user's choices of 16 Nov 2026, from
/// `designs/graphs-20261116/`): one long page, a tile per graph, and a 7 days / 4 weeks / All
/// switch. Facts only: no target lines, no "normal" bands, no red or green. A graph with nothing
/// to show in the chosen time is left out, so a bottle-only phone sees no breast-side graph.
struct GraphsView: View {
    private let model = AppModel.shared
    @AppStorage("graphs.range") private var rangeName = GraphRange.week.rawValue
    /// The weight graph's Add (the users' choice K, 17 Nov 2026).
    @State private var addingGrowth = false
    /// The page's width inside its margins, to choose one column or two.
    @State private var width: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let data = model.store.data
            let zone = data.householdSettings.timeZone
            let babyID = model.baby?.name ?? ""
            let range = GraphRange(rawValue: rangeName) ?? .week
            let visible = data.visibleSnapshots(babyID: babyID)
            let days = graphDays(visible, babyID: babyID, timeZone: zone, range: range, now: context.date)
            // The daily rhythm report, above the feed graphs (the users' choice D, 17 Nov 2026).
            let rhythm = rhythmDays(visible, babyID: babyID, timeZone: zone, dayHours: data.householdSettings.dayHours,
                                    range: range, now: context.date)
            let growth = visible.filter { $0.event.kind == .growth && $0.event.deletedAt == nil && $0.event.babyID == babyID }
                .sorted { ($0.event.startedAt, $0.event.id) < ($1.event.startedAt, $1.event.id) }
            let rhythmTiles = RhythmTiles(days: Self.hidesRhythm ? [] : rhythm, zone: zone, dayHours: data.householdSettings.dayHours)
            let growthTile = GrowthTile(entries: growth, zone: zone) { addingGrowth = true }
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Graphs")
                        .feedText(.title)
                        .accessibilityAddTraits(.isHeader)
                    Picker("Time shown", selection: $rangeName) {
                        Text("7 days").tag(GraphRange.week.rawValue)
                        Text("4 weeks").tag(GraphRange.fourWeeks.rawValue)
                        Text("All").tag(GraphRange.all.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 2)
                    if days.isEmpty && rhythm.isEmpty {
                        growthTile
                        Tile {
                            Text("No feeds logged yet.")
                                .feedText(.body)
                                .foregroundStyle(Theme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if width >= 2 * 340 + 11 {
                        // Two side by side when the unfolded Duo is wide enough (an even number
                        // of columns, as Apple advises).
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 11, alignment: .top),
                                            GridItem(.flexible(), spacing: 11, alignment: .top)],
                                  alignment: .leading, spacing: 11) {
                            rhythmTiles
                            growthTile
                            GraphTiles(days: days, zone: zone)
                        }
                    } else {
                        // One column on a phone and the folded Duo.
                        VStack(alignment: .leading, spacing: 11) {
                            rhythmTiles
                            growthTile
                            GraphTiles(days: days, zone: zone)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { width = $0 }
            }
            .defaultScrollAnchor(Self.startsAtBottom ? .bottom : nil)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        // The big Fredoka title is on the page; "Graphs" stays the screen's name.
        .navigationTitle("Graphs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .sheet(isPresented: $addingGrowth) {
            if let me = model.me {
                CareEditor(mode: .newGrowth, me: me, babyID: model.baby?.name ?? "")
            }
        }
    }

    /// Feeding Dev only: launch with `-graphsHideRhythm YES` to leave the rhythm tiles out, so the
    /// weight graph is at the top, for screenshots.
    private static var hidesRhythm: Bool {
        #if FEEDING_DEV
        UserDefaults.standard.bool(forKey: "graphsHideRhythm")
        #else
        false
        #endif
    }

    /// Feeding Dev only: launch with `-graphsAtBottom YES` to open the page scrolled to its end,
    /// for screenshots of the lower tiles.
    private static var startsAtBottom: Bool {
        #if FEEDING_DEV
        UserDefaults.standard.bool(forKey: "graphsAtBottom")
        #else
        false
        #endif
    }
}

/// The tiles, each only when it has something to show.
struct GraphTiles: View {
    let days: [GraphDay]
    let zone: TimeZone

    private var keys: [String] { days.map(\.date.description) }
    private var isWeek: Bool { days.count <= 7 }
    /// Numbers on the bars only when there is room for them.
    private var showsValues: Bool { isWeek }
    private var bar: MarkDimension { .ratio(isWeek ? 0.55 : 0.7) }

    /// The amount axis, with room above the tallest bar for its number.
    private func scale(_ largest: Int) -> ClosedRange<Double> {
        0...max(1, Double(largest) * (showsValues ? 1.22 : 1.05))
    }

    var body: some View {
        if days.contains(where: { $0.feeds > 0 }) { feeds }
        if days.contains(where: { $0.bottleML > 0 }) { bottles }
        if days.contains(where: { $0.longestGap != nil }) { gaps }
        if days.contains(where: { $0.leftSeconds + $0.rightSeconds > 0 }) { sides }
        if days.contains(where: { $0.pumpedML > 0 }) { pumped }
    }

    // MARK: The five graphs

    private var feeds: some View {
        Tile(label: "Feeds each day") {
            Chart(days) { day in
                BarMark(x: .value("Day", day.date.description), y: .value("Feeds", day.feeds), width: bar)
                    .cornerRadius(5)
                    .foregroundStyle(Theme.chart)
                    .opacity(day.isToday ? 0.45 : 1)
                    .annotation(position: .top, spacing: 2) { value("\(day.feeds)", day.feeds > 0) }
                    .accessibilityLabel(GraphText.spokenDay(day, in: zone))
                    .accessibilityValue(GraphText.feeds(day.feeds))
            }
            .chartYScale(domain: scale(days.map(\.feeds).max() ?? 0))
            .modifier(GraphAxes(keys: keys, labels: labels, yAxis: showsValues ? .hidden : .visible, unit: ""))
        }
    }

    private var bottles: some View {
        Tile(label: "Bottles each day · ml") {
            bottleKey
            Chart(days) { day in
                // Formula at the bottom, expressed milk on top; the total over the bar.
                BarMark(x: .value("Day", day.date.description), y: .value("ml", day.formulaML), width: bar)
                    .foregroundStyle(by: .value("Milk", "Formula"))
                    .cornerRadius(3)
                    .opacity(day.isToday ? 0.45 : 1)
                    .annotation(position: .top, spacing: 2) { value("\(day.bottleML)", day.expressedML == 0 && day.bottleML > 0) }
                    .accessibilityLabel(GraphText.spokenDay(day, in: zone))
                    .accessibilityValue(GraphText.bottles(day))
                BarMark(x: .value("Day", day.date.description), y: .value("ml", day.expressedML), width: bar)
                    .foregroundStyle(by: .value("Milk", "Expressed"))
                    .cornerRadius(3)
                    .opacity(day.isToday ? 0.45 : 1)
                    .annotation(position: .top, spacing: 2) { value("\(day.bottleML)", day.expressedML > 0) }
                    .accessibilityHidden(true)
            }
            .chartForegroundStyleScale(["Formula": Theme.bottleMark, "Expressed": Theme.bottleSoft])
            .chartLegend(.hidden)
            .chartYScale(domain: scale(days.map(\.bottleML).max() ?? 0))
            .modifier(GraphAxes(keys: keys, labels: labels, yAxis: showsValues ? .hidden : .visible, unit: ""))
        }
    }

    /// Each day: a soft bar from the shortest gap to the longest, and a dot for the middle one.
    private var gaps: some View {
        let longest = days.compactMap(\.longestGap).max() ?? 0
        let top = max(4, (longest / 3600 / 2).rounded(.up) * 2)
        return Tile(label: "Time between feeds") {
            gapKey
            Chart {
                ForEach(days) { day in
                    if let shortest = day.shortestGap, let longest = day.longestGap, let middle = day.middleGap {
                        BarMark(x: .value("Day", day.date.description),
                                yStart: .value("Shortest", shortest / 3600), yEnd: .value("Longest", longest / 3600),
                                width: .ratio(isWeek ? 0.3 : 0.6))
                            .cornerRadius(7)
                            .foregroundStyle(Theme.chart.opacity(0.3))
                            .opacity(day.isToday ? 0.45 : 1)
                            .accessibilityHidden(true)
                        PointMark(x: .value("Day", day.date.description), y: .value("Middle", middle / 3600))
                            .symbolSize(isWeek ? 70 : 24)
                            .foregroundStyle(Theme.chart)
                            .opacity(day.isToday ? 0.45 : 1)
                            .accessibilityLabel(GraphText.spokenDay(day, in: zone))
                            .accessibilityValue(GraphText.gaps(day))
                    }
                }
            }
            .chartYScale(domain: 0...top)
            .modifier(GraphAxes(keys: keys, labels: labels, yAxis: .visible, unit: "h", step: 2))
        }
    }

    private var sides: some View {
        Tile(label: "Breast each day · minutes") {
            sideKey
            Chart(days) { day in
                BarMark(x: .value("Day", day.date.description), y: .value("Minutes", Double(day.leftSeconds) / 60),
                        width: .ratio(0.85))
                    .foregroundStyle(by: .value("Side", "Left"))
                    .position(by: .value("Side", "Left"), axis: .horizontal, span: .ratio(isWeek ? 0.62 : 0.8))
                    .cornerRadius(3)
                    .opacity(day.isToday ? 0.45 : 1)
                    .accessibilityLabel(GraphText.spokenDay(day, in: zone))
                    .accessibilityValue(GraphText.sides(day))
                BarMark(x: .value("Day", day.date.description), y: .value("Minutes", Double(day.rightSeconds) / 60),
                        width: .ratio(0.85))
                    .foregroundStyle(by: .value("Side", "Right"))
                    .position(by: .value("Side", "Right"), axis: .horizontal, span: .ratio(isWeek ? 0.62 : 0.8))
                    .cornerRadius(3)
                    .opacity(day.isToday ? 0.45 : 1)
                    .accessibilityHidden(true)
            }
            .chartForegroundStyleScale(["Left": Theme.breastMark, "Right": Theme.breastSoft])
            .chartLegend(.hidden)
            .modifier(GraphAxes(keys: keys, labels: labels, yAxis: .visible, unit: "m", step: nil))
        }
    }

    private var pumped: some View {
        Tile(label: "Pumped each day · ml") {
            Chart(days) { day in
                BarMark(x: .value("Day", day.date.description), y: .value("ml", day.pumpedML), width: bar)
                    .cornerRadius(5)
                    .foregroundStyle(Theme.pumpMark)
                    .opacity(day.isToday ? 0.45 : 1)
                    .annotation(position: .top, spacing: 2) { value("\(day.pumpedML)", day.pumpedML > 0) }
                    .accessibilityLabel(GraphText.spokenDay(day, in: zone))
                    .accessibilityValue(GraphText.pumped(day))
            }
            .chartYScale(domain: scale(days.map(\.pumpedML).max() ?? 0))
            .modifier(GraphAxes(keys: keys, labels: labels, yAxis: showsValues ? .hidden : .visible, unit: ""))
        }
    }

    // MARK: Parts

    private var labels: [String: String] {
        Dictionary(uniqueKeysWithValues: GraphText.labelled(days).map {
            ($0.date.description, GraphText.axisLabel($0, in: zone, week: isWeek))
        })
    }

    @ViewBuilder
    private func value(_ text: String, _ shows: Bool) -> some View {
        if shows && showsValues {
            Text(text).feedText(.small).foregroundStyle(Theme.textMuted)
        }
    }

    private func keyItem(_ colour: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(colour).frame(width: 10, height: 10)
            Text(title)
        }
    }

    private var bottleKey: some View {
        HStack(spacing: 10) {
            keyItem(Theme.bottleMark, "Formula")
            keyItem(Theme.bottleSoft, "Expressed")
        }
        .modifier(KeyStyle())
    }

    private var sideKey: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                FeedMarkView(.side(.left), size: 12, relativeTo: .caption2, colour: Theme.breastMark)
                Text("Left")
            }
            HStack(spacing: 4) {
                FeedMarkView(.side(.right), size: 12, relativeTo: .caption2, colour: Theme.breastSoft)
                Text("Right")
            }
        }
        .modifier(KeyStyle())
    }

    private var gapKey: some View {
        HStack(spacing: 10) {
            keyItem(Theme.chart.opacity(0.3), "Shortest to longest")
            HStack(spacing: 4) {
                Circle().fill(Theme.chart).frame(width: 8, height: 8)
                Text("Middle")
            }
        }
        .modifier(KeyStyle())
    }
}

/// A key on its own line under a tile's label (as in the mockup), so a long label is never
/// squeezed; its sizes stop growing where Home's key does.
private struct KeyStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .feedText(.small)
            .foregroundStyle(Theme.textMuted)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// Every graph's axes: every day on the bottom (only some labelled), and the amounts up the right
/// side when the bars carry no numbers. Applied to the chart only, so the tile's label still grows.
private struct GraphAxes: ViewModifier {
    let keys: [String]
    let labels: [String: String]
    let yAxis: Visibility
    let unit: String
    var step: Double? = nil

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
            .frame(height: 140)
            .padding(.top, 4)
            // Day names and numbers stop growing where seven of them still fit across the tile
            // (as in Apple's Health app); each bar's day and number are read out by VoiceOver.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}
