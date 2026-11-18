import FeedingCore
import SwiftUI

/// One first's page (design review D8): the photo in a rounded frame with the gutter round it, then
/// the title, the age and date, the note and who logged it, and Edit. Delete is inside Edit. A
/// photo still coming shows the drawn tile with "On its way".
struct FirstPage: View {
    let id: String
    let me: MemberID
    let babyID: String
    /// The Undo bar lives on the Journal tab; a delete from here shows it there.
    let onUndo: (UndoAction) -> Void

    private let model = AppModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: FirstEditor.Mode?

    var body: some View {
        let data = model.store.data
        let zone = data.householdSettings.timeZone
        let today = PlainDate(Date(), in: zone)
        Group {
            if let first = data.events[id]?.snapshot, first.event.deletedAt == nil, let details = first.payload?.milestone {
                let day = PlainDate(first.event.startedAt, in: zone)
                let age = data.birthDate(babyID: babyID).flatMap { BabyAge(on: day, birthDate: $0) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        MediaPicture(id: details.media.first, full: true, cornerRadius: 26)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1.15, contentMode: .fit)
                            .accessibilityElement()
                            .accessibilityLabel(details.media.isEmpty ? "No photo" : "Photo of \(details.title)")
                        Text(details.title)
                            .feedText(.title)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4)
                        Text(JournalText.ageAndDate(age: age, day: day, today: today))
                            .feedText(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                        if let note = first.payload?.note {
                            Text(note).feedText(.body)
                        }
                        loggedBy(first.event.loggedBy)
                        Button { editing = .edit(id: id) } label: {
                            Text("Edit")
                                .feedText(.button)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                        .foregroundStyle(Theme.text)
                        .padding(.top, 8)
                    }
                    .padding(16)
                }
            } else {
                Text("This first isn't here any more.")
                    .feedText(.body)
                    .foregroundStyle(Theme.textMuted)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("First")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .sheet(item: $editing) { mode in
            FirstEditor(mode: mode, me: me, babyID: babyID) { outcome in
                if let action = JournalUndo.action(for: outcome, me: me) { onUndo(action) }
                if case .deleted = outcome { dismiss() }
            }
        }
    }

    private func loggedBy(_ member: MemberID) -> some View {
        let name = model.memberNames[member] ?? "the other parent"
        return HStack(spacing: 8) {
            Avatar(name: name, colour: model.memberColours[member] ?? .teal, size: 22)
            Text("Logged by \(name)").feedText(.subheadline).foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The Undo bar after Save, Delete or taking a photo out (design review D15).
enum JournalUndo {
    @MainActor
    static func action(for outcome: FirstEditor.Outcome, me: MemberID) -> UndoAction? {
        let model = AppModel.shared
        switch outcome {
        case .added(let id, let title, let photo):
            return UndoAction(message: JournalText.added(title)) {
                model.store.change { data in
                    if !data.undoAdd(id, now: Date()) { data.deleteMilestone(id, by: me, now: Date()) }
                }
                if let photo { model.media.forget(photo) }
            }
        case .deleted(let id, let title):
            return UndoAction(message: JournalText.deleted(title)) {
                guard model.sync.mayUndo(id) else { return }
                model.store.change { $0.undoHeld(id, by: me, now: Date()) }
            }
        case .saved(let id, let photoRemoved):
            guard photoRemoved else { return nil }
            return UndoAction(message: JournalText.photoRemoved) {
                guard model.sync.mayUndo(id) else { return }
                model.store.change { $0.undoHeld(id, by: me, now: Date()) }
            }
        }
    }
}
