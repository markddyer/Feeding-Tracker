import FeedingCore
import SwiftUI

/// One first's page (design review D8): the photo in a rounded frame with the gutter round it, then
/// the title, the age and date, the note and who logged it, and Edit. Delete is inside Edit. A
/// photo still coming shows the drawn tile with "On its way".
struct FirstPage: View {
    let id: String
    let me: MemberID
    let babyID: String
    /// In the open Duo's right-hand column, beside the line, rather than a screen of its own.
    var embedded = false

    private let model = AppModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: FirstEditor.Mode?
    @State private var pageHeight: CGFloat = 0

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
                        // The whole photo, at its own shape (the parents' choice, 19 Nov 2026): at
                        // most the column's width, and at most 70% of the screen's height, so the
                        // title is still in sight under a tall photo.
                        MediaPicture(id: details.media.first, full: true, cornerRadius: 26)
                            .frame(maxWidth: .infinity, maxHeight: pageHeight > 0 ? pageHeight * 0.7 : nil, alignment: .leading)
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
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        .modifier(PageBar(embedded: embedded))
        .sheet(item: $editing) { mode in
            FirstEditor(mode: mode, me: me, babyID: babyID) { outcome in
                // The bar shows on whatever screen is in front: this page, or the one under it.
                if let action = JournalUndo.action(for: outcome, me: me) { UndoCenter.shared.show(action) }
                if case .deleted = outcome, !embedded { dismiss() }
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

/// A page of its own has the screen's name for Back; beside the line it has no bar of its own.
private struct PageBar: ViewModifier {
    let embedded: Bool

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .navigationTitle("First")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(removing: .title)
                .safeAreaInset(edge: .bottom) {
                    UndoCenterBar()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
        }
    }
}

/// The Undo bar after Save, Delete or taking a photo out (design review D15). An Undo is saved
/// with the checked write (task T17): if this phone can't write it, nothing changes, no photo is
/// removed, and the bar says so with Undo to try again while the hold lasts.
enum JournalUndo {
    @MainActor
    static func action(for outcome: FirstEditor.Outcome, me: MemberID) -> UndoAction? {
        let model = AppModel.shared
        switch outcome {
        case .added(let id, let title, let photo):
            return checked(JournalText.added(title)) {
                let (neverSent, onPhone) = model.store.changeChecked { data -> Bool in
                    if data.undoAdd(id, now: Date()) { return true }
                    data.deleteMilestone(id, by: me, now: Date())
                    return false
                }
                // A first that never left the phone takes its photo with it, once that is saved.
                // One already sent is deleted instead, and its photo goes by the delete's rules.
                if onPhone, neverSent, let photo { model.media.forget(photo) }
                return onPhone
            }
        case .deleted(let id, let title):
            return checked(JournalText.deleted(title)) {
                guard model.sync.mayUndo(id) else { return true }
                return model.store.changeChecked { $0.undoHeld(id, by: me, now: Date()) }.saved
            }
        case .saved(let id, let photoRemoved):
            guard photoRemoved else { return nil }
            return checked(JournalText.photoRemoved) {
                guard model.sync.mayUndo(id) else { return true }
                return model.store.changeChecked { $0.undoHeld(id, by: me, now: Date()) }.saved
            }
        }
    }

    /// An Undo that, if it couldn't be saved on this phone, shows a bar to try again.
    @MainActor
    private static func checked(_ message: String, _ undo: @escaping @MainActor () -> Bool) -> UndoAction {
        UndoAction(message: message) {
            guard !undo() else { return }
            UndoCenter.shared.show(checked("Couldn't undo on this phone. Try again", undo))
        }
    }
}
