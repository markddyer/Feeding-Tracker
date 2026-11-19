import AVFoundation
import FeedingCore
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeedingDev

/// The journal's own copies of photos and videos (task T7): scaled, converted, and with no place
/// in them (D17); refused when the phone is nearly full (D19). Made-up pictures only.
@Suite("The journal's copies of photos and videos")
struct MediaStoreTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)

    func store(freeSpace: Int64 = 50_000_000_000) -> MediaStore {
        MediaStore(files: MediaFiles(folder: folder.appendingPathComponent("Media")), freeSpace: { freeSpace })
    }

    /// A drawn picture with a place and a time in it, as a camera would write.
    func picture(_ type: UTType, width: Int = 3000, height: Int = 2000) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("source-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "img")")
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.95, green: 0.6, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5074, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 0.1278, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:30 07:40:12",
                                             kCGImagePropertyExifOffsetTimeOriginal: "+01:00"],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    func longSide(_ url: URL) throws -> Int {
        let values = try properties(url)
        return max(values[kCGImagePropertyPixelWidth] as? Int ?? 0, values[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    @Test(arguments: [UTType.jpeg, .heic])
    func aPhotoIsScaledConvertedAndHasNoPlace(_ type: UTType) async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try picture(type)
        #expect(try properties(source)[kCGImagePropertyGPSDictionary] != nil)
        let added = try await store().addPhoto(from: source, id: "photo-1")
        let files = MediaFiles(folder: folder.appendingPathComponent("Media"))
        // 3000 by 2000 scaled to a long side of 2048: 1365 or 1364 high, as the encoder rounds.
        #expect(added.details.kind == .photo)
        #expect(added.details.width == 2048)
        #expect((1364...1365).contains(added.details.height))
        #expect(try longSide(files.fileURL("photo-1")) == 2048)
        #expect(try longSide(files.thumbnailURL("photo-1")) == 400)
        for url in [files.fileURL("photo-1"), files.thumbnailURL("photo-1")] {
            let values = try properties(url)
            #expect(values[kCGImagePropertyGPSDictionary] == nil)
            #expect((values[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
            #expect(CGImageSourceGetType(try #require(CGImageSourceCreateWithURL(url as CFURL, nil))) as String? == UTType.jpeg.identifier)
        }
        // The time it was taken is read for the first's "When", before the copy drops it.
        #expect(added.takenAt == Date(timeIntervalSince1970: 1_793_342_412))
        #expect(added.byteSize > 0)
    }

    /// The picker's bytes go straight into the clean copy, never to a file with the place in it.
    @Test func aPhotoFromMemoryHasNoPlace() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try Data(contentsOf: try picture(.jpeg))
        let added = try await store().addPhoto(data: data, id: "from-memory")
        let files = MediaFiles(folder: folder.appendingPathComponent("Media"))
        #expect(try properties(files.fileURL("from-memory"))[kCGImagePropertyGPSDictionary] == nil)
        #expect(added.takenAt == Date(timeIntervalSince1970: 1_793_342_412))
    }

    /// A time with no time zone isn't guessed; a time zone that isn't real is refused.
    @Test func aTimeTakenWithNoTimeZoneIsNotGuessed() throws {
        #expect(MediaStore.timeZone(offset: "+01:00")?.secondsFromGMT() == 3600)
        #expect(MediaStore.timeZone(offset: "-05:30")?.secondsFromGMT() == -19800)
        #expect(MediaStore.timeZone(offset: "+01:90") == nil)
        #expect(MediaStore.timeZone(offset: "+25:00") == nil)
        let url = folder.appendingPathComponent("no-zone.jpg")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = try #require(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()),
                                   [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:30 00:20:00"]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        #expect(MediaStore.photoDate(try #require(CGImageSourceCreateWithURL(url as CFURL, nil))) == nil)
    }

    @Test func aSmallPhotoIsNeverMadeLarger() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let added = try await store().addPhoto(from: try picture(.jpeg, width: 800, height: 600), id: "small")
        #expect(added.details.width == 800)
        #expect(added.details.height == 600)
    }

    @Test func somethingThatIsNotAPhotoIsRefused() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = folder.appendingPathComponent("note.txt")
        try Data("not a photo".utf8).write(to: text)
        await #expect(throws: MediaStore.Refusal.unreadablePhoto) { try await store().addPhoto(from: text) }
        await #expect(throws: MediaStore.Refusal.unreadableVideo) { try await store().addVideo(from: text) }
    }

    /// Space kept free for feeds: nothing is made when it would eat into the reserve.
    @Test func nothingIsMadeWhenThePhoneIsNearlyFull() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try picture(.jpeg)
        let nearlyFull = store(freeSpace: SpaceRule.reserveBytes + 1_000_000)
        await #expect(throws: MediaStore.Refusal.notEnoughSpace) { try await nearlyFull.addPhoto(from: source) }
        // The editor's way in: the picker's or the camera's bytes, refused before anything is written.
        let bytes = try Data(contentsOf: source)
        await #expect(throws: MediaStore.Refusal.notEnoughSpace) { try await nearlyFull.addPhoto(data: bytes) }
        #expect(MediaFiles(folder: folder.appendingPathComponent("Media")).storedIDs().isEmpty)
        let work = (try? FileManager.default.contentsOfDirectory(atPath: MediaStore.workFolder.path)) ?? []
        #expect(work.isEmpty)
    }

    /// A short clip with a place in it, as a phone camera would write.
    func clip(seconds: Double) async throws -> URL {
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
        let place = AVMutableMetadataItem()
        place.identifier = .quickTimeMetadataLocationISO6709
        place.value = "+51.5074-000.1278/" as NSString
        place.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [place]
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
        #expect(writer.status == .completed)
        return url
    }

    func hasPlace(_ url: URL) async throws -> Bool {
        try await hasPlace(AVURLAsset(url: url))
    }

    func hasPlace(_ asset: AVURLAsset) async throws -> Bool {
        var items = try await asset.load(.metadata)
        for format in try await asset.load(.availableMetadataFormats) {
            items += (try? await asset.loadMetadata(for: format)) ?? []
        }
        for track in try await asset.load(.tracks) {
            items += (try? await track.load(.metadata)) ?? []
        }
        return items.contains { $0.identifier == .quickTimeMetadataLocationISO6709 || $0.commonKey == .commonKeyLocation }
    }

    @Test func aVideoHasNoPlaceAndIsCutTo15Seconds() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await clip(seconds: 18)
        #expect(try await hasPlace(source))
        let added = try await store().addVideo(from: source, id: "video-1")
        let files = MediaFiles(folder: folder.appendingPathComponent("Media"))
        #expect(added.details.kind == .video)
        #expect(added.details.durationSeconds == 15)
        #expect(added.details.width == 320)
        #expect(MediaStore.fileSize(files.fileURL("video-1")) <= MediaSizes.videoAim)
        #expect(try await !hasPlace(files.videoAsset("video-1")))
        let stored = try await files.videoAsset("video-1").load(.duration).seconds
        #expect(abs(stored - 15) < 0.2)
        #expect(try longSide(files.thumbnailURL("video-1")) <= 400)
        #expect(try properties(files.thumbnailURL("video-1"))[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func leftoversGoAtLaunch() throws {
        try FileManager.default.createDirectory(at: MediaStore.workFolder.appendingPathComponent("x"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: MediaStore.exportsFolder, withIntermediateDirectories: true)
        MediaStore.removeLeftovers()
        #expect(!FileManager.default.fileExists(atPath: MediaStore.workFolder.path))
        #expect(!FileManager.default.fileExists(atPath: MediaStore.exportsFolder.path))
    }
}
