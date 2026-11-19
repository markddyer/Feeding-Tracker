import AVFoundation
import FeedingCore
import Foundation
import Testing
@testable import FeedingDev

/// Videos made smaller after Save (step 2, design review D16; eng2 D4; tasks T13, T17).
@Suite("Videos after Save")
@MainActor
struct VideoQueueTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("videos-\(UUID().uuidString)")
    let me: MemberID = "parent-a"

    /// A short clip, as a phone camera writes one.
    func clip(seconds: Double = 2) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("clip-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<Int(seconds * 10) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 7 % 255), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    /// A household on a stand-in file, its photo sync and the video queue, all in `folder`.
    func parts(me: MemberID? = "parent-a") throws -> (store: HouseholdStore, media: MediaSync, files: MediaFiles, videos: VideoQueue, suite: String) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "videos-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = HouseholdStore(fileURL: folder.appendingPathComponent("household.json"), alarmsSet: { false })
        let files = MediaFiles(folder: folder.appendingPathComponent("Media"))
        let media = MediaSync(store: store, household: HouseholdSync(store: store), files: files, defaults: defaults,
                              queueFile: folder.appendingPathComponent("media-uploads.json"))
        return (store, media, files, queue(store: store, media: media, files: files, me: me), suite)
    }

    /// The queue as a new launch reads it from its file.
    func queue(store: HouseholdStore, media: MediaSync, files: MediaFiles, me: MemberID? = "parent-a") -> VideoQueue {
        VideoQueue(store: store, media: media, files: files, folder: folder.appendingPathComponent("Staged"),
                   queueFile: folder.appendingPathComponent("video-queue.json"), me: { me })
    }

    func settled(_ videos: VideoQueue) async {
        for _ in 0..<1_000 {
            try? await Task.sleep(for: .milliseconds(20))
            if videos.converting == nil, !videos.jobs.contains(where: { $0.isPending && !$0.handedOff && !$0.failing }) { break }
        }
        try? await Task.sleep(for: .milliseconds(100))
    }

    func addFirst(_ store: HouseholdStore, media: [String], now: Date = Date()) -> String? {
        store.changeChecked {
            $0.addMilestone(id: "first-1", babyID: "baby", title: "First smile", media: media, at: now - 600, by: me,
                            timeZoneID: "Europe/London", now: now)
        }.result
    }

    /// Picked: staged with its still at once, out of backups. Saved: made smaller, queued for
    /// iCloud, the original gone; the journal's copy is a video.
    @Test func aSavedVideoIsMadeSmallerAndQueued() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, media, files, videos, suite) = try parts()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let job = try await videos.stage(try await clip())
        #expect(files.hasThumbnail(job.id))
        #expect(!files.hasFile(job.id))
        let staged = try #require(videos.stagedURL(job))
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(try staged.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(videos.commit([job.id], to: "first-1"))
        #expect(addFirst(store, media: [job.id]) == "first-1")
        videos.kick()
        await settled(videos)
        #expect(videos.jobs.isEmpty)
        #expect(media.uploads.map(\.id) == [job.id])
        #expect(files.isVideoFile(job.id) == true)
        #expect(media.kind(of: job.id) == .video)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    /// The app stopped after Save: a new launch reads the queue from its file and carries on.
    @Test func aVideoSavedBeforeAStopIsMadeAfterIt() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, media, files, videos, suite) = try parts()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let job = try await videos.stage(try await clip())
        #expect(videos.commit([job.id], to: "first-1"))
        #expect(addFirst(store, media: [job.id]) == "first-1")
        let relaunched = queue(store: store, media: media, files: files)
        relaunched.launch()
        await settled(relaunched)
        #expect(media.uploads.map(\.id) == [job.id])
        #expect(relaunched.jobs.isEmpty)
    }

    /// Made smaller and on the way to iCloud before a stop: never made again, never failed, and
    /// its copy kept (Codex review of step 2).
    @Test func aVideoAlreadyMadeIsNeverMadeAgainOrLost() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, media, files, videos, suite) = try parts()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let job = try await videos.stage(try await clip())
        #expect(videos.commit([job.id], to: "first-1"))
        #expect(addFirst(store, media: [job.id]) == "first-1")
        videos.kick()
        await settled(videos)
        #expect(media.uploads.map(\.id) == [job.id])
        // As if the app stopped before the original went: the job is back, made and handed over.
        var made = job
        made.eventID = "first-1"
        made.savedAt = Date()
        made.converted = true
        made.handedOff = true
        let staged = try #require(videos.stagedURL(made))
        try FileManager.default.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: staged)
        try JSONEncoder().encode([made]).write(to: folder.appendingPathComponent("video-queue.json"))
        let relaunched = queue(store: store, media: media, files: files)
        relaunched.launch()
        await settled(relaunched)
        #expect(relaunched.jobs.isEmpty)
        #expect(files.isVideoFile(job.id) == true)
        #expect(media.uploads.map(\.id) == [job.id])
        #expect(store.data.events["first-1"]?.snapshot.payload?.milestone?.media == [job.id])
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    /// Eng2 D4: one that can't be made smaller leaves the first on both phones, and is told here.
    @Test func aVideoThatCantBeMadeSmallerLeavesItsFirst() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, media, _, videos, suite) = try parts()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let job = try await videos.stage(try await clip())
        try Data("not a video".utf8).write(to: try #require(videos.stagedURL(job)))
        #expect(videos.commit([job.id], to: "first-1"))
        #expect(addFirst(store, media: [job.id]) == "first-1")
        videos.kick()
        await settled(videos)
        let details = store.data.events["first-1"]?.snapshot.payload?.milestone
        #expect(details?.media == [])
        #expect(details?.removedMedia == [job.id])
        #expect(videos.failed(of: "first-1").map(\.id) == [job.id])
        #expect(media.uploads.isEmpty)
        videos.clearFailures(of: "first-1")
        #expect(videos.jobs.isEmpty)
    }

    /// The failure is told only once it is written into the first: with no account known yet, it
    /// waits, and the first still names it; once known, it is written (Codex review of step 2).
    @Test func aFailureWaitsUntilItCanBeWritten() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, media, files, videos, suite) = try parts(me: nil)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let job = try await videos.stage(try await clip())
        try Data("not a video".utf8).write(to: try #require(videos.stagedURL(job)))
        #expect(videos.commit([job.id], to: "first-1"))
        #expect(addFirst(store, media: [job.id]) == "first-1")
        videos.kick()
        await settled(videos)
        #expect(videos.jobs.first?.failing == true)
        #expect(videos.failed(of: "first-1").isEmpty)
        #expect(store.data.events["first-1"]?.snapshot.payload?.milestone?.media == [job.id])
        let known = queue(store: store, media: media, files: files)
        known.kick()
        await settled(known)
        #expect(known.failed(of: "first-1").map(\.id) == [job.id])
        #expect(store.data.events["first-1"]?.snapshot.payload?.milestone?.removedMedia == [job.id])
    }

    /// Taken out in an edit still held for Undo: it waits, original kept; Undo brings it back and
    /// it is made (Codex review of step 2).
    @Test func aVideoTakenOutWaitsWhileUndoCanBringItBack() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, media, _, videos, suite) = try parts()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let job = try await videos.stage(try await clip())
        #expect(videos.commit([job.id], to: "first-1"))
        #expect(addFirst(store, media: [job.id], now: Date() - 120) == "first-1")
        let original = try #require(store.data.events["first-1"]?.snapshot)
        store.changeChecked {
            $0.editMilestone("first-1", from: original, title: "First smile", note: nil, media: [], at: original.event.startedAt,
                             by: me, now: Date())
        }
        videos.kick()
        // Inside the 10-second Undo: it waits, nothing made, nothing deleted.
        try await Task.sleep(for: .milliseconds(800))
        let staged = try #require(videos.stagedURL(job))
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(videos.holds(job.id))
        #expect(media.uploads.isEmpty)
        let undone = store.changeChecked { $0.undoHeld("first-1", by: me, now: Date()) }
        #expect(undone.result)
        videos.kick()
        await settled(videos)
        #expect(media.uploads.map(\.id) == [job.id])
    }

    /// A first deleted for good (its Undo over): its video is never made, and its original goes.
    @Test func aVideoWhoseFirstWasDeletedIsNotMade() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, media, _, videos, suite) = try parts()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let job = try await videos.stage(try await clip())
        #expect(videos.commit([job.id], to: "first-1"))
        #expect(addFirst(store, media: [job.id], now: Date() - 120) == "first-1")
        store.changeChecked { $0.deleteMilestone("first-1", by: me, now: Date() - 60) }
        videos.kick()
        await settled(videos)
        #expect(videos.jobs.isEmpty)
        #expect(media.uploads.isEmpty)
    }

    /// Discard: the draft goes, original and still. A draft an editor left, and any original no
    /// job names, go at the next launch.
    @Test func draftsAndUntrackedOriginalsGo() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (_, _, files, videos, suite) = try parts()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let discarded = try await videos.stage(try await clip())
        let discardedFile = try #require(videos.stagedURL(discarded))
        videos.discard(discarded.id)
        #expect(!FileManager.default.fileExists(atPath: discardedFile.path))
        #expect(!files.hasThumbnail(discarded.id))
        let left = try await videos.stage(try await clip())
        let leftFile = try #require(videos.stagedURL(left))
        let stray = leftFile.deletingLastPathComponent().appendingPathComponent("stray.mov")
        try Data("x".utf8).write(to: stray)
        videos.launch()
        #expect(videos.jobs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: leftFile.path))
        #expect(!FileManager.default.fileExists(atPath: stray.path))
    }
}
