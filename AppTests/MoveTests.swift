import FeedingCore
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeedingDev

/// The move from Feeding Dev to Feeding, on the phone (docs/planning/08-going-live.md): the move
/// file made from Feeding Dev's household and photo folder, then brought into another household
/// and photo folder, as the real app does. Made-up data and pictures only.
@MainActor
@Suite("The move from Little Log Dev, on the phone")
struct MoveTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("move-\(UUID().uuidString)", isDirectory: true)
    let devA: MemberID = "dev-a"
    let devB: MemberID = "dev-b"
    let realA: MemberID = "real-a"
    let realB: MemberID = "real-b"
    let now = Date()

    /// A drawn picture, 3000 by 2000.
    func picture() throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("source.jpg")
        let context = try #require(CGContext(data: nil, width: 3000, height: 2000, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.95, green: 0.6, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    func member(_ id: MemberID, _ name: String) throws -> PlainRecord {
        PlainRecord(type: .member, name: id.rawValue, modifiedAt: now,
                    payload: try PayloadCoder.encode(MemberPayload(displayName: name, colour: "sunflower")))
    }

    /// Feeding Dev: a feed by Parent B, and a first by Parent A with one photo. Returns the move
    /// file, and the photo's and the first's IDs.
    func devMoveFile() async throws -> (url: URL, photo: String, first: String) {
        let devFiles = MediaFiles(folder: folder.appendingPathComponent("DevMedia"))
        let added = try await MediaStore(files: devFiles, freeSpace: { 50_000_000_000 }).addPhoto(from: picture())
        var dev = HouseholdData()
        dev.put(PlainRecord(type: .baby, name: "dev-baby", modifiedAt: now,
                            payload: try PayloadCoder.encode(BabyPayload(name: "Baby"))))
        dev.put(try member(devA, "A"))
        dev.put(try member(devB, "B"))
        dev.startFeed(babyID: "dev-baby", side: .left, by: devB, timeZoneID: "Europe/London", now: now.addingTimeInterval(-3600))
        let firstID = dev.addMilestone(babyID: "dev-baby", title: "First smile", media: [added.id],
                                       at: now.addingTimeInterval(-600), by: devA,
                                       timeZoneID: "Europe/London", now: now.addingTimeInterval(-600))
        let first = try #require(firstID)
        let made = try await HouseholdMover.make(dev, babyID: "dev-baby", me: devA, files: devFiles, free: { 50_000_000_000 },
                                                 now: now) { _ in [] }
        #expect(made.entries == 2)
        #expect(made.media == 1)
        #expect(made.leftOut == 0)
        return (made.url, added.id, first)
    }

    /// Feeding, set up: its own baby, and both parents (or only Parent A).
    func realStore(otherJoined: Bool = true) throws -> HouseholdStore {
        let house = folder.appendingPathComponent("House", isDirectory: true)
        try FileManager.default.createDirectory(at: house, withIntermediateDirectories: true)
        let store = HouseholdStore(fileURL: house.appendingPathComponent("household.json"), alarmsSet: { false })
        let records = [PlainRecord(type: .baby, name: "real-baby", modifiedAt: now,
                                   payload: try PayloadCoder.encode(BabyPayload(name: "Baby"))),
                       try member(realA, "A")] + (otherJoined ? [try member(realB, "B")] : [])
        store.change { data in records.forEach { data.put($0) } }
        return store
    }

    @Test("The entries come in, the photo lands in the folder, and it queues with its first")
    func bringsEverythingIn() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (url, photo, first) = try await devMoveFile()
        let store = try realStore()
        let files = MediaFiles(folder: folder.appendingPathComponent("Media"))
        var queued: [MediaUpload] = []
        let brought = try await HouseholdMover.bringIn(MoveFile.Reader(url: url), store: store, files: files, me: realA,
                                                       uploaded: [], queued: [], free: 50_000_000_000, now: now,
                                                       queue: { queued += $0; return true }, unqueue: { _ in })
        #expect(brought == HouseholdMover.Brought(entries: 2, alreadyHere: 0, media: 1, mediaLeftOut: 0))
        #expect(Set(store.data.allEvents.map(\.loggedBy)) == [realA, realB])
        #expect(Set(store.data.allEvents.map(\.babyID)) == ["real-baby"])
        #expect(store.data.events[first]?.snapshot.payload?.milestone?.media == [photo])
        #expect(files.hasFile(photo) && files.hasThumbnail(photo))
        let devFiles = MediaFiles(folder: folder.appendingPathComponent("DevMedia"))
        #expect(try Data(contentsOf: files.fileURL(photo)) == Data(contentsOf: devFiles.fileURL(photo)))
        #expect(queued.map(\.id) == [photo])
        #expect(queued.first?.eventID == first)
        let details = try #require(PayloadCoder.decode(MediaDetails.self, from: queued.first?.payload))
        #expect(details.kind == .photo)
        #expect(max(details.width, details.height) == 2048)
        #expect(queued.first?.byteSize == MediaStore.fileSize(files.fileURL(photo)) + MediaStore.fileSize(files.thumbnailURL(photo)))

        // The same file again: nothing new, and a photo iCloud has already isn't queued again.
        var again: [MediaUpload] = []
        let second = try await HouseholdMover.bringIn(MoveFile.Reader(url: url), store: store, files: files, me: realA,
                                                      uploaded: [photo], queued: [], free: 50_000_000_000, now: now,
                                                      queue: { again += $0; return true }, unqueue: { _ in })
        #expect(second.entries == 0)
        #expect(second.alreadyHere == 2)
        #expect(again.isEmpty)
    }

    @Test("Without the other parent, or the space, nothing changes and no file is placed")
    func refusedLeavesNothing() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (url, photo, _) = try await devMoveFile()
        let files = MediaFiles(folder: folder.appendingPathComponent("Media"))

        let alone = try realStore(otherJoined: false)
        let before = alone.data
        await #expect(throws: HouseholdMover.Failure.problem(.otherParentMissing)) {
            try await HouseholdMover.bringIn(MoveFile.Reader(url: url), store: alone, files: files, me: realA,
                                             uploaded: [], queued: [], free: 50_000_000_000, now: now,
                                             queue: { _ in true }, unqueue: { _ in })
        }
        #expect(alone.data == before)
        #expect(!files.hasFile(photo))

        let full = try realStore()
        let fullBefore = full.data
        await #expect(throws: HouseholdMover.Failure.notEnoughSpace) {
            try await HouseholdMover.bringIn(MoveFile.Reader(url: url), store: full, files: files, me: realA,
                                             uploaded: [], queued: [], free: SpaceRule.reserveBytes, now: now,
                                             queue: { _ in true }, unqueue: { _ in })
        }
        #expect(full.data == fullBefore)
        #expect(!files.hasFile(photo))
    }

    @Test("The photos are queued before the firsts are saved; if the save fails, they come off again")
    func queueFirstThenSave() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (url, photo, _) = try await devMoveFile()
        let store = try realStore()
        let before = store.data
        let files = MediaFiles(folder: folder.appendingPathComponent("Media"))
        var queue: [String] = []
        var savedWhenQueued: Bool?
        // The household file's folder goes: the save can't be written.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("House"))
        await #expect(throws: HouseholdMover.Failure.notOnPhone) {
            try await HouseholdMover.bringIn(MoveFile.Reader(url: url), store: store, files: files, me: realA,
                                             uploaded: [], queued: [], free: 50_000_000_000, now: now,
                                             queue: { uploads in
                                                 savedWhenQueued = store.data != before
                                                 queue += uploads.map(\.id)
                                                 return true
                                             },
                                             unqueue: { ids in queue.removeAll { ids.contains($0) } })
        }
        #expect(savedWhenQueued == false)
        #expect(queue.isEmpty)
        #expect(store.data == before)
        _ = photo
    }

    @Test("A queue that can't be written stops the move before anything is saved")
    func queueRefused() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (url, _, _) = try await devMoveFile()
        let store = try realStore()
        let before = store.data
        let files = MediaFiles(folder: folder.appendingPathComponent("Media"))
        await #expect(throws: HouseholdMover.Failure.notQueued) {
            try await HouseholdMover.bringIn(MoveFile.Reader(url: url), store: store, files: files, me: realA,
                                             uploaded: [], queued: [], free: 50_000_000_000, now: now,
                                             queue: { _ in false }, unqueue: { _ in })
        }
        #expect(store.data == before)
    }

    @Test("A photo whose thumbnail is missing gets one made, so it still moves")
    func thumbnailMade() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let devFiles = MediaFiles(folder: folder.appendingPathComponent("DevMedia"))
        let added = try await MediaStore(files: devFiles, freeSpace: { 50_000_000_000 }).addPhoto(from: picture())
        try FileManager.default.removeItem(at: devFiles.thumbnailURL(added.id))
        #expect(await HouseholdMover.makeThumbnail(added.id, in: devFiles))
        #expect(devFiles.hasThumbnail(added.id))
        #expect(await HouseholdMover.details(added.id, in: devFiles)?.kind == .photo)
    }

    @Test("The file's name says when, and nothing about the household")
    func fileName() {
        let name = HouseholdMover.fileName(now: now)
        #expect(name.hasPrefix("Little Log move "))
        #expect(name.hasSuffix(".\(MoveFile.fileExtension)"))
    }
}
