import FeedingCore
import PhotosUI
import SwiftUI

/// Adding or changing a first (design review D9, step 1: one photo per first). One form in a
/// sheet: Cancel and Save at the top; What happened, with the ideas under it (D38); the photo; When
/// (from the photo when it was taken earlier, D17); and the note. Delete is inside Edit (D8), with
/// its own question (D15). Save works at once (D16).
struct FirstEditor: View {
    enum Mode: Hashable, Identifiable {
        case new(title: String?)
        case edit(id: String)

        var id: Self { self }
    }

    /// What happened, for the Undo bar.
    enum Outcome {
        case added(id: String, title: String, photo: String?)
        case saved(id: String, photoRemoved: Bool)
        case deleted(id: String, title: String)
    }

    let mode: Mode
    let me: MemberID
    let babyID: String
    let onDone: (Outcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var when: Date
    /// When was set from the photo, and nobody changed it since.
    @State private var whenFromPhoto = false
    @State private var whenTouched = false
    /// The item in the slot: the one already saved, or one just picked.
    @State private var photoID: String?
    /// A photo picked here and not saved yet: its details, to queue on Save.
    @State private var picked: MediaStore.Added?
    @State private var pickerItem: PhotosPickerItem?
    @State private var working = false
    @State private var pickProblem: String?
    @State private var confirmingDelete = false
    private let original: EventSnapshot?

    init(mode: Mode, me: MemberID, babyID: String, onDone: @escaping (Outcome) -> Void) {
        self.mode = mode
        self.me = me
        self.babyID = babyID
        self.onDone = onDone
        switch mode {
        case .new(let idea):
            original = nil
            _title = State(initialValue: idea ?? "")
            _note = State(initialValue: "")
            _when = State(initialValue: Date())
            _photoID = State(initialValue: nil)
        case .edit(let id):
            let snapshot = AppModel.shared.store.data.events[id]?.snapshot
            original = snapshot
            _title = State(initialValue: snapshot?.payload?.milestone?.title ?? "")
            _note = State(initialValue: snapshot?.payload?.note ?? "")
            _when = State(initialValue: snapshot?.event.startedAt ?? Date())
            _photoID = State(initialValue: snapshot?.payload?.milestone?.media.first)
        }
    }

    private var data: HouseholdData { AppModel.shared.store.data }
    private var zone: TimeZone { data.householdSettings.timeZone }
    private var today: PlainDate { PlainDate(Date(), in: zone) }

    /// Why Save is off, if it is.
    private var problem: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Say what happened." }
        let dateChanged = original.map { $0.event.startedAt != when } ?? true
        if dateChanged, let refusal = data.milestoneDateProblem(when, babyID: babyID, now: Date().addingTimeInterval(60)) {
            return JournalText.refusal(refusal, today: today)
        }
        if working { return "The photo is getting ready." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                whatHappened
                photoSection
                whenSection
                noteSection
                if case .edit = mode {
                    Section {
                        Button("Delete this first", role: .destructive) { confirmingDelete = true }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .foregroundStyle(Theme.text)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(screenTitle).feedText(.dayHeading).accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() }.tint(Theme.text) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(problem != nil).tint(Theme.text)
                }
            }
            .confirmationDialog(JournalText.deleteQuestion, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text(JournalText.deleteWarning)
            }
            .onChange(of: pickerItem) { _, item in
                if let item { Task { await take(item) } }
            }
        }
    }

    private var screenTitle: String {
        if case .edit = mode { return "Edit this first" }
        return JournalText.addAFirst
    }

    // MARK: Sections

    private var whatHappened: some View {
        Section {
            TextField("First smile", text: $title)
                .feedText(.body)
                .submitLabel(.done)
                .onChange(of: title) { _, new in
                    let kept = MilestoneLimits.title(new)
                    if kept != new { title = kept }
                }
            FlowLayout(spacing: 6) {
                ForEach(JournalText.ideas.filter { $0 != title }, id: \.self) { idea in
                    Button(idea) { title = idea }
                        .feedText(.smallButton)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .frame(minHeight: 44)
                        .background(Theme.background, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        } header: {
            header("What happened")
        } footer: {
            if let count = JournalText.count(title, limit: MilestoneLimits.titleCharacters) {
                Text(count).feedText(.small).foregroundStyle(Theme.textMuted)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var photoSection: some View {
        Section {
            HStack(spacing: 14) {
                Group {
                    if photoID == nil && !working {
                        // An empty slot: a hole in the tile, in the page colour, with "+".
                        Text("+")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                    } else {
                        MediaPicture(id: photoID, cornerRadius: 14)
                    }
                }
                .frame(width: 66, height: 66)
                .overlay {
                    if working { ProgressView().tint(Theme.textMuted) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(photoID == nil ? "Choose from Photos" : "Choose another", selection: $pickerItem,
                                 matching: .images, photoLibrary: .shared())
                        .feedText(.smallButton)
                        .foregroundStyle(Theme.text)
                        .frame(minHeight: 44)
                    if photoID != nil {
                        Button("Take the photo out") { removePhoto() }
                            .feedText(.smallButton)
                            .foregroundStyle(Theme.textMuted)
                            .frame(minHeight: 44)
                            .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            header("Photo")
        } footer: {
            if let pickProblem {
                Text(pickProblem).feedText(.subheadline).foregroundStyle(Theme.notice)
            } else {
                Text("A photo isn't needed: a first can be saved without one.").foregroundStyle(Theme.textMuted)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var whenSection: some View {
        Section {
            DatePicker("When", selection: Binding {
                when
            } set: {
                when = $0
                whenTouched = true
                whenFromPhoto = false
            }, in: ...Date().addingTimeInterval(60))
            if whenFromPhoto {
                Text("From the photo").feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
        } header: {
            header("When")
        } footer: {
            if let problem, problem != "Say what happened.", problem != "The photo is getting ready." {
                Text(problem).feedText(.subheadline).foregroundStyle(Theme.notice)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var noteSection: some View {
        Section {
            TextField("Optional", text: $note, axis: .vertical)
                .lineLimit(3...12)
                .onChange(of: note) { _, new in
                    let kept = MilestoneLimits.note(new)
                    if kept != new { note = kept }
                }
        } header: {
            header("Note")
        } footer: {
            if let count = JournalText.count(note, limit: MilestoneLimits.noteCharacters) {
                Text(count).feedText(.small).foregroundStyle(Theme.textMuted)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private func header(_ text: String) -> some View {
        Text(text).feedText(.label).foregroundStyle(Theme.textMuted)
    }

    // MARK: The photo

    /// The picked photo becomes the journal's own copy at once (scaled, no place in it), so Save
    /// never waits.
    private func take(_ item: PhotosPickerItem) async {
        working = true
        pickProblem = nil
        defer {
            working = false
            pickerItem = nil
        }
        guard let files = MediaFiles.appGroup() else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw MediaStore.Refusal.unreadablePhoto }
            try FileManager.default.createDirectory(at: MediaStore.workFolder, withIntermediateDirectories: true)
            let source = MediaStore.workFolder.appendingPathComponent("picked-\(UUID().uuidString)")
            try data.write(to: source)
            defer { try? FileManager.default.removeItem(at: source) }
            let added = try await MediaStore(files: files).addPhoto(from: source)
            if let previous = picked { files.remove(previous.id) }
            picked = added
            photoID = added.id
            AppModel.shared.media.noteNewFiles()
            if !whenTouched, let takenAt = added.takenAt, let fromPhoto = MilestoneWhen.fromPhotos(takenAt: [takenAt], now: Date()) {
                when = fromPhoto
                whenFromPhoto = true
            }
        } catch let refusal as MediaStore.Refusal {
            pickProblem = JournalText.refusal(refusal)
        } catch {
            pickProblem = JournalText.refusal(.unreadablePhoto)
        }
    }

    private func removePhoto() {
        if let picked, let files = MediaFiles.appGroup() { files.remove(picked.id) }
        picked = nil
        photoID = nil
        if whenFromPhoto, !whenTouched {
            when = original?.event.startedAt ?? Date()
            whenFromPhoto = false
        }
    }

    // MARK: Saving

    private func cancel() {
        // A photo picked here and never saved goes from the phone.
        if let picked, let files = MediaFiles.appGroup() { files.remove(picked.id) }
        dismiss()
    }

    private func save() {
        let store = AppModel.shared.store
        let now = Date()
        let media = photoID.map { [$0] } ?? []
        switch mode {
        case .new:
            let id = UUID().uuidString
            let added = store.change {
                $0.addMilestone(id: id, babyID: babyID, title: title, note: note, media: media, at: when, by: me,
                                timeZoneID: TimeZone.current.identifier, now: now)
            }
            guard added != nil else { return }
            queue(eventID: id, now: now)
            onDone(.added(id: id, title: HouseholdData.cleanTitle(title), photo: picked?.id))
        case .edit(let id):
            guard let original else { return }
            let before = original.payload?.milestone?.media ?? []
            let saved = store.change {
                $0.editMilestone(id, from: original, title: title, note: note, media: media, at: when, by: me, now: now)
            }
            guard saved else { return }
            queue(eventID: id, now: now)
            onDone(.saved(id: id, photoRemoved: before.contains { !media.contains($0) }))
        }
        dismiss()
    }

    /// A photo picked here goes into the upload queue, behind the feeds.
    private func queue(eventID: String, now: Date) {
        guard let picked else { return }
        AppModel.shared.media.add(MediaUpload(id: picked.id, eventID: eventID, byteSize: picked.byteSize,
                                              payload: try? PayloadCoder.encode(picked.details), queuedAt: now, pause: nil))
    }

    private func delete() {
        guard case .edit(let id) = mode else { return }
        if let picked, let files = MediaFiles.appGroup() { files.remove(picked.id) }
        let deleted = AppModel.shared.store.change { $0.deleteMilestone(id, by: me, now: Date()) }
        guard deleted else { return }
        onDone(.deleted(id: id, title: original?.payload?.milestone?.title ?? "First"))
        dismiss()
    }
}
