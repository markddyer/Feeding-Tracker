import AVFoundation
import FeedingCore
import Foundation
import ImageIO

/// The move from Feeding Dev to Feeding (docs/planning/08-going-live.md): Feeding Dev makes the
/// move file (`MoveFile`), the parent saves it to Files, and the real app on the same phone brings
/// it in. The rules for what moves and how each parent's ID is matched are in FeedingCore
/// (`HouseholdMove`); this is the phone's part: the photo and video files, and the upload queue.
@MainActor
enum HouseholdMover {
    /// The file name: no names in it, so it says nothing about the household in Files.
    static func fileName(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM yyyy HH.mm"
        return "Little Log move \(formatter.string(from: now)).\(MoveFile.fileExtension)"
    }

    /// Move files being made: one at a time, the one before cleared first (Codex review).
    static var movesFolder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Moves", isDirectory: true) }

    // MARK: Making the file (Feeding Dev)

    struct Made: Equatable {
        let url: URL
        let entries: Int
        let media: Int
        /// Photos and videos the firsts show that aren't on this phone and couldn't be fetched.
        let leftOut: Int
    }

    enum MakeFailure: Error, Equatable {
        case notEnoughSpace
        case couldNotWrite
    }

    /// Writes the move file for `babyID`. `fetch` brings any photo or video not on this phone yet;
    /// a thumbnail still missing is made from its file. Refused when the file would eat into the
    /// space kept free for feeds.
    static func make(_ data: HouseholdData, babyID: String, me: MemberID, files: MediaFiles?, free: () -> Int64, now: Date,
                     fetch: ([String]) async -> Set<String>) async throws(MakeFailure) -> Made {
        let move = data.move(babyID: babyID, by: me, now: now)
        let ids = move.mediaIDs
        _ = await fetch(ids)
        var items: [MoveFile.Item] = []
        for id in ids {
            guard let files, files.hasFile(id) else { continue }
            if !files.hasThumbnail(id), !(await makeThumbnail(id, in: files)) { continue }
            items.append(MoveFile.Item(id: id, file: files.fileURL(id), thumbnail: files.thumbnailURL(id)))
        }
        try? FileManager.default.removeItem(at: movesFolder)
        let folder = movesFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(fileName(now: now))
        // The items, and room for the list of entries.
        guard let bytes = try? MoveFile.bytes(of: items), SpaceRule.fits(bytes + 20_000_000, free: free()) else {
            throw .notEnoughSpace
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await Task.detached(priority: .userInitiated) { try MoveFile.write(move, items: items, to: url) }.value
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw .couldNotWrite
        }
        return Made(url: url, entries: move.entries.count, media: items.count, leftOut: ids.count - items.count)
    }

    /// A thumbnail made from an item's file, as `MediaStore` makes them. False if it couldn't be.
    static func makeThumbnail(_ id: String, in files: MediaFiles) async -> Bool {
        let work = MediaStore.workFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        guard (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil else { return false }
        let target = work.appendingPathComponent("thumbnail.jpg")
        let image: CGImage?
        if files.isVideoFile(id) == true {
            let generator = AVAssetImageGenerator(asset: files.videoAsset(id))
            generator.appliesPreferredTrackTransform = true
            let side = CGFloat(MediaSizes.thumbnailLongSide)
            generator.maximumSize = CGSize(width: side, height: side)
            image = try? await generator.image(at: .zero).image
        } else {
            image = CGImageSourceCreateWithURL(files.fileURL(id) as CFURL, nil)
                .flatMap { MediaStore.upright($0, longSide: MediaSizes.thumbnailLongSide) }
        }
        guard let image, MediaStore.writeJPEG(image, to: target, quality: 0.75) else { return false }
        return (try? files.keepThumbnail(from: target, for: id)) != nil
    }

    // MARK: Bringing it in (Feeding)

    struct Brought: Equatable {
        let entries: Int
        let alreadyHere: Int
        let media: Int
        /// Photos and videos in the file that couldn't be put on this phone.
        let mediaLeftOut: Int
    }

    enum Failure: Error, Equatable {
        case problem(MoveProblem)
        case notEnoughSpace
        /// The entries couldn't be written to this phone: nothing changed.
        case notOnPhone
        /// The photos couldn't be queued for iCloud: nothing changed.
        case notQueued
    }

    /// Brings `reader`'s move in: the photo and video files first; then each photo queues for
    /// iCloud with the first that owns it; then the entries, in one checked save. The queue is
    /// written before the firsts (as a first's Save does, task T17), so a first never reaches the
    /// other phone naming a photo nobody will send; a queued photo waits for its first. If the
    /// save fails, what this call queued comes off again and nothing changed. An item iCloud
    /// already has (`uploaded`) or already queued (`queued`) isn't queued again, so bringing the
    /// same file in twice is safe.
    static func bringIn(_ reader: MoveFile.Reader, store: HouseholdStore, files: MediaFiles, me: MemberID,
                        uploaded: Set<String>, queued: Set<String>, free: Int64, now: Date,
                        queue: ([MediaUpload]) -> Bool, unqueue: ([String]) -> Void) async throws(Failure) -> Brought {
        let move = reader.move
        if let problem = store.data.moveProblem(move, me: me) { throw .problem(problem) }
        let owners = move.mediaOwners
        let wanted = move.media.filter { owners[$0.id] != nil }
        // What isn't here yet, and room to copy the largest item through the work folder.
        let missing = wanted.map { item in
            (files.hasFile(item.id) ? 0 : item.file.length) + (files.hasThumbnail(item.id) ? 0 : item.thumbnail.length)
        }
        let largest = wanted.map { $0.file.length + $0.thumbnail.length }.max() ?? 0
        guard SpaceRule.fits(missing.reduce(0, +) + largest, free: free) else { throw .notEnoughSpace }

        var carried: [String: (details: MediaDetails, bytes: Int64)] = [:]
        for item in wanted {
            guard await place(item, from: reader, in: files), let details = await details(item.id, in: files) else { continue }
            carried[item.id] = (details, MediaStore.fileSize(files.fileURL(item.id)) + MediaStore.fileSize(files.thumbnailURL(item.id)))
        }
        let ids = Set(carried.keys)

        // The firsts as the move will leave them, to queue each photo with its first.
        var proposed = store.data
        do throws(MoveProblem) {
            try proposed.bringIn(move, me: me, carried: ids, now: now)
        } catch {
            throw .problem(error)
        }
        let uploads = move.mediaIDs.compactMap { id -> MediaUpload? in
            guard let item = carried[id], !uploaded.contains(id), !queued.contains(id), let first = owners[id],
                  proposed.events[first]?.snapshot.payload?.milestone?.media.contains(id) == true else { return nil }
            return MediaUpload(id: id, eventID: first, byteSize: item.bytes, payload: try? PayloadCoder.encode(item.details),
                               queuedAt: now, pause: nil)
        }
        guard queue(uploads) else { throw .notQueued }

        let (result, saved) = store.changeChecked { data -> Result<MoveOutcome, MoveProblem> in
            do throws(MoveProblem) {
                return .success(try data.bringIn(move, me: me, carried: ids, now: now))
            } catch {
                return .failure(error)
            }
        }
        let outcome: MoveOutcome
        switch (saved, result) {
        case (true, .success(let value)):
            outcome = value
        case (false, _):
            unqueue(uploads.map(\.id))
            throw .notOnPhone
        case (true, .failure(let problem)):
            unqueue(uploads.map(\.id))
            throw .problem(problem)
        }
        return Brought(entries: outcome.addedCount, alreadyHere: outcome.alreadyHere, media: carried.count,
                       mediaLeftOut: move.media.count - carried.count)
    }

    /// Copies the halves of one item not on this phone yet out of the move file into `files`, off
    /// the main actor. False if it couldn't; only what this call wrote is taken away again, never
    /// a file that was here before (Codex review).
    private static func place(_ item: MovedMedia, from reader: MoveFile.Reader, in files: MediaFiles) async -> Bool {
        let needFile = !files.hasFile(item.id)
        let needThumbnail = !files.hasThumbnail(item.id)
        guard needFile || needThumbnail else { return true }
        let work = MediaStore.workFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                if needFile {
                    let file = work.appendingPathComponent("file")
                    try reader.extract(item.file, to: file)
                    try files.keepFile(from: file, for: item.id)
                }
                if needThumbnail {
                    let thumbnail = work.appendingPathComponent("thumbnail")
                    try reader.extract(item.thumbnail, to: thumbnail)
                    try files.keepThumbnail(from: thumbnail, for: item.id)
                }
            }.value
            return true
        } catch {
            if needFile { try? FileManager.default.removeItem(at: files.fileURL(item.id)) }
            if needThumbnail { try? FileManager.default.removeItem(at: files.thumbnailURL(item.id)) }
            return false
        }
    }

    /// What the upload queue needs to know of an item, read from its file: photo or video, its
    /// size in pixels (stored upright), and a video's length. Nil unless the file and its
    /// thumbnail can both be read.
    static func details(_ id: String, in files: MediaFiles) async -> MediaDetails? {
        guard let thumbnail = CGImageSourceCreateWithURL(files.thumbnailURL(id) as CFURL, nil),
              CGImageSourceGetCount(thumbnail) > 0, let isVideo = files.isVideoFile(id) else { return nil }
        if isVideo {
            let asset = files.videoAsset(id)
            guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return nil }
            let size = await MediaStore.uprightSize(asset)
            return MediaDetails(kind: .video, width: size.width, height: size.height, durationSeconds: duration.seconds)
        }
        guard let source = CGImageSourceCreateWithURL(files.fileURL(id) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return MediaDetails(kind: .photo, width: width, height: height)
    }
}
