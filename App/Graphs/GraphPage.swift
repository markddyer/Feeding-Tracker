import Charts
import FeedingCore
import SwiftUI

/// Which graph's page to open, on which day (or, for weight, which weight).
struct GraphPageRequest: Hashable {
    var kind: GraphKind
    var day: PlainDate?
    var weightID: String?
}

/// A graph's own page (the users' choice C, 21 Nov 2026, `docs/planning/10-graph-pages.md`): the
/// graph bigger, ‹ › to change the day, the day's totals, then the entries the day's bar counts,
/// in time order. A tap on another bar picks its day; a tap on an entry opens it to edit, as in
/// History. Two columns on the open Duo: the graph on the left, the entries on the right. Built
/// from the same rules as the bars (`graphDayDetails`, `rhythmDays`), so the two always agree.
struct GraphPage: View {
    let request: GraphPageRequest
    private let model = AppModel.shared
    /// The same 7 days / 4 weeks / All as the Graphs tab.
    @AppStorage("graphs.range") private var rangeName = GraphRange.week.rawValue
    @State private var picked: PlainDate?
    @State private var pickedWeight: String?
    @State private var width: CGFloat = 0
    @State private var editing: EventEditor.Mode?
    @State private var careEditing: CareEditor.Mode?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let facts = PageFacts(kind: request.kind, data: model.store.data, babyID: model.baby?.name ?? "",
                                  range: request.kind == .rhythm ? .all : GraphRange(rawValue: rangeName) ?? .week,
                                  wanted: picked ?? request.day, now: context.date)
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 11) {
                        if request.kind == .weight {
                            weightPage(facts, now: context.date)
                        } else if let day = facts.day {
                            let top = VStack(alignment: .leading, spacing: 11) { dayTop(facts, day: day) }
                            let list = VStack(alignment: .leading, spacing: 8) { dayEntries(facts, day: day, now: context.date) }
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
                                Text("Nothing logged yet.")
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
                .onAppear {
                    if let id = request.weightID { scroller.scrollTo(id, anchor: .center) }
                }
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(GraphText.title(request.kind))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { mode in
            if let me = model.me { EventEditor(mode: mode, me: me, babyID: model.baby?.name ?? "") }
        }
        .sheet(item: $careEditing) { mode in
            if let me = model.me { CareEditor(mode: mode, me: me, babyID: model.baby?.name ?? "") }
        }
    }

    // MARK: A day's graph: the graph, the day, its totals

    @ViewBuilder
    private func dayTop(_ facts: PageFacts, day: PlainDate) -> some View {
        if request.kind != .rhythm {
            Picker("Time shown", selection: $rangeName) {
                Text("7 days").tag(GraphRange.week.rawValue)
                Text("4 weeks").tag(GraphRange.fourWeeks.rawValue)
                Text("All").tag(GraphRange.all.rawValue)
            }
            .pickerStyle(.segmented)
        }
        Tile {
            if GraphKey.shows(request.kind) {
                GraphKey(kind: request.kind, dayHours: facts.dayHours)
            }
            switch request.kind {
            case .rhythm:
                if let row = facts.rhythmDay {
                    RhythmHourLabels()
                    RhythmRow(day: row, zone: facts.zone, label: RhythmText.rowLabel(row, in: facts.zone, week: true))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(RhythmText.spokenDay(row, in: facts.zone))
                        .accessibilityValue(RhythmText.spokenRhythm(row))
                }
            case .asleep, .nappies:
                RhythmGraphChart(kind: request.kind, days: facts.rhythmDays, zone: facts.zone, selected: day, height: 200) { picked = $0 }
            default:
                FeedGraphChart(kind: request.kind, days: facts.graphDays, zone: facts.zone, selected: day, height: 200) { picked = $0 }
            }
        }
        DayStepper(day: day, dates: facts.dates, today: facts.today, zone: facts.zone) { picked = $0 }
        FlowLayout(spacing: 6) {
            ForEach(Array(summary(facts).enumerated()), id: \.offset) { _, chip in
                Chip(chip.mark, chip.text, background: Theme.surface)
            }
        }
        if request.kind == .gaps {
            Text(GraphText.gapsExplained)
                .feedText(.small)
                .foregroundStyle(Theme.textMuted)
        }
    }

    /// The day's totals, as chips: the bar's own numbers, and a little more.
    private func summary(_ facts: PageFacts) -> [SummaryChip] {
        var chips: [SummaryChip] = []
        func add(_ mark: FeedMark?, _ text: String) { chips.append(SummaryChip(mark: mark, text: text)) }
        let time = GraphText.elapsed
        if let g = facts.graphDay {
            switch request.kind {
            case .bottles:
                add(.bottle, "\(g.bottleML) ml")
                if g.formulaML > 0 { add(nil, "Formula \(g.formulaML) ml") }
                if g.expressedML > 0 { add(nil, "Expressed \(g.expressedML) ml") }
            case .gaps:
                if let shortest = g.shortestGap, let longest = g.longestGap, let middle = g.middleGap {
                    if g.gaps.count == 1 {
                        add(nil, "One gap · \(time(shortest))")
                    } else {
                        add(nil, "Shortest \(time(shortest))")
                        add(nil, "Middle \(time(middle))")
                        add(nil, "Longest \(time(longest))")
                    }
                }
            case .breast:
                add(.side(.left), "Left \(time(TimeInterval(g.leftSeconds)))")
                add(.side(.right), "Right \(time(TimeInterval(g.rightSeconds)))")
                add(nil, GraphText.count(facts.details?.breastFeeds.count ?? 0, "feed", "feeds"))
            case .pumped:
                add(.pump, "\(g.pumpedML) ml")
                add(nil, GraphText.count(g.pumpSessions, "session", "sessions"))
            default:
                add(nil, GraphText.count(g.feeds, "feed", "feeds"))
                if g.leftSeconds + g.rightSeconds > 0 { add(.side(.left), time(TimeInterval(g.leftSeconds + g.rightSeconds))) }
                if g.bottleML > 0 { add(.bottle, "\(g.bottleML) ml") }
                if let shortest = g.shortestGap, let longest = g.longestGap {
                    add(nil, shortest == longest ? "Gap \(time(shortest))" : "Gaps \(time(shortest)) to \(time(longest))")
                }
            }
        } else if let r = facts.rhythmDay {
            switch request.kind {
            case .asleep:
                add(.sleep, "Asleep \(time(r.sleepSeconds))")
                add(nil, "Night \(time(r.nightSleepSeconds))")
                add(nil, "Day \(time(r.daySleepSeconds))")
            case .nappies:
                add(nil, GraphText.count(r.nappies.count, "nappy", "nappies"))
                add(.wee, GraphText.count(r.wees, "wee", "wees"))
                add(.poo, GraphText.count(r.poos, "poo", "poos"))
            default:
                add(.sleep, "Asleep \(time(r.sleepSeconds))")
                add(nil, GraphText.count(r.feeds.count, "feed", "feeds"))
                add(nil, GraphText.count(r.nappies.count, "nappy", "nappies"))
            }
        }
        return chips
    }

    // MARK: A day's entries

    @ViewBuilder
    private func dayEntries(_ facts: PageFacts, day: PlainDate, now: Date) -> some View {
        let zone = facts.zone
        switch request.kind {
        case .gaps:
            let gaps = facts.details?.gaps ?? []
            let longest = gaps.count > 1 ? gaps.max { $0.seconds < $1.seconds }?.id : nil
            if gaps.isEmpty { nothing }
            ForEach(gaps) { gap in
                GapRow(gap: gap, day: day, zone: zone, longest: gap.id == longest)
            }
        case .feeds, .bottles, .breast, .pumped:
            let entries = feedEntries(facts.details)
            if entries.isEmpty { nothing }
            ForEach(entries, id: \.id) { snapshot in
                feedRow(snapshot, facts: facts, day: day)
            }
        case .asleep:
            let sleeps = facts.rhythmDay?.sleeps ?? []
            if sleeps.isEmpty { nothing }
            ForEach(sleeps) { sleep in sleepRow(sleep, facts: facts, day: day, now: now) }
        case .nappies:
            let nappies = facts.rhythmDay?.nappies ?? []
            if nappies.isEmpty { nothing }
            ForEach(nappies) { nappy in careRow(nappy.id, facts: facts, now: now) }
        default:
            let entries = facts.rhythmDay?.entries ?? []
            if entries.isEmpty { nothing }
            ForEach(entries) { entry in
                switch entry {
                case .sleep(let sleep): sleepRow(sleep, facts: facts, day: day, now: now)
                case .feed(let feed):
                    if let snapshot = facts.data.events[feed.id]?.snapshot { feedRow(snapshot, facts: facts, day: day) }
                case .nappy(let nappy): careRow(nappy.id, facts: facts, now: now)
                }
            }
        }
    }

    private var nothing: some View {
        Text(GraphText.nothingThatDay)
            .feedText(.body)
            .foregroundStyle(Theme.textMuted)
            .padding(.top, 4)
    }

    private func feedEntries(_ details: GraphDayDetails?) -> [EventSnapshot] {
        guard let details else { return [] }
        switch request.kind {
        case .bottles: return details.bottleFeeds
        case .breast: return details.breastFeeds
        case .pumped: return details.pumps
        default: return details.feeds
        }
    }

    private func feedRow(_ snapshot: EventSnapshot, facts: PageFacts, day: PlainDate) -> some View {
        Button {
            // Details from a newer app version can't be edited here.
            guard snapshot.payload != nil else { return }
            editing = .edit(id: snapshot.id)
        } label: {
            HistoryRow(snapshot, zone: facts.zone, answer: facts.who.doneBy(snapshot.id),
                       note: GraphText.feedTiming(snapshot, on: day, in: facts.zone))
        }
        .buttonStyle(PressStyle())
        .accessibilityHint(snapshot.payload == nil ? "" : "Opens it to change")
    }

    @ViewBuilder
    private func sleepRow(_ sleep: RhythmSleep, facts: PageFacts, day: PlainDate, now: Date) -> some View {
        if let snapshot = facts.data.events[sleep.id]?.snapshot {
            let crosses = sleep.fromDayBefore || sleep.intoNextDay
            careButton(snapshot, row: CareRow(snapshot, zone: facts.zone, now: now, answer: facts.who.doneBy(sleep.id),
                                              timeText: GraphText.clock(sleep.spanStart, on: day, in: facts.zone),
                                              note: crosses ? GraphText.partOfSleep(sleep.end.timeIntervalSince(sleep.start),
                                                                                    on: day, in: facts.zone) : nil))
        }
    }

    @ViewBuilder
    private func careRow(_ id: String, facts: PageFacts, now: Date) -> some View {
        if let snapshot = facts.data.events[id]?.snapshot {
            careButton(snapshot, row: CareRow(snapshot, zone: facts.zone, now: now, answer: facts.who.doneBy(id)))
        }
    }

    private func careButton(_ snapshot: EventSnapshot, row: CareRow) -> some View {
        Button {
            guard snapshot.payload != nil else { return }
            careEditing = .edit(id: snapshot.id)
        } label: {
            row
        }
        .buttonStyle(PressStyle())
        .accessibilityHint(snapshot.payload == nil ? "" : "Opens it to change")
    }

    // MARK: Weight: the line, then every weight, newest first

    @ViewBuilder
    private func weightPage(_ facts: PageFacts, now: Date) -> some View {
        let selected = pickedWeight ?? request.weightID
        if let latest = facts.weights.last {
            Tile {
                if facts.weights.count > 1 {
                    WeightChart(weights: facts.weights, zone: facts.zone, selected: selected, height: 200) { pickedWeight = $0 }
                } else {
                    Text(CareText.weight(latest.grams)).feedText(.total)
                }
            }
            FlowLayout(spacing: 6) {
                Chip(.growth, CareText.weight(latest.grams), background: Theme.surface)
                Chip(nil, GraphText.count(facts.weights.count, "weight", "weights"), background: Theme.surface)
            }
        }
        if facts.growthEntries.isEmpty { nothing }
        ForEach(facts.growthEntries.reversed(), id: \.id) { snapshot in
            let weight = facts.weights.first { $0.id == snapshot.id }
            let change = weight.flatMap { entry in
                entry.change.flatMap { grams in entry.previousAt.map { GraphText.weightChange(grams, since: $0, in: facts.zone) } }
            }
            careButton(snapshot, row: CareRow(snapshot, zone: facts.zone, now: now, answer: facts.who.doneBy(snapshot.id),
                                              timeText: GraphText.shortDate(snapshot.event.startedAt, in: facts.zone),
                                              note: change))
                .overlay {
                    if snapshot.id == selected {
                        RoundedRectangle(cornerRadius: 18).stroke(Theme.text, lineWidth: 2)
                    }
                }
                .accessibilityAddTraits(snapshot.id == selected ? .isSelected : [])
                .id(snapshot.id)
        }
    }
}

/// One of a day's totals.
private struct SummaryChip {
    let mark: FeedMark?
    let text: String
}

/// What the page needs, worked out once per redraw.
private struct PageFacts {
    let data: HouseholdData
    let zone: TimeZone
    let dayHours: DayHours
    let today: PlainDate
    let who: WhoDidIt
    var graphDays: [GraphDay] = []
    var rhythmDays: [RhythmDay] = []
    var details: GraphDayDetails?
    var weights: [WeightEntry] = []
    var growthEntries: [EventSnapshot] = []
    /// The days the graph shows, oldest first, and the one picked: kept inside them.
    var dates: [PlainDate] = []
    var day: PlainDate?

    @MainActor
    init(kind: GraphKind, data: HouseholdData, babyID: String, range: GraphRange, wanted: PlainDate?, now: Date) {
        self.data = data
        zone = data.householdSettings.timeZone
        dayHours = data.householdSettings.dayHours
        today = PlainDate(now, in: zone)
        who = data.whoDidIt(babyID: babyID, now: now)
        let visible = data.visibleSnapshots(babyID: babyID)
        switch kind {
        case .weight:
            weights = FeedingCore.weights(visible, babyID: babyID)
            growthEntries = visible.filter { $0.event.kind == .growth && $0.event.deletedAt == nil && $0.event.babyID == babyID }
                .sorted { ($0.event.startedAt, $0.event.id) < ($1.event.startedAt, $1.event.id) }
        case _ where kind.isFeedGraph:
            graphDays = FeedingCore.graphDays(visible, babyID: babyID, timeZone: zone, range: range, now: now)
            dates = graphDays.map(\.date)
        default:
            rhythmDays = FeedingCore.rhythmDays(visible, babyID: babyID, timeZone: zone, dayHours: dayHours, range: range, now: now)
            dates = rhythmDays.map(\.date)
        }
        if let first = dates.first, let last = dates.last {
            day = min(max(wanted ?? last, first), last)
        }
        if kind.isFeedGraph, let day {
            details = graphDayDetails(visible, babyID: babyID, timeZone: zone, day: day, now: now)
        }
    }

    var graphDay: GraphDay? { graphDays.first { $0.date == day } }
    var rhythmDay: RhythmDay? { rhythmDays.first { $0.date == day } }
}

/// "‹ Tuesday 17 Nov ›": back to the graph's first day, forward up to today.
private struct DayStepper: View {
    let day: PlainDate
    let dates: [PlainDate]
    let today: PlainDate
    let zone: TimeZone
    let pick: (PlainDate) -> Void

    var body: some View {
        let index = dates.firstIndex(of: day)
        HStack {
            Button { if let index, index > 0 { pick(dates[index - 1]) } } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled((index ?? 0) == 0)
            .accessibilityLabel("Day before")
            Spacer()
            Text(GraphText.dayName(day, today: today, in: zone))
                .feedText(.smallButton)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { if let index, index < dates.count - 1 { pick(dates[index + 1]) } } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(index.map { $0 >= dates.count - 1 } ?? true)
            .accessibilityLabel("Day after")
        }
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(Theme.text)
    }
}

/// One gap between two feeds: "22:05 · to 00:40 · 2h 35m", with "Longest" under the longest.
private struct GapRow: View {
    let gap: FeedGap
    let day: PlainDate
    let zone: TimeZone
    let longest: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(GraphText.clock(gap.from, on: day, in: zone))
                .feedText(.smallButton)
                .fixedSize()
                .frame(minWidth: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Chip(nil, "to \(GraphText.clock(gap.to, on: day, in: zone))")
                if longest {
                    Text(GraphText.longest)
                        .feedText(.small)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(GraphText.elapsed(gap.seconds))
                .feedText(.smallButton)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(GraphText.clock(gap.from, on: day, in: zone)) to \(GraphText.clock(gap.to, on: day, in: zone)): "
            + HomeText.spokenElapsed(gap.seconds) + (longest ? ". Longest." : "."))
    }
}
