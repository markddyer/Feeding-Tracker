import Foundation

// What lies behind each graph on the Graphs tab, one day at a time (the users' choice C, 21 Nov
// 2026, `docs/planning/10-graph-pages.md`): a tap on a graph opens its own page, with the entries
// a day's bar counts under it. Built from the same rules as the bars (`graphDays`, `rhythmDays`),
// so a bar and its list always agree. Facts only: times, lengths, amounts and who.

/// The graphs that open a page of their own, in the order the Graphs tab shows them.
public enum GraphKind: String, CaseIterable, Hashable, Sendable {
    case rhythm, asleep, nappies, weight, feeds, bottles, gaps, breast, pumped

    /// The graphs drawn from `graphDays`; the others come from `rhythmDays`, or (weight) from
    /// every weight logged.
    public var isFeedGraph: Bool {
        switch self {
        case .feeds, .bottles, .gaps, .breast, .pumped: true
        case .rhythm, .asleep, .nappies, .weight: false
        }
    }
}

/// The time from one feed's start to the next feed's start. It belongs to the day the later feed
/// started, as in `GraphDay.gaps`.
public struct FeedGap: Hashable, Sendable, Identifiable {
    public var earlierID: String
    public var laterID: String
    public var from: Date
    public var to: Date

    public var id: String { laterID }
    public var seconds: TimeInterval { to.timeIntervalSince(from) }
}

/// The gaps between `feeds`, oldest first. Every feed counts, not only one day's, so a day's first
/// gap starts at the feed before it. Shared by `graphDays` and `graphDayDetails`.
func feedGaps(of feeds: [EventSnapshot]) -> [FeedGap] {
    let sorted = feeds.sorted { ($0.event.startedAt, $0.event.id) < ($1.event.startedAt, $1.event.id) }
    return zip(sorted, sorted.dropFirst()).map {
        FeedGap(earlierID: $0.event.id, laterID: $1.event.id, from: $0.event.startedAt, to: $1.event.startedAt)
    }
}

/// The feeds and pumping sessions that `graphDays` counts: live, this baby's, started by `now`.
func graphSnapshots(_ snapshots: [EventSnapshot], babyID: String, now: Date) -> [EventSnapshot] {
    snapshots.filter {
        $0.event.deletedAt == nil && $0.event.babyID == babyID && $0.event.startedAt <= now
            && ($0.event.kind == .feed || $0.event.kind == .pump)
    }
}

/// One day behind the five feed graphs: the entries each bar counts, oldest first.
public struct GraphDayDetails: Sendable {
    public var date: PlainDate
    /// Every feed that started on this day ("Feeds each day").
    public var feeds: [EventSnapshot] = []
    /// The feeds with a bottle ("Bottles each day").
    public var bottleFeeds: [EventSnapshot] = []
    /// The feeds with the breast ("Breast each day").
    public var breastFeeds: [EventSnapshot] = []
    /// The pumping sessions ("Pumped each day").
    public var pumps: [EventSnapshot] = []
    /// The gaps that ended on this day ("Time between feeds").
    public var gaps: [FeedGap] = []

    public init(date: PlainDate) {
        self.date = date
    }
}

/// The entries behind `day`'s bars on the five feed graphs. A day is the household's calendar day
/// in `timeZone`, as on the graphs. Pass `visibleSnapshots`, as the graphs do, so a feed logged on
/// both phones shows once.
public func graphDayDetails(_ snapshots: [EventSnapshot], babyID: String, timeZone: TimeZone,
                            day: PlainDate, now: Date) -> GraphDayDetails {
    let live = graphSnapshots(snapshots, babyID: babyID, now: now)
    let onDay = live.filter { PlainDate($0.event.startedAt, in: timeZone) == day }
        .sorted { ($0.event.startedAt, $0.event.id) < ($1.event.startedAt, $1.event.id) }
    var details = GraphDayDetails(date: day)
    details.feeds = onDay.filter { $0.event.kind == .feed }
    details.bottleFeeds = details.feeds.filter { !($0.payload?.feed?.bottles.isEmpty ?? true) }
    details.breastFeeds = details.feeds.filter { !($0.payload?.feed?.breast.isEmpty ?? true) }
    details.pumps = onDay.filter { $0.event.kind == .pump }
    details.gaps = feedGaps(of: live.filter { $0.event.kind == .feed })
        .filter { PlainDate($0.to, in: timeZone) == day }
    return details
}

// MARK: - The daily rhythm, in time order

/// One line of a day's rhythm: a sleep (from where it starts on this day), a feed or a nappy.
public enum RhythmEntry: Hashable, Sendable, Identifiable {
    case sleep(RhythmSleep)
    case feed(DayChartFeed)
    case nappy(NappyChange)

    public var id: String {
        switch self {
        case .sleep(let sleep): "sleep:" + sleep.id
        case .feed(let feed): "feed:" + feed.id
        case .nappy(let nappy): "nappy:" + nappy.id
        }
    }

    /// The event's ID, to open it.
    public var eventID: String {
        switch self {
        case .sleep(let sleep): sleep.id
        case .feed(let feed): feed.id
        case .nappy(let nappy): nappy.id
        }
    }

    /// Where it sits on the day: a sleep from the day before sits at the day's start.
    public var at: Date {
        switch self {
        case .sleep(let sleep): sleep.start
        case .feed(let feed): feed.startedAt
        case .nappy(let nappy): nappy.at
        }
    }
}

extension RhythmDay {
    /// The day's sleeps, feeds and nappies in time order, as the row draws them left to right.
    /// At the same moment a sleep comes first, then a feed, then a nappy.
    public var entries: [RhythmEntry] {
        func order(_ entry: RhythmEntry) -> Int {
            switch entry {
            case .sleep: 0
            case .feed: 1
            case .nappy: 2
            }
        }
        let all = sleeps.map(RhythmEntry.sleep) + feeds.map(RhythmEntry.feed) + nappies.map(RhythmEntry.nappy)
        return all.sorted { ($0.at, order($0), $0.id) < ($1.at, order($1), $1.id) }
    }
}

// MARK: - Weight

/// One weight on the weight graph, with the change since the one before.
public struct WeightEntry: Hashable, Sendable, Identifiable {
    public var id: String
    public var at: Date
    public var grams: Int
    /// The weight before this one, when there is one: its time and the change in grams.
    public var previousAt: Date?
    public var change: Int?
}

/// Every weight of `babyID`, oldest first, as the weight graph draws them. Deleted entries, other
/// babies and growth entries with no weight are left out.
public func weights(_ snapshots: [EventSnapshot], babyID: String) -> [WeightEntry] {
    let measured = snapshots.compactMap { snapshot -> (EventSnapshot, Int)? in
        guard snapshot.event.kind == .growth, snapshot.event.deletedAt == nil, snapshot.event.babyID == babyID,
              let grams = snapshot.payload?.growth?.weightGrams else { return nil }
        return (snapshot, grams)
    }
    .sorted { ($0.0.event.startedAt, $0.0.event.id) < ($1.0.event.startedAt, $1.0.event.id) }
    var entries: [WeightEntry] = []
    for (snapshot, grams) in measured {
        let previous = entries.last
        entries.append(WeightEntry(id: snapshot.event.id, at: snapshot.event.startedAt, grams: grams,
                                   previousAt: previous?.at, change: previous.map { grams - $0.grams }))
    }
    return entries
}
