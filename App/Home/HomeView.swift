import FeedingCore
import SwiftUI

/// The home screen (`docs/planning/05-visual-redesign.md`, "Home"): a greeting and the baby's
/// name, the time since the last feed started inside its ring, the window bar, the next side and
/// the last feed, the last 24 hours as a chart, and the row of nights. The feed buttons are pinned
/// at the bottom. Facts only: no targets, no verdicts.
struct HomeView: View {
    let me: MemberID
    let babyID: String

    /// Shared with the Duo's second column, whose "I'll take it" shows its Undo bar here.
    @Binding var undo: UndoAction?

    private let model = AppModel.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.secondColumnShowing) private var secondColumnShowing

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let facts = HomeFacts(data: model.store.data, babyID: babyID, baby: model.babyDetails, me: me,
                                  names: model.memberNames, colours: model.memberColours, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SyncProblemBanner()
                    GreetingHeader(facts: facts)
                    HeroTile(facts: facts)
                    if let feed = facts.feedInProgress {
                        ThisFeedTile(feed: feed)
                    }
                    if facts.feedInProgress == nil, let window = facts.window {
                        WindowBar(facts: facts, window: window)
                            .padding(.vertical, 4)
                    }
                    sideAndLastFeed(facts)
                    // On the unfolded Duo these two are in the second column instead.
                    if !secondColumnShowing {
                        DayTile(facts: facts)
                        NightsTile(facts: facts, me: me, onUndo: { undo = $0 })
                    }
                    SyncedNote()
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(Self.startsAtBottom ? .bottom : nil)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let undo, undo.expiresAt > context.date {
                        UndoBanner(action: undo) { self.undo = nil }
                    }
                    FeedControls(facts: facts, me: me, babyID: babyID, onUndo: { undo = $0 })
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                // Flat, like every surface (DESIGN.md): the page scrolls under a plain edge.
                .background(Theme.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
    }

    /// Feeding Dev only: launch with `-homeAtBottom YES` to open the page scrolled to its end,
    /// for screenshots of the lower tiles.
    private static var startsAtBottom: Bool {
        #if FEEDING_DEV
        UserDefaults.standard.bool(forKey: "homeAtBottom")
        #else
        false
        #endif
    }

    /// Next side and Last feed side by side (1 to 1.35), or stacked at the accessibility sizes.
    @ViewBuilder
    private func sideAndLastFeed(_ facts: HomeFacts) -> some View {
        // During a feed, the "This feed" tile takes their place.
        let next = facts.feedInProgress == nil ? facts.nextSide : nil
        let last = facts.feedInProgress == nil ? facts.lastFinishedFeed : nil
        if next != nil || last != nil {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(TileRow(shares: next != nil && last != nil ? [1, 1.35] : [1]))
            layout {
                if let next { NextSideTile(side: next) }
                if let last { LastFeedTile(feed: last, facts: facts) }
            }
        }
    }
}

/// Everything the home screen shows, worked out once per refresh.
struct HomeFacts {
    let data: HouseholdData
    let babyID: String
    let baby: BabyPayload?
    let me: MemberID
    let names: [MemberID: String]
    let colours: [MemberID: ParentColour]
    let now: Date
    let settings: HouseholdSettings
    let lastFeedStart: Date?
    let feedInProgress: EventSnapshot?
    let nextSide: BreastSide?

    init(data: HouseholdData, babyID: String, baby: BabyPayload? = nil, me: MemberID, names: [MemberID: String],
         colours: [MemberID: ParentColour] = [:], now: Date) {
        self.data = data
        self.babyID = babyID
        self.baby = baby
        self.me = me
        self.names = names
        self.colours = colours
        self.now = now
        settings = data.householdSettings
        lastFeedStart = data.allEvents.latestFeedStart(babyID: babyID, now: now)
        feedInProgress = data.feedInProgress(babyID: babyID)
        nextSide = suggestedNextSide(data.snapshots, babyID: babyID, now: now)
    }

    func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: settings.timeZone))
    }

    /// A parent in a sentence: "you", or their name.
    func name(_ member: MemberID) -> String {
        member == me ? "you" : (names[member] ?? "the other parent")
    }

    /// A parent's own name, for their avatar's initial.
    func displayName(_ member: MemberID) -> String {
        names[member] ?? (member == me ? "You" : "Other parent")
    }

    /// A parent's colour, with the defaults until their Member record arrives.
    func colour(_ member: MemberID) -> ParentColour {
        colours[member] ?? (member == me ? .sunflower : .teal)
    }

    /// The other parent's name, once this phone has it.
    var otherName: String? {
        names.first { $0.key != me }?.value
    }

    /// This parent's latest feed, when the other parent finished it for them in the last two
    /// hours and it has no sides or bottle amounts yet, so this phone can offer to add them. (A
    /// bottle-only parent's feed already has its bottle from the start, without the amount.)
    var feedFinishedForMe: (feed: EventSnapshot, by: MemberID)? {
        let feeds = data.snapshots.filter { $0.event.isLiveFeed && $0.event.babyID == babyID }
        guard let last = feeds.max(by: { $0.event.startedAt < $1.event.startedAt }),
              last.event.loggedBy == me,
              let endedAt = last.event.endedAt, now.timeIntervalSince(endedAt) < 2 * 3600,
              let by = last.payload?.stamp(.endedAt)?.by, by != me,
              let feed = last.payload?.feed, feed.breast.isEmpty, feed.bottles.allSatisfy({ $0.ml == nil })
        else { return nil }
        return (last, by)
    }

    /// How far through the window the time since the last feed is, from 0 to 1.
    var windowProgress: Double {
        guard let lastFeedStart else { return 0 }
        return min(1, max(0, now.timeIntervalSince(lastFeedStart) / settings.window.closesAfter))
    }

    /// The feeding window from the last feed's start, once there is a feed.
    var window: FeedWindow? {
        lastFeedStart.map { FeedWindow(lastFeedStart: $0, settings: settings.window) }
    }

    /// The latest feed that has finished.
    var lastFinishedFeed: EventSnapshot? {
        data.snapshots
            .filter { $0.event.isLiveFeed && $0.event.babyID == babyID && $0.event.endedAt != nil }
            .max { $0.event.startedAt < $1.event.startedAt }
    }

    /// "L 12m · R 8m · Formula 30 ml": a feed's details in words, for the screens not redesigned
    /// yet (the Duo's timeline and the details panel).
    static func details(_ snapshot: EventSnapshot) -> String {
        guard let payload = snapshot.payload else { return "details from a newer app version" }
        var parts: [String] = []
        for segment in payload.feed?.breast ?? [] {
            let side = segment.side == .left ? "L" : "R"
            parts.append(segment.durationSeconds.map { "\(side) \($0 / 60)m" } ?? side)
        }
        for bottle in payload.feed?.bottles ?? [] {
            let milk = bottle.milk == .formula ? "Formula" : "Expressed"
            parts.append(bottle.ml.map { "\(milk) \($0) ml" } ?? milk)
        }
        if let pump = payload.pump {
            parts.append("Pumped \(pump.totalML) ml")
        }
        return parts.isEmpty ? "Feed" : parts.joined(separator: " · ")
    }

    /// The totals under the chart: the same stretch as the chart.
    var totals: FeedSummary {
        summarise(data.snapshots, babyID: babyID, from: now.addingTimeInterval(-24 * 3600), to: now)
    }

    var chart: [DayChartFeed] {
        dayChart(data.snapshots, babyID: babyID, now: now)
    }

    /// The night that is on now, or the one coming tonight.
    var tonight: PlainDate {
        switch settings.dayHours.period(at: now, in: settings.timeZone) {
        case .night(let night): night
        case .day(let day): day
        }
    }

    var partOfDay: PartOfDay {
        settings.dayHours.partOfDay(at: now, in: settings.timeZone)
    }

    var ageInDays: Int? {
        baby?.ageInDays(at: now, in: settings.timeZone)
    }

    /// Five nights back, tonight, and tomorrow night (the approved mockup).
    var nights: [NightDuty] {
        data.householdState.nights(around: tonight, before: 5, after: 1)
    }
}

// MARK: - The parts, top to bottom

/// "Good morning", then the baby's name and age.
struct GreetingHeader: View {
    let facts: HomeFacts

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: HomeText.greetingSymbol(facts.partOfDay))
                    .imageScale(.small)
                Text(HomeText.greeting(facts.partOfDay))
            }
            .feedText(.greeting)
            .foregroundStyle(Theme.textMuted)
            FlowLayout(spacing: 8) {
                Text(facts.baby?.name ?? "Baby")
                    .feedText(.title)
                    .accessibilityAddTraits(.isHeader)
                if let days = facts.ageInDays {
                    Text(HomeText.age(days: days))
                        .feedText(.chip)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.surface, in: Capsule())
                        .accessibilityLabel(days == 0 ? "Born today" : "\(HomeText.age(days: days)) old")
                }
            }
        }
        .padding(.top, 2)
    }
}

/// The ring and the main time: the biggest thing on the screen.
struct HeroTile: View {
    let facts: HomeFacts
    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(FeedingStyle.storageKey) private var feedingStyle = ""
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 104

    private var running: RunningFeed? {
        facts.feedInProgress.map { RunningFeed($0, bottleOnly: feedingStyle == FeedingStyle.bottleOnly.rawValue) }
    }

    var body: some View {
        let running = running
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        let ring = min(ringSize, 150)
        layout {
            // During a feed the ring takes the feed's colour, with the side being fed (or the
            // bottle) in the middle.
            WindowRing(progress: facts.windowProgress, colour: running?.colour ?? Theme.primary,
                       track: running == nil ? Theme.track : Theme.background)
                .overlay {
                    if let mark = running?.centre {
                        FeedMarkView(mark, size: ring * 0.3, relativeTo: .largeTitle)
                    }
                }
                .frame(width: ring, height: ring)
                .accessibilityHidden(true)
            words
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(running?.tint ?? Theme.surface, in: RoundedRectangle(cornerRadius: Radius.hero))
    }

    private var strong: Font.Weight { look == .night ? .semibold : .bold }

    @ViewBuilder
    private var words: some View {
        if let feed = facts.feedInProgress, let running {
            let kinds = running.bottleKinds.map { "\($0) · " } ?? ""
            let by = feed.event.loggedBy == facts.me ? "" : " by \(facts.displayName(feed.event.loggedBy))"
            VStack(alignment: .leading, spacing: 4) {
                Text("Feeding now").feedText(.subheadline).foregroundStyle(Theme.textMuted)
                Text(feed.event.startedAt, style: .timer)
                    .feedText(.mainTime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(kinds)started \(Text(facts.clock(feed.event.startedAt)).fontWeight(strong))\(by)")
                    .feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
            .accessibilityElement(children: .combine)
        } else if let start = facts.lastFeedStart {
            let elapsed = facts.now.timeIntervalSince(start)
            VStack(alignment: .leading, spacing: 4) {
                Text("Last feed").feedText(.subheadline).foregroundStyle(Theme.textMuted)
                Text(HomeText.elapsed(elapsed))
                    .feedText(.mainTime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("ago, at \(Text(facts.clock(start)).fontWeight(strong))")
                    .feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last feed started \(HomeText.spokenElapsed(elapsed)) ago, at \(facts.clock(start))")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("No feeds logged yet").feedText(.title)
                Text("Tap Start feed when one begins.").feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

/// The ring round the time: how far through the window it is. `track` behind, `primary` for the
/// time so far, 11 point round-ended line (DESIGN.md, "Shapes").
struct WindowRing: View {
    let progress: Double
    var colour: Color = Theme.primary
    var track: Color = Theme.track
    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 11)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(colour, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        // Keeps the line inside the frame.
        .padding(5.5)
        // When a feed starts, the ring empties and starts again (DESIGN.md, "Motion"). Still at
        // night and with Reduce Motion: the button's haptic marks it instead.
        .animation(look == .night || reduceMotion ? nil : .easeInOut(duration: 0.3), value: progress)
    }
}

/// What a running feed is so far, for the hero's colours and shapes.
struct RunningFeed {
    let snapshot: EventSnapshot
    /// A bottle feed: bottles and no sides, or any feed on a bottle-only phone before it has sides.
    let isBottle: Bool
    /// The side being fed now.
    let currentSide: BreastSide?

    init(_ snapshot: EventSnapshot, bottleOnly: Bool) {
        let details = snapshot.payload?.feed
        let sides = details?.breast ?? []
        self.snapshot = snapshot
        isBottle = sides.isEmpty && (bottleOnly || !(details?.bottles.isEmpty ?? true))
        currentSide = sides.last.flatMap { $0.durationSeconds == nil ? $0.side : nil }
    }

    var tint: Color { isBottle ? Theme.bottleTint : Theme.breastTint }
    var colour: Color { isBottle ? Theme.bottle : Theme.breast }
    var centre: FeedMark? { isBottle ? .bottle : currentSide.map { .side($0) } }

    /// "Formula", or "Formula + Expressed milk", for a bottle feed.
    var bottleKinds: String? {
        guard isBottle, let bottles = snapshot.payload?.feed?.bottles, !bottles.isEmpty else { return nil }
        return bottles.map { HomeText.milkName($0.milk) }.joined(separator: " + ")
    }
}

/// The running feed so far: a chip for each side and bottle, with a live clock on the side
/// being fed now ("◑ 4:02 running").
struct ThisFeedTile: View {
    let feed: EventSnapshot

    var body: some View {
        let segments = feed.payload?.feed?.breast ?? []
        let bottles = feed.payload?.feed?.bottles ?? []
        if !segments.isEmpty || !bottles.isEmpty {
            Tile(label: "This feed") {
                FeedChips(snapshot: feed)
            }
        }
    }
}

/// A chip with a live clock, tinted by its kind: the side being fed now.
struct LiveChip: View {
    let mark: FeedMark
    let since: Date
    /// The kind's tint by default; the background colour on a row that already has the tint.
    var background: Color?

    var body: some View {
        HStack(spacing: 5) {
            FeedMarkView(mark)
            Text(since, style: .timer)
            Text("running")
        }
        .feedText(.chip)
        .lineLimit(1)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background ?? mark.tint, in: RoundedRectangle(cornerRadius: Radius.chip))
        .accessibilityElement(children: .combine)
    }
}

/// The window bar: the time so far, the shaded feeding window, a mark for now, then "Feeding
/// window 10:25" and a bell with the alert time.
struct WindowBar: View {
    let facts: HomeFacts
    let window: FeedWindow
    @Environment(\.look) private var look

    var body: some View {
        let settings = facts.settings.window
        let opensShare = min(1, max(0, settings.opensAfter / max(1, settings.closesAfter)))
        let progress = facts.windowProgress
        let strong: Font.Weight = look == .night ? .semibold : .bold
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6)
                        .fill(Theme.window)
                        .frame(width: width * (1 - opensShare))
                        .offset(x: width * opensShare)
                    Capsule()
                        .fill(Theme.primary)
                        .frame(width: max(12, width * progress))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.text)
                        .frame(width: 4, height: 20)
                        .offset(x: min(max(0, width * progress - 2), width - 4))
                }
            }
            .frame(height: 12)
            HStack(alignment: .firstTextBaseline) {
                Text("Feeding window \(Text(facts.clock(window.opensAt)).fontWeight(strong).foregroundStyle(Theme.text))")
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 8)
                if settings.alertsEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "bell").imageScale(.small)
                        Text(facts.clock(window.closesAt)).fontWeight(strong)
                    }
                } else {
                    Text("Alerts off").foregroundStyle(Theme.textMuted)
                }
            }
            .feedText(.subheadline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.alertsEnabled
            ? "Feeding window opens at \(facts.clock(window.opensAt)). Alert at \(facts.clock(window.closesAt))."
            : "Feeding window opens at \(facts.clock(window.opensAt)). Alerts are off.")
    }
}

/// The suggested next side: its half-moon and "Left".
struct NextSideTile: View {
    let side: BreastSide

    var body: some View {
        Tile(label: "Next side", tint: Theme.breastTint) {
            HStack(spacing: 8) {
                FeedMarkView(.side(side), size: 26, relativeTo: .title3)
                Text(side == .left ? "Left" : "Right").feedText(.tileValue)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suggested next side: \(side == .left ? "left" : "right")")
    }
}

/// The last finished feed as chips, with the avatar of who logged it.
struct LastFeedTile: View {
    let feed: EventSnapshot
    let facts: HomeFacts

    var body: some View {
        let who = feed.event.loggedBy
        let chips = HomeText.chips(feed)
        Tile(label: "Last feed", tint: Theme.bottleTint,
             accessory: AnyView(Avatar(name: facts.displayName(who), colour: facts.colour(who), size: 20))) {
            FeedChips(snapshot: feed)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last feed: \(chips.map(\.spoken).joined(separator: ", ")). Logged by \(facts.name(who)).")
    }
}

/// The last 24 hours: the chart, then the totals.
struct DayTile: View {
    let facts: HomeFacts
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Total: Identifiable {
        let value: Int
        let unit: String
        var id: String { unit }
    }

    var body: some View {
        let totals = facts.totals
        Tile(label: "Last 24 hours", accessory: AnyView(key)) {
            DayChart(feeds: facts.chart, now: facts.now, clock: facts.clock)
            totalsRow(totals)
        }
    }

    private var key: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                FeedMarkView(.side(.left), size: 12, relativeTo: .caption2)
                Text("Breast")
            }
            HStack(spacing: 4) {
                FeedMarkView(.bottle, size: 12, relativeTo: .caption2)
                Text("Bottle")
            }
        }
        .feedText(.small)
        .foregroundStyle(Theme.textMuted)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }

    private func totalsRow(_ totals: FeedSummary) -> some View {
        var items = [
            Total(value: totals.feeds, unit: totals.feeds == 1 ? "feed" : "feeds"),
            Total(value: totals.breastFeeds, unit: "at the breast"),
            Total(value: totals.expressedML + totals.formulaML, unit: "ml from bottles"),
        ]
        // Pumping only when there was some. A session with no amounts counts as a session.
        if totals.pumpedML > 0 {
            items.append(Total(value: totals.pumpedML, unit: "ml pumped"))
        } else if totals.pumpSessions > 0 {
            items.append(Total(value: totals.pumpSessions, unit: totals.pumpSessions == 1 ? "pumping session" : "pumping sessions"))
        }
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(item.value)").feedText(.total)
                    Text(item.unit).feedText(.small).foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.value) \(item.unit)")
            }
        }
        .padding(.top, 2)
    }
}

/// One 8 point bar per feed across the last 24 hours, coloured and placed by its start. A longer
/// feed stands a little taller, up to 45 minutes. A feed with breast and bottle shows both.
struct DayChart: View {
    let feeds: [DayChartFeed]
    let now: Date
    let clock: (Date) -> String
    var hours: Double = 24

    private let barWidth: CGFloat = 8
    private let baseline: CGFloat = 6

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .bottomLeading) {
                    Capsule()
                        .fill(Theme.track)
                        .frame(height: 2)
                        .offset(y: -baseline)
                    ForEach(feeds) { feed in
                        bar(feed)
                            .offset(x: x(feed, width), y: -baseline)
                    }
                }
                .frame(width: width, height: proxy.size.height, alignment: .bottomLeading)
            }
            .frame(height: 56)
            HStack {
                Text("24h ago")
                Spacer()
                Text("12h")
                Spacer()
                Text("now")
            }
            .feedText(.small)
            .foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chart of feeds in the last 24 hours")
        .accessibilityValue(feeds.isEmpty ? "No feeds"
            : feeds.map { "\(clock($0.startedAt)), \(HomeText.kinds($0))" }.joined(separator: "; "))
    }

    private func x(_ feed: DayChartFeed, _ width: CGFloat) -> CGFloat {
        let span = hours * 3600
        let share = (feed.startedAt.timeIntervalSince(now) + span) / span
        return CGFloat(min(1, max(0, share))) * (width - barWidth)
    }

    private func height(_ feed: DayChartFeed) -> CGFloat {
        let longest: TimeInterval = 45 * 60
        return 16 + 24 * CGFloat(min(feed.duration, longest) / longest)
    }

    private func bar(_ feed: DayChartFeed) -> some View {
        let total = height(feed)
        return VStack(spacing: 0) {
            if feed.bottle {
                Rectangle().fill(Theme.bottleMark).frame(height: feed.breast ? total / 2 : total)
            }
            if feed.breast {
                Rectangle().fill(Theme.breastMark).frame(height: feed.bottle ? total / 2 : total)
            }
            if !feed.breast && !feed.bottle {
                Rectangle().fill(Theme.textMuted).frame(height: total)
            }
        }
        .frame(width: barWidth)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 4))
    }
}

/// The row of nights, who is on tonight, and "I'll take it".
struct NightsTile: View {
    let facts: HomeFacts
    let me: MemberID
    let onUndo: (UndoAction) -> Void

    var body: some View {
        let state = facts.data.householdState
        let nights = facts.nights
        let onTonight = nights.first { $0.night == facts.tonight }?.onDuty
        let noRota = state.rota == nil && state.claims.isEmpty
        let waiting = !facts.data.unacknowledgedChanges(by: me).isEmpty
        Tile(label: "Nights") {
            if noRota {
                Text("No night rota yet: both phones alert at night.")
                    .feedText(.subheadline)
            } else {
                NightsRow(nights: nights, tonight: facts.tonight, facts: facts)
            }
            if onTonight != me {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        whoIsOn(onTonight, noRota: noRota)
                        Spacer(minLength: 0)
                        takeButton(noRota: noRota)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        whoIsOn(onTonight, noRota: noRota)
                        takeButton(noRota: noRota)
                    }
                }
            } else {
                whoIsOn(onTonight, noRota: noRota)
                    .frame(minHeight: 44, alignment: .leading)
            }
            if waiting {
                Text("Waiting for \(facts.otherName.map { "\($0)'s phone" } ?? "the other phone") to see your change. Until then, this phone alerts as if on duty.")
                    .feedText(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    @ViewBuilder
    private func whoIsOn(_ member: MemberID?, noRota: Bool) -> some View {
        if let member {
            Text(HomeText.onTonight(facts.names[member] ?? facts.name(member).capitalizedFirst, isMe: member == me))
                .feedText(.smallButton)
        } else if !noRota {
            Text("No one has taken tonight").feedText(.smallButton)
        }
    }

    private func takeButton(noRota: Bool) -> some View {
        // With no rota there is no "on tonight" line before it, so it says which night.
        PillButton(noRota ? "I'll take tonight" : "I'll take it") {
            let night = facts.tonight
            AppModel.shared.store.change { $0.claimNight(night, by: me, now: Date()) }
            onUndo(UndoAction(message: "You're on tonight") {
                AppModel.shared.store.change { $0.undoClaim(night, by: me) }
            })
        }
    }
}

/// Seven nights, each with the on-duty parent's initial in their colour. Tonight has a ring.
struct NightsRow: View {
    let nights: [NightDuty]
    let tonight: PlainDate
    let facts: HomeFacts

    var body: some View {
        HStack(spacing: 2) {
            ForEach(nights, id: \.night) { duty in
                let isTonight = duty.night == tonight
                VStack(spacing: 5) {
                    Text(Self.weekday(duty.night, short: true))
                        .feedText(.small)
                        .foregroundStyle(isTonight ? Theme.text : Theme.textMuted)
                    avatar(duty.onDuty)
                        .overlay {
                            if isTonight {
                                Circle().stroke(Theme.text, lineWidth: 3).padding(-5)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(duty, isTonight: isTonight))
            }
        }
        .padding(.bottom, 5)
        // Seven circles must fit across the phone, so the row stops growing here.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private func avatar(_ member: MemberID?) -> some View {
        if let member {
            Avatar(name: facts.displayName(member), colour: facts.colour(member))
        } else {
            EmptyAvatar()
        }
    }

    private func label(_ duty: NightDuty, isTonight: Bool) -> String {
        let day = Self.weekday(duty.night, short: false)
        let who = duty.onDuty.map { facts.name($0) } ?? "nobody yet"
        return isTonight ? "Tonight, \(day): \(who)" : "\(day): \(who)"
    }

    /// "Mon", or "Monday", in the phone's language.
    static func weekday(_ date: PlainDate, short: Bool) -> String {
        let symbols = short ? Calendar.current.shortWeekdaySymbols : Calendar.current.weekdaySymbols
        // Calendar symbols start on Sunday; `weekday` is 1 for Monday to 7 for Sunday.
        return symbols[date.weekday % 7]
    }
}

// MARK: - Banners

/// A sync problem, in the `notice` colour: never red, and never about the baby.
struct SyncProblemBanner: View {
    var body: some View {
        if let problem = AppModel.shared.sync.problem ?? AppModel.shared.store.problem {
            Text(problem)
                .feedText(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.notice.opacity(0.22), in: RoundedRectangle(cornerRadius: Radius.smallButton))
        }
    }
}

/// When the phones last synced, small, at the foot of the page.
struct SyncedNote: View {
    var body: some View {
        let sync = AppModel.shared.sync
        if sync.problem == nil, AppConfig.syncEnabled, let fetched = sync.lastFetchAt {
            Text("Synced \(fetched, style: .relative) ago")
                .feedText(.small)
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
