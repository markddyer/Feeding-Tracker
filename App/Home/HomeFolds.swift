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

/// Tonight on the open Duo's left page (the Book): who is on, and any ask or wait, as one even card
/// beside the others. A tap opens the week of nights and the buttons in a window (`TonightSheet`):
/// the page has no room to show them in place without scrolling (the parents' ask, 24 Nov 2026).
struct TonightCard: View {
    let facts: HomeFacts
    let me: MemberID
    let open: () -> Void

    var body: some View {
        let onTonight = facts.nights.first { $0.night == facts.tonight }?.onDuty
        let lines = Self.lines(facts: facts, me: me, onTonight: onTonight)
        Button(action: open) {
            // On a short card, the ask or the wait before who is on: the circle shows who is on.
            FactCard(mark: mark(onTonight), title: "Tonight", detail: lines.joined(separator: "\n"),
                     shortDetail: lines.last, spoken: "Tonight: " + lines.joined(separator: ". "), opens: true)
        }
        .buttonStyle(PressStyle())
        .accessibilityHint("Opens the week of nights and its buttons.")
    }

    @ViewBuilder
    private func mark(_ member: MemberID?) -> some View {
        if let member {
            Avatar(name: facts.displayName(member), colour: facts.colour(member), size: 24)
        } else {
            EmptyAvatar(size: 24)
        }
    }

    /// Who is on ("Sam's on", "You're on", "Both phones alert", "No rota yet"), then the one line
    /// that matters most after it: a wait for the other phone (this phone alerts as if on duty
    /// until then), else an ask, else "Both phones alert" with no rota. The short form of what
    /// `TonightLines` says in full.
    static func lines(facts: HomeFacts, me: MemberID, onTonight: MemberID?) -> [String] {
        let noRota = facts.data.householdState.rota == nil && facts.nights.allSatisfy { $0.onDuty == nil }
        let who: String
        var then: String?
        if let onTonight {
            who = onTonight == me ? "You're on" : "\(facts.name(onTonight).capitalizedFirst)'s on"
        } else if noRota {
            who = "No rota yet"
            then = "Both phones alert"
        } else {
            who = "Both phones alert"
        }
        let other = facts.otherMember.map { facts.name($0).capitalizedFirst } ?? "the other parent"
        switch facts.askStatus {
        case .waiting: then = "You asked \(other)"
        case .declined(_, let by): then = "\(facts.name(by).capitalizedFirst) said not tonight"
        default: break
        }
        if !facts.data.unacknowledgedChanges(by: me).isEmpty {
            then = "Waiting for \(facts.otherName.map { "\($0)'s phone" } ?? "the other phone")"
        }
        return [who] + [then].compactMap { $0 }
    }
}

/// Tonight's window, from its card on the open Duo: who is on with "I'll take it" and the rest, any
/// ask line, and the week of nights. A tap that has an Undo closes it, so the Undo card shows.
struct TonightSheet: View {
    let me: MemberID
    let babyID: String
    let onUndo: (UndoAction) -> Void
    private let model = AppModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let facts = HomeFacts(data: model.store.data, babyID: babyID, baby: model.babyDetails, me: me,
                                  names: model.memberNames, colours: model.memberColours, now: context.date)
            let noRota = facts.data.householdState.rota == nil && facts.nights.allSatisfy { $0.onDuty == nil }
            VStack(alignment: .leading, spacing: 14) {
                Text("Tonight").feedText(.dayHeading).accessibilityAddTraits(.isHeader)
                TonightLines(facts: facts, me: me, onUndo: { onUndo($0); dismiss() }, noRota: noRota)
                    .environment(\.chipBackground, Theme.surface)
                if !noRota {
                    NightsRow(nights: facts.nights, tonight: facts.tonight, facts: facts)
                }
                BigButton(title: "Done", prominent: true) { dismiss() }
                    .padding(.top, 4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(Theme.text)
        .presentationDetents([.height(310)])
        .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        .presentationBackground(Theme.background)
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
