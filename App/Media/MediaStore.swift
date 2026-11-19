import AVFoundation
import FeedingCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Makes the journal's own copy of a photo or video a parent picked or took (journal plan,
/// "Photos never fill iCloud by surprise" and "No location data"; task T7):
/// - a photo: at most 2048 pixels on its long side, as JPEG (a HEIC photo is converted in the same
///   step; a Live Photo arrives from the picker as its still photo), with no metadata at all, so
///   no place;
/// - a video (a screen recording too): its first 15 seconds, made smaller (aiming at 720p and
///   under 8 MB, with sound), with the place and other personal metadata removed;
/// - a thumbnail of at most 400 pixels for each.
/// The place is removed here, once, so Share and the export send the stored file as it is (D17).
/// It reads the time the item was taken before that, for the first's "When" (design review D17).
/// Nothing is made when it would eat into the space kept free for feeds (D19).
struct MediaStore: Sendable {
    let files: MediaFiles
    /// Free space now, in bytes (a stand-in in tests).
    let freeSpace: @Sendable () -> Int64

    init(files: MediaFiles, freeSpace: (@Sendable () -> Int64)? = nil) {
        self.files = files
        self.freeSpace = freeSpace ?? { files.freeSpace() }
    }

    /// The journal's copy, in `MediaFiles`, ready to queue (`MediaSync.add`).
    struct Added: Sendable, Equatable {
        let id: String
        let details: MediaDetails
        /// The file and the thumbnail together, for the household allowance.
        let byteSize: Int64
        /// When it was taken, if the source says, for the first's "When". Never stored.
        let takenAt: Date?
    }

    /// Why an item wasn't added. The first is kept either way.
    enum Refusal: Error, Equatable {
        /// "This photo couldn't be added."
        case unreadablePhoto
        /// "This video couldn't be added."
        case unreadableVideo
        /// "Not enough space on this iPhone."
        case notEnoughSpace
    }

    // MARK: Work folders (outside voice OE8)

    /// Work in progress, in the app's own temporary folder.
    static var workFolder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("MediaWork", isDirectory: true) }
    /// Exports being made (task T10).
    static var exportsFolder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true) }

    /// At launch: work and half-made exports left by an app that was stopped go.
    static func removeLeftovers() {
        try? FileManager.default.removeItem(at: workFolder)
        try? FileManager.default.removeItem(at: exportsFolder)
    }

    // MARK: Photos

    func addPhoto(from source: URL, id: String = UUID().uuidString) async throws -> Added {
        try needSpace(Self.fileSize(source) + 2_000_000)
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw Refusal.unreadablePhoto }
        return try await addPhoto(image, id: id)
    }

    /// A photo straight from memory (the picker's or the camera's bytes): the original, with its
    /// place, is never written to the phone (Codex review of T7 and T8).
    func addPhoto(data: Data, id: String = UUID().uuidString) async throws -> Added {
        try needSpace(Int64(data.count) + 2_000_000)
        guard let image = CGImageSourceCreateWithData(data as CFData, nil) else { throw Refusal.unreadablePhoto }
        return try await addPhoto(image, id: id)
    }

    private func addPhoto(_ image: CGImageSource, id: String) async throws -> Added {
        guard CGImageSourceGetCount(image) > 0,
              let full = Self.upright(image, longSide: MediaSizes.photoLongSide),
              let thumbnail = Self.upright(image, longSide: MediaSizes.thumbnailLongSide) else {
            throw Refusal.unreadablePhoto
        }
        let takenAt = Self.photoDate(image)
        let work = try Self.makeWorkFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let fileURL = work.appendingPathComponent("file.jpg")
        let thumbnailURL = work.appendingPathComponent("thumbnail.jpg")
        guard Self.writeJPEG(full, to: fileURL, quality: 0.82), Self.writeJPEG(thumbnail, to: thumbnailURL, quality: 0.75) else {
            throw Refusal.unreadablePhoto
        }
        try keep(file: fileURL, thumbnail: thumbnailURL, id: id)
        return Added(id: id, details: MediaDetails(kind: .photo, width: full.width, height: full.height),
                     byteSize: Self.fileSize(fileURL) + Self.fileSize(thumbnailURL), takenAt: takenAt)
    }

    /// The image upright, at most `longSide` pixels on its long side (never made larger).
    static func upright(_ source: CGImageSource, longSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A JPEG with the pixels only: no metadata is written, so no place.
    static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// When a photo was taken: its camera time with the time zone it was taken in, or the GPS
    /// clock's time (UTC). With neither, the moment isn't known for sure, so nil: a photo taken
    /// abroad would otherwise be read in this phone's zone and could land on the wrong day.
    static func photoDate(_ source: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let zone = (exif[kCGImagePropertyExifOffsetTimeOriginal] as? String).flatMap(timeZone(offset:)) {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.timeZone = zone
            if let date = formatter.date(from: taken) { return date }
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let day = gps[kCGImagePropertyGPSDateStamp] as? String, let time = gps[kCGImagePropertyGPSTimeStamp] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.date(from: "\(day) \(time.prefix(8))")
        }
        return nil
    }

    /// "+01:00" or "-05:30" as a time zone; nil for anything else ("+01:90", "+25:00").
    static func timeZone(offset: String) -> TimeZone? {
        let parts = offset.dropFirst().split(separator: ":")
        guard let sign = offset.first, sign == "+" || sign == "-", parts.count == 2,
              parts[0].count == 2, parts[1].count == 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]), (0...14).contains(hours), (0..<60).contains(minutes)
        else { return nil }
        return TimeZone(secondsFromGMT: (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60))
    }

    // MARK: Videos

    func addVideo(from source: URL, id: String = UUID().uuidString) async throws -> Added {
        try needSpace(Self.fileSize(source) + 2 * MediaSizes.videoAim)
        let asset = AVURLAsset(url: source)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty,
              let duration = try? await asset.load(.duration), duration.seconds > 0 else {
            throw Refusal.unreadableVideo
        }
        let takenAt = await Self.videoDate(asset)
        let length = min(duration.seconds, MediaSizes.longestVideo)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: length, preferredTimescale: 600))
        let work = try Self.makeWorkFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        // Smaller steps until it is under the aim; refused if even the smallest isn't.
        var made: URL?
        for (step, preset) in [AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPresetMediumQuality].enumerated() {
            let output = work.appendingPathComponent("video-\(step).mp4")
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            session.timeRange = range
            session.metadata = []
            session.metadataItemFilter = .forSharing()
            session.shouldOptimizeForNetworkUse = true
            do {
                try await session.export(to: output, as: .mp4)
            } catch {
                continue
            }
            if Self.fileSize(output) <= MediaSizes.videoAim {
                made = output
                break
            }
            // Too big: gone before the next, smaller try, so the work never piles up.
            try? FileManager.default.removeItem(at: output)
        }
        guard let made else { throw Refusal.unreadableVideo }
        let copy = AVURLAsset(url: made)
        let generator = AVAssetImageGenerator(asset: copy)
        generator.appliesPreferredTrackTransform = true
        let side = CGFloat(MediaSizes.thumbnailLongSide)
        generator.maximumSize = CGSize(width: side, height: side)
        let thumbnailURL = work.appendingPathComponent("thumbnail.jpg")
        guard let still = try? await generator.image(at: .zero).image,
              Self.writeJPEG(still, to: thumbnailURL, quality: 0.75) else {
            throw Refusal.unreadableVideo
        }
        let size = await Self.uprightSize(copy)
        try needSpace(Self.fileSize(made) + Self.fileSize(thumbnailURL))
        try keep(file: made, thumbnail: thumbnailURL, id: id)
        return Added(id: id, details: MediaDetails(kind: .video, width: size.width, height: size.height, durationSeconds: length),
                     byteSize: Self.fileSize(made) + Self.fileSize(thumbnailURL), takenAt: takenAt)
    }

    static func videoDate(_ asset: AVURLAsset) async -> Date? {
        guard let item = try? await asset.load(.creationDate) else { return nil }
        return try? await item.load(.dateValue)
    }

    static func uprightSize(_ asset: AVURLAsset) async -> (width: Int, height: Int) {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return (0, 0) }
        let size = natural.applying(transform)
        return (Int(abs(size.width).rounded()), Int(abs(size.height).rounded()))
    }

    // MARK: Helpers

    /// Refuses when `bytes` more would eat into the space kept free for feeds (D19).
    private func needSpace(_ bytes: Int64) throws {
        guard SpaceRule.fits(bytes, free: freeSpace()) else { throw Refusal.notEnoughSpace }
    }

    private func keep(file: URL, thumbnail: URL, id: String) throws {
        do {
            try files.keepFile(from: file, for: id)
            try files.keepThumbnail(from: thumbnail, for: id)
        } catch {
            files.remove(id)
            throw Refusal.notEnoughSpace
        }
    }

    private static func makeWorkFolder() throws -> URL {
        let folder = workFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
