import AVFoundation
import FeedingCore
import Foundation

/// The firsts' photos and videos on this phone: for each item, its file and its thumbnail, named
/// by the item's ID, in the App Group's `Media` folder, with file protection. Never inside
/// `household.json` (journal plan, "Where photos live on the phone"). `MediaStore` (task T7)
/// makes the files; `MediaSync` sends and fetches them.
struct MediaFiles: Sendable {
    let folder: URL

    /// The App Group's `Media` folder, made if missing. Nil without the App Group.
    static func appGroup() -> MediaFiles? {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID) else {
            return nil
        }
        return MediaFiles(folder: group.appendingPathComponent("Media", isDirectory: true))
    }

    func fileURL(_ id: String) -> URL { folder.appendingPathComponent("\(id).file") }
    func thumbnailURL(_ id: String) -> URL { folder.appendingPathComponent("\(id).thumbnail") }

    func hasFile(_ id: String) -> Bool { FileManager.default.fileExists(atPath: fileURL(id).path) }
    func hasThumbnail(_ id: String) -> Bool { FileManager.default.fileExists(atPath: thumbnailURL(id).path) }

    /// A stored video, for playing or reading. Its file name has no ".mp4", so the type is given:
    /// the journal's videos are always MP4 (`MediaStore.addVideo`).
    func videoAsset(_ id: String) -> AVURLAsset {
        AVURLAsset(url: fileURL(id), options: [AVURLAssetOverrideMIMETypeKey: "video/mp4"])
    }

    /// Copies a file CloudKit downloaded into this folder. CloudKit may remove its copy once the
    /// fetch ends, so this is called at once.
    func keepFile(from source: URL, for id: String) throws { try keep(source, at: fileURL(id)) }
    func keepThumbnail(from source: URL, for id: String) throws { try keep(source, at: thumbnailURL(id)) }

    /// Removes an item's file and thumbnail.
    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: fileURL(id))
        try? FileManager.default.removeItem(at: thumbnailURL(id))
    }

    /// The free space iPhone counts for files the parents asked for, in bytes.
    func freeSpace() -> Int64 {
        let values = try? folder.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// The IDs of the items with a file or a thumbnail here. Leftover half-copied files go.
    func storedIDs() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var ids = Set<String>()
        for name in names {
            if name.hasSuffix(".part") {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            } else if let dot = name.lastIndex(of: "."), [".file", ".thumbnail"].contains(String(name[dot...])) {
                ids.insert(String(name[..<dot]))
            }
        }
        return ids
    }

    private func keep(_ source: URL, at target: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let staging = folder.appendingPathComponent("\(UUID().uuidString).part")
        do {
            try manager.copyItem(at: source, to: staging)
            try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                      ofItemAtPath: staging.path)
            _ = try? manager.removeItem(at: target)
            try manager.moveItem(at: staging, to: target)
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }
}
