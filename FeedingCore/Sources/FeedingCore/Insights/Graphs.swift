import Foundation

// The Graphs tab (plan v1, Phase 2; the user's choices of 16 Nov 2026). Facts only: counts,
// amounts and times, per calendar day. No targets and no verdicts.

/// How far back the Graphs tab looks.
public enum GraphRange: String, CaseIterable, Sendable {
    case week, fourWeeks, all

    /// Days shown, counting today; nil for every day since the first feed or pump.
    public var days: Int? {
        switch self {
        case .week: 7
        case .fourWeeks: 28
        case .all: nil
        }
    }
}

/// One calendar day of facts, midnight to midnight in the household's time zone.
public struct GraphDay: Hashable, Sendable, Identifiable {
    public var date: PlainDate
    /// Today is not over, so the screen draws it lighter.
    public var isToday: Bool
    public var feeds = 0
    public var formulaML = 0
    public var expressedML = 0
    public var leftSeconds = 0
    public var rightSeconds = 0
    public var pumpSessions = 0
    public var pumpedML = 0
    /// From each feed's start to the next feed's start, kept under the day the next feed started.
    public var gaps: [TimeInterval] = []

    public init(date: PlainDate, isToday: Bool) {
        self.date = date
        self.isToday = isToday
    }

    public var id: PlainDate { date }
    public var bottleML: Int { formulaML + expressedML }
    public var shortestGap: TimeInterval? { gaps.min() }
    public var longestGap: TimeInterval? { gaps.max() }

    /// The middle gap: half were shorter and half longer (with an even count, halfway between
    /// the two middle ones).
    public var middleGap: TimeInterval? {
        let sorted = gaps.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// The days the Graphs tab shows, oldest first, ending today. A day counts what started on it in
/// `timeZone` (the household's), wherever the phone was. The days start no earlier than the first
/// feed or pump, so a new household sees no empty days before it began. Deleted events, other
/// babies and anything that starts after `now` are left out; pass `visibleSnapshots`, so a feed
/// logged on both phones counts once.
public func graphDays(_ snapshots: [EventSnapshot], babyID: String, timeZone: TimeZone,
                      range: GraphRange, now: Date) -> [GraphDay] {
    let live = graphSnapshots(snapshots, babyID: babyID, now: now)
    guard let first = live.map(\.event.startedAt).min() else { return [] }
    let today = PlainDate(now, in: timeZone)
    let firstDay = PlainDate(first, in: timeZone)
    let start = max(firstDay, range.days.map { today.adding(days: 1 - $0) } ?? firstDay)
    let count = today.days(since: start) + 1
    guard count > 0 else { return [] }
    var days = (0..<count).map { GraphDay(date: start.adding(days: $0), isToday: $0 == count - 1) }

    func index(of instant: Date) -> Int? {
        let offset = PlainDate(instant, in: timeZone).days(since: start)
        return days.indices.contains(offset) ? offset : nil
    }

    for snapshot in live {
        guard let i = index(of: snapshot.event.startedAt) else { continue }
        if snapshot.event.kind == .feed {
            days[i].feeds += 1
            guard let feed = snapshot.payload?.feed else { continue }
            days[i].formulaML += feed.ml(of: .formula)
            days[i].expressedML += feed.ml(of: .expressed)
            for segment in feed.breast {
                let seconds = max(0, segment.durationSeconds ?? 0)
                switch segment.side {
                case .left: days[i].leftSeconds += seconds
                case .right: days[i].rightSeconds += seconds
                }
            }
        } else {
            days[i].pumpSessions += 1
            days[i].pumpedML += snapshot.payload?.pump?.totalML ?? 0
        }
    }

    // Every feed, not only those in range, so the first day's first gap starts at the feed before.
    // The same gaps a graph's page lists (`graphDayDetails`).
    for gap in feedGaps(of: live.filter { $0.event.kind == .feed }) {
        if let i = index(of: gap.to) { days[i].gaps.append(gap.seconds) }
    }
    return days
}
