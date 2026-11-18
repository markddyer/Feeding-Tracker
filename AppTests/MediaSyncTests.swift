import CloudKit
import FeedingCore
import Foundation
import Testing
@testable import FeedingDev

/// The parts of `MediaSync` and `MediaFiles` a simulator can check (journal task T6). The
/// photos share and the transfers themselves are checked on the two phones (task T14).
@Suite("Photos in iCloud")
struct MediaSyncTests {
    /// The journal plan's error map: what each iCloud error means for a photo or video.
    @Test func eachErrorMeansTheRightThing() {
        #expect(MediaFailure(CKError(.serverRecordChanged)) == .clash)
        #expect(MediaFailure(CKError(.networkUnavailable)) == .retryLater(after: nil))
        #expect(MediaFailure(CKError(.networkFailure)) == .retryLater(after: nil))
        #expect(MediaFailure(CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 7.0])) == .retryLater(after: 7))
        #expect(MediaFailure(CKError(.quotaExceeded)) == .iCloudFull)
        #expect(MediaFailure(CKError(.zoneNotFound)) == .zoneMissing)
        #expect(MediaFailure(CKError(.userDeletedZone)) == .zoneMissing)
        #expect(MediaFailure(CKError(.permissionFailure)) == .notSharedYet)
        #expect(MediaFailure(CKError(.participantMayNeedVerification)) == .notSharedYet)
        #expect(MediaFailure(CKError(.unknownItem)) == .missing)
        #expect(MediaFailure(CKError(.changeTokenExpired)) == .tokenExpired)
        #expect(MediaFailure(CKError(.operationCancelled)) == .stopped)
        #expect(MediaFailure(CancellationError()) == .stopped)
        #expect(MediaFailure(MediaRunStop()) == .stopped)
        #expect(MediaFailure(UnreadableTally()) == .refused)
        #expect(MediaFailure(CKError(.limitExceeded)) == .refused)
        #expect(MediaFailure(CocoaError(.fileNoSuchFile)) == .refused)
    }

    /// An all-or-nothing save that clashed on the tally is read as a clash (so the tally is read
    /// again), not as the record that failed only because the other one did. The reading again is
    /// checked on the two phones (task T14).
    @Test func aClashInsideAnAllOrNothingSaveIsReadAsAClash() {
        let error = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [
            CKRecord.ID(recordName: "media-1"): CKError(.batchRequestFailed),
            CKRecord.ID(recordName: "mediaTally"): CKError(.serverRecordChanged),
        ]])
        #expect(MediaFailure(error) == .clash)
    }

    /// An item queued is still queued after the app starts again; one refused is tried again.
    @MainActor
    @Test func theUploadListIsKeptBetweenLaunches() throws {
        let suite = "media-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HouseholdStore()
        let household = HouseholdSync(store: store)
        let item = MediaUpload(id: "media-1", eventID: "event-1", byteSize: 2_345_678, payload: Data([1, 2]),
                               queuedAt: Date(timeIntervalSince1970: 1_794_650_000), pause: nil, binding: "_parentA|__defaultOwner__")
        let first = MediaSync(store: store, household: household, files: nil, defaults: defaults)
        first.add(item)
        first.add(MediaUpload(id: "media-2", eventID: "event-1", byteSize: 10, payload: nil, queuedAt: item.queuedAt,
                              pause: .refused, binding: "_parentA|__defaultOwner__"))
        first.stop()
        let again = MediaSync(store: store, household: household, files: nil, defaults: defaults)
        #expect(again.uploads.map(\.id) == ["media-1", "media-2"])
        #expect(again.uploads.first == item)
        #expect(again.uploads.last?.pause == nil)
    }

    @Test func aShareWithNoParentsNamesNone() {
        #expect(MediaSync.parentIDs(nil).isEmpty)
    }

    /// A file CloudKit downloaded is copied in under the item's ID, and goes with its thumbnail.
    @Test func filesAreKeptByTheItemsIDAndRemovedTogether() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("media-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = MediaFiles(folder: folder)
        let download = FileManager.default.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString)")
        try Data([1, 2, 3]).write(to: download)
        defer { try? FileManager.default.removeItem(at: download) }
        try files.keepFile(from: download, for: "media-1")
        try files.keepThumbnail(from: download, for: "media-1")
        #expect(files.hasFile("media-1"))
        #expect(files.hasThumbnail("media-1"))
        #expect(try Data(contentsOf: files.fileURL("media-1")) == Data([1, 2, 3]))
        // CloudKit's own copy is left alone.
        #expect(FileManager.default.fileExists(atPath: download.path))
        #expect(files.storedIDs() == ["media-1"])
        files.remove("media-1")
        #expect(!files.hasFile("media-1"))
        #expect(!files.hasThumbnail("media-1"))
        #expect(files.freeSpace() > 0)
    }

    /// A copy left half-made by an app that was stopped is cleared away.
    @Test func halfMadeCopiesAreClearedAway() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("media-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1]).write(to: folder.appendingPathComponent("abc.part"))
        try Data([1]).write(to: folder.appendingPathComponent("media-9.thumbnail"))
        let files = MediaFiles(folder: folder)
        #expect(files.storedIDs() == ["media-9"])
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("abc.part").path))
    }
}
