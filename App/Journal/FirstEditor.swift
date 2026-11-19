import AVFoundation
import FeedingCore
import PhotosUI
import SwiftUI

/// Adding or changing a first (design review D9). One form in a sheet: Cancel and Save at the top;
/// What happened, with the ideas under it (D38); up to 4 photos in slots, the first the cover, each
/// moved, made the cover or taken out (D13, D35); When (from the photos when they were taken
/// earlier, D17); and the note. Delete is inside Edit (D8), with
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
        case added(id: String, title: String, photos: [String])
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
    /// The items in the slots, in order: the first is the cover (D9).
    @State private var items: [String]
    /// The slot shown large, to drag in its square and move.
    @State private var selected: String?
    /// Photos picked or taken here and not saved yet: their details, to queue on Save.
    @State private var drafts: [String: MediaStore.Added] = [:]
    /// Photos taken with the camera here: kept in Photos too, after Save (D20).
    @State private var takenImages: [String: UIImage] = [:]
    /// Videos picked or taken here, staged and not saved yet: made smaller after Save (D16).
    @State private var videoDrafts: [String: VideoQueue.Job] = [:]
    /// A picked video longer than 15 seconds: the parent chooses the 15 seconds to keep.
    @State private var trimming: VideoQueue.Job?
    /// The microphone is off for Feeding: said once (journal plan).
    @AppStorage("journal.microphoneOffTold") private var microphoneOffTold = false
    /// Where each photo sits in its square on the line (D39), by media ID.
    @State private var crops: [String: MediaCrop]
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var choosingPhoto = false
    /// Photos being made ready, one at a time in the order chosen; Discard stops them.
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
    /// The first as it was when the editor opened. Kept in the view's state, so a rebuild after the
    /// other phone's change never moves the starting point under the parent's draft (Codex review
    /// of step 2): Save applies only what changed from this.
    @State private var original: EventSnapshot?

    init(mode: Mode, me: MemberID, babyID: String, onDone: @escaping (Outcome) -> Void) {
        self.mode = mode
        self.me = me
        self.babyID = babyID
        self.onDone = onDone
        switch mode {
        case .new(let idea):
            _original = State(initialValue: nil)
            _title = State(initialValue: idea ?? "")
            _note = State(initialValue: "")
            _when = State(initialValue: Date())
            _items = State(initialValue: [])
            _crops = State(initialValue: [:])
        case .edit(let id):
            let snapshot = AppModel.shared.store.data.events[id]?.snapshot
            _original = State(initialValue: snapshot)
            _title = State(initialValue: snapshot?.payload?.milestone?.title ?? "")
            _note = State(initialValue: snapshot?.payload?.note ?? "")
            _when = State(initialValue: snapshot?.event.startedAt ?? Date())
            _items = State(initialValue: snapshot?.payload?.milestone?.media ?? [])
            _crops = State(initialValue: snapshot?.payload?.milestone?.crops ?? [:])
        }
    }

    private var data: HouseholdData { AppModel.shared.store.data }
    private var zone: TimeZone { data.householdSettings.timeZone }
    private var today: PlainDate { PlainDate(Date(), in: zone) }
    /// The first's list when this editor opened. Saving applies only what changed from it, so an
    /// item the other phone added meanwhile stays (`editMilestone`).
    private var originalMedia: [String] { original?.payload?.milestone?.media ?? [] }

    /// The slot shown large: the one chosen, or the cover.
    private var selectedItem: String? { selected.flatMap { items.contains($0) ? $0 : nil } ?? items.first }

    /// Something changed here: title, date, note or photo, or a photo still getting ready (D37).
    private var isDirty: Bool {
        if working { return true }
        if let original {
            return HouseholdData.cleanTitle(title) != original.payload?.milestone?.title
                || HouseholdData.cleanNote(note) != original.payload?.note
                || when != original.event.startedAt
                || items != originalMedia
                || Self.moved(crops) != Self.moved(original.payload?.milestone?.crops ?? [:])
        }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !items.isEmpty || whenTouched
    }

    /// The crops that move a photo off its middle.
    private static func moved(_ crops: [String: MediaCrop]) -> [String: MediaCrop] {
        crops.filter { $0.value != .middle }
    }

    /// Why Save is off, if it is.
    private var problem: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Say what happened." }
        if working { return "A photo or video is getting ready." }
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
                // Video only with room for a recording beyond the space kept for feeds (D19).
                CameraPicker(onPhoto: { image in
                    startImport([{ try await makeCopy(ofTaken: image) }])
                }, onVideo: roomForVideo ? { movie in
                    startImport([{ try await stage(takenVideo: movie) }])
                } : nil, onFailure: {
                    pickProblem = JournalText.refusal(.unreadableVideo)
                })
                    .ignoresSafeArea()
            }
            // A Save or Delete that didn't happen says so where it can't be missed; the form stays.
            .alert("Not saved", isPresented: Binding {
                saveProblem != nil
            } set: {
                if !$0 { saveProblem = nil }
            }) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveProblem ?? "")
            }
            .sheet(item: $trimming) { job in
                if let staged = AppModel.shared.videos.stagedURL(job) {
                    VideoTrimmer(url: staged) { trimmed in
                        working = true
                        Task {
                            try? await AppModel.shared.videos.replaceStaged(job.id, with: trimmed)
                            try? FileManager.default.removeItem(at: trimmed)
                            working = false
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            .confirmationDialog(JournalText.deleteQuestion, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text(JournalText.deleteWarning)
            }
            .onChange(of: pickerItems) { _, chosen in
                guard !chosen.isEmpty else { return }
                pickerItems = []
                startImport(chosen.map { item in { try await makeCopy(ofPicked: item) } })
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
            if items.isEmpty {
                HStack(spacing: 14) {
                    emptySlot.frame(width: 66, height: 66)
                    photoButtons
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element) { index, id in slot(id, index: index) }
                        if items.count < MilestoneLimits.mediaItems { addSlot }
                    }
                    if let shown = selectedItem, let index = items.firstIndex(of: shown) {
                        // The chosen photo in its square, as the Journal's line shows a cover; a
                        // drag moves it inside (D39).
                        CropSquare(id: shown, crop: Binding {
                            crops[shown] ?? .middle
                        } set: {
                            crops[shown] = $0
                        })
                        .frame(maxWidth: 280)
                        FlowLayout(spacing: 6) {
                            if index > 0 {
                                IdeaButton(idea: "Make it the cover", fill: Theme.background) { move(shown, to: 0) }
                                IdeaButton(idea: "Move earlier", fill: Theme.background) { move(shown, to: index - 1) }
                            }
                            if index < items.count - 1 {
                                IdeaButton(idea: "Move later", fill: Theme.background) { move(shown, to: index + 1) }
                            }
                            IdeaButton(idea: "Take it out", fill: Theme.background) { remove(shown) }
                        }
                        .disabled(working)
                    }
                }
                .padding(.vertical, 6)
            }
        } header: {
            header("Photos and videos")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let pickProblem {
                    Text(pickProblem).feedText(.subheadline).foregroundStyle(Theme.text)
                } else if items.isEmpty {
                    Text("A photo or video isn't needed: a first can be saved without one.").foregroundStyle(Theme.textMuted)
                } else {
                    Text("Up to 4 photos or short videos. The first is the cover, shown on the Journal.").foregroundStyle(Theme.textMuted)
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
        .photosPicker(isPresented: $choosingPhoto, selection: $pickerItems,
                      maxSelectionCount: max(1, MilestoneLimits.mediaItems - items.count),
                      // The order tapped is the order kept: the first tapped is the cover.
                      selectionBehavior: .ordered, matching: .any(of: [.images, .videos]), photoLibrary: .shared())
    }

    /// One slot: the photo in its square, "Cover" on the first; a tap shows it large below.
    private func slot(_ id: String, index: Int) -> some View {
        Button { selected = id } label: {
            MediaPicture(id: id, cornerRadius: 14, crop: crops[id] ?? .middle)
                .frame(width: 62, height: 62)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.text, lineWidth: id == selectedItem ? 3 : 0)
                }
                .overlay(alignment: .topTrailing) {
                    if isVideo(id) { PlayMark(size: 18).padding(4) }
                }
                .overlay(alignment: .bottom) {
                    if index == 0 {
                        Text("Cover")
                            .feedText(.chip)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 5)
                            // The slot already says "the cover" to VoiceOver.
                            .accessibilityHidden(true)
                            .background(Theme.surface, in: Capsule())
                            .padding(3)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("slot-\(id)")
        .accessibilityLabel("\(isVideo(id) ? "Video" : "Photo") \(index + 1) of \(items.count)\(index == 0 ? ", the cover" : "")")
        .accessibilityAddTraits(id == selectedItem ? .isSelected : [])
        // D35: moved with VoiceOver too.
        .accessibilityActions {
            if index > 0 {
                Button("Make it the cover") { move(id, to: 0) }
                Button("Move earlier") { move(id, to: index - 1) }
            }
            if index < items.count - 1 { Button("Move later") { move(id, to: index + 1) } }
            Button("Take it out") { remove(id) }
        }
    }

    /// The "+" slot: Choose from Photos, or Take a photo.
    private var addSlot: some View {
        Menu {
            Button("Choose from Photos") { choosingPhoto = true }
            if CameraPicker.isAvailable { Button("Take a photo or video") { tapCamera() } }
        } label: {
            emptySlot.frame(width: 62, height: 62)
        }
        .disabled(working)
        .accessibilityLabel("Add a photo")
    }

    /// An empty slot: a hole in the tile, in the page colour, with "+" (or the ring while a photo
    /// gets ready).
    private var emptySlot: some View {
        ZStack {
            Theme.background
            if working {
                ProgressView().tint(Theme.textMuted)
            } else {
                Text("+")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var photoButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotoButton(title: "Choose from Photos") { choosingPhoto = true }
            if CameraPicker.isAvailable {
                PhotoButton(title: "Take a photo or video") { tapCamera() }
            }
        }
        .disabled(working)
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
            if let dateProblem {
                Text(dateProblem).feedText(.subheadline).foregroundStyle(Theme.text)
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
            if CameraPicker.microphoneOff, !microphoneOffTold {
                microphoneOffTold = true
                pickProblem = "The microphone is off for Feeding, so the camera takes photos only. You can turn it on in iPhone Settings."
            } else if !roomForVideo {
                pickProblem = "Not enough space on this iPhone for a video, so the camera takes photos only."
            }
            if cameraExplained { openCamera() } else { explainingCamera = true }
        }
    }

    private func openCamera() { usingCamera = true }

    /// Room for a 15-second recording and its smaller copy, beyond the space kept for feeds.
    private var roomForVideo: Bool {
        MediaFiles.appGroup().map { SpaceRule.fits(300_000_000, free: $0.freeSpace()) } ?? false
    }

    /// Photos made ready one at a time, in the order chosen. Adding waits until they are done;
    /// Discard stops them, and one that finishes late is thrown away, files and all.
    /// What one pick or capture became: a photo's copy, or a staged video.
    private enum Imported {
        case photo(MediaStore.Added, taken: UIImage?)
        /// `long`: more than 15 seconds, so the parent picks the part to keep.
        case video(VideoQueue.Job, long: Bool)

        var id: String {
            switch self {
            case .photo(let added, _): added.id
            case .video(let job, _): job.id
            }
        }
    }

    private func startImport(_ makers: [@MainActor () async throws -> Imported]) {
        importTask?.cancel()
        let token = UUID()
        importToken = token
        working = true
        pickProblem = nil
        importTask = Task {
            for make in makers {
                guard token == importToken, !Task.isCancelled else { break }
                do {
                    let made = try await make()
                    guard token == importToken, !Task.isCancelled, items.count < MilestoneLimits.mediaItems else {
                        letGo(made)
                        continue
                    }
                    use(made)
                } catch let refusal as MediaStore.Refusal {
                    if token == importToken { pickProblem = JournalText.refusal(refusal) }
                } catch {
                    if token == importToken { pickProblem = JournalText.refusal(.unreadablePhoto) }
                }
            }
            if token == importToken { working = false }
        }
    }

    /// The picker's bytes go straight into the journal's copy (scaled, no place in it), never to a
    /// file of their own.
    private func makeCopy(ofPicked item: PhotosPickerItem) async throws -> Imported {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            // A video: its original staged, made smaller after Save (D16).
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                throw MediaStore.Refusal.unreadableVideo
            }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            let duration = (try? await AVURLAsset(url: movie.url).load(.duration).seconds) ?? 0
            let long = duration > MediaSizes.longestVideo + 0.5 && UIVideoEditorController.canEditVideo(atPath: movie.url.path)
            return .video(try await AppModel.shared.videos.stage(movie.url), long: long)
        }
        guard let files = MediaFiles.appGroup(),
              let bytes = try await item.loadTransferable(type: Data.self) else { throw MediaStore.Refusal.unreadablePhoto }
        return .photo(try await keepDraft(files: files, bytes: bytes), taken: nil)
    }

    /// A video taken here (15 seconds at most): staged like a picked one, and copied to Photos
    /// from its original after Save (D20).
    private func stage(takenVideo movie: URL) async throws -> Imported {
        defer { try? FileManager.default.removeItem(at: movie) }
        return .video(try await AppModel.shared.videos.stage(movie, takenHere: true), long: false)
    }

    /// The draft's ID is held before its files are written, so the clean-up never takes them
    /// half-way (Codex review of step 2).
    private func keepDraft(files: MediaFiles, bytes: Data) async throws -> MediaStore.Added {
        let id = UUID().uuidString
        AppModel.shared.media.holdDraft(id)
        do {
            return try await MediaStore(files: files).addPhoto(data: bytes, id: id)
        } catch {
            AppModel.shared.media.releaseDraft(id)
            throw error
        }
    }

    private func makeCopy(ofTaken image: UIImage) async throws -> Imported {
        guard let files = MediaFiles.appGroup() else { throw MediaStore.Refusal.unreadablePhoto }
        let bytes = await Task.detached { image.jpegData(compressionQuality: 0.95) }.value
        guard let bytes else { throw MediaStore.Refusal.unreadablePhoto }
        return .photo(try await keepDraft(files: files, bytes: bytes), taken: image)
    }

    /// One made too late (Discard, or the slots were full): it goes, files and all.
    private func letGo(_ made: Imported) {
        switch made {
        case .photo(let added, _):
            AppModel.shared.media.forget(added.id)
        case .video(let job, _):
            AppModel.shared.videos.discard(job.id)
        }
    }

    /// True for a video in a slot. Read again when the item's file arrives (`fileVersions`).
    private func isVideo(_ id: String) -> Bool {
        _ = AppModel.shared.media.fileVersions[id]
        return videoDrafts[id] != nil || AppModel.shared.isVideo(id)
    }

    /// A new photo goes in the next slot and is shown large; When follows the photos while the
    /// parent hasn't set it (D17).
    private func use(_ made: Imported) {
        switch made {
        case .photo(let added, let taken):
            drafts[added.id] = added
            if let taken { takenImages[added.id] = taken }
        case .video(let job, let long):
            videoDrafts[job.id] = job
            if long { trimming = job }
        }
        items.append(made.id)
        selected = made.id
        followPhotosForWhen()
    }

    /// Moves an item to `index`; 0 makes it the cover.
    private func move(_ id: String, to index: Int) {
        guard let from = items.firstIndex(of: id), items.indices.contains(index) else { return }
        items.remove(at: from)
        items.insert(id, at: index)
        selected = id
    }

    /// Takes an item out. One picked here goes from the phone, with its place in the square.
    private func remove(_ id: String) {
        items.removeAll { $0 == id }
        if drafts.removeValue(forKey: id) != nil {
            crops[id] = nil
            takenImages[id] = nil
            AppModel.shared.media.forget(id)
        }
        if videoDrafts.removeValue(forKey: id) != nil {
            crops[id] = nil
            AppModel.shared.videos.discard(id)
        }
        selected = items.first
        followPhotosForWhen()
    }

    /// When, from the photos picked here, while the parent hasn't set it (`MilestoneWhen`).
    private func followPhotosForWhen() {
        guard !whenTouched else { return }
        // Only times the first could have: one before the birth date, say, is left out
        // (Codex review of step 2).
        let taken = items.compactMap { drafts[$0]?.takenAt ?? videoDrafts[$0]?.takenAt }
            .filter { data.milestoneDateProblem($0, babyID: babyID, now: Date()) == nil }
        if let fromPhotos = MilestoneWhen.fromPhotos(takenAt: taken, now: Date()) {
            when = fromPhotos
            whenFromPhoto = true
        } else if whenFromPhoto {
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

    /// Lets go of everything made here: photos picked or taken and not saved go from the phone.
    private func cleanUp() {
        importTask?.cancel()
        importToken = UUID()
        for id in drafts.keys { AppModel.shared.media.forget(id) }
        drafts = [:]
        for id in videoDrafts.keys { AppModel.shared.videos.discard(id) }
        videoDrafts = [:]
    }

    private func save() {
        let store = AppModel.shared.store
        let now = Date()
        // A time picked in this minute is now (the picker's own boundary).
        let at = min(when, now)
        let media = items
        // Only the places of photos this first will hold.
        let crops = crops.filter { media.contains($0.key) }
        switch mode {
        case .new:
            let id = UUID().uuidString
            // The photos are queued first, then the first saved: if the app stops between the
            // two, the queue keeps them and waits for their first (a day at most). A queue that
            // can't be written stops Save here, so no first names a photo that isn't queued.
            guard queue(eventID: id, now: now) else {
                saveProblem = Self.notOnPhone
                return
            }
            // Written to this phone before it counts as saved (task T17).
            let (added, onPhone) = store.changeChecked {
                $0.addMilestone(id: id, babyID: babyID, title: title, note: note, media: media, crops: crops, at: at, by: me,
                                timeZoneID: TimeZone.current.identifier, now: now)
            }
            guard added != nil, onPhone else {
                unqueueDrafts()
                saveProblem = onPhone ? (dateProblem ?? "This first couldn't be saved. Check the date.") : Self.notOnPhone
                return
            }
            finishSave()
            onDone(.added(id: id, title: HouseholdData.cleanTitle(title),
                          photos: media.filter { drafts[$0] != nil || videoDrafts[$0] != nil }))
        case .edit(let id):
            guard let original else { return }
            guard queue(eventID: id, now: now) else {
                saveProblem = Self.notOnPhone
                return
            }
            let (saved, onPhone) = store.changeChecked {
                $0.editMilestone(id, from: original, title: title, note: note, media: media, crops: crops, at: at, by: me,
                                 now: now)
            }
            guard saved, onPhone else {
                unqueueDrafts()
                if !onPhone {
                    saveProblem = Self.notOnPhone
                } else if wouldPassFour(id) {
                    saveProblem = "This first has 4 photos now: the other phone added some. Take one out to add yours."
                } else {
                    saveProblem = data.events[id]?.event.deletedAt != nil
                        ? "This first was deleted on the other phone." : (dateProblem ?? "This first couldn't be saved.")
                }
                return
            }
            finishSave()
            onDone(.saved(id: id, photoRemoved: originalMedia.contains { !media.contains($0) }))
        }
        dismiss()
    }

    /// The app's words when a change couldn't be written to this phone.
    static let notOnPhone = "Couldn't save on this phone. Nothing was changed. Try again, or free up some space."

    /// The photos picked here go into the upload queue, behind the feeds, in slot order, in one
    /// write. False, and none queued, when the queue couldn't be written to this phone.
    private func queue(eventID: String, now: Date) -> Bool {
        // Videos first: written to their own queue, to be made smaller after Save (D16).
        let videos = items.filter { videoDrafts[$0] != nil }
        guard AppModel.shared.videos.commit(videos, to: eventID) else { return false }
        let uploads = items.compactMap { id in
            drafts[id].map { draft in
                MediaUpload(id: id, eventID: eventID, byteSize: draft.byteSize,
                            payload: try? PayloadCoder.encode(draft.details), queuedAt: now, pause: nil)
            }
        }
        guard AppModel.shared.media.add(uploads) else {
            AppModel.shared.videos.uncommit(videos)
            return false
        }
        return true
    }

    private func unqueueDrafts() {
        AppModel.shared.media.unqueue(Array(drafts.keys))
        AppModel.shared.videos.uncommit(Array(videoDrafts.keys))
    }

    /// True when the first as it is now, with this editor's changes, would hold more than 4.
    private func wouldPassFour(_ id: String) -> Bool {
        let now = data.events[id]?.snapshot.payload?.milestone?.media ?? []
        let takenOut = Set(originalMedia).subtracting(items)
        return Set(now).union(items).subtracting(takenOut).count > MilestoneLimits.mediaItems
    }

    /// Saved: the photos are no longer drafts, and those taken here go to Photos too (asked now,
    /// after Save: D20).
    private func finishSave() {
        for id in drafts.keys { AppModel.shared.media.releaseDraft(id) }
        for id in videoDrafts.keys { AppModel.shared.media.releaseDraft(id) }
        AppModel.shared.videos.kick()
        let taken = items.compactMap { takenImages[$0] }
        Task {
            for image in taken { await PhotosCopy.keep(image) }
            // Videos taken here: from their kept originals, also after a stop (`VideoQueue`).
            await AppModel.shared.videos.copyTakenToPhotos()
        }
    }

    private func delete() {
        guard case .edit(let id) = mode else { return }
        let (deleted, onPhone) = AppModel.shared.store.changeChecked { $0.deleteMilestone(id, by: me, now: Date()) }
        guard onPhone else {
            // Nothing was deleted: the form stays as it was, a new photo with it.
            saveProblem = Self.notOnPhone
            return
        }
        guard deleted else { return }
        cleanUp()
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
    @State private var loaded: (key: String, image: UIImage)?
    /// The drag under way: where it started, and the crop then. A new drag starts somewhere else,
    /// so a drag the system cancelled never leaves the next one starting from an old crop.
    @State private var drag: (origin: CGPoint, start: MediaCrop)?
    @State private var side: CGFloat = 0

    var body: some View {
        // Asked again when this photo's file arrives (`MediaSync.fileVersions`).
        let key = "\(id)|\(AppModel.shared.media.fileVersions[id] ?? 0)"
        let image = loaded.flatMap { $0.key == key ? $0.image : nil }
        let size = image?.size ?? .zero
        let movable = size.width > 0 && abs(size.width - size.height) > 1
        VStack(alignment: .leading, spacing: 8) {
            Theme.background
                .overlay {
                    if let image {
                        CroppedImage(image: image, crop: crop).modifier(NightDimmed(look: look))
                    } else {
                        // Not on this phone yet: the tile with "On its way", and nothing to drag.
                        MediaPicture(id: id)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(Rectangle())
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { side = $0 }
                // Only a photo that can move takes the drag; any other leaves the form to scroll.
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard side > 0 else { return }
                        if drag?.origin != value.startLocation { drag = (value.startLocation, crop) }
                        guard let start = drag?.start else { return }
                        crop = start.dragged(dx: value.translation.width, dy: value.translation.height,
                                             width: size.width, height: size.height, box: side)
                    }
                    .onEnded { _ in drag = nil }, isEnabled: movable)
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
        .task(id: key) {
            let image = await MediaPicture.load(id, full: true)
            guard !Task.isCancelled else { return }
            loaded = image.map { (key, $0) }
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
