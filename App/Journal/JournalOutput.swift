import BackgroundTasks
import FeedingCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

// Share and Export (journal plan, "Share is in the first build" and "Export ships with the first
// Journal build"; CEO review D11, D15, D17; design review D12, D25; eng D4; outside voice OE8,
// OV8; tasks T10, T6, T7, T21). Nothing here sends anything by itself: only a parent's tap does.

// MARK: - Share

/// The card a photo's first is shared as (design review D25): 1080 × 1350 pixels, always in the
/// day look. The whole photo, fitted, on top; below, a band in the page colour with the first's
/// shape, the title in Fredoka (the band grows for a long title) and the age in SF Pro Rounded.
/// Nothing is written on the photo; no baby's name, app name or place. A new picture, so it carries
/// no metadata from the photo.
struct ShareCard: View {
    static let size = CGSize(width: 1080, height: 1350)

    let photo: UIImage
    let title: String
    /// "8 weeks"; nil with no birth date.
    let age: String?

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 48)
                .padding(.top, 48)
            VStack(alignment: .leading, spacing: 16) {
                SparkleShape()
                    .fill(Theme.textMuted)
                    .frame(width: 56, height: 56)
                Text(title)
                    .font(.custom("Fredoka-SemiBold", fixedSize: 76))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let age {
                    Text(age)
                        .font(.system(size: 44, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.horizontal, 72)
            .padding(.top, 40)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.background)
        // Always the day look (D25), whatever the phone shows.
        .environment(\.colorScheme, .light)
    }

    /// The card as a JPEG, at 1080 × 1350 pixels.
    @MainActor
    static func jpeg(photo: UIImage, title: String, age: String?) -> Data? {
        let renderer = ImageRenderer(content: ShareCard(photo: photo, title: title, age: age))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage?.jpegData(compressionQuality: 0.9)
    }
}

/// A first with a photo, shared as its card. The card is drawn when the share sheet asks for it.
struct FirstCardShare: Transferable {
    let photoURL: URL
    let title: String
    let age: String?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { card in try await card.jpeg() }
            .suggestedFileName { "\($0.title).jpg" }
    }

    func jpeg() async throws -> Data {
        let url = photoURL
        let photo = await Task.detached { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        }.value
        guard let photo, let data = await ShareCard.jpeg(photo: photo, title: title, age: age) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }
}

/// Share on a first's page (D11, D15): the card for a photo; one line of text with no photo; the
/// note and who logged it never go. A photo not on this phone yet is fetched first, the same
/// careful way as the export's; if it can't be, Share says so and offers to try again.
struct ShareFirstButton: View {
    let firstID: String
    let title: String
    let age: String?
    let photoID: String?

    private let model = AppModel.shared
    @State private var failed = false
    @State private var tries = 0

    var body: some View {
        let files = MediaFiles.appGroup()
        // Asked again when the photo arrives (`MediaSync.fileVersions`).
        let version = photoID.map { model.media.fileVersions[$0] ?? 0 } ?? 0
        let photoURL = photoID.flatMap { id in files.flatMap { $0.hasFile(id) ? $0.fileURL(id) : nil } }
        Group {
            if photoID == nil {
                ShareLink(item: JournalText.shareLine(title: title, age: age)) { label("Share") }
            } else if let photoURL {
                ShareLink(item: FirstCardShare(photoURL: photoURL, title: title, age: age),
                          preview: SharePreview(title)) { label("Share") }
            } else if failed {
                Button {
                    failed = false
                    tries += 1
                } label: {
                    label("Couldn't get the photo · Try again")
                }
            } else {
                label("Getting the photo…")
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityLabel("Share waits for the photo to reach this iPhone")
            }
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(Theme.text)
        .id(version)
        .task(id: "\(photoID ?? "-")|\(tries)") {
            guard let photoID, photoURL == nil else { return }
            let fetched = await model.media.fetchForShare(photoID)
            if !Task.isCancelled, !fetched, files?.hasFile(photoID) != true { failed = true }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .feedText(.button)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Export

/// "Export the journal" (design review D12; eng D4; OV8): one file with every photo and video,
/// named by date and title, and the list of firsts. It asks iOS to let it carry on if the phone
/// is locked (a continued-processing task, with iOS's own progress display); if iOS says no, it
/// runs with the app open and says so, and stops if the app leaves the screen. If iOS stops it,
/// the half-made file is deleted and the parent is told. The file is kept until the screen closes.
///
/// Each Export tap is an attempt with its own ID: a late answer from iOS to an attempt that was
/// cancelled is ended at once and changes nothing (Codex review of T10).
@MainActor
@Observable
final class JournalExporter {
    enum State: Equatable {
        case ready
        case gettingPhotos(done: Int, total: Int)
        case packing
        /// The file, and how many photos it leaves out ("Save without these").
        case done(URL, leftOut: Int)
        /// The titles of the firsts whose items couldn't be fetched.
        case missing([String])
        case stopped
        case noSpace
    }

    private(set) var state: State = .ready
    /// iOS didn't let it carry on in the background: the app must stay open until it finishes.
    private(set) var keepOpen = false

    /// What the exporter works with; stand-ins in tests.
    struct Sources {
        /// The export, leaving out the given items.
        var plan: @MainActor (_ leavingOut: Set<String>) -> JournalExportPlan
        var files: MediaFiles?
        var fetch: @MainActor (_ ids: [String], _ progress: @MainActor (Int) -> Void) async -> Set<String>
        var byteSizes: @MainActor () -> [String: Int64]
        var freeSpace: @MainActor () -> Int64
        /// Ask iOS to let the export go on in the background; false runs it here.
        var useBackgroundTask = true
        /// Where an export's state is kept for a notification's tap after the app was closed.
        var defaults: UserDefaults = .standard
    }

    private let sources: Sources
    private var attempt = UUID()
    /// The attempt whose export has begun, so it never runs twice.
    private var begun: UUID?
    private var work: Task<Void, Never>?
    private var backgroundTask: BGContinuedProcessingTask?
    private var pendingRequest: String?
    /// The folder this export writes in, from the moment it is made; deleted on every way out.
    private var folder: URL?
    /// Items confirmed missing: "Save without these" leaves them out.
    private var missingIDs: Set<String> = []
    private var leavingObserver: NSObjectProtocol?
    private static let resumeKey = "journal.exportResume"

    init(sources: Sources) {
        self.sources = sources
        leavingObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Without iOS's background task, nothing may carry on once the app has left the
                // screen (Codex review of T10): it stops, and says so.
                guard let self, self.keepOpen, self.work != nil else { return }
                self.cancel()
                self.state = .stopped
            }
        }
        restore()
    }

    isolated deinit {
        if let leavingObserver { NotificationCenter.default.removeObserver(leavingObserver) }
    }

    /// The app's own sources.
    static func live(babyID: String) -> JournalExporter {
        let model = AppModel.shared
        let files = MediaFiles.appGroup()
        return JournalExporter(sources: Sources(
            // Step 1 holds photos only; videos come with step 2 (task T13).
            plan: { leavingOut in model.store.data.journalExport(babyID: babyID, fileExtension: { _ in "jpg" }, leavingOut: leavingOut) },
            files: files,
            fetch: { ids, progress in await model.media.fetchForExport(ids, progress: progress) },
            byteSizes: { model.media.byteSizes() },
            freeSpace: { files?.freeSpace() ?? 0 }))
    }

    var isWorking: Bool { work != nil }

    /// Export, or try again. `skippingMissing`: "Save without these", packing what is here.
    func start(skippingMissing: Bool = false) {
        guard work == nil else { return }
        removeFiles()
        let attempt = UUID()
        self.attempt = attempt
        let leaveOut = skippingMissing ? missingIDs : []
        if !skippingMissing { missingIDs = [] }
        keepOpen = false
        state = skippingMissing ? .packing : .gettingPhotos(done: 0, total: sources.plan([]).items.count)
        work = Task {
            if sources.useBackgroundTask, let identifier = registerBackgroundTask(attempt: attempt, leaveOut: leaveOut) {
                pendingRequest = identifier
                let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Exporting the journal",
                                                               subtitle: skippingMissing ? "Packing the file" : "Getting photos")
                request.strategy = .fail
                if (try? await BGTaskScheduler.shared.submitTaskRequest(request)) != nil {
                    // Accepted: its handler runs the export. If it hasn't begun within 10 seconds,
                    // the request is taken back and it runs here.
                    try? await Task.sleep(for: .seconds(10))
                    guard self.attempt == attempt, begun != attempt else { return }
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
                }
                pendingRequest = nil
            }
            guard self.attempt == attempt, begun != attempt, !Task.isCancelled else { return }
            keepOpen = true
            await export(attempt: attempt, leaveOut: leaveOut)
        }
    }

    /// Cancel: everything made so far goes, and a late answer from iOS changes nothing.
    func cancel() {
        attempt = UUID()
        work?.cancel()
        work = nil
        if let pendingRequest { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: pendingRequest) }
        pendingRequest = nil
        finishBackgroundTask(success: false)
        removeFiles()
        keepOpen = false
        state = .ready
    }

    /// The screen closed: an export under way stops, and the file goes.
    func close() {
        cancel()
        clearResume()
    }

    private func registerBackgroundTask(attempt: UUID, leaveOut: Set<String>) -> String? {
        guard let bundle = Bundle.main.bundleIdentifier else { return nil }
        let identifier = "\(bundle).export.\(attempt.uuidString)"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let task = task as? BGContinuedProcessingTask, self.attempt == attempt, self.begun != attempt else {
                    // An attempt cancelled meanwhile, or already running here: ended at once.
                    task.setTaskCompleted(success: false)
                    return
                }
                self.pendingRequest = nil
                self.backgroundTask = task
                task.expirationHandler = { [weak self] in
                    Task { @MainActor in self?.stoppedByIOS(attempt: attempt) }
                }
                self.work = Task { await self.export(attempt: attempt, leaveOut: leaveOut) }
            }
        }
        return registered ? identifier : nil
    }

    private func export(attempt: UUID, leaveOut: Set<String>) async {
        begun = attempt
        let fullPlan = sources.plan([])
        guard let files = sources.files else {
            state = .missing(Self.titles(fullPlan.items))
            end(success: false)
            return
        }
        let sizes = sources.byteSizes()
        let ids = fullPlan.items.map(\.mediaID).filter { !leaveOut.contains($0) }
        backgroundTask?.progress.totalUnitCount = Int64(ids.count * 2 + 1)
        // Room for what is still to fetch and for the packed file, with the reserve kept (D19);
        // checked again before packing, from the files themselves.
        let toFetch = ids.filter { !files.hasFile($0) }.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }
        let packed = ids.reduce(Int64(0)) { $0 + (sizes[$1] ?? Self.fileSize(files.fileURL($1))) }
        guard SpaceRule.exportFits(toDownload: toFetch, packedFile: packed, free: sources.freeSpace()) else {
            state = .noSpace
            end(success: false)
            return
        }

        if ids.contains(where: { !files.hasFile($0) }) {
            state = .gettingPhotos(done: 0, total: ids.count)
            let missing = await sources.fetch(ids) { [weak self] done in
                guard let self, self.attempt == attempt else { return }
                state = .gettingPhotos(done: done, total: ids.count)
                backgroundTask?.progress.completedUnitCount = Int64(done)
            }
            guard self.attempt == attempt, !Task.isCancelled else { return }
            if !missing.isEmpty {
                showMissing(missing.union(leaveOut), in: fullPlan)
                return
            }
        }
        // A photo that went from this phone since: back to the choice, never a silent gap.
        let gone = ids.filter { !files.hasFile($0) }
        if !gone.isEmpty {
            showMissing(Set(gone).union(leaveOut), in: fullPlan)
            return
        }

        let plan = sources.plan(leaveOut)
        // From the files themselves, with the list and room for the zip's own overhead.
        let needed = plan.items.reduce(Int64(plan.listText.utf8.count)) { $0 + Self.fileSize(files.fileURL($1.mediaID)) }
        guard SpaceRule.fits(needed + needed / 50 + 1_000_000, free: sources.freeSpace()) else {
            state = .noSpace
            end(success: false)
            return
        }
        state = .packing
        backgroundTask?.updateTitle("Exporting the journal", subtitle: "Packing the file")
        let folder = MediaStore.exportsFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.folder = folder
        let base = Int64(ids.count)
        do {
            let zip = try await Self.pack(plan, files: files, into: folder) { [weak self] staged in
                guard let self, self.attempt == attempt else { return }
                backgroundTask?.progress.completedUnitCount = base + Int64(staged)
            }
            guard self.attempt == attempt, !Task.isCancelled else {
                try? FileManager.default.removeItem(at: folder)
                return
            }
            backgroundTask?.progress.completedUnitCount = base * 2 + 1
            state = .done(zip, leftOut: leaveOut.count)
            clearResume()
            end(success: true)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            guard self.attempt == attempt else { return }
            self.folder = nil
            state = Self.isDiskFull(error) ? .noSpace : .stopped
            end(success: false)
        }
    }

    /// Missing items named, and the export not called complete (journal plan); in the background,
    /// the task ends and the parent is told, the list kept for when the app opens (OV8, T21).
    private func showMissing(_ ids: Set<String>, in plan: JournalExportPlan) {
        missingIDs = ids
        state = .missing(Self.titles(plan.items.filter { ids.contains($0.mediaID) }))
        sources.defaults.set(["missing": ids.sorted()], forKey: Self.resumeKey)
        if UIApplication.shared.applicationState != .active {
            Self.notify("Some photos couldn't be fetched for the export. Tap to choose what to do.")
        }
        end(success: false)
    }

    /// iOS ended the background task early: the half-made file goes, and the parent is told.
    private func stoppedByIOS(attempt: UUID) {
        guard self.attempt == attempt else { return }
        self.attempt = UUID()
        work?.cancel()
        work = nil
        removeFiles()
        state = .stopped
        sources.defaults.set(["stopped": true], forKey: Self.resumeKey)
        Self.notify("The export stopped before it finished. Tap to try again.")
        finishBackgroundTask(success: false)
    }

    /// An export a notification was about, after the app was closed: shown as it was left.
    private func restore() {
        guard let saved = sources.defaults.dictionary(forKey: Self.resumeKey) else { return }
        if let ids = saved["missing"] as? [String] {
            // Only items still named by a first and still not on this phone.
            let items = sources.plan([]).items.filter { ids.contains($0.mediaID) && sources.files?.hasFile($0.mediaID) != true }
            guard !items.isEmpty else {
                clearResume()
                return
            }
            missingIDs = Set(items.map(\.mediaID))
            state = .missing(Self.titles(items))
        } else if saved["stopped"] != nil {
            state = .stopped
        }
    }

    private func clearResume() {
        sources.defaults.removeObject(forKey: Self.resumeKey)
    }

    private func end(success: Bool) {
        work = nil
        keepOpen = false
        finishBackgroundTask(success: success)
    }

    private func finishBackgroundTask(success: Bool) {
        backgroundTask?.setTaskCompleted(success: success)
        backgroundTask = nil
    }

    private func removeFiles() {
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
    }

    private static func titles(_ items: [JournalExportPlan.Item]) -> [String] {
        var seen = Set<String>()
        return items.map(\.title).filter { seen.insert($0).inserted }
    }

    /// The export's folder (copies that share storage with the originals, clones), packed into one
    /// file by iOS itself (`NSFileCoordinator`'s `forUploading`, a zip; no third-party code). It
    /// stops when the export is cancelled; the caller deletes `folder` on every way out.
    nonisolated static func pack(_ plan: JournalExportPlan, files: MediaFiles, into folder: URL,
                                 staged: @escaping @MainActor (Int) -> Void) async throws -> URL {
        let packer = Task.detached { () throws -> URL in
            let journal = folder.appendingPathComponent("Journal", isDirectory: true)
            try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
            for (index, item) in plan.items.enumerated() {
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: files.fileURL(item.mediaID), to: journal.appendingPathComponent(item.fileName))
                await staged(index + 1)
            }
            try Data(plan.listText.utf8).write(to: journal.appendingPathComponent(JournalExportPlan.listFileName))
            try Task.checkCancellation()
            let zip = folder.appendingPathComponent("Journal \(Self.today()).zip")
            var coordinatorError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: journal, options: [.forUploading], error: &coordinatorError) { packed in
                do { try FileManager.default.copyItem(at: packed, to: zip) } catch { copyError = error }
            }
            if let error = coordinatorError ?? copyError { throw error }
            try FileManager.default.removeItem(at: journal)
            try Task.checkCancellation()
            return zip
        }
        return try await withTaskCancellationHandler { try await packer.value } onCancel: { packer.cancel() }
    }

    nonisolated private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    nonisolated static func isDiskFull(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) { return true }
        return (error.userInfo[NSUnderlyingErrorKey] as? Error).map(isDiskFull) ?? false
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// The export's notice; a tap opens the Export screen as it was left (`NotificationTaps`).
    nonisolated static let noticeID = "journalExport"

    private static func notify(_ body: String) {
        let content = UNMutableNotificationContent()
        content.body = body
        content.sound = nil
        content.interruptionLevel = .active
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: noticeID, content: content, trigger: nil))
    }
}

/// The Export screen (design review D12): the privacy note and Export; then "Getting photos: 12 of
/// 48" and "Packing the file", with Cancel; then "Save the file". Missing items are named, with
/// "Save without these 3" or "Try again"; an export iOS stopped says so, with "Try again".
struct ExportView: View {
    @State private var exporter: JournalExporter
    @Environment(\.dismiss) private var dismiss

    init(babyID: String) {
        _exporter = State(initialValue: JournalExporter.live(babyID: babyID))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export the journal").feedText(.title).accessibilityAddTraits(.isHeader)
                    content
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Theme.text)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(Theme.text) }
            }
        }
        .onDisappear { exporter.close() }
    }

    @ViewBuilder
    private var content: some View {
        let words = JournalText.export(exporter.state)
        Text(words.heading).feedText(.dayHeading)
        if let detail = words.detail {
            Text(detail).feedText(.body).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        if exporter.keepOpen {
            Text("Keep Feeding open until it finishes: this iPhone didn't let it carry on in the background.")
                .feedText(.subheadline)
                .foregroundStyle(Theme.text)
        }
        switch exporter.state {
        case .ready:
            button("Export") { exporter.start() }
        case .gettingPhotos(let done, let total):
            ProgressView(value: Double(done), total: Double(max(total, 1))).tint(Theme.textMuted)
            button("Cancel") { exporter.cancel() }
        case .packing:
            ProgressView().tint(Theme.textMuted)
            button("Cancel") { exporter.cancel() }
        case .done(let file, _):
            ShareLink(item: file) { label("Save the file") }
                .buttonStyle(PressStyle())
        case .missing(let titles):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(titles, id: \.self) { Text("· \($0)").feedText(.body) }
            }
            button(JournalText.saveWithout(titles.count)) { exporter.start(skippingMissing: true) }
            button("Try again") { exporter.start() }
        case .stopped, .noSpace:
            button("Try again") { exporter.start() }
        }
    }

    private func button(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { label(text) }
            .buttonStyle(PressStyle())
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .feedText(.button)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
