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
    /// The item on screen, by its ID, when a first has more than one (D8: "1 of 3", a swipe): kept
    /// while that item stays, whatever the other phone changes around it (Codex review of step 2).
    @State private var currentID: String?
    @State private var explainingFailure = false

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
                        let shownID = currentID.flatMap { details.media.contains($0) ? $0 : nil } ?? details.media.first
                        if details.media.count > 1 {
                            MediaPager(ids: details.media, selection: Binding { shownID } set: { currentID = $0 },
                                       height: pageHeight > 0 ? pageHeight * 0.62 : 420)
                        } else {
                            Group {
                                if let only = details.media.first, AppModel.shared.isVideo(only) {
                                    MediaItemView(id: only)
                                        .aspectRatio(1, contentMode: .fit)
                                        .accessibilityElement(children: .contain)
                                        .accessibilityLabel("Video of \(details.title)")
                                } else {
                                    MediaPicture(id: details.media.first, full: true, cornerRadius: 26)
                                        .accessibilityElement()
                                        .accessibilityLabel(details.media.isEmpty ? "No photo" : "Photo of \(details.title)")
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: pageHeight > 0 ? pageHeight * 0.7 : nil, alignment: .leading)
                        }
                        Text(details.title)
                            .feedText(.title)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4)
                        Text(JournalText.ageAndDate(age: age, day: day, today: today))
                            .feedText(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                        videoStatus
                        if let note = first.payload?.note {
                            Text(note).feedText(.body)
                        }
                        loggedBy(first.event.loggedBy)
                        // Share and Edit, two soft buttons (D8); Delete is inside Edit.
                        HStack(spacing: 10) {
                            // The item on screen (journal plan, "Share").
                            ShareFirstButton(firstID: id, title: details.title, age: age?.words,
                                             photoID: shownID)
                            Button { editing = .edit(id: id) } label: {
                                Text("Edit")
                                    .feedText(.button)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                            .foregroundStyle(Theme.text)
                        }
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

    /// This phone's videos for the first: still being made smaller, or one that couldn't be
    /// (eng2 D4: it was taken off the first on both phones), explained on tap.
    @ViewBuilder
    private var videoStatus: some View {
        let videos: VideoQueue = model.videos
        if !videos.failed(of: id).isEmpty {
            Button { explainingFailure = true } label: {
                Label(JournalText.videoNotAdded, systemImage: "exclamationmark.circle")
                    .feedText(.subheadline)
                    .foregroundStyle(Theme.text)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .alert(JournalText.videoNotAdded, isPresented: $explainingFailure) {
                Button("OK", role: .cancel) { videos.clearFailures(of: id) }
            } message: {
                Text("It couldn't be made smaller for the journal, so it was left out on both phones. The first is kept. You can add the video again in Edit.")
            }
        } else if !videos.pending(of: id).isEmpty {
            Text("Getting a video ready").feedText(.subheadline).foregroundStyle(Theme.textMuted)
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

/// A first's photos, one at a time (design review D8): a swipe moves between them, with "1 of 3" in
/// the corner. Each whole photo fits the frame. VoiceOver reads "Photo 1 of 3" and moves with its
/// adjustable actions (D35).
struct MediaPager: View {
    let ids: [String]
    @Binding var selection: String?
    let height: CGFloat

    var body: some View {
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? 0
        TabView(selection: $selection) {
            ForEach(ids, id: \.self) { id in
                MediaItemView(id: id, isCurrent: id == selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(Optional(id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: height)
        .overlay(alignment: .topTrailing) {
            Text("\(current + 1) of \(ids.count)")
                .feedText(.chip)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Theme.surface, in: Capsule())
                .padding(10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(ids.indices.contains(current) && AppModel.shared.isVideo(ids[current]) ? "Video" : "Photo") \(current + 1) of \(ids.count)")
        // Names the item shown, for the tap tests; VoiceOver doesn't read it.
        .accessibilityIdentifier("pager-\(ids.indices.contains(current) ? ids[current] : "")")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selection = ids[min(current + 1, ids.count - 1)]
            case .decrement: selection = ids[max(current - 1, 0)]
            @unknown default: break
            }
        }
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
                .undoCenterCard()
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
        case .added(let id, let title, let photos):
            return checked(JournalText.added(title)) {
                let (neverSent, onPhone) = model.store.changeChecked { data -> Bool in
                    if data.undoAdd(id, now: Date()) { return true }
                    data.deleteMilestone(id, by: me, now: Date())
                    return false
                }
                // A first that never left the phone takes its photos with it, once that is saved.
                // One already sent is deleted instead, and its photos go by the delete's rules.
                // Also those a later edit inside the Undo window added (Codex review of step 2).
                if onPhone, neverSent {
                    photos.forEach(model.media.forget)
                    photos.forEach(model.videos.forget)
                    model.media.forgetUploads(ofFirst: id)
                }
                return onPhone
            }
        case .deleted(let id, let title):
            return checked(JournalText.deleted(title)) {
                guard model.sync.mayUndo(id) else { return true }
                guard !model.store.data.undoWouldPassTheLimit(id) else { return tooMany() }
                return model.store.changeChecked { $0.undoHeld(id, by: me, now: Date()) }.saved
            }
        case .saved(let id, let photoRemoved):
            guard photoRemoved else { return nil }
            return checked(JournalText.photoRemoved) {
                guard model.sync.mayUndo(id) else { return true }
                guard !model.store.data.undoWouldPassTheLimit(id) else { return tooMany() }
                return model.store.changeChecked { $0.undoHeld(id, by: me, now: Date()) }.saved
            }
        }
    }

    /// Undo would make more than 4, as the other phone added some meanwhile: nothing is dropped to
    /// make room, and the bar says why (Codex review of step 2).
    @MainActor
    private static func tooMany() -> Bool {
        var notice = UndoAction(message: "This first has 4 photos now, so Undo can't bring it back") {}
        notice.canUndo = false
        UndoCenter.shared.show(notice)
        return true
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
