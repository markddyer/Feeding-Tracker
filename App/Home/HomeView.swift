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
    @State private var scroll = ScrollPosition()
    /// "Change time" from the Undo bar, the poo's details (the users' choice Q), and the
    /// medicine list.
    @State private var timeChange: TimeChange?
    @State private var pooDetails: PooDetailsTarget?
    @State private var editingMedicines = false
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
                    // Above the ring: it waits for an answer. It goes once answered.
                    if case .askedOfMe(let ask) = facts.askStatus {
                        AskCard(ask: ask, facts: facts, me: me, onUndo: { undo = $0 })
                    }
                    // Each morning until 12:00: last night, as a handover (X3, DD4).
                    if let night = lastNight(at: context.date) {
                        LastNightLine(night: night, zone: model.store.data.householdSettings.timeZone)
                    }
                    HeroTile(facts: facts)
                    if let feed = facts.feedInProgress {
                        ThisFeedTile(feed: feed)
                    }
                    if facts.feedInProgress == nil, let window = facts.window {
                        WindowBar(facts: facts, window: window)
                            .padding(.vertical, 4)
                    }
                    // Sleep and Nappy above Next side and Last feed (the users' choice A, 17 Nov
                    // 2026); Medicine under them (K).
                    sleepAndNappy(facts)
                    sideAndLastFeed(facts)
                    medicineAndBath(facts)
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
            .scrollPosition($scroll)
            // A tapped notification about an ask: back to the top, where its card is.
            .onChange(of: NotificationTaps.shared.homeRequests) {
                withAnimation { scroll.scrollTo(edge: .top) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FeedControls(facts: facts, me: me, babyID: babyID, onUndo: { undo = $0 })
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                // Flat, like every surface (DESIGN.md): the page scrolls under a plain edge.
                .background(Theme.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        // The Undo card, at the top (DD7).
        .undoCard(undo, onChangeTime: { timeChange = $0 }) { shown in
            if undo?.id == shown.id { undo = nil }
        }
        .task { openDevSheet() }
        .sheet(item: $timeChange) { change in
            ChangeTimeSheet(change: change, me: me, zone: model.store.data.householdSettings.timeZone)
        }
        .sheet(item: $pooDetails) { target in
            PooDetailsSheet(target: target, me: me, zone: model.store.data.householdSettings.timeZone, log: log)
        }
        .sheet(isPresented: $editingMedicines) {
            NavigationStack { MedicineListEditor() }
        }
    }

    private var log: CareLog {
        CareLog(me: me, babyID: babyID, onUndo: { undo = $0 })
    }

    /// Sleep and Nappy side by side, or stacked at the accessibility sizes.
    private func sleepAndNappy(_ facts: HomeFacts) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(TileRow(shares: [1, 1]))
        return layout {
            SleepTile(facts: facts, log: log)
            NappyTile(facts: facts, log: log) { pooDetails = $0 }
        }
    }

    /// Medicine and Bath side by side (design D6: Bath half-width beside Medicine), stacked at the
    /// accessibility sizes. With no medicines listed, Bath alone.
    @ViewBuilder
    private func medicineAndBath(_ facts: HomeFacts) -> some View {
        if facts.data.medicines.isEmpty {
            BathTile(facts: facts, log: log)
        } else {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(TileRow(shares: [1, 1]))
            layout {
                MedicineTile(facts: facts, log: log) { editingMedicines = true }
                BathTile(facts: facts, log: log)
            }
        }
    }

    /// Feeding Dev only: launch with `-homeSheet pooDetails` (the poo's colour and consistency,
    /// for the last nappy), `changeTime` (Change time, for the last nappy) or `medicines` (the
    /// medicine list), for screenshots.
    private func openDevSheet() {
        #if FEEDING_DEV
        let last = lastNappy(model.store.data.visibleSnapshots(babyID: babyID), babyID: babyID, now: Date())
        switch UserDefaults.standard.string(forKey: "homeSheet") {
        case "pooDetails":
            if let last { pooDetails = PooDetailsTarget(id: last.id, isNew: true) }
        case "changeTime":
            if let last { timeChange = TimeChange(ids: [last.id], field: .start, title: "Wee and poo", at: last.at) }
        case "medicines":
            editingMedicines = true
        default:
            break
        }
        // `-homeUndo nappy` (or `wokeUp`, `bath`): one quick log at launch, to see its Undo card.
        switch UserDefaults.standard.string(forKey: "homeUndo") {
        case "nappy": log.nappy(wee: true, poo: false)
        case "wokeUp": log.wokeUp()
        case "bath": log.bath()
        default: break
        }
        #endif
    }

    /// Last night, from its end until 12:00. Feeding Dev's `-homeLastNight YES` shows the night
    /// before at any hour, for screenshots.
    private func lastNight(at now: Date) -> LastNight? {
        let who = model.store.data.whoDidIt(babyID: babyID, now: now)
        #if FEEDING_DEV
        if UserDefaults.standard.bool(forKey: "homeLastNight") {
            let today = PlainDate(now, in: model.store.data.householdSettings.timeZone)
            let night = who.night(today.adding(days: -1))
            if !night.items.isEmpty { return night }
        }
        #endif
        return who.lastNight()
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
    /// Every event the screens show: a feed logged on both phones shows once (the first one
    /// logged). Alerts read every event instead (`reconcile`), so a merge never moves an alert.
    let visible: [EventSnapshot]

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
        visible = data.visibleSnapshots(babyID: babyID)
        nextSide = suggestedNextSide(visible, babyID: babyID, now: now)
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
        let feeds = visible.filter { $0.event.isLiveFeed && $0.event.babyID == babyID }
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
        visible
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
        summarise(visible, babyID: babyID, from: now.addingTimeInterval(-24 * 3600), to: now)
    }

    var chart: [DayChartFeed] {
        dayChart(visible, babyID: babyID, now: now)
    }

    /// The night that is on now, or the one coming tonight.
    var tonight: PlainDate {
        settings.tonight(at: now)
    }

    /// The other parent, once this phone has their Member record.
    var otherMember: MemberID? {
        names.keys.filter { $0 != me }.min { $0.rawValue < $1.rawValue }
    }

    /// Where an ask for tonight stands on this phone: the card, or the asker's line.
    var askStatus: NightAskStatus? {
        data.nightAskStatus(night: tonight, me: me)
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

/// The last 24 hours as one strip: each feed is a block from when it started to when it ended
/// (to now while it runs), so feeds close together sit side by side and touch only if they really
/// overlapped. Coloured by kind; a feed with breast and bottle shows both (the user's choice, 15 Nov
/// 2026, option C on `chart-overlap-20261115`).
struct DayChart: View {
    let feeds: [DayChartFeed]
    let now: Date
    let clock: (Date) -> String
    var hours: Double = 24

    private let stripHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7).fill(Theme.chartStrip)
                    ForEach(feeds) { feed in
                        let place = Self.place(start: feed.startedAt, duration: feed.duration, now: now, hours: hours, width: width)
                        block(feed)
                            .frame(width: place.width)
                            .offset(x: place.x)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .frame(height: stripHeight)
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
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chart of feeds in the last 24 hours")
        .accessibilityValue(feeds.isEmpty ? "No feeds" : feeds.map { feed in
            "\(clock(feed.startedAt)), \(HomeText.kinds(feed)), \(feed.running ? "running, " : "")\(HomeText.spokenElapsed(feed.duration))"
        }.joined(separator: "; "))
    }

    /// Where a feed's block sits on a strip `width` wide covering the `hours` up to `now`: from its
    /// start, as wide as it lasted, at least `minWidth` so a short feed still shows, and kept
    /// inside the strip.
    static func place(start: Date, duration: TimeInterval, now: Date, hours: Double, width: CGFloat,
                      minWidth: CGFloat = 3) -> (x: CGFloat, width: CGFloat) {
        let span = hours * 3600
        let from = now.addingTimeInterval(-span)
        let startShare = min(1, max(0, start.timeIntervalSince(from) / span))
        let endShare = min(1, max(startShare, start.addingTimeInterval(max(0, duration)).timeIntervalSince(from) / span))
        let blockWidth = min(width, max(minWidth, CGFloat(endShare - startShare) * width))
        let x = min(CGFloat(startShare) * width, width - blockWidth)
        return (max(0, x), blockWidth)
    }

    /// Bottle above breast when a feed had both; a feed this version can't read is muted.
    private func block(_ feed: DayChartFeed) -> some View {
        VStack(spacing: 0) {
            if feed.bottle { Rectangle().fill(Theme.bottleMark) }
            if feed.breast { Rectangle().fill(Theme.breastMark) }
            if !feed.breast && !feed.bottle { Rectangle().fill(Theme.textMuted) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
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
        // Nothing in the week's row to show: no rota, and nobody has taken a night.
        let noRota = state.rota == nil && nights.allSatisfy { $0.onDuty == nil }
        // Someone took tonight: either parent can give it back to both phones.
        let taken = state.claim(for: facts.tonight) != nil && facts.otherMember != nil
        let waiting = !facts.data.unacknowledgedChanges(by: me).isEmpty
        Tile(label: "Nights") {
            if noRota {
                Text("No night rota yet: both phones alert at night.")
                    .feedText(.subheadline)
            } else {
                NightsRow(nights: nights, tonight: facts.tonight, facts: facts)
            }
            if onTonight == me {
                if facts.askStatus == nil, let other = facts.otherMember {
                    if taken {
                        lineAndButtons(whoIsOn(onTonight, noRota: noRota)) {
                            askButton(other, nobodyOn: false)
                            bothPhonesButton
                        }
                    } else {
                        lineAndButton(whoIsOn(onTonight, noRota: noRota), askButton(other, nobodyOn: false))
                    }
                } else if taken {
                    lineAndButton(whoIsOn(onTonight, noRota: noRota), bothPhonesButton)
                } else {
                    whoIsOn(onTonight, noRota: noRota)
                        .frame(minHeight: 44, alignment: .leading)
                }
            } else if taken {
                lineAndButtons(whoIsOn(onTonight, noRota: noRota)) {
                    takeButton(noRota: noRota)
                    bothPhonesButton
                }
            } else if onTonight == nil, facts.askStatus == nil, let other = facts.otherMember {
                // Nobody is on (both phones alert): take tonight, or ask the other parent to.
                VStack(alignment: .leading, spacing: 4) {
                    whoIsOn(onTonight, noRota: noRota)
                    FlowLayout(spacing: 8) {
                        takeButton(noRota: noRota)
                        askButton(other, nobodyOn: true)
                    }
                }
            } else {
                lineAndButton(whoIsOn(onTonight, noRota: noRota), takeButton(noRota: noRota))
            }
            switch facts.askStatus {
            case .waiting:
                askLine(HomeText.askWaiting(facts.otherMember.map { facts.name($0) } ?? "the other parent",
                                            nobodyOn: onTonight == nil))
            case .declined(_, let by):
                askLine(HomeText.askDeclined(facts.name(by).capitalizedFirst))
            default:
                EmptyView()
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
            Text(HomeText.bothPhonesTonight).feedText(.smallButton)
        }
    }

    /// A line with two buttons under it, side by side while they fit.
    private func lineAndButtons(_ line: some View, @ViewBuilder _ buttons: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            line
            FlowLayout(spacing: 8) {
                buttons()
            }
        }
    }

    /// "Both phones tonight": gives a taken night back. It only adds alerting, so it needs no
    /// Undo; "I'll take it" or an ask settles the night again.
    private var bothPhonesButton: some View {
        PillButton(HomeText.bothPhonesButton) {
            let night = facts.tonight
            AppModel.shared.store.change { $0.setBothPhones(night, by: me, now: Date()) }
        }
    }

    /// A line with its button beside it, or under it when there isn't room.
    private func lineAndButton(_ line: some View, _ button: some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                line
                Spacer(minLength: 0)
                button
            }
            VStack(alignment: .leading, spacing: 4) {
                line
                button
            }
        }
    }

    private func askLine(_ text: String) -> some View {
        Text(text)
            .feedText(.subheadline)
            .foregroundStyle(Theme.textMuted)
    }

    private func takeButton(noRota: Bool) -> some View {
        // With no rota there is no "on tonight" line before it, so it says which night.
        PillButton(noRota ? "I'll take tonight" : "I'll take it") {
            Self.take(facts.tonight, me: me, onUndo: onUndo)
        }
    }

    /// "I'll take it": a claim, with Undo. Once the claim has reached the other phone, Undo makes
    /// both phones alert instead (`undoTake`), so nothing goes quiet.
    static func take(_ night: PlainDate, me: MemberID, onUndo: (UndoAction) -> Void) {
        AppModel.shared.store.change { $0.claimNight(night, by: me, now: Date()) }
        onUndo(UndoAction(message: "You're on tonight") {
            AppModel.shared.store.change { $0.undoTake(night, by: me, now: Date()) }
        })
    }

    /// "Ask Sam to take it". Nothing changes for alerts until the answer is yes; Undo takes the
    /// ask back, even after it has reached the other phone.
    private func askButton(_ other: MemberID, nobodyOn: Bool) -> some View {
        let name = facts.name(other)
        return PillButton(HomeText.askButton(name, nobodyOn: nobodyOn)) {
            let night = facts.tonight
            guard AppModel.shared.store.change({ $0.askNight(night, by: me, now: Date()) }) else { return }
            onUndo(UndoAction(message: "You asked \(name)") {
                AppModel.shared.store.change { $0.withdrawAsk(night, by: me, now: Date()) }
            })
        }
    }
}

/// "Alex asks you to take tonight", with "I'll take it" and "Not tonight". Only on the asked
/// parent's Home, until they answer. A request, not a hand-off: Alex stays on duty until the
/// answer is yes. After "Not tonight", "I'll take it" stays in the Nights tile.
struct AskCard: View {
    let ask: NightAsk
    let facts: HomeFacts
    let me: MemberID
    let onUndo: (UndoAction) -> Void

    var body: some View {
        let asker = ask.askedBy
        Tile(label: "Tonight",
             accessory: AnyView(Avatar(name: facts.displayName(asker), colour: facts.colour(asker), size: 20))) {
            Text(HomeText.askedOfMe(by: facts.name(asker).capitalizedFirst))
                .feedText(.tileValue)
                .fixedSize(horizontal: false, vertical: true)
            // Large: the card waits for an answer, often at night (the first phone test found the
            // small pills hard to hit). Side by side, or one above the other when they don't fit.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { answers }
                VStack(spacing: 8) { answers }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var answers: some View {
        PillButton("I'll take it", large: true) {
            NightsTile.take(ask.night, me: me, onUndo: onUndo)
        }
        PillButton("Not tonight", large: true) {
            let night = ask.night
            AppModel.shared.store.change { $0.declineAsk(night, by: me, now: Date()) }
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
        let who = duty.onDuty.map { facts.name($0) } ?? "both phones"
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
