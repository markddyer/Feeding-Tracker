import Foundation

/// Feeding Dev only: a short log of what sync did, kept in the App Group's `Library/Caches`, so it
/// can be copied off a real phone without asking the parents for screenshots:
///
///     xcrun devicectl device copy from --device <id> --domain-type appGroupDataContainer \
///       --domain-identifier group.com.tracker.feeding.dev \
///       --source Library/Caches/sync-log.txt --destination sync-log.txt
///
/// It holds record types, record names and errors, never feed details. It stays on the phone.
/// Feeding (the real app) writes nothing.
@MainActor
enum SyncLog {
    private static let maxLines = 400

    static func add(_ line: String) {
        #if FEEDING_DEV
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)?
            .appendingPathComponent("Library/Caches", isDirectory: true) else { return }
        let url = folder.appendingPathComponent("sync-log.txt")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var lines = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        lines.append("\(Date().formatted(date: .omitted, time: .standard)) \(line)")
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        #endif
    }
}
