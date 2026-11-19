import AVFoundation
import CoreTransferable
import FeedingCore
import Foundation
import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

/// Videos made smaller after Save, so Save never waits (design review D16; eng OV3, eng2 D4;
/// tasks T13 and T17). One at a time, only while the app is on screen, never in the time the
/// feeds and alarms need after a push.
///
///     pick ──► original copied into Application Support (staged, kept out of backups; deleted
///              on Discard), a still kept as its thumbnail, so the slot and the line show it
///     Save ──► this queue written (checked), with the household it belongs to ──► the first
///     each video, every step saved before the next (so a stop anywhere carries on later):
///       made smaller (15 s, smaller, no place) ──► queued for iCloud behind the feeds
///         ──► copied to Photos if taken here (D20) ──► the original deleted
///     waits: while its first is held for Undo, missing (a day, as the photo queue), or the file
///            fills again from iCloud; while the phone is too full
///     fails: its ID joins the first's removed list once that is written, so both phones drop
///            the slot; this phone then says "A video couldn't be added"
@MainActor
@Observable
final class VideoQueue {
    struct Job: Codable, Hashable, Sendable {
        var id: String
        /// The first it belongs to; nil while it is a draft in an editor.
        var eventID: String?
        /// The original's file extension ("mov", "mp4"), so AVFoundation reads it.
        var fileExtension: String
        var queuedAt: Date
        /// When it was taken, if the original says (for the first's When).
        var takenAt: Date?
        /// When Save gave it to its first.
        var savedAt: Date?
        /// The account and household it was saved in: sent only there (Codex review of step 2).
        var binding: String?
        /// Taken with the camera here: copied to Photos after Save (D20).
        var takenHere = false
        /// The journal's copy is made; its size and details, for the upload.
        var converted = false
        var byteSize: Int64?
        var details: Data?
        /// Queued for iCloud.
        var handedOff = false
        /// Couldn't be made smaller; its removal from the first is still to be written.
        var failing = false
        /// Couldn't be made smaller, and taken off its first: kept only for the status line.
        var failed = false

        var isPending: Bool { eventID != nil && !failed }
    }

    private(set) var jobs: [Job] = []
    /// The video being made smaller now.
    private(set) var converting: String?

    private let store: HouseholdStore
    private let media: MediaSync
    private let files: MediaFiles?
    private let folder: URL?
    private let queueFile: URL?
    private let me: @MainActor () -> MemberID?
    private var worker: Task<Void, Never>?
    /// The queue file was read (or there was none): untracked originals may be swept at launch.
    private let loaded: Bool
    /// When to look again at a video waiting for its first's Undo.
    private var retry: Task<Void, Never>?

    init(store: HouseholdStore, media: MediaSync, files: MediaFiles?, folder: URL?, queueFile: URL?,
         me: @escaping @MainActor () -> MemberID?) {
        self.store = store
        self.media = media
        self.files = files
        self.folder = folder
        self.queueFile = queueFile
        self.me = me
        if let queueFile, let saved = try? Data(contentsOf: queueFile) {
            if let decoded = try? JSONDecoder().decode([Job].self, from: saved) {
                jobs = decoded
                loaded = true
            } else {
                loaded = false
            }
        } else {
            loaded = true
        }
    }

    /// The app's own: the originals in Application Support (never cleared by iOS like the
    /// temporary folder), kept out of backups, the queue beside them.
    static func live(store: HouseholdStore, media: MediaSync, me: @escaping @MainActor () -> MemberID?) -> VideoQueue {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return VideoQueue(store: store, media: media, files: MediaFiles.appGroup(),
                          folder: support?.appendingPathComponent("JournalVideos", isDirectory: true),
                          queueFile: support?.appendingPathComponent("video-queue.json"), me: me)
    }

    func stagedURL(_ job: Job) -> URL? {
        folder?.appendingPathComponent("\(job.id).\(job.fileExtension)")
    }

    /// True for a video still on its way to iCloud from this phone.
    func isPending(_ id: String) -> Bool { jobs.contains { $0.id == id && $0.isPending && !$0.handedOff } }
    /// True for any video this queue holds.
    func holds(_ id: String) -> Bool { jobs.contains { $0.id == id } }

    func pending(of eventID: String) -> [Job] { jobs.filter { $0.eventID == eventID && $0.isPending && !$0.handedOff } }
    func failed(of eventID: String) -> [Job] { jobs.filter { $0.eventID == eventID && $0.failed } }

    /// The parent has read "A video couldn't be added": it goes.
    func clearFailures(of eventID: String) {
        jobs.removeAll { $0.eventID == eventID && $0.failed }
        save()
    }

    // MARK: The editor

    /// A video picked or taken: the original copied into the staging folder (the space kept free
    /// for feeds checked first, D19), a still kept as its thumbnail, held as a draft so the
    /// clean-up leaves it. Nothing is kept unless the queue is written too.
    func stage(_ source: URL, takenHere: Bool = false) async throws -> Job {
        guard let folder, let files else { throw MediaStore.Refusal.unreadableVideo }
        let id = UUID().uuidString
        media.holdDraft(id)
        let fileExtension = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let staged = folder.appendingPathComponent("\(id).\(fileExtension)")
        do {
            let size = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            guard SpaceRule.fits(size + 2 * MediaSizes.videoAim, free: files.freeSpace()) else {
                throw MediaStore.Refusal.notEnoughSpace
            }
            try makeFolder(folder)
            try await Task.detached { try FileManager.default.copyItem(at: source, to: staged) }.value
            let asset = AVURLAsset(url: staged)
            guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else {
                throw MediaStore.Refusal.unreadableVideo
            }
            try await keepStill(of: asset, id: id, files: files)
            media.noteFileChanged(id)
            let job = Job(id: id, eventID: nil, fileExtension: fileExtension, queuedAt: Date(),
                          takenAt: await MediaStore.videoDate(asset), takenHere: takenHere)
            jobs.append(job)
            guard save() else {
                jobs.removeAll { $0.id == id }
                throw MediaStore.Refusal.notEnoughSpace
            }
            return job
        } catch {
            try? FileManager.default.removeItem(at: staged)
            files.remove(id)
            media.releaseDraft(id)
            throw error is MediaStore.Refusal ? error : MediaStore.Refusal.unreadableVideo
        }
    }

    /// The parent trimmed a long video to the 15 seconds to keep: its original is that part now.
    func replaceStaged(_ id: String, with trimmed: URL) async throws {
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.eventID == nil }), let files,
              let staged = stagedURL(jobs[index]) else { return }
        let target = staged.deletingPathExtension().appendingPathExtension(trimmed.pathExtension.isEmpty ? "mov" : trimmed.pathExtension)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: trimmed, to: target)
        if target != staged { try? FileManager.default.removeItem(at: staged) }
        jobs[index].fileExtension = target.pathExtension
        try await keepStill(of: AVURLAsset(url: target), id: id, files: files)
        media.noteFileChanged(id)
        save()
    }

    private func makeFolder(_ folder: URL) throws {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Originals can hold a place: never in a backup (Codex review of step 2).
        var folderURL = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folderURL.setResourceValues(values)
    }

    /// The still a slot and the Journal's line show until the video is ready.
    private func keepStill(of asset: AVURLAsset, id: String, files: MediaFiles) async throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let side = CGFloat(MediaSizes.thumbnailLongSide)
        generator.maximumSize = CGSize(width: side, height: side)
        let still = try await generator.image(at: .zero).image
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("still-\(id).jpg")
        defer { try? FileManager.default.removeItem(at: work) }
        guard MediaStore.writeJPEG(still, to: work, quality: 0.75) else { throw MediaStore.Refusal.unreadableVideo }
        try files.keepThumbnail(from: work, for: id)
    }

    /// Discard, or taken out in the editor: the draft goes, original and still.
    func discard(_ id: String) {
        guard let job = jobs.first(where: { $0.id == id }), job.eventID == nil else { return }
        if let staged = stagedURL(job) { try? FileManager.default.removeItem(at: staged) }
        jobs.removeAll { $0.id == id }
        save()
        media.forget(id)
    }

    /// Undo of an add: the first never left this phone, so its videos go.
    func forget(_ id: String) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        if let staged = stagedURL(job) { try? FileManager.default.removeItem(at: staged) }
        jobs.removeAll { $0.id == id }
        save()
    }

    /// Save: these drafts now belong to `eventID` and to this account and household, in one
    /// checked write, before the first is written. False, and nothing changed, if it couldn't be.
    func commit(_ ids: [String], to eventID: String) -> Bool {
        guard !ids.isEmpty else { return true }
        let before = jobs
        let now = Date()
        let binding = media.currentBinding()
        for index in jobs.indices where ids.contains(jobs[index].id) {
            jobs[index].eventID = eventID
            jobs[index].savedAt = now
            jobs[index].binding = binding
        }
        guard save() else {
            jobs = before
            return false
        }
        return true
    }

    /// The first couldn't be saved after all: drafts again.
    func uncommit(_ ids: [String]) {
        for index in jobs.indices where ids.contains(jobs[index].id) {
            jobs[index].eventID = nil
            jobs[index].savedAt = nil
        }
        save()
    }

    // MARK: Launch and the work

    /// At launch: drafts an editor left (the app was stopped) go, and any original no job names;
    /// saved ones carry on when the app is on screen.
    func launch() {
        for job in jobs where job.eventID == nil {
            if let staged = stagedURL(job) { try? FileManager.default.removeItem(at: staged) }
            files?.remove(job.id)
        }
        if jobs.contains(where: { $0.eventID == nil }) {
            jobs.removeAll { $0.eventID == nil }
            save()
        }
        if loaded, let folder {
            let named = Set(jobs.compactMap { stagedURL($0)?.lastPathComponent })
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where !named.contains(name) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
        kick()
    }

    /// Starts the work unless it is going. Only with the app on screen: a push that wakes the app
    /// is the feeds' and alarms' time (Codex review of step 2).
    func kick() {
        guard worker == nil, UIApplication.shared.applicationState != .background else { return }
        worker = Task { [weak self] in
            var passed = Set<String>()
            while let self, !Task.isCancelled,
                  let job = jobs.first(where: { $0.isPending && !passed.contains($0.id) }) {
                passed.insert(job.id)
                guard await step(job.id) else { break }
            }
            self?.worker = nil
        }
    }

    /// The app left the screen: the video being made stops, and carries on next time.
    func stop() {
        worker?.cancel()
    }

    private enum Readiness { case go, wait(until: Date?), drop }

    /// Whether a video may be worked on now. Its first held for Undo, or not here yet (Save
    /// stopped between its writes, or the file filling again), makes it wait; only a first that
    /// left it out for good drops it.
    private func readiness(_ job: Job, now: Date = Date()) -> Readiness {
        guard let eventID = job.eventID else { return .wait(until: nil) }
        let data = store.data
        if data.isWaitingForICloud(now: now) { return .wait(until: nil) }
        let grace = now.timeIntervalSince(job.savedAt ?? job.queuedAt) > 86_400
        guard let stored = data.events[eventID] else { return grace ? .drop : .wait(until: nil) }
        let milestone = stored.snapshot.payload?.milestone
        if stored.event.deletedAt == nil, milestone?.media.contains(job.id) == true { return .go }
        if let held = stored.heldUndo, held.media.contains(job.id) || held.addedRemovals.contains(job.id),
           let until = stored.uploadNotBefore, until > now {
            return .wait(until: until)
        }
        if stored.event.deletedAt != nil || milestone?.removedMedia.contains(job.id) == true { return .drop }
        return grace ? .drop : .wait(until: nil)
    }

    /// One step further for a video. False to stop for now (a write that failed, or the app
    /// leaving the screen): it carries on at the next kick.
    private func step(_ id: String) async -> Bool {
        guard let job = jobs.first(where: { $0.id == id }) else { return true }
        if job.failing { return writeFailure(job) }
        switch readiness(job) {
        case .drop:
            drop(job)
            return true
        case .wait(let until):
            if let until { lookAgain(at: until) }
            return true
        case .go:
            break
        }
        guard let files else { return false }
        if !job.converted {
            guard let staged = stagedURL(job), FileManager.default.fileExists(atPath: staged.path) else {
                markFailing(job)
                return writeFailure(job)
            }
            converting = job.id
            var assertion = UIBackgroundTaskIdentifier.invalid
            assertion = UIApplication.shared.beginBackgroundTask(withName: "A video for the journal") { [weak self] in
                MainActor.assumeIsolated {
                    // Out of time: the work stops and carries on next time; the assertion ends now.
                    self?.worker?.cancel()
                    UIApplication.shared.endBackgroundTask(assertion)
                    assertion = .invalid
                }
            }
            defer {
                if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
                converting = nil
            }
            let added: MediaStore.Added
            do {
                added = try await MediaStore(files: files).addVideo(from: staged, id: job.id, sourceAlreadyKept: true)
            } catch MediaStore.Refusal.notEnoughSpace {
                // Waits until there is room; never given up for that.
                return true
            } catch {
                if Task.isCancelled { return false }
                markFailing(job)
                return writeFailure(job)
            }
            // Looked at again now it is made: a first deleted meanwhile drops it.
            if case .drop = readiness(job) {
                drop(job)
                return true
            }
            guard update(job.id, { $0.converted = true; $0.byteSize = added.byteSize
                                   $0.details = try? PayloadCoder.encode(added.details) }) else { return false }
            media.noteFileChanged(job.id)
        }
        if let current = jobs.first(where: { $0.id == id }), !current.handedOff {
            let upload = MediaUpload(id: current.id, eventID: current.eventID ?? "", byteSize: current.byteSize ?? 0,
                                     payload: current.details, queuedAt: Date(), pause: nil, binding: current.binding)
            guard media.add(upload) else { return false }
            guard update(current.id, { $0.handedOff = true }) else { return false }
        }
        finishIfDone(id)
        return true
    }

    /// Done with it once it is on its way to iCloud and, if taken here, in Photos.
    private func finishIfDone(_ id: String) {
        guard let job = jobs.first(where: { $0.id == id }), job.handedOff, !job.takenHere else { return }
        if let staged = stagedURL(job) { try? FileManager.default.removeItem(at: staged) }
        jobs.removeAll { $0.id == id }
        save()
    }

    /// Videos taken here and saved: copied to Photos from their originals (asked after Save,
    /// D20), at Save and again after a stop.
    func copyTakenToPhotos() async {
        for job in jobs where job.takenHere && job.eventID != nil && !job.failed {
            guard let staged = stagedURL(job), FileManager.default.fileExists(atPath: staged.path) else {
                update(job.id) { $0.takenHere = false }
                continue
            }
            await PhotosCopy.keepVideo(staged, deleteAfter: false)
            update(job.id) { $0.takenHere = false }
            finishIfDone(job.id)
        }
    }

    private func drop(_ job: Job) {
        if let staged = stagedURL(job) { try? FileManager.default.removeItem(at: staged) }
        if !job.handedOff { files?.remove(job.id) }
        jobs.removeAll { $0.id == job.id }
        save()
    }

    private func markFailing(_ job: Job) {
        update(job.id) { $0.failing = true }
    }

    /// The failure written into the first (its ID on the removed list), so both phones drop the
    /// slot; only then is it told. Until it can be (no account yet, the file filling again, a
    /// write that failed), it stays to be tried again.
    private func writeFailure(_ job: Job) -> Bool {
        guard let eventID = job.eventID, let me = me() else { return true }
        let data = store.data
        if data.isWaitingForICloud(now: Date()) { return true }
        if data.events[eventID] != nil {
            let (_, saved) = store.changeChecked { $0.dropFailedMedia(job.id, from: eventID, by: me, now: Date()) }
            guard saved else { return false }
        }
        if let staged = stagedURL(job) { try? FileManager.default.removeItem(at: staged) }
        files?.remove(job.id)
        update(job.id) {
            $0.failing = false
            $0.failed = data.events[eventID] != nil
        }
        if data.events[eventID] == nil { jobs.removeAll { $0.id == job.id } }
        save()
        SyncLog.add("media: a video couldn't be made smaller; taken off its first")
        return true
    }

    private func lookAgain(at date: Date) {
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, date.timeIntervalSinceNow + 1)))
            guard !Task.isCancelled else { return }
            self?.kick()
        }
    }

    /// Changes a job and saves the queue; false (the change kept in memory) if it couldn't be.
    @discardableResult
    private func update(_ id: String, _ change: (inout Job) -> Void) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return false }
        change(&jobs[index])
        return save()
    }

    @discardableResult
    private func save() -> Bool {
        guard let queueFile, let encoded = try? JSONEncoder().encode(jobs) else { return false }
        do {
            try FileManager.default.createDirectory(at: queueFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: queueFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }
}

/// A video from the photo picker, copied out of the picker's own file at once.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
extension VideoQueue.Job: Identifiable {}
