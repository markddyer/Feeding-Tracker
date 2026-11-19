import FeedingCore
import SwiftUI

/// Setting or correcting the baby's birth date (design review D14, D41): from the Journal's soft
/// row, its "…" menu, and Settings. Saved for both phones. A date after a first is refused, and the
/// refusal names the first in the way.
struct BirthDateEditor: View {
    let babyID: String

    private let model = AppModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date

    init(babyID: String) {
        self.babyID = babyID
        let data = AppModel.shared.store.data
        let zone = data.householdSettings.timeZone
        let start = data.birthDate(babyID: babyID).flatMap { Self.date($0, in: zone) } ?? Date()
        _day = State(initialValue: start)
    }

    private var zone: TimeZone { model.store.data.householdSettings.timeZone }

    /// "That's after 'First smile' (30 Oct). Pick a date on or before 30 Oct."
    private var refusal: String? {
        let data = model.store.data
        let today = PlainDate(Date(), in: zone)
        guard let blocking = data.firstBefore(birthDate: PlainDate(day, in: zone), babyID: babyID) else { return nil }
        let when = JournalText.date(PlainDate(blocking.event.startedAt, in: zone), today: today)
        return "That's after \u{2018}\(blocking.payload?.milestone?.title ?? "a first")\u{2019} (\(when)). Pick a date on or before \(when)."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Born", selection: $day, in: ...Date(), displayedComponents: .date)
                        .environment(\.timeZone, zone)
                } footer: {
                    if let refusal {
                        Text(refusal).feedText(.subheadline).foregroundStyle(Theme.text)
                    } else {
                        Text("Each first shows the baby's age on its day. Saved on both phones.")
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .foregroundStyle(Theme.text)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Birth date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Birth date").feedText(.dayHeading).accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.text) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(refusal != nil).tint(Theme.text)
                }
            }
        }
    }

    private func save() {
        let chosen = PlainDate(day, in: zone)
        let blocking = model.store.change { $0.setBirthDate(chosen, babyID: babyID, now: Date()) }
        if blocking == nil { dismiss() }
    }

    /// Noon on that day in the household's time zone, so the picker shows the right day anywhere.
    static func date(_ day: PlainDate, in zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
    }
}
