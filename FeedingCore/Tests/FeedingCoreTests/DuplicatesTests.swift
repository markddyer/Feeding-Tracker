import Foundation
import Testing
@testable import FeedingCore

/// One feed logged on both phones (plan v1, "Conflicts"; the user's choice of 15 Nov 2026: show the
/// feed logged first, with "They were two feeds" to undo).
@Suite("One feed logged on both phones")
struct DuplicatesTests {
    let start = at(2026, 11, 15, 10, 30)

    /// Parent A starts a feed; Parent B starts one 2 seconds later, before the phones sync.
    func bothStarted() -> (data: HouseholdData, first: String, second: String) {
        var data = HouseholdData()
        let first = data.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: "Europe/London", now: start)
        let second = data.startFeed(babyID: baby, side: .right, by: parentB, timeZoneID: "Europe/London",
                                    now: start.addingTimeInterval(2))
        return (data, first, second)
    }

    @Test func theScreensShowTheFeedLoggedFirst() {
        let (data, first, second) = bothStarted()
        #expect(data.hiddenDuplicates(babyID: baby) == [second])
        #expect(data.visibleSnapshots(babyID: baby).map(\.id) == [first])
        // Both phones show the first feed as the running one, not the newest.
        #expect(data.feedInProgress(babyID: baby)?.id == first)
    }

    @Test func theTotalsCountItOnce() {
        let (data, _, _) = bothStarted()
        let now = start.addingTimeInterval(600)
        #expect(summarise(data.visibleSnapshots(babyID: baby), babyID: baby, from: now.addingTimeInterval(-86_400), to: now).feeds == 1)
        #expect(dayChart(data.visibleSnapshots(babyID: baby), babyID: baby, now: now).count == 1)
    }

    @Test func alertsStillCountEveryFeed() {
        // reconcile reads all events: the copy's later start still counts, so a merge never
        // changes when a phone alerts.
        let (data, _, _) = bothStarted()
        #expect(data.allEvents.latestFeedStart(babyID: baby, now: start.addingTimeInterval(60)) == start.addingTimeInterval(2))
    }

    @Test func theyWereTwoFeeds() {
        var (data, first, second) = bothStarted()
        data.markDistinct(second, first, by: parentB, now: start.addingTimeInterval(60))
        #expect(data.hiddenDuplicates(babyID: baby).isEmpty)
        #expect(Set(data.visibleSnapshots(babyID: baby).map(\.id)) == [first, second])
        #expect(data.distinctFeedPairs == [[first, second]])
        // Either order names the same record, so both phones agree.
        #expect(SettingKey.distinct(first, second) == SettingKey.distinct(second, first))
    }

    @Test func theCopyFinishesWithTheFirstFeedOnItsOwnPhone() throws {
        var (data, first, second) = bothStarted()
        let end = start.addingTimeInterval(20 * 60)
        data.finishFeed(first, by: parentA, now: end)
        // Only the copy's own parent finishes it, so the phones never edit the same record.
        #expect(data.strandedDuplicates(by: parentA).isEmpty)
        #expect(data.strandedDuplicates(by: parentB).map(\.id) == [second])
        let changed = data.finishStrandedDuplicates(by: parentB, now: end.addingTimeInterval(5))
        #expect(changed)
        let copy = try #require(data.events[second]?.snapshot)
        #expect(copy.event.endedAt == end)
        #expect(copy.payload?.feed?.breast.last?.durationSeconds == 20 * 60 - 2)
        let again = data.finishStrandedDuplicates(by: parentB, now: end.addingTimeInterval(10))
        #expect(!again)
        #expect(data.feedInProgress(babyID: baby) == nil)
    }

    @Test func aCopyStartedAfterTheFirstEndedEndsAtItsOwnStart() throws {
        var data = HouseholdData()
        let first = data.add(kind: .feed, babyID: baby, startedAt: start, endedAt: start.addingTimeInterval(60),
                             payload: EventPayload(feed: FeedDetails()), by: parentA, timeZoneID: "Europe/London", now: start)
        let second = data.startFeed(babyID: baby, side: nil, by: parentB, timeZoneID: "Europe/London",
                                    now: start.addingTimeInterval(180))
        #expect(data.hiddenDuplicates(babyID: baby) == [second])
        data.finishStrandedDuplicates(by: parentB, now: start.addingTimeInterval(200))
        #expect(data.events[second]?.event.endedAt == start.addingTimeInterval(180))
        #expect(data.events[first]?.event.endedAt == start.addingTimeInterval(60))
    }

    @Test func aCopyMarkedAsTwoFeedsIsNotFinished() {
        var (data, first, second) = bothStarted()
        data.markDistinct(first, second, by: parentA, now: start.addingTimeInterval(30))
        data.finishFeed(first, by: parentA, now: start.addingTimeInterval(600))
        #expect(data.strandedDuplicates(by: parentB).isEmpty)
        #expect(data.feedInProgress(babyID: baby)?.id == second)
    }

    @Test func oneParentLoggingTwiceIsTwoFeeds() {
        var data = HouseholdData()
        data.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: "Europe/London", now: start)
        data.add(kind: .feed, babyID: baby, startedAt: start.addingTimeInterval(120), endedAt: start.addingTimeInterval(600),
                 payload: EventPayload(feed: FeedDetails()), by: parentA, timeZoneID: "Europe/London", now: start.addingTimeInterval(700))
        #expect(data.hiddenDuplicates(babyID: baby).isEmpty)
    }
}
