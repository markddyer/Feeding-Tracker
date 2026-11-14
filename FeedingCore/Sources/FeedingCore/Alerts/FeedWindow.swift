import Foundation

/// The feed window for one baby, measured from the start of the last feed.
///
/// Times are absolute: "4 hours later" is 4 real hours, even across a clock change.
public struct FeedWindow: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case recentlyFed
        case open
        case closed
    }

    public let lastFeedStart: Date
    public let opensAt: Date
    public let closesAt: Date

    public init(lastFeedStart: Date, settings: FeedWindowSettings) {
        self.lastFeedStart = lastFeedStart
        opensAt = lastFeedStart.addingTimeInterval(settings.opensAfter)
        closesAt = lastFeedStart.addingTimeInterval(settings.closesAfter)
    }

    public func state(at now: Date) -> State {
        if now >= closesAt { return .closed }
        if now >= opensAt { return .open }
        return .recentlyFed
    }
}
