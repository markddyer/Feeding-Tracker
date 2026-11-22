import FeedingCore
import FeedingInsights
import SwiftUI

/// Settings › NHS information (task AI5; D9, D10): every NHS passage the app may show, each with
/// its summaries, and where Parent A records checking each one against its NHS page. A passage or
/// summary is offered on a card only once checked, and again within 90 days; the ticks are shared
/// household settings (`HouseholdData.passageChecks`), so a check needs no new build.
struct PassagesListView: View {
    private let model = AppModel.shared

    var body: some View {
        let data = model.store.data
        let today = PlainDate(Date(), in: data.householdSettings.timeZone)
        let waiting = Set(NHSPassages.needsChecking(data.passageChecks, today: today))
        List {
            Section {
                ForEach(NHSPassages.all) { passage in
                    let ids = [passage.id] + passage.summaries.map(\.id)
                    let left = ids.filter(waiting.contains).count
                    NavigationLink {
                        PassageCheckView(passage: passage)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                let title = PassageBlock.title(of: passage)
                                Text(title)
                                if passage.page != title {
                                    Text(passage.page)
                                        .feedText(.subheadline)
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                            Spacer(minLength: 8)
                            CheckState(checked: left == 0)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(waiting.isEmpty ? "All checked" : "\(waiting.count) to check")
                    .feedText(.label)
                    .foregroundStyle(Theme.textMuted)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Each passage is word for word from the NHS website. Little Log shows a passage, or its short summary, only once one of you has checked it against its NHS page, and again every \(NHSPassages.checkEveryDays) days. Ticks are shared by both phones.")
                    LicenceLink()
                }
                .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("NHS information")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NHS information").feedText(.dayHeading).accessibilityAddTraits(.isHeader)
            }
        }
    }
}

/// One passage: its words as on the NHS page, then a tick for the passage and one for each summary.
struct PassageCheckView: View {
    let passage: Passage
    private let model = AppModel.shared

    var body: some View {
        let data = model.store.data
        let today = PlainDate(Date(), in: data.householdSettings.timeZone)
        let checks = data.passageChecks
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NHSPassageTile(passage: passage)
                Tile {
                    checkRow(id: passage.id, label: "Checked against the NHS page", checks: checks, today: today)
                }
                ForEach(passage.summaries) { summary in
                    Tile(label: "Summary · written by AI") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(summary.words).feedText(.body)
                            checkRow(id: summary.id, label: "Summary checked against the passage", checks: checks,
                                     today: today)
                        }
                    }
                }
                Text("Open the NHS page and read it beside this copy. Tick the passage when the words are the same. Tick a summary when it says only what the passage says.")
                    .feedText(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        // The passage's own heading is on the tile, and may hold a number, so the bar says only this.
        .navigationTitle("NHS passage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NHS passage").feedText(.dayHeading).accessibilityAddTraits(.isHeader)
            }
        }
    }

    /// The tick, and under it when it was last checked.
    private func checkRow(id: String, label: String, checks: PassageChecks, today: PlainDate) -> some View {
        let checked = NHSPassages.isChecked(id, copied: passage.copied, checks: checks, today: today)
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(label, isOn: Binding {
                checked
            } set: { on in
                model.store.change { $0.setPassageCheck(id, checkedOn: on ? today : nil, now: Date()) }
            })
            .tint(Theme.primary)
            Text(Self.state(checks[id], checked: checked))
                .feedText(.subheadline)
                .foregroundStyle(Theme.textMuted)
        }
    }

    /// "Checked 23 Nov 2026", "Last checked 23 Aug 2026 · check again", or "Not checked yet".
    static func state(_ day: PlainDate?, checked: Bool) -> String {
        guard let day else { return "Not checked yet" }
        return checked ? "Checked \(PassageDate.text(day))" : "Last checked \(PassageDate.text(day)) · check again"
    }
}

/// A tick or an empty circle, with its word, in muted text (no green: green means pumping).
private struct CheckState: View {
    let checked: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .accessibilityHidden(true)
            Text(checked ? "Checked" : "To check")
        }
        .feedText(.subheadline)
        .foregroundStyle(Theme.textMuted)
    }
}

/// "Information from the NHS website is licensed under the Open Government Licence v3.0", with its
/// link: said once, where it is easy to find (the NHS's terms, 3.6(a)).
struct LicenceLink: View {
    var body: some View {
        Link(destination: URL(string: NHSPassages.licenceURL)!) {
            Text(NHSPassages.licenceStatement)
                .underline()
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(Theme.textMuted)
    }
}

enum PassageDate {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "23 Nov 2026".
    static func text(_ day: PlainDate) -> String {
        "\(day.day) \(months[day.month - 1]) \(day.year)"
    }
}
