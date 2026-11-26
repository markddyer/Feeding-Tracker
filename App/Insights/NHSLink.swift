import FeedingCore
import FeedingInsights
import SwiftUI

// The "About … ›" NHS link on a form (AI insights step 4: D5 A, D6 A, F12, Y7, Y8; design D3 B, D11 A,
// D13 A, D17 A, D18 A, D19 A, D20 A; DESIGN.md, "NHS link on a form"). The NHS's own words, which
// Parent A ticked within 90 days, chosen by the form's kind only, never by a value logged. No AI:
// it shows whether AI insights is on or off, and sends nothing anywhere.

/// What a link is about: one table, keyed by the form (and its kind's topics in `NHSPassages`).
enum NHSLinkSubject {
    /// `bottles`: "Bottles through the day" (`14-bottles-through-the-day.md`): the bottle-feeding
    /// passages only, whatever else the baby has.
    case poo, nappy, sleep, growth, bath, feed, pump, bottles

    var kind: InsightKind {
        switch self {
        case .poo, .nappy: .nappy
        case .sleep: .sleep
        case .growth: .weight
        case .bath: .bath
        case .feed, .bottles: .feed
        case .pump: .pump
        }
    }

    /// The link's words: "About nappies" in a nappy's editor (a wee-only nappy too, design D18 A).
    var title: String {
        switch self {
        case .poo: "About baby poo"
        case .nappy: "About nappies"
        case .sleep: "About baby sleep"
        case .growth: "About weight"
        case .bath: "About bathing"
        case .feed: "About feeding"
        case .pump: "About expressing"
        case .bottles: "About bottle feeding"
        }
    }

    /// The editor's link for an entry's kind; none for medicines, firsts and the rest (D6 A).
    init?(_ kind: EventKind) {
        switch kind {
        case .nappy: self = .nappy
        case .sleep: self = .sleep
        case .growth: self = .growth
        case .bath: self = .bath
        case .feed: self = .feed
        case .pump: self = .pump
        default: return nil
        }
    }
}

@MainActor
enum NHSLinks {
    /// The passages a link opens now: `NHSPassages.forLink`, for the baby's age and the ways the
    /// baby feeds (A8), ticked within 90 days.
    static func passages(_ subject: NHSLinkSubject, model: AppModel = .shared, now: Date = Date()) -> [Passage] {
        let data = model.store.data
        guard let babyID = model.baby?.name else { return [] }
        let facts = data.insightFacts(babyID: babyID, now: now)
        let today = facts.today ?? PlainDate(now, in: data.householdSettings.timeZone)
        let passages = NHSPassages.forLink(subject.kind, ageInDays: facts.ageInDays,
                                           breastfeeds: subject != .bottles && facts.days.contains { $0.breastFeeds > 0 },
                                           bottleFeeds: subject == .bottles || facts.days.contains { $0.bottleFeeds > 0 },
                                           checks: data.passageChecks, today: today)
        return subject == .bottles ? bottleFeedingOnly(passages) : passages
    }

    /// "About bottle feeding" opens the bottle-feeding passages alone, never the feed topic's
    /// general ones, such as reflux (Codex review of `14-bottles-through-the-day.md`, 4).
    static func bottleFeedingOnly(_ passages: [Passage]) -> [Passage] {
        passages.filter { $0.feeding == .bottleFeeding }
    }

    /// "Checked against the NHS page by Sam, 23 Nov.", true on both phones; with no name for a tick
    /// made before 25 Nov 2026.
    static func checkedLine(_ passages: [Passage], model: AppModel = .shared) -> String {
        let data = model.store.data
        let ids = passages.flatMap { [$0.id] + $0.summaries.map(\.id) }
        guard let checked = data.passageChecker(of: passages.map(\.id) + ids) else { return "Information from the NHS website." }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let day = "\(checked.day.day) \(months[checked.day.month - 1])"
        if let by = checked.by, let name = model.memberNames[by] {
            return "Information from the NHS website. Checked against the NHS page by \(name), \(day)."
        }
        return "Information from the NHS website. Checked against the NHS page on \(day)."
    }
}

/// The link: one row in the NHS blue box, "NHS" muted, the words, a muted ›. Hidden when no passage
/// is ticked for it, but never while its sheet is open. `onOpenChange` lets a panel that closes by
/// itself stay open while the sheet shows (Y8).
struct NHSLinkRow: View {
    let subject: NHSLinkSubject
    /// In a system form (an editor): the form draws the row's box.
    var inForm = false
    var onOpenChange: (Bool) -> Void = { _ in }
    @State private var open = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // The row stays while its sheet is open, so the sheet isn't torn away when a tick passes
        // its 90 days; the sheet then says so (Codex step 4 review, 15).
        if open || !NHSLinks.passages(subject).isEmpty {
            Button {
                open = true
            } label: {
                label
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, inForm ? 0 : 12)
                    .padding(.vertical, inForm ? 0 : 6)
                    .background {
                        if !inForm { NHSLinkBox(cornerRadius: 12) }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("NHS information: \(subject.title)")
            .accessibilityHint("Opens the NHS's pages.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("nhsLink")
            .sheet(isPresented: $open) { NHSLinkSheet(subject: subject) }
            .onChange(of: open) { onOpenChange(open) }
        }
    }

    @ViewBuilder
    private var label: some View {
        let nhs = Text("NHS").feedText(.label).foregroundStyle(Theme.textMuted)
        let words = Text(subject.title).feedText(.smallButton).foregroundStyle(Theme.text)
        let chevron = Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textMuted)
        if typeSize.isAccessibilitySize {
            HStack {
                VStack(alignment: .leading, spacing: 2) { nhs; words }
                Spacer(minLength: 8)
                chevron
            }
        } else {
            HStack(spacing: 10) { nhs; words; Spacer(minLength: 8); chevron }
        }
    }
}

/// The NHS blue box: `bottle-tint` with a 4 pt `bottle-mark` edge at the left.
struct NHSLinkBox: View {
    var cornerRadius: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.bottleTint
            Theme.bottleMark.frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// What a link opens: the subject's passages by their own headings, one at a time (so a pair a card
/// never shows together is never side by side, Y7); one passage opens at once; an emptied list
/// says so, with Back to the form (design D11 A). Looked at again each minute, so a tick that
/// passes its 90 days while the sheet is open takes its passage away (Codex step 4 review, 15).
struct NHSLinkSheet: View {
    let subject: NHSLinkSubject

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let passages = NHSLinks.passages(subject, now: context.date)
                Group {
                    if passages.count == 1, let only = passages.first {
                        NHSPassagePage(subject: subject, id: only.id)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if passages.isEmpty {
                                    NoCheckedPages()
                                } else {
                                    list(passages)
                                    Text(NHSLinks.checkedLine(passages))
                                        .feedText(.subheadline)
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .navigationTitle(subject.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseSheetButton()
                }
            }
            .background(Theme.background.ignoresSafeArea())
        }
        .tint(Theme.text)
        .presentationBackground(Theme.background)
    }

    private func list(_ passages: [Passage]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(passages.enumerated()), id: \.element.id) { index, passage in
                if index > 0 { Rectangle().fill(Theme.background).frame(height: 1.5) }
                NavigationLink {
                    NHSPassagePage(subject: subject, id: passage.id)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(passage.title).feedText(.body).fontWeight(.semibold)
                            if passage.page != passage.title {
                                Text(passage.page).feedText(.subheadline).foregroundStyle(Theme.textMuted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textMuted)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nhsPassageRow")
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile))
    }
}

/// One passage, word for word, in the NHS blue box (`NHSCardBox`, with no summary). Found by its ID
/// among the passages the link may open now, each minute: gone past its 90 days, it says so.
private struct NHSPassagePage: View {
    let subject: NHSLinkSubject
    let id: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let passage = NHSLinks.passages(subject, now: context.date).first(where: { $0.id == id }) {
                        NHSCardBox(passage: passage, summary: nil)
                        Text(NHSLinks.checkedLine([passage])).feedText(.subheadline).foregroundStyle(Theme.textMuted)
                    } else {
                        NoCheckedPages()
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .accessibilityIdentifier("nhsPassagePage")
    }
}

/// The emptied list (design D11 A), with Back to the form.
private struct NoCheckedPages: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Text("No checked NHS pages on this right now.")
            .feedText(.body)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile))
        BigButton(title: "Back to your form", prominent: false) { dismiss() }
    }
}

/// The sheet's round ✕.
private struct CloseSheetButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Close")
    }
}
