import Foundation

// Hands-free logging with Siri (`docs/planning/15-hands-free-siri.md`, V1 to V4): what Siri asks
// after "Finish the feed", where a spoken bottle goes, and which amounts it takes. The same rules
// for the phone and the watch. The answers are saved through the watch's own taps
// (`applyWatchAction`: `addSide`, `addBottle`, `amount`, `pooDetails`), so an entry made by voice
// is the same as one made by a tap.

/// One question Siri asks about a feed that has just finished.
public enum VoiceFeedQuestion: Hashable, Sendable {
    /// "How much formula did Sam drink, in ml?", for a bottle with no amount.
    case amount(bottleID: String, milk: MilkKind)
    /// "Which side: left, right, left then right, or right then left?", for a feed with no side and
    /// no bottle on a phone that breastfeeds.
    case sides
    /// "Formula or expressed milk?", then its amount, for a bottle-only feed with no bottle yet.
    case milkAndAmount
}

/// The sides of a breastfeed in the order they were given: the last one is what the next-side
/// suggestion reads (`suggestedNextSide`).
public enum VoiceSides: String, CaseIterable, Hashable, Sendable {
    case left
    case right
    case leftThenRight
    case rightThenLeft

    public var sides: [BreastSide] {
        switch self {
        case .left: [.left]
        case .right: [.right]
        case .leftThenRight: [.left, .right]
        case .rightThenLeft: [.right, .left]
        }
    }
}

/// Facts about one feed, read from the household file on the phone or from `WatchState` on the
/// watch.
public struct VoiceFeedFacts: Hashable, Sendable {
    public var id: String
    public var endedAt: Date?
    /// This parent started it.
    public var mine: Bool
    public var details: FeedDetails

    public init(id: String, endedAt: Date?, mine: Bool, details: FeedDetails) {
        self.id = id
        self.endedAt = endedAt
        self.mine = mine
        self.details = details
    }
}

/// Where "Add a bottle" puts its bottle.
public enum VoiceBottleTarget: Hashable, Sendable {
    /// This feed takes it.
    case feed(id: String)
    /// The feed running now already has its bottle: its amount comes at Finish.
    case runningHasBottle(feedID: String)
    /// The other parent's feed is running: only the parent who started it adds its bottle.
    case runningNotMine
    /// The last feed already has a bottle of this milk.
    case alreadyHas(feedID: String)
    /// No feed running, and none finished in the last 2 hours.
    case noFeed
}

public enum VoiceLog {
    /// A spoken amount is taken from 5 to 300 ml, as the watch's wheel.
    public static let amounts = 5...300

    /// "Add a bottle" reaches back to a feed that finished this long ago at most.
    public static let addBottleWithin: TimeInterval = 2 * 3600

    public static func isAmount(_ ml: Int) -> Bool { amounts.contains(ml) }

    /// What Siri asks once a feed has finished: each bottle's missing amount; with no bottle and no
    /// side, the sides (or, on a bottle-only phone, the milk and its amount). Nothing for a feed
    /// that has its details: anything more is added in the app.
    public static func questions(for details: FeedDetails, bottleOnly: Bool) -> [VoiceFeedQuestion] {
        let unmeasured = details.bottles.filter { $0.ml == nil }.map { VoiceFeedQuestion.amount(bottleID: $0.id, milk: $0.milk) }
        if !unmeasured.isEmpty { return unmeasured }
        guard details.bottles.isEmpty, details.breast.isEmpty else { return [] }
        return [bottleOnly ? .milkAndAmount : .sides]
    }

    /// The feed a spoken bottle goes to, as the app's rules: while a feed runs, only the parent
    /// who started it adds its one bottle (the phone's Bottle); otherwise the last feed, if it
    /// finished within 2 hours and has no bottle of this milk yet ("Add to this feed").
    public static func bottleTarget(running: VoiceFeedFacts?, last: VoiceFeedFacts?, milk: MilkKind,
                                    now: Date) -> VoiceBottleTarget {
        if let running {
            guard running.mine else { return .runningNotMine }
            guard running.details.bottles.isEmpty else { return .runningHasBottle(feedID: running.id) }
            return .feed(id: running.id)
        }
        guard let last, let end = last.endedAt, now.timeIntervalSince(end) <= addBottleWithin, end <= now.addingTimeInterval(60)
        else { return .noFeed }
        if last.details.bottles.contains(where: { $0.milk == milk }) { return .alreadyHas(feedID: last.id) }
        return .feed(id: last.id)
    }
}

extension HouseholdData {
    /// The feed running now and the latest finished feed, for "Add a bottle".
    public func voiceFeeds(babyID: String, by me: MemberID, now: Date) -> (running: VoiceFeedFacts?, last: VoiceFeedFacts?) {
        func facts(_ snapshot: EventSnapshot) -> VoiceFeedFacts {
            VoiceFeedFacts(id: snapshot.id, endedAt: snapshot.event.endedAt, mine: snapshot.event.loggedBy == me,
                           details: snapshot.payload?.feed ?? FeedDetails())
        }
        let running = feedInProgress(babyID: babyID).map(facts)
        // What Home shows: a hidden copy of a feed logged on both phones is never chosen (Codex
        // review of doc 15, 4).
        let finished = visibleSnapshots(babyID: babyID).filter {
            $0.event.isLiveFeed && $0.event.babyID == babyID && $0.event.endedAt != nil && $0.event.startedAt <= now
        }
        let last = finished.max { ($0.event.startedAt, $0.id) < ($1.event.startedAt, $1.id) }.map(facts)
        return (running, last)
    }

    /// What Siri asks once this feed has finished. On a bottle-only phone, a breastfeed (the
    /// named breastfeeder's, "Breastfeed (Sam)") still asks its sides, as the app's buttons do
    /// (`isBreastfeed`; Codex review of doc 15, 7).
    public func voiceQuestions(for feed: EventSnapshot, bottleOnly: Bool) -> [VoiceFeedQuestion] {
        VoiceLog.questions(for: feed.payload?.feed ?? FeedDetails(), bottleOnly: bottleOnly && !isBreastfeed(feed))
    }

    /// A bottle's amount, still empty: Siri fills only an empty amount, so an amount the other
    /// parent saved while Siri was asking is never replaced (Codex review of doc 15, 2). Nil when
    /// the bottle has gone; its amount when it has one.
    public func voiceAmountGap(feedID: String, bottleID: String) -> (present: Bool, ml: Int?) {
        guard let bottle = events[feedID]?.snapshot.payload?.feed?.bottles.first(where: { $0.id == bottleID })
        else { return (false, nil) }
        return (true, bottle.ml)
    }
}
