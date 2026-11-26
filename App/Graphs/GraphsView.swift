import Charts
import FeedingCore
import FeedingInsights
import SwiftUI

/// The Graphs tab (plan v1, Phase 2; the user's choices of 16 Nov 2026, from
/// `designs/graphs-20261116/`): one long page, a tile per graph, and a 7 days / 4 weeks / All
/// switch. Facts only: no target lines, no "normal" bands, no red or green. A graph with nothing
/// to show in the chosen time is left out, so a bottle-only phone sees no breast-side graph.
/// A tap on a graph opens its own page (the users' choice C, 21 Nov 2026): on the day tapped, or
/// on today from anywhere else on the tile.
struct GraphsView: View {
    private let model = AppModel.shared
    @AppStorage("graphs.range") private var rangeName = GraphRange.week.rawValue
    /// The weight graph's Add (the users' choice K, 17 Nov 2026).
    @State private var addingGrowth = false
    /// The page's width inside its margins, to choose one column or two.
    @State private var width: CGFloat = 0
    /// The graph page open now.
    @State private var page: GraphPageRequest?
    /// "Bottles through the day" (`14-bottles-through-the-day.md`), from its tile.
    @State private var bottlesPage: BottlesThroughDayRequest?
    /// "This week" (AI insights, AI11), and the graph page one of its lines asked for: opened once
    /// the card has closed, the same way as a tap on a graph (one navigation style, 21 Nov 2026).
    @State private var weekCardOpen = false
    @State private var pageAfterCard: GraphPageRequest?

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
            let open: (GraphKind, PlainDate?) -> Void = { page = GraphPageRequest(kind: $0, day: $1) }
            let bottles = bottlesThroughDay(visible, babyID: babyID, timeZone: zone, now: context.date)
            let feedTiles = GraphTiles(days: days, zone: zone, open: open, bottles: bottles, now: context.date,
                                       openBottles: { bottlesPage = BottlesThroughDayRequest() })
            let rhythmTiles = RhythmTiles(days: Self.hidesRhythm ? [] : rhythm, zone: zone, dayHours: data.householdSettings.dayHours,
                                          open: open)
            let growthTile = GrowthTile(weights: weights(visible, babyID: babyID), entries: growthEntries(visible, babyID: babyID),
                                        zone: zone, add: { addingGrowth = true },
                                        open: { page = GraphPageRequest(kind: .weight, weightID: $0) })
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Graphs")
                        .feedText(.title)
                        .accessibilityAddTraits(.isHeader)
                    // Last week's AI card, Monday to Sunday (step 2 D5, D15).
                    let week = CardShown.now(.week, at: context.date)
                    if week.isAI {
                        AICardLine(title: weekTitle(week), shown: week) { weekCardOpen = true }
                    }
                    Picker("Time shown", selection: $rangeName) {
                        Text("7 days").tag(GraphRange.week.rawValue)
                        Text("4 weeks").tag(GraphRange.fourWeeks.rawValue)
                        Text("All").tag(GraphRange.all.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 2)
                    // Who did what, the last 7 nights; tap for the page (DD3, DD9).
                    WhoDidWhatTile(who: data.whoDidIt(babyID: babyID, now: context.date),
                                   today: PlainDate(context.date, in: zone), zone: zone)
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
                            feedTiles
                        }
                    } else {
                        // One column on a phone and the folded Duo.
                        VStack(alignment: .leading, spacing: 11) {
                            rhythmTiles
                            growthTile
                            feedTiles
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
        .navigationDestination(item: $page) { GraphPage(request: $0) }
        .navigationDestination(item: $bottlesPage) { BottlesThroughDayPage(request: $0) }
        .task {
            #if FEEDING_DEV
            // `-graphsSheet week`: "This week" open at launch, for screenshots.
            if UserDefaults.standard.string(forKey: "graphsSheet") == "week" { weekCardOpen = true }
            #endif
        }
        .sheet(isPresented: $weekCardOpen, onDismiss: {
            // A line can name a day older than the range shows: widen it, or the page would open
            // on another day than the line's.
            if let day = pageAfterCard?.day {
                let today = PlainDate(Date(), in: model.store.data.householdSettings.timeZone)
                rangeName = (GraphRange(rawValue: rangeName) ?? .week).fitting(day, today: today).rawValue
            }
            page = pageAfterCard
            pageAfterCard = nil
        }) {
            InsightCardSheet(kind: .week, openGraph: { pageAfterCard = GraphPageRequest(kind: $0, day: $1) })
        }
        .sheet(isPresented: $addingGrowth) {
            if let me = model.me {
                CareEditor(mode: .newGrowth, me: me, babyID: model.baby?.name ?? "")
            }
        }
    }

    /// "This week · Mon 17 to Sun 23 Nov".
    private func weekTitle(_ shown: CardShown) -> String {
        if case .card(_, let period) = shown { return "This week · \(CardText.weekShort(period.days))" }
        return "This week"
    }

    /// Every growth entry of the baby, oldest first, for the tile's length and head line.
    private func growthEntries(_ visible: [EventSnapshot], babyID: String) -> [EventSnapshot] {
        visible.filter { $0.event.kind == .growth && $0.event.deletedAt == nil && $0.event.babyID == babyID }
            .sorted { ($0.event.startedAt, $0.event.id) < ($1.event.startedAt, $1.event.id) }
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

/// The five feed graphs, each only when it has something to show, and "Bottles through the day"
/// under the feeds when a bottle was logged today or in the 7 days before.
struct GraphTiles: View {
    let days: [GraphDay]
    let zone: TimeZone
    let open: (GraphKind, PlainDate?) -> Void
    var bottles: BottlesThroughDay?
    var now = Date()
    var openBottles: () -> Void = {}

    var body: some View {
        if days.contains(where: { $0.feeds > 0 }) { tile(.feeds) }
        if let bottles, bottles.hasBottles {
            BottlesThroughDayTile(facts: bottles, zone: zone, now: now, open: openBottles)
        }
        if days.contains(where: { $0.bottleML > 0 }) { tile(.bottles) }
        if days.contains(where: { $0.longestGap != nil }) { tile(.gaps) }
        if days.contains(where: { $0.leftSeconds + $0.rightSeconds > 0 }) { tile(.breast) }
        if days.contains(where: { $0.pumpedML > 0 }) { tile(.pumped) }
    }

    private func tile(_ kind: GraphKind) -> some View {
        GraphTile(kind: kind, open: open) {
            FeedGraphChart(kind: kind, days: days, zone: zone) { open(kind, $0) }
        }
    }
}

/// A graph's tile: its label with a ›, its key, then the graph. A tap on a day opens the graph's
/// page on that day; a tap anywhere else on the tile, or on the ›, opens it on today.
struct GraphTile<Content: View>: View {
    let kind: GraphKind
    var dayHours: DayHours = .standard
    var accessory: AnyView?
    let open: (GraphKind, PlainDate?) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Tile(label: GraphText.tileLabel(kind), accessory: AnyView(HStack(spacing: 8) {
            accessory
            GraphOpenButton(kind: kind) { open(kind, nil) }
        })) {
            if GraphKey.shows(kind) {
                GraphKey(kind: kind, dayHours: dayHours)
            }
            content
        }
        .contentShape(Rectangle())
        .onTapGesture { open(kind, nil) }
    }
}

/// The › on a graph's tile: for VoiceOver and Voice Control, the way to the graph's page.
struct GraphOpenButton: View {
    let kind: GraphKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textMuted)
                .frame(minWidth: 28, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GraphText.showEntries)
        .accessibilityHint(GraphText.title(kind))
    }
}
