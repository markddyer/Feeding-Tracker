import Charts
import FeedingCore
import SwiftUI

// "Bottles through the day" (Parent A, 26 Nov 2026, look A, `docs/planning/14-bottles-through-the-day.md`):
// the bottles logged from midnight, beside the day before by the same clock time and the average of
// the 7 days before by that time, as a line that climbs through the day. Opened from a line in
// Home's Today and a tile on the Graphs tab. Facts only: no "too much", no limit line, no "normal"
// band, no red or green, no up or down arrows. A breastfeed has no amount, so only bottles add up.

/// Which day the page opens on: today when nil.
struct BottlesThroughDayRequest: Hashable {
    var day: PlainDate?
}

/// The page: ‹ day ›, the three numbers, the line with its key, what isn't counted, the NHS's
/// bottle-feeding pages, then the day's bottles, each with its running total. A tap on a bottle
/// opens it to change, as in History. Two columns on the open Duo.
struct BottlesThroughDayPage: View {
    let request: BottlesThroughDayRequest
    private let model = AppModel.shared
    @State private var picked: PlainDate?
    @State private var width: CGFloat = 0
    @State private var editing: EventEditor.Mode?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            // A fresh instant on every redraw (each minute, and each change to the log), so a bottle
            // saved a moment ago is never taken for one after now (Codex review, 5).
            let now = Date()
            let data = model.store.data
            let zone = data.householdSettings.timeZone
            let babyID = model.baby?.name ?? ""
            let facts = Self.facts(data.visibleSnapshots(babyID: babyID), babyID: babyID, zone: zone,
                                   wanted: picked ?? request.day, now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    if let facts {
                        let top = VStack(alignment: .leading, spacing: 11) { pageTop(facts, zone: zone, now: now) }
                        let list = VStack(alignment: .leading, spacing: 8) {
                            rows(facts, data: data, babyID: babyID, zone: zone, now: now)
                        }
                        if width >= 594 - 32 {
                            HStack(alignment: .top, spacing: 11) {
                                top.frame(maxWidth: .infinity, alignment: .topLeading)
                                list.frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        } else {
                            top
                            list
                        }
                    } else {
                        Tile {
                            Text(BottlesText.nothingYet)
                                .feedText(.body)
                                .foregroundStyle(Theme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { width = $0 }
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(BottlesText.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { mode in
            if let me = model.me { EventEditor(mode: mode, me: me, babyID: model.baby?.name ?? "") }
        }
    }

    /// The day asked for, kept between the first day logged and today.
    static func facts(_ visible: [EventSnapshot], babyID: String, zone: TimeZone, wanted: PlainDate?,
                      now: Date) -> BottlesThroughDay? {
        guard let today = bottlesThroughDay(visible, babyID: babyID, timeZone: zone, now: now) else { return nil }
        guard let wanted, wanted != today.date else { return today }
        let day = min(max(wanted, today.firstDate), today.today)
        return bottlesThroughDay(visible, babyID: babyID, timeZone: zone, date: day, now: now) ?? today
    }

    @ViewBuilder
    private func pageTop(_ facts: BottlesThroughDay, zone: TimeZone, now: Date) -> some View {
        BottlesDayStepper(facts: facts, zone: zone, now: now) { picked = $0 }
        BottlesNumbers(facts: facts, zone: zone, now: now)
        Tile {
            BottlesThroughDayChart(facts: facts, zone: zone, now: now, height: 210)
            BottlesKey(facts: facts)
        }
        if let note = BottlesText.alsoNote(facts) {
            Text(note)
                .feedText(.small)
                .foregroundStyle(Theme.textMuted)
                .accessibilityIdentifier("bottlesAlso")
        }
        NHSLinkRow(subject: .bottles)
    }

    @ViewBuilder
    private func rows(_ facts: BottlesThroughDay, data: HouseholdData, babyID: String, zone: TimeZone, now: Date) -> some View {
        let who = data.whoDidIt(babyID: babyID, now: now)
        if facts.day.steps.isEmpty {
            Text(BottlesText.noBottles(facts))
                .feedText(.body)
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 4)
        }
        ForEach(facts.day.steps) { step in
            if let snapshot = data.events[step.id]?.snapshot {
                Button {
                    // Details from a newer app version can't be edited here.
                    guard snapshot.payload != nil else { return }
                    editing = .edit(id: snapshot.id)
                } label: {
                    HistoryRow(snapshot, zone: zone, answer: who.doneBy(snapshot.id), note: BottlesText.runningTotal(step.total))
                }
                .buttonStyle(PressStyle())
                .accessibilityHint(snapshot.payload == nil ? "" : "Opens it to change")
            }
        }
    }
}

/// "‹ Today, by 15:20 ›": back to the first day logged, forward up to today.
private struct BottlesDayStepper: View {
    let facts: BottlesThroughDay
    let zone: TimeZone
    let now: Date
    let pick: (PlainDate) -> Void

    var body: some View {
        HStack {
            Button { pick(facts.date.adding(days: -1)) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(facts.date <= facts.firstDate)
            .accessibilityLabel("Day before")
            Spacer()
            Text(BottlesText.dayHeading(facts, zone: zone, now: now))
                .feedText(.smallButton)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { pick(facts.date.adding(days: 1)) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(facts.date >= facts.today)
            .accessibilityLabel("Day after")
        }
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(Theme.text)
    }
}

/// The three numbers: the day so far (in the bottle tint), the day before by the same time, and the
/// average by the same time, each of the last two with the plain difference under it (Parent A's
/// choice B, 26 Nov 2026: "Difference + 40 ml", like the weight's "+ 140 g since 12 Nov"). Side by
/// side; one under another at the largest text sizes.
private struct BottlesNumbers: View {
    let facts: BottlesThroughDay
    let zone: TimeZone
    let now: Date
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 6))
        layout {
            ForEach(BottlesText.numbers(facts, zone: zone, now: now)) { number in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if number.main { FeedMarkView(.bottle, size: 12, relativeTo: .caption2) }
                        Text(number.label).feedText(.small).foregroundStyle(Theme.textMuted)
                    }
                    Text("\(number.ml) ml").feedText(.total).monospacedDigit()
                    if let difference = number.difference {
                        Text(BottlesText.difference(difference)).feedText(.small).monospacedDigit().foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(number.main ? Theme.bottleTint : Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(number.label): \(number.ml) ml" + (number.difference.map { ". " + BottlesText.difference($0) } ?? ""))
                .accessibilityIdentifier(number.main ? "bottlesSoFar" : "bottlesNumber")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The line that climbs: the day (bottle blue, thick, to now on today), the day before (muted) and
/// the average (muted, dotted), each a step at each bottle. On the page a finger slid along reads
/// any time; the tile's small one has no axes.
struct BottlesThroughDayChart: View {
    let facts: BottlesThroughDay
    let zone: TimeZone
    let now: Date
    var height: CGFloat = 210
    var small = false
    @State private var selected: Double?

    private struct Point {
        let hour: Double
        let ml: Double
    }

    private static func hour(_ clockSecond: Int) -> Double { Double(clockSecond) / 3600 }

    private func line(_ day: BottleDay, to end: Double, total: Int) -> [Point] {
        [Point(hour: 0, ml: 0)] + day.steps.map { Point(hour: Self.hour($0.clockSecond), ml: Double($0.total)) }
            + [Point(hour: end, ml: Double(total))]
    }

    private var dayEnd: Double {
        guard facts.isToday else { return 24 }
        return Self.hour(max(facts.cutOff, facts.day.steps.last?.clockSecond ?? 0))
    }

    private var dayPoints: [Point] { line(facts.day, to: dayEnd, total: facts.soFar) }
    private var beforePoints: [Point] { facts.dayBefore.map { line($0, to: 24, total: $0.whole) } ?? [] }
    private var averagePoints: [Point] {
        guard BottlesText.showsAverage(facts) else { return [] }
        // To the nearest 5 ml, as its number and the bubble say (Codex review, 6).
        return facts.averageSteps.map { Point(hour: Self.hour($0.clockSecond), ml: Double(BottlesText.rounded($0.ml))) }
            + [Point(hour: 24, ml: Double(BottlesText.rounded(facts.average(by: BottlesThroughDay.secondsInClockDay) ?? 0)))]
    }

    /// The amount axis, to the next 100 ml above the tallest line, with a little room.
    private var top: Double {
        let largest = (dayPoints + beforePoints + averagePoints).map(\.ml).max() ?? 0
        return max(100, (largest * 1.08 / 100).rounded(.up) * 100)
    }

    var body: some View {
        chart
            .chartXScale(domain: 0...24)
            .chartYScale(domain: 0...top)
            .chartXAxis(small ? .hidden : .automatic)
            .chartYAxis(small ? .hidden : .automatic)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel {
                        if let hour = value.as(Double.self) {
                            Text(hour < 10 ? "0\(Int(hour))" : "\(Int(hour))").feedText(.small).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel {
                        if let ml = value.as(Double.self) {
                            Text("\(Int(ml))").feedText(.small).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .modifier(Scrub(selected: $selected, on: !small))
            .frame(height: height)
            .padding(.top, small ? 0 : 4)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BottlesText.spokenChart(facts, zone: zone, now: now))
            // VoiceOver reads any hour as a finger does: swipe up or down (Codex review, 3).
            .accessibilityValue(selected.map { BottlesText.scrubLines(facts, at: Int($0 * 3600)).joined(separator: ". ") } ?? "")
            .accessibilityHint(small ? "" : "Swipe up or down to read the amounts at another hour.")
            .accessibilityAdjustableAction { direction in
                guard !small else { return }
                let start = selected ?? (Double(facts.cutOff) / 3600).rounded(.down)
                let step: Double = selected == nil ? 0 : 1
                switch direction {
                case .increment: selected = min(24, start + step)
                case .decrement: selected = max(0, start - step)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("bottlesChart")
    }

    private var chart: some View {
        Chart {
            ForEach(Array(averagePoints.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Time", point.hour), y: .value("ml", point.ml), series: .value("Line", "average"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Theme.textMuted)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 4]))
            }
            ForEach(Array(beforePoints.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Time", point.hour), y: .value("ml", point.ml), series: .value("Line", "before"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Theme.textMuted.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(Array(dayPoints.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Time", point.hour), y: .value("ml", point.ml), series: .value("Line", "day"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Theme.bottleMark)
                    .lineStyle(StrokeStyle(lineWidth: small ? 3 : 3.5, lineJoin: .round))
            }
            if facts.isToday {
                RuleMark(x: .value("Now", Self.hour(facts.cutOff)))
                    .foregroundStyle(Theme.textMuted.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("Now", dayEnd), y: .value("ml", Double(facts.soFar)))
                    .foregroundStyle(Theme.bottleMark)
                    .symbolSize(small ? 30 : 50)
            }
            if let selected, !small {
                RuleMark(x: .value("Picked", selected))
                    .foregroundStyle(Theme.text)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, spacing: 2,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        bubble(Int(selected * 3600))
                    }
            }
        }
    }

    /// "By 09:00 · Today 310 ml · Yesterday 300 ml · Average 290 ml".
    private func bubble(_ second: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(BottlesText.scrubLines(facts, at: second), id: \.self) { line in
                Text(line)
            }
        }
        .feedText(.small)
        .monospacedDigit()
        .foregroundStyle(Theme.background)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.text, in: RoundedRectangle(cornerRadius: 12))
    }

    /// A finger slid along the page's chart picks a time; the tile's chart opens the page instead.
    private struct Scrub: ViewModifier {
        @Binding var selected: Double?
        let on: Bool

        func body(content: Content) -> some View {
            if on {
                content.chartXSelection(value: $selected)
            } else {
                content
            }
        }
    }
}

/// The key under the page's line.
private struct BottlesKey: View {
    let facts: BottlesThroughDay

    var body: some View {
        FlowLayout(spacing: 12) {
            item(BottlesText.dayKey(facts), Theme.bottleMark, width: 3.5)
            if facts.dayBefore != nil { item(BottlesText.beforeKey(facts), Theme.textMuted.opacity(0.75), width: 2) }
            if BottlesText.showsAverage(facts) { item(BottlesText.averageKey(facts), Theme.textMuted, width: 2, dash: [2, 4]) }
        }
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private func item(_ text: String, _ colour: Color, width: CGFloat, dash: [CGFloat] = []) -> some View {
        HStack(spacing: 5) {
            Path { path in
                path.move(to: CGPoint(x: 1, y: 4))
                path.addLine(to: CGPoint(x: 19, y: 4))
            }
            .stroke(colour, style: StrokeStyle(lineWidth: width, lineCap: dash.isEmpty ? .butt : .round, dash: dash))
            .frame(width: 20, height: 8)
            Text(text).feedText(.small).foregroundStyle(Theme.textMuted)
        }
    }
}

/// The tile on the Graphs tab, under "Feeds each day": today's total, the two others in a line, and
/// a small line with no axes. A tap anywhere, or on its ›, opens the page on today.
struct BottlesThroughDayTile: View {
    let facts: BottlesThroughDay
    let zone: TimeZone
    let now: Date
    let open: () -> Void

    var body: some View {
        Tile(label: BottlesText.tileLabel, accessory: AnyView(
            Button(action: open) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(minWidth: 28, minHeight: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(GraphText.showEntries)
            .accessibilityHint(BottlesText.title)
            .accessibilityIdentifier("bottlesTileOpen"))) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(facts.soFar) ml").feedText(.total).monospacedDigit().fixedSize()
                Text(BottlesText.tileLine(facts, zone: zone, now: now))
                    .feedText(.small)
                    .foregroundStyle(Theme.textMuted)
            }
            .accessibilityElement(children: .combine)
            BottlesThroughDayChart(facts: facts, zone: zone, now: now, height: 90, small: true)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

/// Inside Home's Today, under the totals: the bottles since midnight beside yesterday and the
/// average by now. A tap opens the page. Only when a bottle was logged today or in the 7 days before.
struct BottlesTodayLine: View {
    let facts: HomeFacts

    var body: some View {
        if let bottles = bottlesThroughDay(facts.visible, babyID: facts.babyID, timeZone: facts.settings.timeZone,
                                           now: facts.now), bottles.hasBottles {
            NavigationLink(value: BottlesThroughDayRequest(day: nil)) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        FeedMarkView(.bottle, size: 12, relativeTo: .caption2)
                        Text(BottlesText.homeHeading).feedText(.label).foregroundStyle(Theme.textMuted)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Text(BottlesText.homeLine(bottles))
                        .feedText(.smallButton)
                        .monospacedDigit()
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Theme.bottleTint, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(BottlesText.homeHeading): \(BottlesText.homeLine(bottles))")
            .accessibilityHint("Opens \(BottlesText.title)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("bottlesTodayLine")
        }
    }
}

/// The words of "Bottles through the day". Facts only: amounts, times and which day; never "more",
/// "less", "too much", "usual" or "normal".
enum BottlesText {
    static let title = "Bottles through the day"
    static let tileLabel = "Bottles through the day · ml"
    static let homeHeading = "Bottles since midnight"
    static let nothingYet = "No feeds logged yet."

    /// One of the three numbers. `difference`: the day's own total minus this one.
    struct Number: Identifiable {
        let label: String
        let ml: Int
        var main = false
        var difference: Int?
        var id: String { label }
    }

    /// "+ 40 ml", "− 20 ml", "0 ml": a plain difference, like the weight's "+ 140 g since 12 Nov".
    /// Never "more", "less", arrows or colours.
    static func signed(_ ml: Int) -> String {
        "\(ml > 0 ? "+ " : ml < 0 ? "− " : "")\(abs(ml)) ml"
    }

    /// Under the day before and the average: "Difference + 40 ml".
    static func difference(_ ml: Int) -> String { "Difference \(signed(ml))" }

    /// An average over fewer than 2 days would only repeat the day before.
    static func showsAverage(_ facts: BottlesThroughDay) -> Bool { facts.week.count >= 2 }

    /// The average to the nearest 5 ml.
    static func rounded(_ ml: Double) -> Int { Int((ml / 5).rounded()) * 5 }

    /// "15:20" on the household's clock.
    static func clock(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }

    /// "09:00", for a clock time picked on the line.
    static func clock(second: Int) -> String {
        let minutes = max(0, min(second, BottlesThroughDay.secondsInClockDay - 1)) / 60
        let h = minutes / 60, m = minutes % 60
        return "\(h < 10 ? "0" : "")\(h):\(m < 10 ? "0" : "")\(m)"
    }

    /// "Today, by 15:20", "Yesterday", "Tuesday 24 Nov".
    static func dayHeading(_ facts: BottlesThroughDay, zone: TimeZone, now: Date) -> String {
        facts.isToday ? "Today, by \(clock(now, in: zone))" : GraphText.dayName(facts.date, today: facts.today, in: zone)
    }

    /// "7-day average", or fewer days while the log is new.
    static func averageName(_ facts: BottlesThroughDay) -> String { "\(facts.week.count)-day average" }

    static func numbers(_ facts: BottlesThroughDay, zone: TimeZone, now: Date) -> [Number] {
        let by = facts.isToday ? " by \(clock(now, in: zone))" : ""
        var numbers = [Number(label: facts.isToday ? "Today" : "Whole day", ml: facts.soFar, main: true)]
        if let before = facts.dayBeforeByCutOff {
            numbers.append(Number(label: (facts.isToday ? "Yesterday" : "Day before") + by, ml: before,
                                  difference: facts.soFar - before))
        }
        if showsAverage(facts), let average = facts.averageByCutOff {
            numbers.append(Number(label: averageName(facts) + by, ml: rounded(average),
                                  difference: facts.soFar - rounded(average)))
        }
        return numbers
    }

    static func dayKey(_ facts: BottlesThroughDay) -> String { facts.isToday ? "Today" : "That day" }
    static func beforeKey(_ facts: BottlesThroughDay) -> String { facts.isToday ? "Yesterday" : "Day before" }
    static func averageKey(_ facts: BottlesThroughDay) -> String { averageName(facts) }

    /// What isn't in the total: "Also 1 breastfeed today, 18m. A breastfeed has no amount. 1 bottle
    /// had no amount logged." Nil when everything is counted.
    static func alsoNote(_ facts: BottlesThroughDay) -> String? {
        var parts: [String] = []
        let when = facts.isToday ? "today" : "that day"
        if facts.breastFeeds > 0 {
            let feeds = facts.breastFeeds == 1 ? "1 breastfeed" : "\(facts.breastFeeds) breastfeeds"
            let length = facts.breastSeconds > 0 ? ", \(GraphText.elapsed(TimeInterval(facts.breastSeconds)))" : ""
            parts.append("Also \(feeds) \(when)\(length). A breastfeed has no amount.")
        }
        if facts.bottlesWithNoAmount > 0 {
            parts.append(facts.bottlesWithNoAmount == 1 ? "1 bottle had no amount logged."
                         : "\(facts.bottlesWithNoAmount) bottles had no amount logged.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func noBottles(_ facts: BottlesThroughDay) -> String {
        facts.isToday ? "No bottles logged yet today." : "No bottles logged on this day."
    }

    /// Under a bottle's row: "520 ml from midnight".
    static func runningTotal(_ ml: Int) -> String { "\(ml) ml from midnight" }

    /// Home's line: "520 ml today · 480 ml yesterday by now · 500 ml average by now".
    static func homeLine(_ facts: BottlesThroughDay) -> String {
        var parts = ["\(facts.soFar) ml today"]
        if let before = facts.dayBeforeByCutOff { parts.append("\(before) ml yesterday by now") }
        if showsAverage(facts), let average = facts.averageByCutOff { parts.append("\(rounded(average)) ml average by now") }
        return parts.joined(separator: " · ")
    }

    /// The tile's line beside today's total: "by 15:20 · yesterday 480 · average 500".
    static func tileLine(_ facts: BottlesThroughDay, zone: TimeZone, now: Date) -> String {
        var parts = ["by \(clock(now, in: zone))"]
        if let before = facts.dayBeforeByCutOff { parts.append("yesterday \(before)") }
        if showsAverage(facts), let average = facts.averageByCutOff { parts.append("average \(rounded(average))") }
        return parts.joined(separator: " · ")
    }

    /// The bubble on the line at a picked time: "Yesterday 300 ml (+ 10 ml)". Today's own value, and
    /// so the differences, only up to now.
    static func scrubLines(_ facts: BottlesThroughDay, at second: Int) -> [String] {
        var lines = ["By \(clock(second: second))"]
        let own = !facts.isToday || second <= facts.cutOff ? facts.day.total(by: second) : nil
        if let own { lines.append("\(dayKey(facts)) \(own) ml") }
        func line(_ name: String, _ ml: Int) -> String {
            "\(name) \(ml) ml" + (own.map { " (\(signed($0 - ml)))" } ?? "")
        }
        if let before = facts.dayBefore { lines.append(line(beforeKey(facts), before.total(by: second))) }
        if showsAverage(facts), let average = facts.average(by: second) { lines.append(line("Average", rounded(average))) }
        return lines
    }

    /// VoiceOver's reading of the line.
    static func spokenChart(_ facts: BottlesThroughDay, zone: TimeZone, now: Date) -> String {
        var parts = ["A line of the bottles from midnight"]
        parts += numbers(facts, zone: zone, now: now).map { "\($0.label): \($0.ml) ml" }
        if facts.isToday, let before = facts.dayBefore { parts.append("Yesterday, the whole day: \(before.whole) ml") }
        return parts.joined(separator: ". ") + "."
    }
}
