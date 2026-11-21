import FeedingCore
import SwiftUI

/// The Firsts list (X2, D9; design review D42): every first with its date and the baby's age on
/// it, oldest first, ready for the red book or a check. Facts only: never a typical age. A row
/// opens the first's page; "Copy as text" copies the whole list. With no birth date: dates only,
/// and "Add the birth date".
struct FirstsListView: View {
    let me: MemberID
    let babyID: String

    private let model = AppModel.shared
    @State private var settingBirthDate = false
    @State private var copied = false

    var body: some View {
        let data = model.store.data
        let rows = data.firstsList(babyID: babyID)
        let today = PlainDate(Date(), in: data.householdSettings.timeZone)
        List {
            Text("Firsts list")
                .feedText(.title)
                .accessibilityAddTraits(.isHeader)
                .plainRow()
            if rows.isEmpty {
                Text("No firsts yet. Each first you add shows here, with the baby's age.")
                    .feedText(.body)
                    .foregroundStyle(Theme.textMuted)
                    .plainRow()
            } else {
                Text("Oldest first")
                    .feedText(.label)
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityAddTraits(.isHeader)
                    .plainRow()
                ForEach(rows) { row in
                    NavigationLink(value: JournalView.Route(id: row.id)) {
                        Text(row.line(today: today))
                            .feedText(.body)
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    // A real link, so VoiceOver and Switch Control open it; with no ">".
                    .navigationLinkIndicatorVisibility(.hidden)
                    .plainRow()
                }
            }
            if data.birthDate(babyID: babyID) == nil {
                Button("Add the birth date") { settingBirthDate = true }
                    .feedText(.smallButton)
                    .foregroundStyle(Theme.text)
                    .frame(minHeight: 44)
                    .plainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Firsts list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = rows.copiedText
                    copied = true
                } label: {
                    Text(copied ? "Copied" : "Copy as text")
                }
                .disabled(rows.isEmpty)
                .tint(Theme.text)
            }
        }
        .sheet(isPresented: $settingBirthDate) { BirthDateEditor(babyID: babyID) }
        .undoCenterCard()
    }
}

extension View {
    /// A row with no separator or background, and the page's 16-point gutter.
    func plainRow() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
