import FeedingCore
import FeedingInsights
import SwiftUI

/// The home screen, calmer since 24 Nov 2026 (`docs/planning/13-calm-home.md`): the top tile
/// (the time since the last feed started, the window bar, then the last feed's chips and the next
/// side), one plain list of Sleep, Nappy, each medicine and Bath, then Tonight, Today and Recent,
/// folded. The baby's name is in the top bar. The feed buttons are pinned at the bottom. On the
/// open Duo this is the Book's left page, "now". Facts only: no targets, no verdicts.
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
    /// An entry opened from Recent, to change it.
    @State private var editing: EventEditor.Mode?
    @State private var careEditing: CareEditor.Mode?
    /// The morning card, from the afternoon's slim line (with no night's entries).
    @State private var morningCard: MorningCardRequest?
    /// Tonight's window, from its card on the open Duo (`TonightSheet`).
    @State private var showingTonight = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.secondColumnShowing) private var secondColumnShowing

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let facts = HomeFacts(data: model.store.data, babyID: babyID, baby: model.babyDetails, me: me,
                                  names: model.memberNames, colours: model.memberColours, now: context.date)
            Group {
                // The open Duo's left page, "now" (the Book, CH7 and CH10): the top tile and the
                // even cards, which shrink together to fit, so the page doesn't scroll (the
                // parents' ask, 24 Nov 2026). What waits above the top tile is at the top of the
                // right page. Only when even the shortest cards can't fit (the largest text
                // sizes) does it scroll, rather than cut words off.
                if secondColumnShowing {
                    ViewThatFits(in: .vertical) {
                        duoPage(facts, fitsPage: true)
                        ScrollView {
                            duoPage(facts, fitsPage: false).padding(.bottom, 16)
                        }
                        .scrollIndicators(.hidden)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HomeTopLines(facts: facts, me: me, babyID: babyID, onUndo: { undo = $0 }) {
                                morningCard = MorningCardRequest()
                            }
                            HeroTile(facts: facts)
                            // A calmer Home (`13-calm-home.md`): one plain list of things to log,
                            // then the folded parts.
                            CareList(facts: facts, log: log, askDetails: { pooDetails = $0 },
                                     editMedicines: { editingMedicines = true })
                            VStack(alignment: .leading, spacing: 4) {
                                TonightFold(facts: facts, me: me, onUndo: { undo = $0 })
                                TodayFold(facts: facts)
                                RecentFold(facts: facts) { open($0) }
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
                }
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
        .sheet(item: $editing) { mode in
            EventEditor(mode: mode, me: me, babyID: babyID)
        }
        .sheet(item: $careEditing) { mode in
            CareEditor(mode: mode, me: me, babyID: babyID)
        }
        .sheet(item: $morningCard) { request in
            InsightCardSheet(kind: .morning, night: request.night)
        }
        .sheet(isPresented: $showingTonight) {
            TonightSheet(me: me, babyID: babyID, onUndo: { undo = $0 })
        }
    }

    /// The open Duo's left page: the top tile and the cards. With `fitsPage` the cards shrink to
    /// the page's height, and the page asks only for the least it needs, so `ViewThatFits` takes
    /// it whenever the shortest cards fit.
    private func duoPage(_ facts: HomeFacts, fitsPage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HeroTile(facts: facts)
                .fixedSize(horizontal: false, vertical: true)
            CareFacts(facts: facts, me: me, fitsPage: fitsPage, askDetails: { pooDetails = $0 },
                      openTonight: { showingTonight = true })
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var log: CareLog {
        CareLog(me: me, babyID: babyID, onUndo: { undo = $0 })
    }

    /// Opens an entry from Recent to change it: a feed or pumping in the feed form, anything else
    /// in the care form, as History does.
    private func open(_ entry: EventSnapshot) {
        let kind = entry.event.kind
        if kind == .feed || kind == .pump { editing = .edit(id: entry.id) } else { careEditing = .edit(id: entry.id) }
    }

    /// Feeding Dev only: launch with `-homeSheet pooDetails` (the poo's colour and consistency,
    /// for the last nappy), `changeTime` (Change time, for the last nappy), `medicines` (the
    /// medicine list), `insightCard` (the morning's AI card) or `tonight` (Tonight's window from
    /// the open Duo's card), for screenshots.
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
        case "insightCard":
            // The morning card as "Last night" opens it, with the night's entries under it.
            morningCard = MorningCardRequest(night: HomeTopLines.lastNight(at: Date(), babyID: babyID))
        case "tonight":
            showingTonight = true
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

    /// Feeding Dev only: launch with `-homeAtBottom YES` to open the page scrolled to its end,
    /// for screenshots of the lower tiles.
    private static var startsAtBottom: Bool {
        #if FEEDING_DEV
        UserDefaults.standard.bool(forKey: "homeAtBottom")
        #else
        false
        #endif
    }

}

/// What waits above Home's top tile: a sync problem, an ask from the other parent (until it is
/// answered), and each morning until 12:00 "Last night", or by day the AI card's slim line. On the
/// phone it sits above the top tile; on the open Duo at the top of the right page, so the left
/// page never needs to scroll (CH10).
struct HomeTopLines: View {
    let facts: HomeFacts
    let me: MemberID
    let babyID: String
    let onUndo: (UndoAction) -> Void
    /// Opens the morning card from the slim line.
    let openCard: () -> Void

    var body: some View {
        SyncProblemBanner()
        // It waits for an answer. It goes once answered.
        if case .askedOfMe(let ask) = facts.askStatus {
            AskCard(ask: ask, facts: facts, me: me, onUndo: onUndo)
        }
        // Each morning until 12:00: last night, as a handover (X3, DD4), with the AI's card when
        // there is one (AI insights, the parents' pick A). From then until the night starts, the
        // card alone as a slim line.
        let night = Self.lastNight(at: facts.now, babyID: babyID)
        let card = night != nil || Self.cardLineTime(facts.now) ? CardShown.now(.morning, at: facts.now) : .nothing
        if let night {
            LastNightLine(night: night, zone: facts.settings.timeZone, card: card)
        } else if card.isAI {
            AICardLine(title: CardText.title(.morning), shown: card, open: openCard)
        }
    }

    /// Last night, from its end until 12:00. Feeding Dev's `-homeLastNight YES` shows the night
    /// before at any hour, for screenshots.
    static func lastNight(at now: Date, babyID: String) -> LastNight? {
        let data = AppModel.shared.store.data
        let who = data.whoDidIt(babyID: babyID, now: now)
        #if FEEDING_DEV
        if UserDefaults.standard.bool(forKey: "homeCardLine") { return nil }
        if UserDefaults.standard.bool(forKey: "homeLastNight") {
            let today = PlainDate(now, in: data.householdSettings.timeZone)
            let night = who.night(today.adding(days: -1))
            if !night.items.isEmpty { return night }
        }
        #endif
        return who.lastNight()
    }

    /// By day on the household's clock: the morning card's slim line shows then, once "Last night"
    /// has gone at 12:00, until the night starts. Feeding Dev: `-homeCardLine YES` shows it at any
    /// hour, without "Last night", for screenshots.
    static func cardLineTime(_ now: Date) -> Bool {
        #if FEEDING_DEV
        if UserDefaults.standard.bool(forKey: "homeCardLine") { return true }
        #endif
        let settings = AppModel.shared.store.data.householdSettings
        if case .day = settings.dayHours.period(at: now, in: settings.timeZone) { return true }
        return false
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

    /// The feeding window from the last feed's start, once there is a feed.
    var window: FeedWindow? {
        lastFeedStart.map { FeedWindow(lastFeedStart: $0, settings: settings.window) }
    }

    /// Where now is against that window, for the bar in the top tile.
    var windowSteps: WindowSteps? {
        window.map { WindowSteps(window: $0, settings: settings.window, now: now) }
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

/// The baby's name and age, in the top bar beside Ask and Settings (`13-calm-home.md`, CH4).
/// "Good morning" went with the calmer Home. No `TimelineView` here: inside a toolbar item it put
/// SwiftUI into an endless loop (a blank screen at 100% busy, 24 Nov 2026). It is redrawn with
/// the page, which is enough for an age in days.
struct HomeTitle: View {
    var body: some View {
        let model = AppModel.shared
        let zone = model.store.data.householdSettings.timeZone
        HStack(spacing: 8) {
                Text(model.babyDetails?.name ?? "Baby")
                    .feedText(.dayHeading)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let days = model.babyDetails?.ageInDays(at: Date(), in: zone) {
                    Text(HomeText.age(days: days))
                        .feedText(.chip)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.surface, in: Capsule())
                        .accessibilityLabel(days == 0 ? "Born today" : "\(HomeText.age(days: days)) old")
                }
            }
            .foregroundStyle(Theme.text)
            .fixedSize()
    }
}

/// The top tile: the time since the last feed started, the biggest thing on the screen, with the
/// window bar under it (the users' choice C, 21 Nov 2026: the bar took the ring's place). During
/// a feed: its timer, with the side being fed (or the bottle) beside it, and no bar.
struct HeroTile: View {
    let facts: HomeFacts
    @Environment(\.look) private var look
    @AppStorage(FeedingStyle.storageKey) private var feedingStyle = ""

    private var running: RunningFeed? {
        facts.feedInProgress.map { RunningFeed($0, bottleOnly: feedingStyle == FeedingStyle.bottleOnly.rawValue) }
    }

    var body: some View {
        let running = running
        content(running)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(running?.tint ?? Theme.surface, in: RoundedRectangle(cornerRadius: Radius.hero))
    }

    private var strong: Font.Weight { look == .night ? .semibold : .bold }

    @ViewBuilder
    private func content(_ running: RunningFeed?) -> some View {
        if let feed = facts.feedInProgress, let running {
            let kinds = running.bottleKinds.map { "\($0) · " } ?? ""
            let by = feed.event.loggedBy == facts.me ? "" : " by \(facts.displayName(feed.event.loggedBy))"
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Feeding now").feedText(.subheadline).foregroundStyle(Theme.textMuted)
                        Text(feed.event.startedAt, style: .timer)
                            .feedText(.mainTime)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("\(kinds)started \(Text(facts.clock(feed.event.startedAt)).fontWeight(strong))\(by)")
                            .feedText(.subheadline).foregroundStyle(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let mark = running.centre {
                        FeedMarkView(mark, size: 40, relativeTo: .largeTitle)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
                feedingFoot(feed)
            }
        } else if let start = facts.lastFeedStart {
            let elapsed = facts.now.timeIntervalSince(start)
            let steps = facts.windowSteps
            VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // Who did the last feed sits beside its label (`13-calm-home.md`, CH3).
                HStack(spacing: 6) {
                    Text("Last feed").feedText(.subheadline).foregroundStyle(Theme.textMuted)
                    if let last = facts.lastFinishedFeed {
                        Avatar(name: facts.displayName(last.event.loggedBy), colour: facts.colour(last.event.loggedBy), size: 20)
                    }
                }
                // "1h 40m ago, at 13:22" on one line, or the time over the rest when it won't fit.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        mainTime(elapsed)
                        ago(start)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        mainTime(elapsed)
                        ago(start)
                    }
                }
                if let steps {
                    WindowBar(steps: steps, clock: facts.clock)
                        .padding(.top, 10)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last feed started \(HomeText.spokenElapsed(elapsed)) ago, at \(facts.clock(start)). "
                                + (steps?.spoken(facts.clock) ?? ""))
            lastFeedFoot
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("No feeds logged yet").feedText(.title)
                Text("Tap Start feed when one begins.").feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func mainTime(_ elapsed: TimeInterval) -> some View {
        Text(HomeText.elapsed(elapsed))
            .feedText(.mainTime)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func ago(_ start: Date) -> some View {
        Text("ago, at \(Text(facts.clock(start)).fontWeight(strong).foregroundStyle(Theme.text))")
            .feedText(.subheadline).foregroundStyle(Theme.textMuted)
    }

    // MARK: The foot (`13-calm-home.md`, CH3): what the Next side and Last feed tiles said

    /// Under the bar: the last feed's chips, and the suggested next side. Nothing when there is
    /// neither (a bottle-only household has no next side).
    @ViewBuilder
    private var lastFeedFoot: some View {
        let last = facts.lastFinishedFeed
        let next = facts.nextSide
        if last != nil || next != nil {
            foot {
                if let last { FeedChips(snapshot: last) }
                Spacer(minLength: 6)
                if let next { nextSide(next) }
            } spoken: {
                [last.map { feed in
                    "Last feed: \(HomeText.chips(feed).map(\.spoken).joined(separator: ", ")). Logged by \(facts.name(feed.event.loggedBy))."
                 }, next.map { "Suggested next side: \($0 == .left ? "left" : "right")." }]
                    .compactMap { $0 }.joined(separator: " ")
            }
        }
    }

    /// During a feed: the feed so far (a live clock on the side being fed), and when the last one
    /// started.
    @ViewBuilder
    private func feedingFoot(_ feed: EventSnapshot) -> some View {
        let details = feed.payload?.feed
        let hasChips = !(details?.breast.isEmpty ?? true) || !(details?.bottles.isEmpty ?? true)
        let last = facts.lastFinishedFeed
        if hasChips || last != nil {
            foot {
                if hasChips { FeedChips(snapshot: feed) }
                Spacer(minLength: 6)
                if let last {
                    Text("Last feed \(Text(facts.clock(last.event.startedAt)).fontWeight(strong).foregroundStyle(Theme.text))")
                        .feedText(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize()
                }
            } spoken: {
                [hasChips ? "This feed: \(HomeText.chips(feed).map(\.spoken).joined(separator: ", "))." : nil,
                 last.map { "Last feed started at \(facts.clock($0.event.startedAt))." }]
                    .compactMap { $0 }.joined(separator: " ")
            }
        }
    }

    /// A line under the bar, then its contents in a row (or a column when too wide).
    private func foot<Content: View>(@ViewBuilder _ content: () -> Content, spoken: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.background).frame(height: 1.5)
            HStack(alignment: .center, spacing: 8) {
                content()
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken())
    }

    /// "Next ◐ Left".
    private func nextSide(_ side: BreastSide) -> some View {
        HStack(spacing: 6) {
            Text("Next").feedText(.subheadline).foregroundStyle(Theme.textMuted)
            FeedMarkView(.side(side), size: 18, relativeTo: .subheadline)
            Text(side == .left ? "Left" : "Right").feedText(.smallButton)
        }
        .fixedSize()
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

/// The last 24 hours, inside Home's Today (`13-calm-home.md`, CH6): the key, the strip, then the
/// totals.
struct DaySummary: View {
    let facts: HomeFacts
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Total: Identifiable {
        let value: Int
        let unit: String
        var id: String { unit }
    }

    var body: some View {
        let totals = facts.totals
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Last 24 hours").feedText(.small).foregroundStyle(Theme.textMuted)
                Spacer(minLength: 8)
                key
            }
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

/// Who is on tonight, with "I'll take it" and the rest, any ask's line, and "waiting for the
/// other phone": the part of Home's Tonight that always shows (`13-calm-home.md`, CH6). The week
/// of nights folds under it (`TonightFold`).
struct TonightLines: View {
    let facts: HomeFacts
    let me: MemberID
    let onUndo: (UndoAction) -> Void
    /// Nothing in the week's row to show: no rota, and nobody has taken a night.
    let noRota: Bool

    var body: some View {
        let state = facts.data.householdState
        let nights = facts.nights
        let onTonight = nights.first { $0.night == facts.tonight }?.onDuty
        // Someone took tonight: either parent can give it back to both phones.
        let taken = state.claim(for: facts.tonight) != nil && facts.otherMember != nil
        let waiting = !facts.data.unacknowledgedChanges(by: me).isEmpty
        VStack(alignment: .leading, spacing: 7) {
            if noRota {
                Text("No night rota yet: both phones alert at night.")
                    .feedText(.subheadline)
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
/// answer is yes. After "Not tonight", "I'll take it" stays in Tonight.
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
            TonightLines.take(ask.night, me: me, onUndo: onUndo)
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
    /// Feeding Dev's Duo preview leaves it out: the simulator has no iCloud, and the real phones
    /// don't show it, so the preview measures the page as the phones see it.
    @Environment(\.previewHidesSyncProblem) private var hidden

    var body: some View {
        if !hidden, let problem = AppModel.shared.sync.problem ?? AppModel.shared.store.problem {
            Text(problem)
                .feedText(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.notice.opacity(0.22), in: RoundedRectangle(cornerRadius: Radius.smallButton))
        }
    }
}

extension EnvironmentValues {
    /// True in Feeding Dev's Duo preview only (`DuoPreview`): no iCloud banner there.
    @Entry var previewHidesSyncProblem = false
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
