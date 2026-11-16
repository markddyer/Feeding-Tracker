import FeedingCore
import Foundation

/// Where the watch app keeps what it last heard from the phone, and its waiting taps: a file in
/// the watch's App Group, so the watch face can read it too.
enum WatchFile {
    private static var url: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FeedingAppGroup") as? String,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return folder.appendingPathComponent("watch-state.json")
    }

    static func load() -> WatchSaved {
        guard let url, let data = try? Data(contentsOf: url),
              let saved = WatchCoding.decode(WatchSaved.self, from: data) else { return WatchSaved() }
        return saved
    }

    static func save(_ saved: WatchSaved) {
        guard let url, let data = try? WatchCoding.encode(saved) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// The links from the watch face into the watch app. Each variant has its own scheme
/// (`FeedingWatchScheme` in both Info.plists), so Feeding and Feeding Dev can sit on one watch.
enum WatchLinks {
    /// The watch face's Start feed.
    static let startFeedHost = "start-feed"

    static var startFeed: URL? {
        scheme.flatMap { URL(string: "\($0)://\(startFeedHost)") }
    }

    private static var scheme: String? {
        Bundle.main.object(forInfoDictionaryKey: "FeedingWatchScheme") as? String
    }
}
