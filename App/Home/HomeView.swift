import FeedingCore
import SwiftUI

/// The home screen (plan v1, "Screens"): the time since the last feed started first, then the
/// window, the suggested side, the last feed, the last 24 hours and tonight's duty, with the feed
/// buttons pinned at the bottom. Facts only: no targets, no verdicts.
struct HomeView: View {
    let me: MemberID
    let babyID: String

    private let model = AppModel.shared
    @State private var undo: UndoAction?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let facts = HomeFacts(data: model.store.data, babyID: babyID, me: me, names: model.memberNames, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SyncBanner()
                    header(facts)
                    if let next = facts.nextSide, facts.feedInProgress == nil {
                        line("Next side", next == .left ? "Left" : "Right", note: "a suggestion")
                    }
                    if let last = facts.lastFeedSummary {
                        line("Last feed", last)
                    }
                    line("Last 24 hours", facts.dayTotals)
                    DutyRow(facts: facts, me: me, onUndo: { undo = $0 })
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if let undo, undo.expiresAt > context.date {
                        UndoBanner(action: undo) { self.undo = nil }
                    }
                    FeedControls(facts: facts, me: me, babyID: babyID, onUndo: { undo = $0 })
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                // Solid black behind the buttons, fading in at the top edge, so the page that
                // scrolls under them never shows through.
                .background {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .bottom)
                            .frame(height: 12)
                        Theme.background
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func header(_ facts: HomeFacts) -> some View {
        HStack(alignment: .center, spacing: 18) {
            WindowRing(progress: facts.windowProgress)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                if let inProgress = facts.feedInProgress {
                    Text("Feed in progress").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    Text(inProgress.event.startedAt, style: .timer)
                        .feedText(.mainTime)
                    Text(inProgress.event.loggedBy == me
                         ? "Started \(facts.clock(inProgress.event.startedAt))"
                         : "Started \(facts.clock(inProgress.event.startedAt)) by \(facts.name(inProgress.event.loggedBy))")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                } else if let start = facts.lastFeedStart {
                    Text("Last feed started").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    Text("\(AlertText.duration(facts.now.timeIntervalSince(start))) ago")
                        .feedText(.mainTime)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("at \(facts.clock(start))").font(.subheadline).foregroundStyle(Theme.secondaryText)
                } else {
                    Text("No feeds logged yet").feedText(.title)
                    Text("Tap Start feed when one begins.").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        if let window = facts.windowLine {
            Text(window).font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
    }

    private func line(_ title: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).feedText(.label).foregroundStyle(Theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.body)
                if let note {
                    Text(note).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
}

/// Everything the home screen shows, worked out once per refresh.
struct HomeFacts {
    let data: HouseholdData
    let babyID: String
    let me: MemberID
    let names: [MemberID: String]
    let now: Date
    let settings: HouseholdSettings
    let lastFeedStart: Date?
    let feedInProgress: EventSnapshot?
    let nextSide: BreastSide?

    init(data: HouseholdData, babyID: String, me: MemberID, names: [MemberID: String], now: Date) {
        self.data = data
        self.babyID = babyID
        self.me = me
        self.names = names
        self.now = now
        settings = data.householdSettings
        lastFeedStart = data.allEvents.latestFeedStart(babyID: babyID, now: now)
        feedInProgress = data.feedInProgress(babyID: babyID)
        nextSide = suggestedNextSide(data.snapshots, babyID: babyID, now: now)
    }

    func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: settings.timeZone))
    }

    func name(_ member: MemberID) -> String {
        member == me ? "you" : (names[member] ?? "the other parent")
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

    var windowLine: String? {
        guard let lastFeedStart, settings.window.alertsEnabled else {
            return lastFeedStart == nil ? nil : "Alerts are off"
        }
        let window = FeedWindow(lastFeedStart: lastFeedStart, settings: settings.window)
        return "Window opens \(clock(window.opensAt)) · Alert at \(clock(window.closesAt))"
    }

    /// "L 12m · R 8m · Formula 30 ml, logged by Parent A".
    var lastFeedSummary: String? {
        let feeds = data.snapshots.filter { $0.event.isLiveFeed && $0.event.babyID == babyID && $0.event.endedAt != nil }
        guard let last = feeds.max(by: { $0.event.startedAt < $1.event.startedAt }) else { return nil }
        return "\(Self.details(last)), logged by \(name(last.event.loggedBy))"
    }

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

    var dayTotals: String {
        let totals = summarise(data.snapshots, babyID: babyID, from: now.addingTimeInterval(-24 * 3600), to: now)
        var parts = ["\(totals.feeds) \(totals.feeds == 1 ? "feed" : "feeds")", "\(totals.breastFeeds) at the breast"]
        if totals.expressedML > 0 { parts.append("\(totals.expressedML) ml expressed") }
        if totals.formulaML > 0 { parts.append("\(totals.formulaML) ml formula") }
        if totals.pumpSessions > 0 { parts.append("\(totals.pumpedML) ml pumped") }
        return parts.joined(separator: " · ")
    }

    /// The night that is on now, or the one coming tonight.
    var tonight: PlainDate {
        switch settings.dayHours.period(at: now, in: settings.timeZone) {
        case .night(let night): night
        case .day(let day): day
        }
    }
}

/// The ring round the time: how far through the window it is. One colour throughout.
struct WindowRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.raisedSurface, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityLabel("Progress through the feed window")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// "Parent B is on tonight", with "I'll take tonight" and whether the other phone has seen it.
struct DutyRow: View {
    let facts: HomeFacts
    let me: MemberID
    let onUndo: (UndoAction) -> Void

    var body: some View {
        let state = facts.data.householdState
        let onDuty = state.roster(for: me).onDuty(night: facts.tonight)
        let waiting = !facts.data.unacknowledgedChanges(by: me).isEmpty
        VStack(alignment: .leading, spacing: 8) {
            Text("Tonight").feedText(.label).foregroundStyle(Theme.secondaryText)
            if state.rota == nil && state.claims.isEmpty {
                Text("No night rota yet: both phones alert at night.")
            } else {
                Text(onDuty == me ? "You're on tonight" : "\(facts.name(onDuty).capitalizedFirst) is on tonight")
            }
            if onDuty != me || state.rota == nil {
                Button("I'll take tonight") {
                    let night = facts.tonight
                    AppModel.shared.store.change { $0.claimNight(night, by: me, now: Date()) }
                    onUndo(UndoAction(message: "You're on tonight") {
                        AppModel.shared.store.change { $0.undoClaim(night, by: me) }
                    })
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
            if waiting {
                Text("Waiting for \(facts.otherName.map { "\($0)'s phone" } ?? "the other phone") to see your change. Until then, this phone alerts as if on duty.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// Shows a sync problem, or when the phones last synced.
struct SyncBanner: View {
    var body: some View {
        let sync = AppModel.shared.sync
        if let problem = sync.problem ?? AppModel.shared.store.problem {
            Text(problem)
                .font(.footnote)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warning.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        } else if AppConfig.syncEnabled, let fetched = sync.lastFetchAt {
            Text("Synced \(fetched, style: .relative) ago")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
