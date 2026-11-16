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

    /// The watch face's Finish, while this parent's feed runs: names the feed, so a face that is a
    /// little behind can't finish a different one.
    static let finishFeedHost = "finish-feed"
    /// The watch face during the other parent's feed: only opens the app.
    static let showFeedHost = "show-feed"

    static var startFeed: URL? {
        scheme.flatMap { URL(string: "\($0)://\(startFeedHost)") }
    }

    static func finishFeed(_ feedID: String) -> URL? {
        guard let scheme else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = finishFeedHost
        parts.queryItems = [URLQueryItem(name: "feed", value: feedID)]
        return parts.url
    }

    static var showFeed: URL? {
        scheme.flatMap { URL(string: "\($0)://\(showFeedHost)") }
    }

    /// The feed a Finish link names.
    static func feedID(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "feed" }?.value
    }

    private static var scheme: String? {
        Bundle.main.object(forInfoDictionaryKey: "FeedingWatchScheme") as? String
    }
}
