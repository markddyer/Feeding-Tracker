import Foundation

// What the home screen shows besides the time since the last feed: the suggested next side, the
// last 24 hours, and feeds both parents logged. None of it affects the alerts.

/// The side to suggest for the next feed: the other side from the last breast segment of the
/// most recent feed that used the breast. Feeds with only bottles are skipped, and so are pumping
/// sessions. Nil when no feed has used the breast. It is only ever a suggestion.
public func suggestedNextSide(_ snapshots: [EventSnapshot], babyID: String, now: Date) -> BreastSide? {
    let feeds = snapshots.filter { $0.event.isLiveFeed && $0.event.babyID == babyID && $0.event.startedAt <= now }
    let newestFirst = feeds.sorted { ($0.event.startedAt, $0.event.id) > ($1.event.startedAt, $1.event.id) }
    for snapshot in newestFirst {
        if let last = snapshot.payload?.feed?.breast.last {
            return last.side.other
        }
    }
    return nil
}

/// The amount of the most recent bottle of `milk` with an amount, or of any bottle when there is
/// none of that milk. Where the amount wheel starts, so the usual amount is a short turn away.
public func lastBottleAmount(_ snapshots: [EventSnapshot], babyID: String, milk: MilkKind) -> Int? {
    let feeds = snapshots.filter { $0.event.isLiveFeed && $0.event.babyID == babyID }
    let newestFirst = feeds.sorted { ($0.event.startedAt, $0.event.id) > ($1.event.startedAt, $1.event.id) }
    let bottles = newestFirst.flatMap { ($0.payload?.feed?.bottles ?? []).reversed() }.filter { $0.ml != nil }
    return (bottles.first { $0.milk == milk } ?? bottles.first)?.ml
}

/// Totals for a stretch of time, such as the last 24 hours. No targets and no verdicts.
public struct FeedSummary: Hashable, Sendable {
    public var feeds = 0
    /// Feeds with at least one breast segment.
    public var breastFeeds = 0
    public var expressedML = 0
    public var formulaML = 0
    public var pumpSessions = 0
    public var pumpedML = 0
    /// Feeds whose details this app version can't read. They count in `feeds` only.
    public var feedsWithoutDetails = 0

    public init() {}
}

/// Totals for events of `babyID` that started from `start` to `end`, both included. Deleted
/// events don't count.
public func summarise(_ snapshots: [EventSnapshot], babyID: String, from start: Date, to end: Date) -> FeedSummary {
    var summary = FeedSummary()
    for snapshot in snapshots {
        let event = snapshot.event
        guard event.deletedAt == nil, event.babyID == babyID, event.startedAt >= start, event.startedAt <= end else { continue }
        switch event.kind {
        case .feed:
            summary.feeds += 1
            guard let feed = snapshot.payload?.feed else {
                if snapshot.payload == nil { summary.feedsWithoutDetails += 1 }
                continue
            }
            if !feed.breast.isEmpty { summary.breastFeeds += 1 }
            summary.expressedML += feed.ml(of: .expressed)
            summary.formulaML += feed.ml(of: .formula)
        case .pump:
            summary.pumpSessions += 1
            summary.pumpedML += snapshot.payload?.pump?.totalML ?? 0
        default:
            break
        }
    }
    return summary
}

/// Two feeds that look like the same feed, logged once on each phone.
public struct DuplicatePair: Hashable, Sendable {
    /// The one shown: the one created first.
    public var kept: String
    /// The one folded into it. The app can undo this.
    public var duplicate: String
}

/// How close two feeds' starts must be to count as one feed logged twice.
public let duplicateWindow: TimeInterval = 5 * 60

/// Feeds of the same baby, starting within 5 minutes of each other and logged by different
/// parents. Each feed is in at most one pair; each is matched with the nearest candidate.
/// `confirmedDistinct` holds pairs of event IDs the parents said are two real feeds.
public func duplicateFeeds(_ events: [Event], confirmedDistinct: Set<Set<String>> = []) -> [DuplicatePair] {
    let feeds = events.filter(\.isLiveFeed).sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    var matched: Set<String> = []
    var pairs: [DuplicatePair] = []
    for (index, feed) in feeds.enumerated() where !matched.contains(feed.id) {
        let candidates = feeds[(index + 1)...].filter { other in
            !matched.contains(other.id)
                && other.babyID == feed.babyID
                && other.loggedBy != feed.loggedBy
                && other.startedAt.timeIntervalSince(feed.startedAt) <= duplicateWindow
                && !confirmedDistinct.contains([feed.id, other.id])
        }
        guard let partner = candidates.min(by: {
            ($0.startedAt.timeIntervalSince(feed.startedAt), $0.id) < ($1.startedAt.timeIntervalSince(feed.startedAt), $1.id)
        }) else { continue }
        let firstCreated = (feed.createdAt, feed.id) <= (partner.createdAt, partner.id)
        pairs.append(DuplicatePair(kept: firstCreated ? feed.id : partner.id, duplicate: firstCreated ? partner.id : feed.id))
        matched.formUnion([feed.id, partner.id])
    }
    return pairs
}
