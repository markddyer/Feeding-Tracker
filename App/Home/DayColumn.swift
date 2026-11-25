import FeedingCore
import SwiftUI

/// The open Duo's right page, "today" (the Book, `docs/planning/13-calm-home.md`, CH7 and CH8):
/// the totals line, then the day as a timeline, earlier at the top like a calendar, with
/// the log buttons along the bottom, under the right thumb. The home screen beside it is "now". It scrolls, so it doesn't need to avoid the
/// fold. Closed, in laptop pose or in Split View, it doesn't show, and Home is the phone page.
struct DayColumn: View {
    let me: MemberID
    let babyID: String
    /// Its taps' Undo card shows over the home column.
    let onUndo: (UndoAction) -> Void

    private let model = AppModel.shared
    @State private var editing: EventEditor.Mode?
    @State private var careEditing: CareEditor.Mode?
    @State private var pooDetails: PooDetailsTarget?
    /// The morning card, from the AI card's slim line at the top.
    @State private var morningCard: MorningCardRequest?

    private var log: CareLog { CareLog(me: me, babyID: babyID, onUndo: onUndo) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let facts = HomeFacts(data: model.store.data, babyID: babyID, baby: model.babyDetails, me: me,
                                  names: model.memberNames, colours: model.memberColours, now: context.date)
            VStack(spacing: 0) {
                // These stay put over the timeline: what waits above the top tile on the phone (a
                // sync problem, an ask, "Last night" or the AI card's line), so the left page never
                // scrolls (CH10), then the day's totals. Tonight is a card on the left page.
                VStack(alignment: .leading, spacing: 10) {
                    HomeTopLines(facts: facts, me: me, babyID: babyID, onUndo: onUndo) {
                        morningCard = MorningCardRequest()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Today").feedText(.dayHeading).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Text(HomeText.daySummary(facts.totals))
                            .feedText(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)
                // Like a calendar, earlier at the top (the user's ask, 24 Nov 2026): it opens at
                // its end, where now and the window ahead are, with when the phones last synced.
                ScrollView {
                    VStack(spacing: 4) {
                        DayTimeline(facts: facts) { open($0) }
                        SyncedNote()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LogDock(facts: facts, log: log) { pooDetails = $0 }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(Theme.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .sheet(item: $editing) { mode in
            EventEditor(mode: mode, me: me, babyID: babyID)
        }
        .sheet(item: $careEditing) { mode in
            CareEditor(mode: mode, me: me, babyID: babyID)
        }
        .sheet(item: $pooDetails) { target in
            PooDetailsSheet(target: target, me: me, zone: model.store.data.householdSettings.timeZone, log: log)
        }
        .sheet(item: $morningCard) { request in
            InsightCardSheet(kind: .morning, night: request.night)
        }
    }

    /// An entry opened to change it, as History does. Details from a newer app version can't be
    /// edited here.
    private func open(_ entry: EventSnapshot) {
        guard entry.payload != nil else { return }
        let kind = entry.event.kind
        if kind == .feed || kind == .pump { editing = .edit(id: entry.id) } else { careEditing = .edit(id: entry.id) }
    }
}

extension DayColumn {
    /// Whether the second column is showing, from the home column's width and the whole
    /// arrangement's. `ArrangementView` gives no direct signal; when it hides the second column the
    /// home column takes the whole width. Unknown widths (0) count as not showing, so nothing is
    /// hidden by mistake.
    static func isShowing(homeWidth: CGFloat, arrangementWidth: CGFloat) -> Bool {
        arrangementWidth > 0 && homeWidth > 0 && homeWidth < arrangementWidth * 0.8
    }
}

extension EnvironmentValues {
    /// True while the Duo's second column (`DayColumn`) shows beside the home screen, so the home
    /// screen can leave out what that column holds. False everywhere else, so nothing is lost if
    /// the arrangement is ever misread: at worst something shows twice.
    @Entry var secondColumnShowing = false
}

// MARK: - The timeline (`13-calm-home.md`, CH8)

/// The last 24 hours, earlier at the top like a calendar (the user's ask, 24 Nov 2026): an hour
/// ruler, the night shaded, sleeps as lilac bars and feeds as pink or blue blocks as long as they
/// lasted, and beside each its time, details and who did it. Under "now", the feeding window and
/// the backup alarm still to come. A tap on an entry or a sleep's bar opens it.
struct DayTimeline: View {
    let facts: HomeFacts
    let open: (EventSnapshot) -> Void

    /// Points for an hour where nothing crowds: the page stretches where entries come close, so
    /// each label stays beside its own time (`TimeScale`).
    private static let hourHeight: CGFloat = 48
    /// The least room between two labels.
    private static let labelGap: CGFloat = 30
    /// Where the lanes and the words start.
    private static let rulerWidth: CGFloat = 28
    private static let sleepX: CGFloat = 34
    private static let feedX: CGFloat = 49
    private static let laneWidth: CGFloat = 11
    private static let wordsX: CGFloat = 68

    var body: some View {
        let now = facts.now
        // Ahead of now, while no feed runs: the window, and the backup alarm when alerts are on.
        let steps = facts.feedInProgress == nil ? facts.windowSteps : nil
        let ahead = steps.map { ($0.backupAt ?? $0.alertAt).addingTimeInterval(15 * 60) } ?? now
        let top = min(max(now.addingTimeInterval(30 * 60), ahead), now.addingTimeInterval(6 * 3600))
        let bottom = now.addingTimeInterval(-24 * 3600)
        let entries = HomeText.recentEntries(facts)
        let labelled = entries.filter { $0.event.kind != .sleep }.map(\.event.startedAt)
            + [steps?.opensAt, steps?.backupAt].compactMap { $0 }
        let scale = TimeScale(earliest: bottom, latest: top, labels: labelled, hourHeight: Self.hourHeight, gap: Self.labelGap)
        let y: (Date) -> CGFloat = scale.y
        ZStack(alignment: .topLeading) {
            ForEach(Array(nightSpans(top: top, bottom: bottom).enumerated()), id: \.offset) { _, span in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.surface.opacity(0.6))
                    .frame(height: y(span.end) - y(span.start))
                    .padding(.leading, Self.rulerWidth - 2)
                    .offset(y: y(span.start))
                    .accessibilityHidden(true)
            }
            ForEach(hours(top: top, bottom: bottom), id: \.self) { hour in
                hourLine(hour).offset(y: y(hour) - 8)
            }
            if let steps { windowMarks(steps, y: y) }
            ForEach(entries.filter { $0.event.kind == .sleep }) { sleep in
                sleepBar(sleep, y: y)
            }
            ForEach(entries.filter { $0.event.kind == .feed }) { feed in
                feedBlock(feed, y: y)
            }
            nowLine.offset(y: y(now) - 9)
            PushDownLayout(spacing: 2) {
                ForEach(labels(entries: entries, steps: steps, y: y)) { label in
                    label.view.layoutValue(key: DesiredY.self, value: label.y)
                }
            }
            .padding(.leading, Self.wordsX)
        }
        .frame(maxWidth: .infinity, minHeight: y(top) + 12, alignment: .topLeading)
    }

    // MARK: The ruler

    /// Each whole hour from the bottom to the top.
    private func hours(top: Date, bottom: Date) -> [Date] {
        let calendar = calendar
        guard var hour = calendar.dateInterval(of: .hour, for: bottom)?.end else { return [] }
        var hours: [Date] = []
        while hour <= top {
            hours.append(hour)
            hour = hour.addingTimeInterval(3600)
        }
        return hours
    }

    private func hourLine(_ hour: Date) -> some View {
        HStack(spacing: 4) {
            Text(hour.formatted(Date.FormatStyle(timeZone: facts.settings.timeZone).hour(.twoDigits(amPM: .omitted))))
                .feedText(.small)
                .monospacedDigit()
                .foregroundStyle(Theme.textMuted)
                .fixedSize()
                .frame(width: Self.rulerWidth - 4, alignment: .leading)
            Rectangle().fill(Theme.surface).frame(height: 1)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private var nowLine: some View {
        HStack(spacing: 4) {
            Text("now")
                .feedText(.small)
                .fontWeight(.bold)
                .fixedSize()
                .frame(width: Self.rulerWidth - 4, alignment: .leading)
            Rectangle().fill(Theme.text).frame(height: 2.5)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    /// The household's nights (21:00 to 07:00 by default) inside the timeline, on its own clock.
    private func nightSpans(top: Date, bottom: Date) -> [(start: Date, end: Date)] {
        let calendar = calendar
        let hours = facts.settings.dayHours
        let nightStart = hours.nightStart.minutesSinceMidnight, dayStart = hours.dayStart.minutesSinceMidnight
        guard nightStart != dayStart else { return [] }
        var spans: [(start: Date, end: Date)] = []
        var day = calendar.startOfDay(for: bottom.addingTimeInterval(-24 * 3600))
        while day < top {
            let endDay = nightStart > dayStart ? calendar.date(byAdding: .day, value: 1, to: day) ?? day : day
            if let start = calendar.date(bySettingHour: nightStart / 60, minute: nightStart % 60, second: 0, of: day),
               let end = calendar.date(bySettingHour: dayStart / 60, minute: dayStart % 60, second: 0, of: endDay) {
                let from = max(start, bottom), to = min(end, top)
                if from < to { spans.append((from, to)) }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(24 * 3600)
        }
        return spans
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = facts.settings.timeZone
        return calendar
    }

    // MARK: The lanes

    /// The window from its opening to the alert, and the stretch to the backup alarm, as narrow
    /// marks in the feeds' lane; their words go with the other labels.
    private func windowMarks(_ steps: WindowSteps, y: (Date) -> CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.window)
                .frame(width: Self.laneWidth, height: max(4, y(steps.alertAt) - y(steps.opensAt)))
                .offset(y: y(steps.opensAt))
            if let backup = steps.backupAt, backup > steps.alertAt {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.backupStripe)
                    .frame(width: Self.laneWidth, height: max(4, y(backup) - y(steps.alertAt) - 2))
                    .offset(y: y(steps.alertAt) + 2)
            }
        }
        .padding(.leading, Self.feedX)
        .accessibilityHidden(true)
    }

    /// A sleep: a lilac bar from when it started to when it ended (to now while it runs). A tap
    /// opens it.
    private func sleepBar(_ sleep: EventSnapshot, y: (Date) -> CGFloat) -> some View {
        let end = sleep.event.endedAt ?? facts.now
        let height = max(4, y(end) - y(sleep.event.startedAt))
        return Button { open(sleep) } label: {
            RoundedRectangle(cornerRadius: Self.laneWidth / 2)
                .fill(Theme.sleepMark.opacity(0.65))
                .frame(width: Self.laneWidth, height: height)
                .frame(width: 24, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: Self.sleepX - 6.5, y: y(sleep.event.startedAt))
        .accessibilityLabel("\(facts.clock(sleep.event.startedAt)): \(CareRow.line(for: sleep, zone: facts.settings.timeZone, now: facts.now))")
        .accessibilityHint("Opens it to change.")
    }

    /// A feed: a block as long as it lasted, pink for the breast, blue for a bottle, both when it
    /// had both (the bottle over the breast, as on the 24-hour strip).
    private func feedBlock(_ feed: EventSnapshot, y: (Date) -> CGFloat) -> some View {
        let end = feed.event.endedAt ?? facts.now
        let details = feed.payload?.feed
        let breast = !(details?.breast.isEmpty ?? true), bottle = !(details?.bottles.isEmpty ?? true)
        return VStack(spacing: 0) {
            if bottle { Rectangle().fill(Theme.bottleMark) }
            if breast || !bottle { Rectangle().fill(breast ? Theme.breastMark : Theme.textMuted) }
        }
        .frame(width: Self.laneWidth, height: max(6, y(end) - y(feed.event.startedAt)))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .offset(x: Self.feedX, y: y(feed.event.startedAt))
        .accessibilityHidden(true)
    }

    // MARK: The words

    private struct TimelineLabel: Identifiable {
        let id: String
        let y: CGFloat
        let view: AnyView
    }

    /// Every label, top to bottom: each entry but the sleeps (their bars say it), then the window
    /// and the backup alarm ahead, centred on their times and pushed down where they would overlap.
    private func labels(entries: [EventSnapshot], steps: WindowSteps?, y: (Date) -> CGFloat) -> [TimelineLabel] {
        var labels: [TimelineLabel] = []
        if let steps {
            if let backup = steps.backupAt {
                labels.append(TimelineLabel(id: "backup", y: y(backup) - 9, view: AnyView(aheadText("bell.fill", "Backup alarm \(facts.clock(backup))"))))
            }
            let alert = steps.alertsEnabled ? " · alert \(facts.clock(steps.alertAt))" : ""
            labels.append(TimelineLabel(id: "window", y: y(steps.opensAt) - 9,
                                view: AnyView(aheadText(nil, "Feeding window from \(facts.clock(steps.opensAt))\(alert)"))))
        }
        let who = facts.data.whoDidIt(babyID: facts.babyID, now: facts.now)
        for entry in entries where entry.event.kind != .sleep {
            labels.append(TimelineLabel(id: entry.id, y: y(entry.event.startedAt) - 13,
                                view: AnyView(entryLabel(entry, answer: who.doneBy(entry.id)))))
        }
        return labels.sorted { $0.y < $1.y }
    }

    private func aheadText(_ symbol: String?, _ text: String) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .feedText(.small)
        .fontWeight(.semibold)
        .foregroundStyle(Theme.textMuted)
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
    }

    /// One entry as one pill holding everything (the user's ask, 24 Nov 2026): its time, its
    /// shapes and numbers (or words), and who did it, as wide as it needs. A tap opens it.
    private func entryLabel(_ entry: EventSnapshot, answer: WhoDidIt.Answer?) -> some View {
        let people = RowPeople(entry, answer: answer)
        let isFeed = entry.event.kind == .feed || entry.event.kind == .pump
        let zone = facts.settings.timeZone
        let line = isFeed ? HomeText.chips(entry, detailed: true).map(\.spoken).joined(separator: ", ")
                          : CareRow.line(for: entry, zone: zone, now: facts.now)
        return HStack(spacing: 0) {
            Button { open(entry) } label: {
                HStack(alignment: .center, spacing: 8) {
                    Text(facts.clock(entry.event.startedAt))
                        .feedText(.smallButton)
                        .monospacedDigit()
                        .fixedSize()
                    if isFeed {
                        feedFacts(entry)
                    } else {
                        fact(CareRow.mark(for: entry), line)
                    }
                    Avatar(name: people.main.name, colour: people.main.colour, size: 20)
                        .workedOutRing(people.main.workedOut)
                }
                .padding(.leading, 10)
                .padding(.trailing, 5)
                .padding(.vertical, 3)
                .frame(minHeight: 28)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.smallButton))
                .contentShape(RoundedRectangle(cornerRadius: Radius.smallButton))
            }
            .buttonStyle(PressStyle())
            .foregroundStyle(Theme.text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(facts.clock(entry.event.startedAt)): \(line). \(people.role) \(people.main.spoken).")
            .accessibilityHint(entry.payload == nil ? "" : "Opens it to change.")
            Spacer(minLength: 0)
        }
    }

    /// A shape and its words, plain inside the pill (never a pill in a pill).
    private func fact(_ mark: FeedMark?, _ text: String) -> some View {
        HStack(spacing: 4) {
            if let mark { FeedMarkView(mark) }
            if !text.isEmpty {
                Text(text).feedText(.chip).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    /// A feed's or pumping's sides, bottles and amounts, short (the block beside it says breast
    /// or bottle), with a live clock on the side being fed while it runs.
    private func feedFacts(_ entry: EventSnapshot) -> some View {
        let segments = entry.payload?.feed?.breast ?? []
        let running = entry.event.endedAt == nil
            ? segments.last.flatMap { $0.durationSeconds == nil ? $0.startedAt : nil } : nil
        let chips = HomeText.chips(entry)
        return HStack(spacing: 8) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                if let running, index == segments.count - 1 {
                    HStack(spacing: 4) {
                        if let mark = chip.mark { FeedMarkView(mark) }
                        Text(running, style: .timer).feedText(.chip).monospacedDigit()
                        Text("running").feedText(.chip)
                    }
                    .fixedSize()
                } else {
                    fact(chip.mark, chip.text)
                }
            }
        }
    }
}

// MARK: - The time scale

/// Times to heights down the timeline, earlier at the top: an hour is `hourHeight` points,
/// except where labels come closer than `gap`; there the page stretches, so marks, hour lines and
/// labels all move together and each label stays beside its own time.
private struct TimeScale {
    private let anchors: [(time: Date, y: CGFloat)]

    init(earliest: Date, latest: Date, labels: [Date], hourHeight: CGFloat, gap: CGFloat) {
        func step(_ from: Date, _ to: Date) -> CGFloat { CGFloat(to.timeIntervalSince(from) / 3600) * hourHeight }
        var anchors: [(time: Date, y: CGFloat)] = [(earliest, 0)]
        var lastLabel: CGFloat?
        for time in labels.sorted() where time >= earliest && time <= latest {
            let previous = anchors[anchors.count - 1]
            let natural = previous.y + step(previous.time, time)
            let y = max(natural, lastLabel.map { $0 + gap } ?? gap / 2)
            anchors.append((time, y))
            lastLabel = y
        }
        let previous = anchors[anchors.count - 1]
        anchors.append((latest, previous.y + step(previous.time, latest)))
        self.anchors = anchors
    }

    func y(_ time: Date) -> CGFloat {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if time <= first.time { return first.y }
        if time >= last.time { return last.y }
        for index in 1..<anchors.count where time <= anchors[index].time {
            let upper = anchors[index - 1], lower = anchors[index]
            let span = lower.time.timeIntervalSince(upper.time)
            let share = span > 0 ? time.timeIntervalSince(upper.time) / span : 1
            return upper.y + CGFloat(share) * (lower.y - upper.y)
        }
        return last.y
    }
}

// MARK: - The labels' layout

/// Where a label would sit, centred on its time.
private struct DesiredY: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

/// Labels down the page, each at its own height unless the one above reaches it; then just
/// under that one. Given in order, top first.
private struct PushDownLayout: Layout {
    var spacing: CGFloat = 2

    private func places(_ width: CGFloat, _ subviews: Subviews) -> [(y: CGFloat, height: CGFloat)] {
        var bottom = -spacing
        return subviews.map { subview in
            let height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            let y = max(subview[DesiredY.self], bottom + spacing)
            bottom = y + height
            return (y, height)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let bottom = places(width, subviews).map { $0.y + $0.height }.max() ?? 0
        return CGSize(width: width, height: max(0, bottom))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, place) in zip(subviews, places(bounds.width, subviews)) {
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + place.y),
                          proposal: ProposedViewSize(width: bounds.width, height: place.height))
        }
    }
}
