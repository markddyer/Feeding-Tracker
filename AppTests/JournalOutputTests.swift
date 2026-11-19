import FeedingCore
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import FeedingDev

/// Share and Export (tasks T10, T6, T7, T21).
@Suite("Share and Export")
@MainActor
struct JournalOutputTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("output-\(UUID().uuidString)")

    func photo(width: Int = 900, height: Int = 1200) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A JPEG with a place and a camera time in it, as a phone camera writes.
    func photoWithPlace() throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("with-place.jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W"]
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: "2026:10:31 07:00:00"]
        CGImageDestinationAddImage(destination, try #require(photo().cgImage),
                                   [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyExifDictionary: exif] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// Design review D25: 1080 × 1350, a new picture with no place or camera details, even from a
    /// photo that has them (the share sheet's own path, `FirstCardShare`).
    @Test func theShareCardIs1080By1350WithNoPlace() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try await FirstCardShare(photoURL: try photoWithPlace(), title: "First smile", age: "8 weeks").jpeg()
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1080)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1350)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
    }

    @Test func aFirstWithNoPhotoSharesOneLine() {
        #expect(JournalText.shareLine(title: "First smile", age: "8 weeks") == "First smile · 8 weeks")
        #expect(JournalText.shareLine(title: "First smile", age: nil) == "First smile")
    }

    /// Design review D12 and D17: each state's words; facts only, and "first", never "milestone".
    @Test func eachExportStateSaysWhatIsHappening() {
        #expect(JournalText.export(.ready).detail?.hasPrefix("This file holds every photo and video. Keep it somewhere private.") == true)
        #expect(JournalText.export(.gettingPhotos(done: 12, total: 48)).heading == "Getting photos: 12 of 48")
        #expect(JournalText.export(.packing).heading == "Packing the file")
        #expect(JournalText.export(.stopped).heading == "The export stopped before it finished")
        #expect(JournalText.export(.missing(["First bath", "First word", "Rolled over"])).heading == "Photos couldn't be fetched")
        #expect(JournalText.export(.done(URL(fileURLWithPath: "/x.zip"), leftOut: 1)).detail?.hasPrefix("It leaves out 1 photo") == true)
        #expect(JournalText.saveWithout(3) == "Save without these 3")
        #expect(JournalText.saveWithout(1) == "Save without this one")
        let states: [JournalExporter.State] = [.ready, .gettingPhotos(done: 1, total: 2), .packing,
                                               .done(URL(fileURLWithPath: "/x.zip"), leftOut: 0), .missing(["A"]), .stopped, .noSpace]
        for state in states {
            let words = JournalText.export(state)
            let all = (words.heading + " " + (words.detail ?? "")).lowercased()
            for banned in ["milestone", "due", "missed", "should"] { #expect(!all.contains(banned), "\(state): \(banned)") }
        }
    }

    @Test func aFullDiskIsTold() {
        #expect(JournalExporter.isDiskFull(CocoaError(.fileWriteOutOfSpace)))
        #expect(JournalExporter.isDiskFull(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
        #expect(!JournalExporter.isDiskFull(CocoaError(.fileNoSuchFile)))
    }

    // MARK: The exporter, with stand-ins

    let items: [JournalExportPlan.Item] = [
        .init(mediaID: "m1", title: "First smile", fileName: "2026-10-31 First smile.jpg"),
        .init(mediaID: "m2", title: "First laugh", fileName: "2026-11-16 First laugh.jpg"),
        .init(mediaID: "m3", title: "First bath", fileName: "2026-11-17 First bath.jpg"),
    ]

    func files() throws -> MediaFiles {
        let files = MediaFiles(folder: folder.appendingPathComponent("Media"))
        try FileManager.default.createDirectory(at: files.folder, withIntermediateDirectories: true)
        return files
    }

    func keep(_ id: String, in files: MediaFiles) throws {
        let source = folder.appendingPathComponent("\(id).jpg")
        try #require(photo().jpegData(compressionQuality: 0.8)).write(to: source)
        try files.keepFile(from: source, for: id)
    }

    /// m1 and m2 on this phone; m3 named but not here. `fetch` decides what a fetch brings.
    func exporter(files: MediaFiles, free: Int64 = 50_000_000_000, defaults: UserDefaults? = nil,
                  fetch: @escaping @MainActor ([String], @MainActor (Int) -> Void) async -> Set<String>) throws -> JournalExporter {
        // Never the app's own settings: a saved export state would reopen the real Export screen.
        let defaults = try defaults ?? #require(UserDefaults(suiteName: "export-\(UUID().uuidString)"))
        try keep("m1", in: files)
        try keep("m2", in: files)
        let items = items
        return JournalExporter(sources: .init(
            plan: { leavingOut in JournalExportPlan(items: items.filter { !leavingOut.contains($0.mediaID) },
                                                    listText: leavingOut.isEmpty ? "Firsts\n" : "Firsts\nThis file leaves out \(leavingOut.count)\n") },
            files: files, fetch: fetch, byteSizes: { [:] }, freeSpace: { free }, useBackgroundTask: false, defaults: defaults))
    }

    func settled(_ exporter: JournalExporter) async {
        for _ in 0..<500 where exporter.isWorking { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// The names inside a zip (they are stored as plain text in its headers).
    func zipHolds(_ zip: URL, _ name: String) throws -> Bool {
        try Data(contentsOf: zip).range(of: Data(name.utf8)) != nil
    }

    /// A photo that can't be fetched is named, the export isn't called complete, and "Save without
    /// these" packs the rest into one file that leaves it out and says so; it goes when the screen
    /// closes.
    @Test func aMissingPhotoIsNamedThenTheRestIsPacked() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "export-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let exporter = try exporter(files: try files(), defaults: defaults) { ids, progress in
            progress(ids.count)
            return ["m3"]
        }
        exporter.start()
        await settled(exporter)
        #expect(exporter.state == .missing(["First bath"]))
        // The app closed and a notification was tapped: the screen comes back as it was left.
        let reopened = try self.exporter(files: try files(), defaults: defaults) { _, _ in [] }
        #expect(reopened.state == .missing(["First bath"]))

        exporter.start(skippingMissing: true)
        await settled(exporter)
        guard case .done(let zip, let leftOut) = exporter.state else {
            Issue.record("not done: \(exporter.state)")
            return
        }
        #expect(leftOut == 1)
        #expect(try Data(contentsOf: zip).prefix(2) == Data("PK".utf8))
        #expect(try zipHolds(zip, "Journal/2026-10-31 First smile.jpg"))
        #expect(try zipHolds(zip, "Journal/2026-11-16 First laugh.jpg"))
        #expect(try zipHolds(zip, "Journal/Firsts.txt"))
        #expect(try !zipHolds(zip, "First bath"))
        exporter.close()
        #expect(!FileManager.default.fileExists(atPath: zip.path))
        #expect(defaults.dictionary(forKey: "journal.exportResume") == nil)
    }

    @Test func everythingFetchedIsPackedWhole() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try files()
        let exporter = try exporter(files: files) { [self] ids, progress in
            try? keep("m3", in: files)
            progress(ids.count)
            return []
        }
        exporter.start()
        await settled(exporter)
        guard case .done(let zip, let leftOut) = exporter.state else {
            Issue.record("not done: \(exporter.state)")
            return
        }
        #expect(leftOut == 0)
        #expect(try zipHolds(zip, "Journal/2026-11-17 First bath.jpg"))
        exporter.close()
        #expect(!FileManager.default.fileExists(atPath: zip.path))
        #expect(exporter.state == .ready)
    }

    /// A fetch that says all is well, yet a photo isn't here: back to the choice, never a gap.
    @Test func aPhotoStillMissingAfterTheFetchIsNamed() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = try exporter(files: try files()) { ids, progress in
            progress(ids.count)
            return []
        }
        exporter.start()
        await settled(exporter)
        #expect(exporter.state == .missing(["First bath"]))
    }

    /// Cancel while it works: it stops, nothing is kept, and the fetch it waited on changes nothing.
    @Test func cancelStopsAndKeepsNothing() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let gate = Box<CheckedContinuation<Void, Never>?>(nil)
        let exporter = try exporter(files: try files()) { _, _ in
            await withCheckedContinuation { gate.value = $0 }
            return []
        }
        exporter.start()
        while gate.value == nil { await Task.yield() }
        exporter.cancel()
        #expect(exporter.state == .ready)
        #expect(!exporter.isWorking)
        gate.value?.resume()
        for _ in 0..<20 { await Task.yield() }
        #expect(exporter.state == .ready)
        let exports = (try? FileManager.default.contentsOfDirectory(atPath: MediaStore.exportsFolder.path)) ?? []
        #expect(exports.allSatisfy { !FileManager.default.fileExists(atPath: MediaStore.exportsFolder.appendingPathComponent($0).appendingPathComponent("Journal").path) })
    }

    /// The space kept free for feeds (D19): an export that would eat into it doesn't start.
    @Test func anExportThatWouldEatIntoTheReserveSaysSo() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = try exporter(files: try files(), free: SpaceRule.reserveBytes) { _, _ in [] }
        exporter.start()
        await settled(exporter)
        #expect(exporter.state == .noSpace)
    }
}
