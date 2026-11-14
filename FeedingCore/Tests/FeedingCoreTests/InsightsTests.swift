import Foundation
import Testing
@testable import FeedingCore

@Suite("Suggested next side")
struct NextSideTests {
    let now = at(2026, 11, 14, 12, 0)

    @Test func afterLeftItSuggestsRight() {
        #expect(suggestedNextSide([snapshot(at(2026, 11, 14, 10, 0), payload: breast(.left))], babyID: baby, now: now) == .right)
    }

    @Test func itUsesTheLastSideOfTheFeed() {
        #expect(suggestedNextSide([snapshot(at(2026, 11, 14, 10, 0), payload: breast(.left, .right))], babyID: baby, now: now) == .left)
    }

    @Test func bottleOnlyFeedsAreSkipped() {
        let events = [
            snapshot(at(2026, 11, 14, 8, 0), payload: breast(.left, .right)),
            snapshot(at(2026, 11, 14, 11, 0), payload: bottles((.formula, 30))),
        ]
        #expect(suggestedNextSide(events, babyID: baby, now: now) == .left)
    }

    @Test func deletedFeedsOtherBabiesAndPumpsDoNotCount() {
        let events = [
            snapshot(at(2026, 11, 14, 8, 0), payload: breast(.right)),
            snapshot(at(2026, 11, 14, 9, 0), deletedAt: at(2026, 11, 14, 9, 30), payload: breast(.left)),
            snapshot(at(2026, 11, 14, 10, 0), babyID: "baby-2", payload: breast(.left)),
            snapshot(at(2026, 11, 14, 11, 0), kind: .pump, payload: EventPayload(pump: PumpDetails(side: .right, rightML: 40))),
        ]
        #expect(suggestedNextSide(events, babyID: baby, now: now) == .left)
    }

    @Test func unreadableAndFutureFeedsAreSkipped() {
        let events = [
            snapshot(at(2026, 11, 14, 8, 0), payload: breast(.left)),
            snapshot(at(2026, 11, 14, 11, 0), payload: nil),
            snapshot(at(2026, 11, 14, 13, 0), payload: breast(.right)),
        ]
        #expect(suggestedNextSide(events, babyID: baby, now: now) == .right)
    }

    @Test func noBreastFeedMeansNoSuggestion() {
        #expect(suggestedNextSide([], babyID: baby, now: now) == nil)
        #expect(suggestedNextSide([snapshot(at(2026, 11, 14, 10, 0), payload: bottles((.expressed, 60)))], babyID: baby, now: now) == nil)
    }
}

@Suite("The last 24 hours")
struct SummaryTests {
    let now = at(2026, 11, 14, 12, 0)
    var dayAgo: Date { now.addingTimeInterval(-.hours(24)) }

    @Test func itAddsUpFeedsBottlesAndPumping() {
        var mixed = breast(.left)
        mixed.feed?.bottles = [Bottle(milk: .formula, ml: 30), Bottle(milk: .expressed, ml: 20)]
        let events = [
            snapshot(dayAgo, payload: breast(.left, .right)),
            snapshot(at(2026, 11, 14, 2, 0), payload: bottles((.expressed, 60))),
            snapshot(at(2026, 11, 14, 6, 0), payload: mixed),
            snapshot(at(2026, 11, 14, 7, 0), kind: .pump, payload: EventPayload(pump: PumpDetails(side: .both, leftML: 50, rightML: 40))),
            snapshot(now, payload: bottles((.formula, nil))),
            // Not counted: too early, deleted, another baby, an unknown kind.
            snapshot(dayAgo.addingTimeInterval(-1), payload: bottles((.formula, 90))),
            snapshot(at(2026, 11, 14, 8, 0), deletedAt: at(2026, 11, 14, 8, 5), payload: bottles((.formula, 90))),
            snapshot(at(2026, 11, 14, 9, 0), babyID: "baby-2", payload: bottles((.formula, 90))),
            snapshot(at(2026, 11, 14, 9, 30), kind: "nappy", payload: EventPayload()),
        ]
        var expected = FeedSummary()
        expected.feeds = 4
        expected.breastFeeds = 2
        expected.expressedML = 80
        expected.formulaML = 30
        expected.pumpSessions = 1
        expected.pumpedML = 90
        #expect(summarise(events, babyID: baby, from: dayAgo, to: now) == expected)
    }

    @Test func aFeedFromANewerAppCountsOnlyAsAFeed() {
        let result = summarise([snapshot(at(2026, 11, 14, 10, 0), payload: nil)], babyID: baby, from: dayAgo, to: now)
        #expect(result.feeds == 1)
        #expect(result.feedsWithoutDetails == 1)
        #expect(result.breastFeeds == 0)
    }

    @Test func aPumpWithoutAmountsStillCountsAsASession() {
        let pump = snapshot(at(2026, 11, 14, 10, 0), kind: .pump, payload: EventPayload(pump: PumpDetails(side: .left)))
        let result = summarise([pump], babyID: baby, from: dayAgo, to: now)
        #expect(result.pumpSessions == 1)
        #expect(result.pumpedML == 0)
        #expect(result.feeds == 0)
    }
}

@Suite("Feeds logged on both phones")
struct DuplicateTests {
    func event(_ hour: Int, _ minute: Int, id: String, by: MemberID, babyID: String = baby, kind: EventKind = .feed,
               createdMinute: Int? = nil, deleted: Bool = false) -> Event {
        snapshot(at(2026, 11, 14, hour, minute), id: id, babyID: babyID, kind: kind, by: by,
                 createdAt: at(2026, 11, 14, hour, createdMinute ?? minute),
                 deletedAt: deleted ? at(2026, 11, 14, 23, 0) : nil).event
    }

    @Test func twoParentsWithinFiveMinutesAreOneFeed() {
        let pairs = duplicateFeeds([
            event(10, 0, id: "a", by: parentA, createdMinute: 3),
            event(10, 2, id: "b", by: parentB, createdMinute: 2),
        ])
        #expect(pairs == [DuplicatePair(kept: "b", duplicate: "a")])
    }

    @Test func exactlyFiveMinutesCountsAndSixDoesNot() {
        #expect(duplicateFeeds([event(10, 0, id: "a", by: parentA), event(10, 5, id: "b", by: parentB)]).count == 1)
        #expect(duplicateFeeds([event(10, 0, id: "a", by: parentA), event(10, 6, id: "b", by: parentB)]).isEmpty)
    }

    @Test func theSameParentTwiceIsNotADuplicate() {
        #expect(duplicateFeeds([event(10, 0, id: "a", by: parentA), event(10, 1, id: "b", by: parentA)]).isEmpty)
    }

    @Test func otherBabiesDeletedFeedsAndPumpsDoNotPair() {
        #expect(duplicateFeeds([event(10, 0, id: "a", by: parentA), event(10, 1, id: "b", by: parentB, babyID: "baby-2")]).isEmpty)
        #expect(duplicateFeeds([event(10, 0, id: "a", by: parentA), event(10, 1, id: "b", by: parentB, deleted: true)]).isEmpty)
        #expect(duplicateFeeds([event(10, 0, id: "a", by: parentA), event(10, 1, id: "b", by: parentB, kind: .pump)]).isEmpty)
    }

    @Test func theNearestPartnerIsChosen() {
        let pairs = duplicateFeeds([
            event(10, 0, id: "a", by: parentA),
            event(10, 4, id: "far", by: parentB),
            event(10, 1, id: "near", by: parentB),
        ])
        #expect(pairs == [DuplicatePair(kept: "a", duplicate: "near")])
    }

    @Test func feedsTheParentsSaidAreDifferentStayApart() {
        let events = [event(10, 0, id: "a", by: parentA), event(10, 1, id: "b", by: parentB)]
        #expect(duplicateFeeds(events, confirmedDistinct: [["a", "b"]]).isEmpty)
    }
}
