import FeedingCore
import FeedingInsights
import SwiftUI

/// Get help now (`docs/planning/12-ai-insights-gauntlet.md`, R4, task AI5): the NHS's urgent list
/// word for word, with its credit and link, and Call 999 and Call 111 pinned at the bottom, in
/// thumb's reach. Built into the app, so it works with no signal, and no AI. Opened from Settings
/// now; Ask opens the same card on a danger sign (step 3). The urgent list shows whether or not it
/// has been checked: the call buttons matter most.
struct GetHelpNowView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Get help now")
                    .feedText(.title)
                    .accessibilityAddTraits(.isHeader)
                NHSPassageTile(passage: NHSPassages.urgent)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) { callButtons }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Get help now")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        // Like a form, it stays in front when a parent comes back at night after a call (D40).
        .modifier(FormOnScreen())
    }

    /// Side by side, or one above the other when the text is too big for both on one row.
    private var callButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { call999; call111 }
            VStack(spacing: 10) { call999; call111 }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.background)
    }

    private var call999: some View {
        // The number in SF Pro Rounded: never a number in Fredoka (DESIGN.md).
        BigButton(title: "Call", prominent: true, amount: "999") { call("999") }
            .accessibilityLabel("Call 9 9 9")
    }

    private var call111: some View {
        BigButton(title: "Call", prominent: false, amount: "111") { call("111") }
            .accessibilityLabel("Call NHS 1 1 1")
    }

    /// A phone that can't call (an iPad, the simulator) does nothing; the number is on the button.
    private func call(_ number: String) {
        guard let url = URL(string: "tel:\(number)") else { return }
        openURL(url)
    }
}

/// An NHS passage on its own tile, apart from the app's own words (the NHS's terms, 3.6(a)): the
/// page's title, the words exactly as on the page, then "Information from the NHS website, as at
/// 22/11/26" and a link to the page.
struct NHSPassageTile: View {
    let passage: Passage

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 12) {
                // Left out when the passage's own heading is the page's title, so it isn't said twice.
                if PassageBlock.title(of: passage) != passage.page {
                    Text(passage.page)
                        .feedText(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                }
                PassageWords(words: passage.words)
                VStack(alignment: .leading, spacing: 6) {
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
                .padding(.top, 4)
            }
        }
    }
}

/// A passage's words: "## " and "### " lines are headings, "- " lines are list items, the rest are
/// paragraphs. Headings are in SF Pro Rounded, not Fredoka, as they hold numbers ("Call 999").
struct PassageWords: View {
    let words: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(PassageBlock.blocks(words).enumerated()), id: \.offset) { index, block in
                switch block {
                case .heading(let text):
                    Text(text)
                        .feedText(.body)
                        .fontWeight(.bold)
                        .padding(.top, index == 0 ? 0 : 8)
                        .accessibilityAddTraits(.isHeader)
                case .subheading(let text):
                    Text(text)
                        .feedText(.body)
                        .fontWeight(.semibold)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                case .item(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").accessibilityHidden(true)
                        Text(text)
                    }
                    .feedText(.body)
                    .accessibilityElement(children: .combine)
                case .paragraph(let text):
                    Text(text).feedText(.body)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum PassageBlock: Hashable {
    case heading(String)
    case subheading(String)
    case item(String)
    case paragraph(String)

    static func blocks(_ words: String) -> [PassageBlock] {
        words.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            if line.hasPrefix("### ") { return .subheading(String(line.dropFirst(4))) }
            if line.hasPrefix("## ") { return .heading(String(line.dropFirst(3))) }
            if line.hasPrefix("- ") { return .item(String(line.dropFirst(2))) }
            return .paragraph(String(line))
        }
    }

    /// The passage's first heading, as its name in lists.
    static func title(of passage: Passage) -> String {
        for block in blocks(passage.words) {
            if case .heading(let text) = block { return text }
        }
        return passage.page
    }
}
