import AVFoundation
import FeedingCore
import PhotosUI
import SwiftUI

/// Adding or changing a first (design review D9, step 1: one photo per first). One form in a
/// sheet: Cancel and Save at the top; What happened, with the ideas under it (D38); the photo; When
/// (from the photo when it was taken earlier, D17); and the note. Delete is inside Edit (D8), with
/// its own question (D15). Save works at once (D16). A swipe down or Cancel with changes asks
/// "Discard this first?" (D37).
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
    /// The item in the slot: the one already saved, or one just picked or taken.
    @State private var photoID: String?
    /// A photo picked or taken here and not saved yet: its details, to queue on Save.
    @State private var picked: MediaStore.Added?
    /// A photo taken with the camera here: kept in Photos too, after Save (D20).
    @State private var takenImage: UIImage?
    /// Where each photo sits in its square on the line (D39), by media ID.
    @State private var crops: [String: MediaCrop]
    @State private var pickerItem: PhotosPickerItem?
    @State private var choosingPhoto = false
    /// The photo being made ready: one at a time, and a newer choice (or Discard) wins.
    @State private var importTask: Task<Void, Never>?
    @State private var importToken = UUID()
    @State private var working = false
    @State private var pickProblem: String?
    @State private var cameraOff = false
    @State private var saveProblem: String?
    @State private var confirmingDelete = false
    @State private var confirmingDiscard = false
    @State private var explainingCamera = false
    @State private var usingCamera = false
    @AppStorage("journal.cameraExplained") private var cameraExplained = false
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
            _crops = State(initialValue: [:])
        case .edit(let id):
            let snapshot = AppModel.shared.store.data.events[id]?.snapshot
            original = snapshot
            _title = State(initialValue: snapshot?.payload?.milestone?.title ?? "")
            _note = State(initialValue: snapshot?.payload?.note ?? "")
            _when = State(initialValue: snapshot?.event.startedAt ?? Date())
            _photoID = State(initialValue: snapshot?.payload?.milestone?.media.first)
            _crops = State(initialValue: snapshot?.payload?.milestone?.crops ?? [:])
        }
    }

    private var data: HouseholdData { AppModel.shared.store.data }
    private var zone: TimeZone { data.householdSettings.timeZone }
    private var today: PlainDate { PlainDate(Date(), in: zone) }
    /// The first's whole list before this editor: step 1 shows only its cover, and the rest is kept
    /// (the other phone may have added some: Codex review of T7 and T8).
    private var originalMedia: [String] { original?.payload?.milestone?.media ?? [] }

    /// Something changed here: title, date, note or photo, or a photo still getting ready (D37).
    private var isDirty: Bool {
        if working { return true }
        if let original {
            return HouseholdData.cleanTitle(title) != original.payload?.milestone?.title
                || HouseholdData.cleanNote(note) != original.payload?.note
                || when != original.event.startedAt
                || photoID != originalMedia.first
                || Self.moved(crops) != Self.moved(original.payload?.milestone?.crops ?? [:])
        }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || picked != nil || whenTouched
    }

    /// The crops that move a photo off its middle.
    private static func moved(_ crops: [String: MediaCrop]) -> [String: MediaCrop] {
        crops.filter { $0.value != .middle }
    }

    /// Why Save is off, if it is.
    private var problem: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Say what happened." }
        if working { return "The photo is getting ready." }
        return dateProblem
    }

    /// A date the store would refuse, in the parents' words. The same boundary as the store's:
    /// a time in this minute counts as now.
    private var dateProblem: String? {
        let dateChanged = original.map { $0.event.startedAt != when } ?? true
        guard dateChanged, let refusal = data.milestoneDateProblem(min(when, Date()), babyID: babyID, now: Date()) else {
            return nil
        }
        return JournalText.refusal(refusal, today: today)
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
            // Never coral here: the date picker and the photo buttons in the text colour.
            .tint(Theme.text)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(screenTitle).feedText(.dayHeading).accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() }.tint(Theme.text) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(problem != nil).tint(Theme.text)
                }
            }
            // A swipe down with changes asks first (D37); iOS closes the sheet itself on Discard.
            .dismissalConfirmationDialog("Discard this first?", shouldPresent: isDirty) {
                Button("Discard", role: .destructive) { cleanUp() }
                Button("Keep editing", role: .cancel) {}
            }
            .confirmationDialog("Discard this first?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    cleanUp()
                    dismiss()
                }
                Button("Keep editing", role: .cancel) {}
            }
            .sheet(isPresented: $explainingCamera) {
                CameraExplainer {
                    cameraExplained = true
                    openCamera()
                }
            }
            .fullScreenCover(isPresented: $usingCamera) {
                CameraPicker { image in startImport { try await makeCopy(ofTaken: image) } }
                    .ignoresSafeArea()
            }
            .confirmationDialog(JournalText.deleteQuestion, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text(JournalText.deleteWarning)
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                pickerItem = nil
                startImport { try await makeCopy(ofPicked: item) }
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
                    IdeaButton(idea: idea, fill: Theme.background) { title = idea }
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
            if let photoID {
                // The cover in its square, as the Journal's line shows it; a drag moves the photo
                // inside it (D39).
                VStack(alignment: .leading, spacing: 10) {
                    CropSquare(id: photoID, crop: Binding {
                        crops[photoID] ?? .middle
                    } set: {
                        crops[photoID] = $0
                    })
                    .frame(maxWidth: 280)
                    .overlay {
                        if working { ProgressView().tint(Theme.textMuted) }
                    }
                    photoButtons
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 14) {
                    Group {
                        if working {
                            Theme.background.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            // An empty slot: a hole in the tile, in the page colour, with "+".
                            Text("+")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.textMuted)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: 66, height: 66)
                    .overlay {
                        if working { ProgressView().tint(Theme.textMuted) }
                    }
                    photoButtons
                }
            }
        } header: {
            header("Photo")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let pickProblem {
                    Text(pickProblem).feedText(.subheadline).foregroundStyle(Theme.text)
                } else if photoID == nil {
                    Text("A photo isn't needed: a first can be saved without one.").foregroundStyle(Theme.textMuted)
                }
                if cameraOff, let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open iPhone Settings", destination: settings)
                        .feedText(.smallButton)
                        .foregroundStyle(Theme.text)
                        .frame(minHeight: 44)
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var photoButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotoButton(title: photoID == nil ? "Choose from Photos" : "Choose another") { choosingPhoto = true }
            if CameraPicker.isAvailable {
                PhotoButton(title: "Take a photo") { tapCamera() }
            }
            if photoID != nil {
                PhotoButton(title: "Take the photo out", muted: true) { removePhoto() }
            }
        }
        .disabled(working)
        .photosPicker(isPresented: $choosingPhoto, selection: $pickerItem, matching: .images, photoLibrary: .shared())
    }

    private var whenSection: some View {
        Section {
            DatePicker("When", selection: Binding {
                when
            } set: {
                when = $0
                whenTouched = true
                whenFromPhoto = false
            }, in: ...Date())
            if whenFromPhoto {
                Text("From the photo").feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
        } header: {
            header("When")
        } footer: {
            if let shown = saveProblem ?? dateProblem {
                Text(shown).feedText(.subheadline).foregroundStyle(Theme.text)
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

    /// The camera: the short screen first time (D20); a camera turned off in Settings says so, with
    /// the way to turn it on.
    private func tapCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            cameraOff = true
            pickProblem = "The camera is off for Feeding. You can turn it on in iPhone Settings."
        default:
            cameraOff = false
            if cameraExplained { openCamera() } else { explainingCamera = true }
        }
    }

    private func openCamera() { usingCamera = true }

    /// One photo made ready at a time. A newer choice, or Discard, wins: an older one that finishes
    /// late is thrown away, files and all.
    private func startImport(_ make: @escaping @MainActor () async throws -> (MediaStore.Added, UIImage?)) {
        importTask?.cancel()
        let token = UUID()
        importToken = token
        working = true
        pickProblem = nil
        importTask = Task {
            do {
                let (added, taken) = try await make()
                guard token == importToken, !Task.isCancelled else {
                    AppModel.shared.media.forget(added.id)
                    return
                }
                use(added, taken: taken)
            } catch let refusal as MediaStore.Refusal {
                if token == importToken { pickProblem = JournalText.refusal(refusal) }
            } catch {
                if token == importToken { pickProblem = JournalText.refusal(.unreadablePhoto) }
            }
            if token == importToken { working = false }
        }
    }

    /// The picker's bytes go straight into the journal's copy (scaled, no place in it), never to a
    /// file of their own.
    private func makeCopy(ofPicked item: PhotosPickerItem) async throws -> (MediaStore.Added, UIImage?) {
        guard let files = MediaFiles.appGroup(),
              let bytes = try await item.loadTransferable(type: Data.self) else { throw MediaStore.Refusal.unreadablePhoto }
        let added = try await MediaStore(files: files).addPhoto(data: bytes)
        AppModel.shared.media.holdDraft(added.id)
        return (added, nil)
    }

    private func makeCopy(ofTaken image: UIImage) async throws -> (MediaStore.Added, UIImage?) {
        guard let files = MediaFiles.appGroup() else { throw MediaStore.Refusal.unreadablePhoto }
        let bytes = await Task.detached { image.jpegData(compressionQuality: 0.95) }.value
        guard let bytes else { throw MediaStore.Refusal.unreadablePhoto }
        let added = try await MediaStore(files: files).addPhoto(data: bytes)
        AppModel.shared.media.holdDraft(added.id)
        return (added, image)
    }

    /// The new photo, its camera picture (if taken here) and its suggested date go in together;
    /// the one before goes. A date the parent set stays.
    private func use(_ added: MediaStore.Added, taken: UIImage?) {
        if let previous = picked { AppModel.shared.media.forget(previous.id) }
        picked = added
        photoID = added.id
        takenImage = taken
        guard !whenTouched else { return }
        if let takenAt = added.takenAt, let fromPhoto = MilestoneWhen.fromPhotos(takenAt: [takenAt], now: Date()) {
            when = fromPhoto
            whenFromPhoto = true
        } else {
            when = original?.event.startedAt ?? Date()
            whenFromPhoto = false
        }
    }

    private func removePhoto() {
        if let picked { AppModel.shared.media.forget(picked.id) }
        picked = nil
        photoID = nil
        takenImage = nil
        if whenFromPhoto, !whenTouched {
            when = original?.event.startedAt ?? Date()
            whenFromPhoto = false
        }
    }

    // MARK: Saving

    private func cancel() {
        if isDirty {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }

    /// Lets go of everything made here: a photo picked or taken and not saved goes from the phone.
    private func cleanUp() {
        importTask?.cancel()
        importToken = UUID()
        if let picked { AppModel.shared.media.forget(picked.id) }
        picked = nil
    }

    private func save() {
        let store = AppModel.shared.store
        let now = Date()
        // A time picked in this minute is now (the picker's own boundary).
        let at = min(when, now)
        // Step 1 changes only the cover: the rest of the list stays as it is.
        let rest = Array(originalMedia.dropFirst())
        let media = photoID == originalMedia.first ? originalMedia : (photoID.map { [$0] } ?? []) + rest
        switch mode {
        case .new:
            let id = UUID().uuidString
            // The photo is queued first, then the first saved: if the app stops between the two,
            // the queue keeps the photo and waits for its first (a day at most).
            queue(eventID: id, now: now)
            let added = store.change {
                $0.addMilestone(id: id, babyID: babyID, title: title, note: note, media: media, crops: crops, at: at, by: me,
                                timeZoneID: TimeZone.current.identifier, now: now)
            }
            guard added != nil else {
                if let picked { AppModel.shared.media.unqueue(picked.id) }
                saveProblem = dateProblem ?? "This first couldn't be saved. Check the date."
                return
            }
            finishSave()
            onDone(.added(id: id, title: HouseholdData.cleanTitle(title), photo: picked?.id))
        case .edit(let id):
            guard let original else { return }
            queue(eventID: id, now: now)
            let saved = store.change {
                $0.editMilestone(id, from: original, title: title, note: note, media: media, crops: crops, at: at, by: me,
                                 now: now)
            }
            guard saved else {
                if let picked { AppModel.shared.media.unqueue(picked.id) }
                saveProblem = data.events[id]?.event.deletedAt != nil
                    ? "This first was deleted on the other phone." : (dateProblem ?? "This first couldn't be saved.")
                return
            }
            finishSave()
            onDone(.saved(id: id, photoRemoved: originalMedia.contains { !media.contains($0) }))
        }
        dismiss()
    }

    /// A photo picked here goes into the upload queue, behind the feeds.
    private func queue(eventID: String, now: Date) {
        guard let picked else { return }
        AppModel.shared.media.add(MediaUpload(id: picked.id, eventID: eventID, byteSize: picked.byteSize,
                                              payload: try? PayloadCoder.encode(picked.details), queuedAt: now, pause: nil))
    }

    /// Saved: the photo is no longer a draft, and one taken here goes to Photos too (asked now,
    /// after Save: D20).
    private func finishSave() {
        if let picked { AppModel.shared.media.releaseDraft(picked.id) }
        if let takenImage { Task { await PhotosCopy.keep(takenImage) } }
    }

    private func delete() {
        guard case .edit(let id) = mode else { return }
        cleanUp()
        let deleted = AppModel.shared.store.change { $0.deleteMilestone(id, by: me, now: Date()) }
        guard deleted else { return }
        onDone(.deleted(id: id, title: original?.payload?.milestone?.title ?? "First"))
        dismiss()
    }
}

/// One of the ideas (design review D38): the whole 44-point capsule takes the tap, not just its
/// words.
struct IdeaButton: View {
    let idea: String
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(idea)
                .feedText(.smallButton)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The cover in Add and Edit (design review D39): the photo in its square, as the Journal's line
/// shows it, and a drag moves the photo inside it. A square photo shows whole and can't move.
/// VoiceOver says which part shows, and its actions move the photo a step.
struct CropSquare: View {
    let id: String
    @Binding var crop: MediaCrop

    @Environment(\.look) private var look
    @State private var loaded: (id: String, image: UIImage)?
    @State private var dragStart: MediaCrop?
    @State private var side: CGFloat = 0

    var body: some View {
        let image = loaded.flatMap { $0.id == id ? $0.image : nil }
        let size = image?.size ?? .zero
        let movable = size.width > 0 && abs(size.width - size.height) > 1
        VStack(alignment: .leading, spacing: 8) {
            Theme.background
                .overlay {
                    if let image {
                        CroppedImage(image: image, crop: crop).modifier(NightDimmed(look: look))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(Rectangle())
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { side = $0 }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard movable, side > 0 else { return }
                        let start = dragStart ?? crop
                        if dragStart == nil { dragStart = crop }
                        crop = start.dragged(dx: value.translation.width, dy: value.translation.height,
                                             width: size.width, height: size.height, box: side)
                    }
                    .onEnded { _ in dragStart = nil })
                .accessibilityElement()
                .accessibilityLabel("Photo in its square")
                .accessibilityValue(movable ? Self.describe(crop, width: size.width, height: size.height) : "The whole photo")
                .accessibilityHint(movable ? "Drag to choose what shows on the Journal." : "")
                .accessibilityActions {
                    if movable {
                        if size.height > size.width {
                            Button("Show more of the top") { step(dy: 1, size: size) }
                            Button("Show more of the bottom") { step(dy: -1, size: size) }
                        } else {
                            Button("Show more of the left") { step(dx: 1, size: size) }
                            Button("Show more of the right") { step(dx: -1, size: size) }
                        }
                    }
                }
            if movable {
                Text("Drag the photo to choose what shows in its square on the Journal.")
                    .feedText(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: id) {
            let image = await MediaPicture.load(id, full: true)
            guard !Task.isCancelled else { return }
            loaded = image.map { (id, $0) }
        }
    }

    /// One VoiceOver step: a tenth of the square.
    private func step(dx: Double = 0, dy: Double = 0, size: CGSize) {
        let box = max(side, 100)
        crop = crop.clamped(width: size.width, height: size.height)
            .dragged(dx: dx * box / 10, dy: dy * box / 10, width: size.width, height: size.height, box: box)
    }

    /// Which part of the photo shows, in words: along the way it can move.
    static func describe(_ crop: MediaCrop, width: Double, height: Double) -> String {
        let tall = height > width
        let side = min(width, height)
        let half = side / (tall ? height : width) / 2
        let at = (tall ? crop.clamped(width: width, height: height).y : crop.clamped(width: width, height: height).x)
        let range = 1 - 2 * half
        let part = range > 0 ? (at - half) / range : 0.5
        let (start, end) = tall ? ("top", "bottom") : ("left", "right")
        switch part {
        case ..<0.05: return "The \(start)"
        case ..<0.4: return "Nearer the \(start)"
        case ...0.6: return "The middle"
        case ...0.95: return "Nearer the \(end)"
        default: return "The \(end)"
        }
    }
}

/// A button under the photo: the whole 44-point row takes the tap, not just its words.
private struct PhotoButton: View {
    let title: String
    var muted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .feedText(.smallButton)
                .foregroundStyle(muted ? Theme.textMuted : Theme.text)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
