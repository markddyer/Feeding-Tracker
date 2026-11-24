import FeedingCore
import SwiftUI

// Home's folded parts (`docs/planning/13-calm-home.md`, CH6): Today, Tonight and Recent, under
// the care list. Each starts closed, shows a one-line summary on its heading, and each phone
// remembers what is open. A line that matters for the alarms (Tonight's who-is-on line and its
// buttons, an ask, "waiting for the other phone") always shows, never folded away.

/// A heading that opens and closes the part under it: the name, a summary, and a chevron. What
/// `always` holds shows either way.
struct FoldSection<Always: View, Inner: View>: View {
    let title: String
    var summary: String = ""
    /// False when there is nothing to open: no chevron, and the heading is not a button.
    var canOpen = true
    @AppStorage private var open: Bool
    private let always: Always
    private let inner: Inner

    init(_ title: String, summary: String = "", key: String, canOpen: Bool = true,
         @ViewBuilder always: () -> Always, @ViewBuilder inner: () -> Inner) {
        self.title = title
        self.summary = summary
        self.canOpen = canOpen
        _open = AppStorage(wrappedValue: false, "home.open.\(key)")
        self.always = always()
        self.inner = inner()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(Theme.surface).frame(height: 1.5).accessibilityHidden(true)
                .padding(.bottom, 4)
            if canOpen {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { open.toggle() }
                } label: {
                    heading
                }
                .buttonStyle(.plain)
                .accessibilityLabel(summary.isEmpty ? title : "\(title), \(summary)")
                .accessibilityValue(open ? "Open" : "Closed")
                .accessibilityHint(open ? "Closes it." : "Opens it.")
                .accessibilityAddTraits(.isHeader)
            } else {
                heading.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            }
            always
            if open && canOpen {
                inner
                    .transition(.opacity)
                    .padding(.bottom, 6)
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 10) {
            Text(title).feedText(.dayHeading)
            Spacer(minLength: 8)
            if !summary.isEmpty {
                Text(summary)
                    .feedText(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if canOpen {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

extension FoldSection where Always == EmptyView {
    init(_ title: String, summary: String = "", key: String, canOpen: Bool = true, @ViewBuilder inner: () -> Inner) {
        self.init(title, summary: summary, key: key, canOpen: canOpen, always: { EmptyView() }, inner: inner)
    }
}

/// Today: the last 24 hours as the strip and the totals, with the totals in a line on the heading.
struct TodayFold: View {
    let facts: HomeFacts

    var body: some View {
        FoldSection("Today", summary: HomeText.daySummary(facts.totals), key: "today") {
            DaySummary(facts: facts)
        }
    }
}

/// Recent: the last 24 hours' entries, newest first, as plain rows in one box. A tap opens the
/// entry to change it, as in History.
struct RecentFold: View {
    let facts: HomeFacts
    let edit: (EventSnapshot) -> Void

    var body: some View {
        let entries = HomeText.recentEntries(facts)
        FoldSection("Recent", summary: entries.first.map { HomeText.recentSummary($0, facts: facts) } ?? "Nothing yet",
                    key: "recent", canOpen: !entries.isEmpty) {
            RecentList(entries: entries, facts: facts, edit: edit)
        }
    }
}

/// The rows of Recent, in one `surface` box with gaps between them.
struct RecentList: View {
    let entries: [EventSnapshot]
    let facts: HomeFacts
    let edit: (EventSnapshot) -> Void

    var body: some View {
        let zone = facts.settings.timeZone
        let who = facts.data.whoDidIt(babyID: facts.babyID, now: facts.now)
        let kept = Set((facts.data.duplicatePairs(babyID: facts.babyID) + facts.data.careDuplicatePairs(babyID: facts.babyID)).map(\.kept))
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { CareDivider() }
                Button {
                    // Details from a newer app version can't be edited here.
                    if entry.payload != nil { edit(entry) }
                } label: {
                    let isFeed = entry.event.kind == .feed || entry.event.kind == .pump
                    if isFeed {
                        HistoryRow(entry, zone: zone, loggedTwice: kept.contains(entry.id), answer: who.doneBy(entry.id))
                            .untintedRow()
                    } else {
                        CareRow(entry, zone: zone, now: facts.now, loggedTwice: kept.contains(entry.id),
                                answer: who.doneBy(entry.id))
                            .untintedRow()
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityHint(entry.payload == nil ? "" : "Opens it to change.")
            }
        }
        .padding(.horizontal, 2)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile))
    }
}

/// Tonight: who is on, with its buttons and any ask line always showing; the week of nights
/// folded under it.
struct TonightFold: View {
    let facts: HomeFacts
    let me: MemberID
    let onUndo: (UndoAction) -> Void

    var body: some View {
        let state = facts.data.householdState
        let noRota = state.rota == nil && facts.nights.allSatisfy { $0.onDuty == nil }
        FoldSection("Tonight", key: "tonight", canOpen: !noRota) {
            TonightLines(facts: facts, me: me, onUndo: onUndo, noRota: noRota)
                .environment(\.chipBackground, Theme.surface)
        } inner: {
            NightsRow(nights: facts.nights, tonight: facts.tonight, facts: facts)
                .padding(.top, 4)
        }
    }
}

extension View {
    /// A History row without its own tint, inside a box that has one (Home's Recent).
    func untintedRow() -> some View {
        environment(\.plainHistoryRow, true)
    }
}

extension EnvironmentValues {
    /// True inside Home's Recent box: History's rows drop their tint there.
    @Entry var plainHistoryRow = false
}
