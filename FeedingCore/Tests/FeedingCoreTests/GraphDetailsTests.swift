import Foundation
import Testing
@testable import FeedingCore

// A graph's own page (`docs/planning/10-graph-pages.md`): the list under a day must hold exactly
// what that day's bar counts.

@Suite("Graph pages")
struct GraphDetailsTests {
    func feed(_ start: Date, id: String = UUID().uuidString, breast: [BreastSegment] = [], bottles: [Bottle] = [],
              deletedAt: Date? = nil, babyID: String = baby) -> EventSnapshot {
        snapshot(start, id: id, babyID: babyID, deletedAt: deletedAt,
                 payload: EventPayload(feed: FeedDetails(breast: breast, bottles: bottles)))
    }

    func pump(_ start: Date, ml: Int) -> EventSnapshot {
        snapshot(start, kind: .pump, payload: EventPayload(pump: PumpDetails(side: .both, leftML: ml, rightML: 0)))
    }

    /// Every day's list against its bars: count, millilitres, breast time, pumping and gaps.
    func expectListsMatchBars(_ events: [EventSnapshot], timeZone: TimeZone, now: Date,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        for day in graphDays(events, babyID: baby, timeZone: timeZone, range: .all, now: now) {
            let details = graphDayDetails(events, babyID: baby, timeZone: timeZone, day: day.date, now: now)
            #expect(details.feeds.count == day.feeds, "feeds on \(day.date)", sourceLocation: sourceLocation)
            let bottleML = details.bottleFeeds.compactMap(\.payload?.feed).map { $0.ml(of: .formula) + $0.ml(of: .expressed) }
            #expect(bottleML.reduce(0, +) == day.bottleML, "bottles on \(day.date)", sourceLocation: sourceLocation)
            let breast = details.breastFeeds.compactMap(\.payload?.feed).flatMap(\.breast).map { $0.durationSeconds ?? 0 }
            #expect(breast.reduce(0, +) == day.leftSeconds + day.rightSeconds, "breast on \(day.date)",
                    sourceLocation: sourceLocation)
            #expect(details.pumps.count == day.pumpSessions, "pumping on \(day.date)", sourceLocation: sourceLocation)
            #expect(details.pumps.compactMap(\.payload?.pump?.totalML).reduce(0, +) == day.pumpedML,
                    sourceLocation: sourceLocation)
            #expect(details.gaps.map(\.seconds) == day.gaps, "gaps on \(day.date)", sourceLocation: sourceLocation)
        }
    }

    @Test func eachDaysListHoldsWhatItsBarsCount() {
        let events = [
            feed(at(2026, 11, 14, 8), breast: [BreastSegment(side: .left, durationSeconds: 600),
                                               BreastSegment(side: .right, durationSeconds: 300)],
                 bottles: [Bottle(milk: .formula, ml: 60)]),
            feed(at(2026, 11, 14, 11), bottles: [Bottle(milk: .expressed, ml: 90), Bottle(milk: .formula)]),
            pump(at(2026, 11, 14, 13), ml: 70),
            feed(at(2026, 11, 14, 23, 59), breast: [BreastSegment(side: .right, durationSeconds: 420)]),
            feed(at(2026, 11, 15, 0, 0), bottles: [Bottle(milk: .formula, ml: 30)]),
            feed(at(2026, 11, 15, 3), deletedAt: at(2026, 11, 15, 4)),
            feed(at(2026, 11, 15, 5), babyID: "baby-2"),
            snapshot(at(2026, 11, 15, 6), payload: nil),
            feed(at(2026, 11, 15, 13)),
        ]
        let now = at(2026, 11, 15, 12)
        expectListsMatchBars(events, timeZone: london, now: now)

        let sunday = graphDayDetails(events, babyID: baby, timeZone: london, day: date("2026-11-15"), now: now)
        // The 13:00 feed hasn't started yet; the deleted feed and the other baby's are left out. A
        // feed whose details this version can't read still counts, as on the bar.
        #expect(sunday.feeds.map(\.event.startedAt) == [at(2026, 11, 15, 0, 0), at(2026, 11, 15, 6)])
        #expect(sunday.bottleFeeds.count == 1)
        #expect(sunday.breastFeeds.isEmpty)
        let saturday = graphDayDetails(events, babyID: baby, timeZone: london, day: date("2026-11-14"), now: now)
        #expect(saturday.feeds.map(\.event.startedAt) == [at(2026, 11, 14, 8), at(2026, 11, 14, 11), at(2026, 11, 14, 23, 59)])
        #expect(saturday.bottleFeeds.count == 2)
        #expect(saturday.breastFeeds.count == 2)
        #expect(saturday.pumps.count == 1)
    }

    /// A day's first gap starts at the feed before it, even on the day before.
    @Test func aGapNamesItsTwoFeeds() {
        let events = [feed(at(2026, 11, 8, 22), id: "a"), feed(at(2026, 11, 9, 1), id: "b"), feed(at(2026, 11, 9, 4, 30), id: "c")]
        let details = graphDayDetails(events, babyID: baby, timeZone: london, day: date("2026-11-09"), now: at(2026, 11, 9, 12))
        #expect(details.gaps.map(\.earlierID) == ["a", "b"])
        #expect(details.gaps.map(\.laterID) == ["b", "c"])
        #expect(details.gaps.map(\.seconds) == [.hours(3), .hours(3.5)])
        #expect(details.gaps.first?.from == at(2026, 11, 8, 22))
    }

    /// The clocks go back on 25 Oct 2026 and forward on 29 Mar 2026 in London: a 25 and a 23 hour
    /// day. A gap across the change is the real time between the two feeds.
    @Test func listsMatchBarsWhenTheClocksChange() {
        let back = [feed(at(2026, 10, 24, 23, 30)), feed(at(2026, 10, 25, 0, 45)),
                    feed(Date(timeIntervalSince1970: 1_792_890_000 + 1800)), // 01:30 GMT, after the change
                    feed(at(2026, 10, 25, 23, 50)), feed(at(2026, 10, 26, 0, 10))]
        expectListsMatchBars(back, timeZone: london, now: at(2026, 10, 26, 9))
        let forward = [feed(at(2026, 3, 28, 23)), feed(at(2026, 3, 29, 0, 30)), feed(at(2026, 3, 29, 3)),
                       feed(at(2026, 3, 30, 0, 5))]
        expectListsMatchBars(forward, timeZone: london, now: at(2026, 3, 30, 9))
        let details = graphDayDetails(forward, babyID: baby, timeZone: london, day: date("2026-03-29"), now: at(2026, 3, 30, 9))
        // 00:30 GMT to 03:00 BST is two and a half hours on the clock face but 1.5 hours real time.
        #expect(details.gaps.map(\.seconds) == [.hours(1.5), .hours(1.5)])
    }

    /// A household half an hour off the hour (Adelaide, +10:30 in November): days start at its
    /// midnight, not at UTC's.
    @Test func listsMatchBarsInAHalfHourTimeZone() throws {
        let adelaide = try #require(TimeZone(identifier: "Australia/Adelaide"))
        let events = [feed(at(2026, 11, 14, 23, 45, in: adelaide)), feed(at(2026, 11, 15, 0, 15, in: adelaide)),
                      feed(at(2026, 11, 15, 2, in: adelaide))]
        let now = at(2026, 11, 15, 9, in: adelaide)
        expectListsMatchBars(events, timeZone: adelaide, now: now)
        let details = graphDayDetails(events, babyID: baby, timeZone: adelaide, day: date("2026-11-15"), now: now)
        #expect(details.feeds.count == 2)
        #expect(details.gaps.map(\.seconds) == [.minutes(30), .minutes(105)])
    }

    /// The daily rhythm's list: the sleep from the night before first, then the day in order.
    @Test func aRhythmDaysEntriesAreInTimeOrder() throws {
        let events = [
            sleepEvent(at(2026, 11, 16, 22, 30), at(2026, 11, 17, 3, 10), id: "night"),
            feed(at(2026, 11, 17, 0, 40), id: "f1"),
            nappyEvent(at(2026, 11, 17, 0, 55), id: "n1"),
            sleepEvent(at(2026, 11, 17, 3, 50), at(2026, 11, 17, 5, 55), id: "s2"),
            feed(at(2026, 11, 17, 3, 50), id: "f2"),
            nappyEvent(at(2026, 11, 17, 3, 50), id: "n2"),
        ]
        let days = rhythmDays(events, babyID: baby, timeZone: london, dayHours: .standard, range: .week,
                              now: at(2026, 11, 17, 12))
        let tuesday = try #require(days.first { $0.date == date("2026-11-17") })
        #expect(tuesday.entries.map(\.eventID) == ["night", "f1", "n1", "s2", "f2", "n2"])
        #expect(tuesday.entries.first?.at == at(2026, 11, 17, 0))
        guard case .sleep(let night) = tuesday.entries.first else { Issue.record("not a sleep"); return }
        #expect(night.spanStart == at(2026, 11, 16, 22, 30))
        #expect(night.spanEnd == at(2026, 11, 17, 3, 10))
        #expect(night.fromDayBefore)
    }

    @Test func eachWeightCarriesItsChangeSinceTheOneBefore() {
        func growth(_ start: Date, _ grams: Int?, id: String, deleted: Bool = false, babyID: String = baby) -> EventSnapshot {
            snapshot(start, id: id, babyID: babyID, kind: .growth, deletedAt: deleted ? start : nil,
                     payload: EventPayload(growth: GrowthDetails(weightGrams: grams, lengthMM: grams == nil ? 540 : nil)))
        }
        let events = [growth(at(2026, 11, 19, 10), 4210, id: "c"), growth(at(2026, 11, 5, 10), 3910, id: "a"),
                      growth(at(2026, 11, 12, 10), 4070, id: "b"), growth(at(2026, 11, 13, 10), nil, id: "length only"),
                      growth(at(2026, 11, 14, 10), 9999, id: "deleted", deleted: true),
                      growth(at(2026, 11, 15, 10), 5000, id: "other", babyID: "baby-2")]
        let list = weights(events, babyID: baby)
        #expect(list.map(\.id) == ["a", "b", "c"])
        #expect(list.map(\.change) == [nil, 160, 140])
        #expect(list.map(\.previousAt) == [nil, at(2026, 11, 5, 10), at(2026, 11, 12, 10)])
    }
}
