import FeedingCore
import SwiftUI

// The "who did what" page (`09-who-does-what.md`, R1 and the design review): each parent's part,
// side by side, as facts. Never a winner, a score word, red or green; both phones see the same,
// with the household's owner on the left (2C). Every number opens the list behind it (X2), drawn
// from the same items (`WhoDidIt`), so a number always equals its list.

/// The page's ranges (design 1C). Each phone remembers the last one; the page opens on 7 days.
enum SharePageRange: String, CaseIterable {
    case day, week, fourWeeks, all

    func range(day: PlainDate) -> ShareRange {
        switch self {
        case .day: .day(day)
        case .week: .lastDays(7)
        case .fourWeeks: .lastDays(28)
        case .all: .all
        }
    }
}

/// Who sits where (2C): the household's owner on the left on both phones, the other parent on the
/// right; anyone else is "Other" (2D).
struct ShareSides: Equatable {
    var left: MemberID?
    var right: MemberID?
    var names: [MemberID: String]
    var colours: [MemberID: ParentColour]

    @MainActor static func current() -> ShareSides {
        let model = AppModel.shared
        let names = model.memberNames
        let members = names.keys.sorted()
        let owner = model.sync.householdOwner.flatMap { members.contains($0) ? $0 : nil }
        let left = owner ?? members.first
        return ShareSides(left: left, right: members.first { $0 != left }, names: names, colours: model.memberColours)
    }

    func name(_ member: MemberID?) -> String {
        guard let member else { return "Other" }
        return names[member] ?? "Other"
    }

    func mark(_ member: MemberID?) -> Color {
        guard let member, let colour = colours[member] else { return Theme.stone }
        return colour.mark
    }

    func colour(_ member: MemberID) -> ParentColour { colours[member] ?? .stone }

    /// True for a member who is neither side: their part is "Other".
    func isOther(_ member: MemberID) -> Bool { member != left && member != right }
}

/// The list behind one number (X2, DD10): one line, one parent (or "Other"), one range.
struct ShareListRequest: Hashable {
    var kind: ShareKind
    /// Nil with `others` false: every parent.
    var member: MemberID?
    var others = false
    var range: ShareRange
    var rangeTitle: String
    /// A time number ("Feeding time"): each row shows the time it added.
    var time = false
}

// MARK: - The tile on Graphs

/// The tile at the top of Graphs (DD3, DD9): the last 7 nights as dots with initials; tap anywhere
/// for the page.
struct WhoDidWhatTile: View {
    let who: WhoDidIt
    let today: PlainDate
    let zone: TimeZone

    var body: some View {
        NavigationLink {
            WhoDidWhatPage()
        } label: {
            Tile {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(ShareText.tileTitle)
                            .feedText(.label)
                            .foregroundStyle(Theme.textMuted)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                    }
                    NightsDots(who: who, evenings: (0..<7).map { today.adding(days: $0 - 6) }, zone: zone,
                               sides: ShareSides.current())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens who did what")
    }
}

// MARK: - The page

struct WhoDidWhatPage: View {
    private let model = AppModel.shared
    @AppStorage("share.range") private var rangeName = SharePageRange.week.rawValue
    /// "Who breastfeeds?" shows once per phone (2A).
    @AppStorage("share.breastfeederAsked") private var breastfeederAsked = false
    /// Days back from today in the Day view. Feeding Dev's screenshots can start on another day
    /// with `-share.dayOffset 1`; nothing else sets it.
    @State private var dayOffset = max(0, UserDefaults.standard.integer(forKey: "share.dayOffset"))
    @State private var askingBreastfeeder = false
    @State private var width: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let data = model.store.data
            let zone = data.householdSettings.timeZone
            let who = data.whoDidIt(babyID: model.baby?.name ?? "", now: context.date)
            let today = PlainDate(context.date, in: zone)
            let pageRange = SharePageRange(rawValue: rangeName) ?? .week
            let day = today.adding(days: -dayOffset)
            let range = pageRange.range(day: day)
            let sides = ShareSides.current()
            let facts = who.facts(range)
            let night = pageRange == .day ? who.night(day) : nil
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    SyncCheckBanner(now: context.date, zone: zone)
                    Picker("Time shown", selection: $rangeName) {
                        ForEach(SharePageRange.allCases, id: \.rawValue) { range in
                            Text(ShareText.rangeTitle(range)).tag(range.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    if pageRange == .day {
                        DayPicker(day: day, today: today, zone: zone, offset: $dayOffset)
                    }
                    if data.breastfeeder == nil {
                        Button { askingBreastfeeder = true } label: {
                            (Text(ShareText.quietBreastfeeds + " · ")
                                + Text(ShareText.setBreastfeeds + " ›").fontWeight(.bold))
                                .feedText(.small)
                                .foregroundStyle(Theme.textMuted)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    if facts.isEmpty && (night?.items.isEmpty ?? true) {
                        Tile {
                            Text(ShareText.nothingLogged(pageRange))
                                .feedText(.body)
                                .foregroundStyle(Theme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        let nights = NightsSection(pageRange: pageRange, who: who, facts: facts, night: night, today: today,
                                                   range: range, zone: zone, sides: sides)
                        let bars = WhoDidWhatSection(facts: facts, range: range, rangeTitle: rangeTitle(pageRange, day, today, zone),
                                                     sides: sides)
                        if width >= 594 - 32 {
                            // Two columns on the open Duo (6A): nights left, who did what right.
                            HStack(alignment: .top, spacing: 11) {
                                nights.frame(maxWidth: .infinity)
                                bars.frame(maxWidth: .infinity)
                            }
                        } else {
                            nights
                            bars
                        }
                    }
                    if sides.right == nil {
                        Text(ShareText.notJoined)
                            .feedText(.small)
                            .foregroundStyle(Theme.textMuted)
                    }
                    if pageRange == .day {
                        Text(ShareText.swipeHint)
                            .feedText(.small)
                            .foregroundStyle(Theme.textMuted)
                            .accessibilityHidden(true)
                    }
                    SyncCheckLine(zone: zone)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { width = $0 }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { drag in
                guard pageRange == .day, abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                if drag.translation.width > 60 {
                    dayOffset += 1
                } else if drag.translation.width < -60, dayOffset > 0 {
                    dayOffset -= 1
                }
            })
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(ShareText.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ShareListRequest.self) { ShareEntriesList(request: $0) }
        .sheet(isPresented: $askingBreastfeeder) {
            BreastfeederSheet(sides: ShareSides.current()) { answer in
                breastfeederAsked = true
                askingBreastfeeder = false
                if let answer { model.store.change { $0.setBreastfeeder(answer, now: Date()) } }
            }
        }
        .onAppear {
            if model.store.data.breastfeeder == nil, !breastfeederAsked { askingBreastfeeder = true }
        }
    }

    private func rangeTitle(_ range: SharePageRange, _ day: PlainDate, _ today: PlainDate, _ zone: TimeZone) -> String {
        range == .day ? ShareText.dayName(day, today: today, in: zone) : ShareText.rangeTitle(range)
    }
}

/// "‹ Yesterday ›" (1C): back as far as there is, forward up to today.
private struct DayPicker: View {
    let day: PlainDate
    let today: PlainDate
    let zone: TimeZone
    @Binding var offset: Int

    var body: some View {
        HStack {
            Button { offset += 1 } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Day before")
            Spacer()
            Text(ShareText.dayName(day, today: today, in: zone))
                .feedText(.smallButton)
            Spacer()
            Button { offset -= 1 } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(offset == 0)
            .accessibilityLabel("Day after")
        }
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(Theme.text)
    }
}

// MARK: - Nights

/// The nights (1A, 1B): Day shows that night in order; 7 days the dots and three bars; 4 weeks and
/// All the bars alone.
private struct NightsSection: View {
    let pageRange: SharePageRange
    let who: WhoDidIt
    let facts: ShareFacts
    let night: LastNight?
    let today: PlainDate
    let range: ShareRange
    let zone: TimeZone
    let sides: ShareSides

    var body: some View {
        switch pageRange {
        case .day:
            if let night, !night.items.isEmpty {
                Tile(label: ShareText.nightTitle(night.night, slept: night.sleptSeconds, in: zone), tint: Theme.sleepTint) {
                    VStack(spacing: 0) {
                        ForEach(night.items) { item in
                            NightLine(item: item, sides: sides, zone: zone)
                        }
                    }
                }
            }
        case .week:
            Tile(label: "Nights · who got up") {
                VStack(alignment: .leading, spacing: 12) {
                    NightsDots(who: who, evenings: (0..<7).map { today.adding(days: $0 - 6) }, zone: zone, sides: sides)
                    bars(alone: false)
                }
            }
        case .fourWeeks, .all:
            if ShareKind.allCases.contains(where: { $0.isNight && facts.total($0).count > 0 }) {
                Tile(label: pageRange == .fourWeeks ? "Nights · 4 weeks" : "Nights · all") {
                    bars(alone: true)
                }
            }
        }
    }

    private func bars(alone: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach([ShareKind.gotUpAtNight, .nightFeeds, .nightNappies], id: \.self) { kind in
                if facts.total(kind).count > 0 {
                    ShareBar(kind: kind, title: ShareText.kindTitle(kind, alone: alone), time: false, facts: facts,
                             range: range, rangeTitle: ShareText.rangeTitle(pageRange), sides: sides)
                }
            }
        }
    }
}

/// One line of a night in the Day view (1A): its time, what it was, and who.
struct NightLine: View {
    let item: ShareItem
    let sides: ShareSides
    let zone: TimeZone

    var body: some View {
        let snapshot = item.eventIDs.first.flatMap { AppModel.shared.store.data.events[$0]?.snapshot }
        let time = item.at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
        let what = ShareText.what(item, snapshot: snapshot)
        let who = ShareEntriesList.person(item)
        HStack(spacing: 10) {
            Text(time)
                .feedText(.smallButton)
                .monospacedDigit()
                .frame(minWidth: 50, alignment: .leading)
            FeedMarkView(ShareBar.mark(item.kind), size: 16, relativeTo: .body)
            Text(what)
                .feedText(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Avatar(name: who.name, colour: who.colour, size: 22)
                .workedOutRing(who.workedOut)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(time): \(what). \(item.kind == .gotUpAtNight ? "Got up" : "Done by") \(who.spoken)\(who.workedOut ? ", probably" : "").")
    }
}

/// One column per night, one dot per wake-up in the colour of who got up, bottom to top in time
/// order, with their initial inside (5A); the night's short day name under it. At the largest
/// text sizes, a list of nights instead (6B).
struct NightsDots: View {
    let who: WhoDidIt
    let evenings: [PlainDate]
    let zone: TimeZone
    let sides: ShareSides
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 17

    var body: some View {
        let wakeUps = Dictionary(grouping: who.items.filter { $0.kind == .gotUpAtNight }, by: \.day)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(evenings, id: \.self) { evening in
                    Text(ShareText.spokenNight(evening, counts: counts(wakeUps[evening] ?? []), in: zone))
                        .feedText(.small)
                }
            }
        } else {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(evenings, id: \.self) { evening in
                    let items = (wakeUps[evening] ?? []).sorted { $0.at < $1.at }
                    VStack(spacing: 3) {
                        ForEach(items.reversed()) { item in
                            Text(String(sides.name(item.member).prefix(1)).uppercased())
                                .font(.system(size: dot * 0.55, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.onParentMark)
                                .frame(width: dot, height: dot)
                                .background(sides.mark(item.member), in: Circle())
                                .overlay {
                                    if !item.saved {
                                        // A worked-out "got up" (7A).
                                        Circle().strokeBorder(Theme.text, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    }
                                }
                        }
                        Text(ShareText.shortNight(evening, in: zone))
                            .feedText(.small)
                            .foregroundStyle(Theme.textMuted)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ShareText.spokenNight(evening, counts: counts(items), in: zone))
                }
            }
            .frame(minHeight: dot * 3 + 24, alignment: .bottom)
        }
    }

    private func counts(_ items: [ShareItem]) -> [(String, Int)] {
        let byMember = Dictionary(grouping: items, by: \.member).mapValues(\.count)
        return [sides.left, sides.right].compactMap { $0 }.map { (sides.name($0), byMember[$0] ?? 0) }
            + byMember.filter { sides.isOther($0.key) }.map { (sides.name($0.key), $0.value) }
    }
}

// MARK: - Who did what

/// One shared bar per kind (DD2, 4A), in the order of the design; a kind with nothing in the range
/// is left out.
private struct WhoDidWhatSection: View {
    let facts: ShareFacts
    let range: ShareRange
    let rangeTitle: String
    let sides: ShareSides

    var body: some View {
        let lines: [(ShareKind, Bool)] = [(.feeds, false), (.feeds, true), (.nappies, false), (.settled, false),
                                          (.medicines, false), (.baths, false), (.pumping, false)]
        let shown = lines.filter { kind, time in time ? facts.total(kind).seconds > 0 : facts.total(kind).count > 0 }
        if !shown.isEmpty {
            Tile(label: ShareText.title) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                        ShareBar(kind: line.0, title: ShareText.kindTitle(line.0, time: line.1), time: line.1, facts: facts,
                                 range: range, rangeTitle: rangeTitle, sides: sides)
                    }
                }
            }
        }
    }
}

/// A shared bar (DD2): the kind's shape and name, the household's total on the right, one bar
/// split in the parents' mark colours (16 points tall, a 2-point gap, round ends) with a grey
/// "Other" part when needed (2D), and under it each parent's number, each its own button that opens
/// the list behind it (X2, 6B). A zero is printed, and the bar is then one colour (2C).
struct ShareBar: View {
    let kind: ShareKind
    let title: String
    let time: Bool
    let facts: ShareFacts
    let range: ShareRange
    let rangeTitle: String
    let sides: ShareSides
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let left = sides.left.map { facts.tally(kind, $0) } ?? ShareTally()
        let right = sides.right.map { facts.tally(kind, $0) } ?? ShareTally()
        let others = facts.tallies[kind, default: [:]].filter { sides.isOther($0.key) }.values
            .reduce(into: ShareTally()) { $0.count += $1.count; $0.seconds += $1.seconds }
        let total = facts.total(kind)
        let value: (ShareTally) -> Double = { time ? $0.seconds : Double($0.count) }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FeedMarkView(Self.mark(kind), size: 16, relativeTo: .body)
                Text(title).feedText(.body).fontWeight(.semibold)
                Spacer(minLength: 4)
                Text(ShareText.number(total, kind: kind, time: time))
                    .feedText(.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(left: left, right: right, others: others, total: total))
            SplitBar(parts: [(value(left), sides.mark(sides.left)), (value(right), sides.mark(sides.right)),
                             (value(others), Theme.stone)])
                .accessibilityHidden(true)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 6))
            layout {
                if let member = sides.left {
                    numberLink(member: member, others: false, tally: left, dotColour: sides.mark(member), leading: true)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                if others.count > 0 {
                    numberLink(member: nil, others: true, tally: others, dotColour: Theme.stone, leading: true)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                }
                if let member = sides.right {
                    numberLink(member: member, others: false, tally: right, dotColour: sides.mark(member),
                               leading: typeSize.isAccessibilitySize)
                }
            }
        }
    }

    private func numberLink(member: MemberID?, others: Bool, tally: ShareTally, dotColour: Color, leading: Bool) -> some View {
        let name = others ? "Other" : sides.name(member)
        let request = ShareListRequest(kind: kind, member: member, others: others, range: range, rangeTitle: rangeTitle, time: time)
        let words = "\(name) \(ShareText.number(tally, kind: kind, time: time))"
        return NavigationLink(value: request) {
            HStack(spacing: 5) {
                if leading { Circle().fill(dotColour).frame(width: 9, height: 9) }
                Text(words)
                    .feedText(.small)
                    .foregroundStyle(others ? Theme.textMuted : Theme.text)
                    .monospacedDigit()
                if !leading { Circle().fill(dotColour).frame(width: 9, height: 9) }
            }
            // A 44-point tap area that hangs below the words, so they sit close under the bar.
            .frame(minHeight: 44, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words)
        .accessibilityHint("Shows these entries")
    }

    static func mark(_ kind: ShareKind) -> FeedMark {
        switch kind {
        case .feeds, .nightFeeds: .side(.left)
        case .nappies, .nightNappies: .wee
        case .settled, .gotUpAtNight: .sleep
        case .medicines: .medicine
        case .baths: .bath
        case .pumping: .pump
        }
    }

    private func spoken(left: ShareTally, right: ShareTally, others: ShareTally, total: ShareTally) -> String {
        var parts: [(String, String)] = []
        if let member = sides.left { parts.append((sides.name(member), ShareText.number(left, kind: kind, time: time))) }
        if let member = sides.right { parts.append((sides.name(member), ShareText.number(right, kind: kind, time: time))) }
        if others.count > 0 { parts.append(("Other", ShareText.number(others, kind: kind, time: time))) }
        return ShareText.spokenLine(title, total: ShareText.number(total, kind: kind, time: time), parts: parts)
    }
}

/// The bar itself: parts in proportion, 2 points apart, the outer ends round.
private struct SplitBar: View {
    let parts: [(Double, Color)]

    var body: some View {
        let shown = parts.filter { $0.0 > 0 }
        let sum = shown.reduce(0) { $0 + $1.0 }
        GeometryReader { proxy in
            let gaps = CGFloat(max(0, shown.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, part in
                    UnevenRoundedRectangle(cornerRadii: .init(
                        topLeading: part.1 == shown.first?.1 ? 8 : 2, bottomLeading: part.1 == shown.first?.1 ? 8 : 2,
                        bottomTrailing: part.1 == shown.last?.1 ? 8 : 2, topTrailing: part.1 == shown.last?.1 ? 8 : 2))
                        .fill(part.1)
                        .frame(width: sum > 0 ? max(4, (proxy.size.width - gaps) * part.0 / sum) : 0)
                }
            }
        }
        .frame(height: 16)
        .background(sum == 0 ? Theme.track : .clear, in: Capsule())
    }
}

// MARK: - iCloud

/// A failed check, or one older than 15 minutes, at the top before the numbers, in `notice`
/// (1D). Only what this phone knows.
private struct SyncCheckBanner: View {
    let now: Date
    let zone: TimeZone

    var body: some View {
        let sync = AppModel.shared.sync
        if AppConfig.syncEnabled, sync.problem != nil || sync.householdFetchFailed
            || (sync.lastCompletedFetchAt.map { now.timeIntervalSince($0) > 15 * 60 } ?? false) {
            Text(ShareText.checkProblem(since: sync.lastCompletedFetchAt, in: zone))
                .feedText(.small)
                .foregroundStyle(Theme.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.notice.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// "Checked with iCloud 07:38" at the bottom (1D).
private struct SyncCheckLine: View {
    let zone: TimeZone

    var body: some View {
        let sync = AppModel.shared.sync
        if AppConfig.syncEnabled {
            Text(sync.lastCompletedFetchAt.map { ShareText.checked($0, in: zone) } ?? ShareText.notCheckedYet)
                .feedText(.small)
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
        }
    }
}

// MARK: - "Who breastfeeds?"

/// Asked on the page the first time, once per phone (DD11, 2A); changed in Settings.
struct BreastfeederSheet: View {
    let sides: ShareSides
    /// Nil for "Not now".
    let onAnswer: (Breastfeeder?) -> Void

    var body: some View {
        // Scrolls, so nothing is cut off at the largest text sizes.
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(ShareText.breastfeederQuestion)
                    .feedText(.title)
                    .accessibilityAddTraits(.isHeader)
                Text(ShareText.breastfeederExplained)
                    .feedText(.body)
                    .foregroundStyle(Theme.textMuted)
                ForEach([sides.left, sides.right].compactMap { $0 }, id: \.self) { member in
                    Button { onAnswer(.member(member)) } label: {
                        HStack(spacing: 12) {
                            Avatar(name: sides.name(member), colour: sides.colour(member), size: 30)
                            Text(sides.name(member)).feedText(.button)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sides.name(member))
                }
                Button { onAnswer(.nobody) } label: {
                    Text(ShareText.nobody).feedText(.button)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                Button { onAnswer(nil) } label: {
                    Text(ShareText.notNow)
                        .feedText(.smallButton)
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .foregroundStyle(Theme.text)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }
}
