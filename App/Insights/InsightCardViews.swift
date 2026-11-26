import FeedingCore
import FeedingInsights
import SwiftUI

// The AI cards (step 2 of `docs/planning/12-ai-insights-gauntlet.md`, task AI11; the look picked
// from `designs/ai-insights-20261122/round2.html`, A, one merged line): Home's "Last night" line
// gains the AI mark and opens one card, the AI's part first, then the night's entries; from the
// afternoon a slim "Yesterday and last night" line; Graphs' "This week" line. Every sentence is the
// app's (`CardWording`); the AI only chose them. With no yes, or the AI off, nothing here shows.

/// What a screen shows for one kind of card now: `InsightCards.onScreen` and the engine's state.
enum CardShown: Equatable {
    /// The AI isn't on, or there is no card for now: screens are as they were.
    case nothing
    case making
    case card(CheckedCard, period: CardPeriod)
    /// No AI card for now (S12): the app's own facts, when there are any, and why.
    case factsOnly(PlainCard?, period: CardPeriod, why: String)

    /// `now` is a screen's clock tick, which can be up to 20 seconds old (Home's). A change made
    /// since (a second "This was wrong") must show at once: a report after `now` doesn't count
    /// (`InsightCards.wrongCount`), so this never looks earlier than the real time.
    @MainActor
    static func now(_ kind: CardKind, at tick: Date, model: AppModel = .shared,
                    engine: InsightEngine = .shared) -> CardShown {
        let now = max(tick, Date())
        guard let babyID = model.baby?.name else { return .nothing }
        switch InsightCards.onScreen(kind, data: model.store.data, babyID: babyID, me: model.me, now: now) {
        case .nothing:
            return .nothing
        case .card(let card, let period):
            return .card(card, period: period)
        case .paused(let period, let plain):
            return .factsOnly(plain, period: period, why: CardText.pausedWhy)
        case .noCard(let period, let plain):
            if engine.making.contains(kind) { return .making }
            // Not looked at yet for this period: the look starts as the screen opens.
            guard let outcome = engine.outcomes[kind], outcome.period == period else { return .making }
            switch outcome.reason {
            case .closed(.waitingForYes), .closed(.turnedOff):
                return .nothing
            case .failed:
                return .factsOnly(plain, period: period, why: CardText.failedWhy(engine.lastFailureAt, model: model))
            case .closed:
                return .factsOnly(plain, period: period, why: CardText.noCardWhy)
            }
        }
    }

    /// An AI card, or one being made: the slim AI lines show only for these.
    var isAI: Bool {
        switch self {
        case .card, .making: true
        case .nothing, .factsOnly: false
        }
    }
}

enum CardText {
    static let foot = "Picked by AI from your log. Every sentence and number is written by Little Log."
    static let pausedWhy = "AI insights are paused after 2 cards were reported wrong. Settings › AI insights can turn them back on."
    static let noCardWhy = "No AI card for now. Settings › AI insights says why."

    @MainActor
    static func failedWhy(_ since: Date?, model: AppModel) -> String {
        let zone = model.store.data.householdSettings.timeZone
        let when = since.map { " since \(InsightSettingsView.since($0, zone: zone))" } ?? ""
        return "Couldn’t reach the AI\(when). Settings › AI insights says why."
    }

    static func title(_ kind: CardKind) -> String {
        kind == .morning ? "Last night and yesterday" : "This week"
    }

    static func making(_ kind: CardKind) -> String {
        kind == .morning ? "Making this morning’s card…" : "Making this week’s card…"
    }

    private static let shortDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    private static let shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                                 "October", "November", "December"]

    /// "Mon 17 to Sun 23 Nov", or "Mon 30 Nov to Sun 6 Dec" across two months.
    static func weekShort(_ span: DateSpan) -> String {
        let (first, last) = (span.first, span.last)
        let start = "\(shortDays[first.weekday - 1]) \(first.day)" + (first.month == last.month ? "" : " \(shortMonths[first.month - 1])")
        return "\(start) to \(shortDays[last.weekday - 1]) \(last.day) \(shortMonths[last.month - 1])"
    }

    /// "Monday 17 to Sunday 23 November".
    static func weekLong(_ span: DateSpan) -> String {
        let (first, last) = (span.first, span.last)
        let start = "\(days[first.weekday - 1]) \(first.day)" + (first.month == last.month ? "" : " \(months[first.month - 1])")
        return "\(start) to \(days[last.weekday - 1]) \(last.day) \(months[last.month - 1])"
    }
}

/// The small "AI" mark on everything the AI picked (the AUP's disclosure, D5).
struct AIMark: View {
    /// 11 pt at the standard text size; it grows with the parent's text size (AI12's audit).
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 11

    var body: some View {
        Text("AI")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
            .accessibilityLabel("Picked by AI")
    }
}

/// A slim line on `surface` that opens a card: Home's "Yesterday and last night" from the
/// afternoon, and Graphs' "This week".
struct AICardLine: View {
    let title: String
    let shown: CardShown
    let open: () -> Void
    @ScaledMetric(relativeTo: .footnote) private var star: CGFloat = 12

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Text("✦")
                    .font(.system(size: star, weight: .heavy))
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
                if shown == .making {
                    Text("\(title) · Making…")
                        .feedText(.smallButton)
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ProgressView().controlSize(.small)
                } else {
                    Text(title)
                        .feedText(.smallButton)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AIMark()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile))
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown == .making ? "\(title), being made by AI" : "\(title), picked by AI")
        .accessibilityHint("Opens the card")
        // One element in place of the button: it must still say it is a button.
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("aiCardLine")
    }
}

/// Home's morning card opened by itself (from the afternoon's line), with the night's entries
/// when there are any to show.
struct MorningCardRequest: Identifiable {
    let id = UUID()
    var night: LastNight?
}

/// One card in a sheet: the AI's card (or "Making…", or the facts only), then the night's entries
/// when opened from "Last night", then "Worried? Get help now".
struct InsightCardSheet: View {
    let kind: CardKind
    var night: LastNight?
    /// Graphs' "This week": a tap on a line opens its graph's page.
    var openGraph: ((GraphKind, PlainDate?) -> Void)?
    @Environment(\.dismiss) private var dismiss
    private let model = AppModel.shared

    /// Feeding Dev only: `-cardAtBottom YES` opens the card at its end, for screenshots.
    private static var atBottom: Bool {
        #if FEEDING_DEV
        UserDefaults.standard.bool(forKey: "cardAtBottom")
        #else
        false
        #endif
    }

    var body: some View {
        let zone = model.store.data.householdSettings.timeZone
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let shown = CardShown.now(kind, at: context.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(CardText.title(kind))
                                .feedText(.title)
                                .accessibilityAddTraits(.isHeader)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .frame(width: 44, height: 44)
                                    .background(Theme.surface, in: Circle())
                            }
                            .accessibilityLabel("Close")
                        }
                        content(shown, zone: zone)
                        if let night, !night.items.isEmpty {
                            NightEntriesTile(night: night, zone: zone)
                        }
                        // The NHS's words under the night, each shut until tapped (Parent A, 26 Nov
                        // 2026: the report on the night first, the NHS further down).
                        ForEach(Self.passages(shown), id: \.passage.id) { item in
                            NHSCardBox(passage: item.passage, summary: item.summary, folds: true)
                        }
                        NavigationLink {
                            GetHelpNowView()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "phone.fill")
                                    .foregroundStyle(Theme.backup)
                                    .accessibilityHidden(true)
                                Text("Worried? Get help now")
                                    .feedText(.smallButton)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.textMuted)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("cardGetHelp")
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(Self.atBottom ? .bottom : nil)
            }
            .foregroundStyle(Theme.text)
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.text)
        // Full height at once (Parent A, 23 Nov 2026): a half-height card needed a drag to read.
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
    }

    @ViewBuilder
    private func content(_ shown: CardShown, zone: TimeZone) -> some View {
        switch shown {
        case .nothing:
            EmptyView()
        case .making:
            Tile {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(CardText.making(kind)).feedText(.body)
                }
                .accessibilityElement(children: .combine)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .card(let card, let period):
            if kind == .week {
                Text(CardText.weekLong(period.days))
                    .feedText(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
            AICardTile(kind: kind, card: card, medicines: kind == .morning ? MedicineChips.given(in: period) : [],
                       zone: zone, openGraph: openGraph.map { open in { graph, day in dismiss(); open(graph, day) } })
        case .factsOnly(let plain, let period, let why):
            PlainCardTile(plain: plain, medicines: MedicineChips.given(in: period), why: why)
        }
    }

    private struct ShownPassage {
        let passage: Passage
        let summary: PassageSummary?
    }

    /// The card's NHS passages: with the AI's checked summary on an AI card, without on "Facts only
    /// today".
    private static func passages(_ shown: CardShown) -> [ShownPassage] {
        switch shown {
        case .nothing, .making: []
        case .card(let card, _): card.passages.map { ShownPassage(passage: $0.passage, summary: $0.summary) }
        case .factsOnly(let plain, _, _): (plain?.passages ?? []).map { ShownPassage(passage: $0, summary: nil) }
        }
    }
}

/// The AI's card: the app's sentences from the AI's choices, the medicine chips, the foot, and
/// "This was wrong" (A7). Its NHS passages sit under the night's entries (`InsightCardSheet`).
struct AICardTile: View {
    let kind: CardKind
    let card: CheckedCard
    let medicines: [MedicineChips.Chip]
    let zone: TimeZone
    var openGraph: ((GraphKind, PlainDate?) -> Void)?

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 9) {
                if kind == .morning {
                    section("Last night", nights: true)
                    section("Yesterday", nights: false)
                } else {
                    label("From your log")
                    ForEach(Array(zip(card.lines, card.factRefs).enumerated()), id: \.offset) { _, item in
                        line(item.0, graph: item.1.measure.graph, day: item.1.scope.date)
                    }
                    ForEach(Array(zip(card.patterns, card.patternChoices).enumerated()), id: \.offset) { _, item in
                        pattern(item.0, graph: item.1.measure.graph, day: item.1.recent.last)
                    }
                }
                MedicineChips(chips: medicines)
                Text(CardText.foot)
                    .feedText(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                WrongReportButton()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // A container, so its buttons keep their own names.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("aiCard")
    }

    /// "Last night" or "Yesterday", with the AI mark, then its facts and patterns.
    @ViewBuilder
    private func section(_ title: String, nights: Bool) -> some View {
        let lines = zip(card.lines, card.factRefs).filter { $0.1.scope.isNight == nights }.map(\.0)
        let patterns = zip(card.patterns, card.patternChoices).filter { $0.1.nights == nights }.map(\.0)
        if !lines.isEmpty || !patterns.isEmpty {
            label(title)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, text in
                Text(text).feedText(.body).monospacedDigit()
            }
            ForEach(Array(patterns.enumerated()), id: \.offset) { _, text in
                pattern(text, graph: nil, day: nil)
            }
        }
    }

    private func label(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .feedText(.label)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            AIMark()
        }
        .padding(.top, 2)
    }

    /// A fact's line; on "This week", a button to its graph's page when there is one.
    @ViewBuilder
    private func line(_ text: String, graph: GraphKind?, day: PlainDate?) -> some View {
        if let graph, let openGraph {
            Button { openGraph(graph, day) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(text).feedText(.body).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    chevron
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the graph")
            .accessibilityIdentifier("cardGraphLine")
        } else {
            Text(text).feedText(.body).monospacedDigit()
        }
    }

    /// A pattern, set apart on `background` with a small "Pattern" label.
    @ViewBuilder
    private func pattern(_ text: String, graph: GraphKind?, day: PlainDate?) -> some View {
        let box = HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pattern").feedText(.label).foregroundStyle(Theme.textMuted)
                Text(text).feedText(.body).monospacedDigit().multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if graph != nil && openGraph != nil { chevron }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        if let graph, let openGraph {
            Button { openGraph(graph, day) } label: { box.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the graph")
                .accessibilityIdentifier("cardGraphLine")
        } else {
            box
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.textMuted)
            .accessibilityHidden(true)
    }
}

/// "Facts only today" (S12): the app's fixed facts, the medicines, and why there is no AI card. No
/// AI mark: nothing on it is the AI's. Its NHS passages, without a summary, sit under the night's
/// entries (`InsightCardSheet`).
struct PlainCardTile: View {
    let plain: PlainCard?
    let medicines: [MedicineChips.Chip]
    let why: String

    var body: some View {
        Tile(label: "Facts only today") {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array((plain?.lines ?? []).enumerated()), id: \.offset) { _, text in
                    Text(text).feedText(.body).monospacedDigit()
                }
                MedicineChips(chips: medicines)
                Text(why)
                    .feedText(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // A container, so its buttons keep their own names.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("factsOnlyCard")
    }
}

/// The medicines given in a card's days and nights, as chips made by the app (R3): the name and
/// the time, as History shows them, never an amount or a next time. The AI never sees them.
struct MedicineChips: View {
    struct Chip: Hashable, Identifiable {
        let id: String
        let text: String
    }

    let chips: [Chip]

    var body: some View {
        if !chips.isEmpty {
            WrapLayout(spacing: 6) {
                ForEach(chips) { chip in
                    HStack(spacing: 5) {
                        FeedMarkView(.medicine, size: 13, relativeTo: .footnote)
                        Text(chip.text).feedText(.smallButton).monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// "Vitamin D · 09:10", for each medicine logged in `period`'s time, in time order.
    @MainActor
    static func given(in period: CardPeriod, model: AppModel = .shared) -> [Chip] {
        let data = model.store.data
        guard let babyID = model.baby?.name else { return [] }
        let settings = data.householdSettings
        let window = InsightCards.window(period, dayHours: settings.dayHours, timeZone: settings.timeZone)
        return data.visibleSnapshots(babyID: babyID)
            .filter { $0.event.kind == .medicine && $0.event.babyID == babyID && window.contains($0.event.startedAt) }
            .sorted { ($0.event.startedAt, $0.event.id) < ($1.event.startedAt, $1.event.id) }
            .map { snapshot in
                let time = snapshot.event.startedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
                                                                               timeZone: settings.timeZone))
                return Chip(id: snapshot.event.id, text: "\(snapshot.payload?.medicine?.name ?? "Medicine") · \(time)")
            }
    }
}

/// An NHS passage on a card: the page's name, the AI-chosen summary marked as AI (checked ahead of
/// time by a parent), then the NHS's own words in full, the credit and the page's link (D9, R7).
/// With `folds`, as on the AI card, it starts shut: one row, "NHS", the page's name and a chevron,
/// that opens it in place (Parent A, 26 Nov 2026). Ask and the forms' links show it open.
struct NHSCardBox: View {
    let passage: Passage
    let summary: PassageSummary?
    var folds = false
    @State private var open = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if folds {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { open.toggle() }
                } label: {
                    foldRow
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("NHS information: \(passage.page)")
                .accessibilityValue(open ? "Open" : "Closed")
                .accessibilityHint(open ? "Hides the NHS's words." : "Shows the NHS's words.")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("cardNHS")
            } else {
                Text("NHS · \(passage.page)")
                    .feedText(.label)
                    .foregroundStyle(Theme.textMuted)
            }
            if !folds || open {
                words
                    .transition(.opacity)
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 11)
        .padding(.vertical, folds ? 2 : 9)
        .padding(.bottom, folds && open ? 7 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bottleTint, in: RoundedRectangle(cornerRadius: 12))
        // The NHS's blue edge on the left (the parents' pick, round 2).
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(Theme.bottleMark)
                .frame(width: 4)
                .accessibilityHidden(true)
        }
    }

    /// The shut row, as the forms' NHS link: "NHS" muted, the page's name, a muted chevron.
    @ViewBuilder
    private var foldRow: some View {
        let nhs = Text("NHS").feedText(.label).foregroundStyle(Theme.textMuted)
        let page = Text(passage.page).feedText(.smallButton).foregroundStyle(Theme.text)
            .multilineTextAlignment(.leading)
        let chevron = Image(systemName: "chevron.down")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.textMuted)
            .rotationEffect(.degrees(open ? 180 : 0))
        if typeSize.isAccessibilitySize {
            HStack {
                VStack(alignment: .leading, spacing: 2) { nhs; page }
                Spacer(minLength: 8)
                chevron
            }
        } else {
            HStack(spacing: 10) { nhs; page; Spacer(minLength: 8); chevron }
        }
    }

    @ViewBuilder
    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Summary · AI")
                        .feedText(.label)
                        .foregroundStyle(Theme.textMuted)
                    Text(summary.words).feedText(.subheadline)
                }
                .accessibilityElement(children: .combine)
            }
            PassageWords(words: passage.words)
            Text(passage.attribution)
                .feedText(.subheadline)
                .foregroundStyle(Theme.textMuted)
            if let url = URL(string: passage.url) {
                Link(destination: url) {
                    Text("Open the NHS page ›")
                        .feedText(.subheadline)
                        .underline()
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .tint(Theme.text)
                .accessibilityLabel("Open the NHS page")
                .accessibilityHint(passage.page)
            }
        }
    }
}

/// "This was wrong" (A7): one report for the household, with no outside service. Two in 30 days
/// pause AI insights on both phones.
struct WrongReportButton: View {
    @State private var asking = false
    @State private var reported = false

    var body: some View {
        Button { asking = true } label: {
            Text(reported ? "Reported as wrong" : "This was wrong")
                .feedText(.smallButton)
                .underline(!reported)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textMuted)
        .disabled(reported)
        .accessibilityIdentifier("cardWrong")
        .confirmationDialog("Report this card as wrong?", isPresented: $asking, titleVisibility: .visible) {
            Button("Report") {
                AppModel.shared.store.change { $0.reportWrongCard(now: Date()) }
                reported = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Two reports in 30 days pause AI insights on both phones, until one of you turns them back on.")
        }
    }
}

/// The night's entries, under the card when it was opened from "Last night" (the merged line).
struct NightEntriesTile: View {
    let night: LastNight
    let zone: TimeZone

    var body: some View {
        let sides = ShareSides.current()
        VStack(alignment: .leading, spacing: 4) {
            Text(ShareText.nightTitle(night.night, slept: night.sleptSeconds, in: zone))
                .feedText(.label)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(night.items) { item in
                    NightLine(item: item, sides: sides, zone: zone)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Theme.sleepTint, in: RoundedRectangle(cornerRadius: Radius.tile))
    }
}
