import FeedingCore
import Foundation
import Testing
@testable import FeedingDev

/// What the home screen offers when one parent finishes the other parent's feed.
@Suite("Home screen facts")
struct HomeFactsTests {
    let start = Date(timeIntervalSince1970: 1_794_650_000)
    let parentA: MemberID = "parent-a"
    let parentB: MemberID = "parent-b"

    /// Parent A starts a feed; Parent B finishes it 20 minutes later.
    func finishedForA(details: ((inout HouseholdData, String) -> Void)? = nil) -> HouseholdData {
        var data = HouseholdData()
        let id = data.startFeed(babyID: "baby-1", side: nil, by: parentA, timeZoneID: "Europe/London", now: start)
        details?(&data, id)
        _ = data.finishFeed(id, by: parentB, now: start.addingTimeInterval(1200))
        return data
    }

    func facts(_ data: HouseholdData, me: MemberID, minutesAfterStart: Double = 25) -> HomeFacts {
        HomeFacts(data: data, babyID: "baby-1", me: me, names: [parentA: "A", parentB: "B"],
                  now: start.addingTimeInterval(minutesAfterStart * 60))
    }

    @Test func theFeederIsOfferedTheDetails() throws {
        let offer = try #require(facts(finishedForA(), me: parentA).feedFinishedForMe)
        #expect(offer.by == parentB)
    }

    @Test func theParentWhoFinishedItIsNotOfferedThem() {
        #expect(facts(finishedForA(), me: parentB).feedFinishedForMe == nil)
    }

    @Test func noOfferOnceTheFeedHasDetails() {
        let data = finishedForA { data, id in
            _ = data.switchSide(id, to: .left, by: self.parentA, now: self.start.addingTimeInterval(60))
        }
        #expect(facts(data, me: parentA).feedFinishedForMe == nil)
    }

    /// A bottle-only parent's feed has its bottle from the start; the offer is for the amount.
    @Test func aBottleWithoutItsAmountIsStillOffered() {
        var data = HouseholdData()
        let id = data.startFeed(babyID: "baby-1", side: nil, bottle: .formula, by: parentA, timeZoneID: "Europe/London", now: start)
        _ = data.finishFeed(id, by: parentB, now: start.addingTimeInterval(1200))
        #expect(facts(data, me: parentA).feedFinishedForMe?.feed.id == id)
        _ = data.edit(id, by: parentA, now: start.addingTimeInterval(1300)) { $0.payload?.feed?.bottles[0].ml = 90 }
        #expect(facts(data, me: parentA).feedFinishedForMe == nil)
    }

    @Test func noOfferAfterTwoHours() {
        #expect(facts(finishedForA(), me: parentA, minutesAfterStart: 20 + 121).feedFinishedForMe == nil)
    }

    @Test func noOfferWhenTheFeederFinishedIt() {
        var data = HouseholdData()
        let id = data.startFeed(babyID: "baby-1", side: nil, by: parentA, timeZoneID: "Europe/London", now: start)
        _ = data.finishFeed(id, by: parentA, now: start.addingTimeInterval(1200))
        #expect(facts(data, me: parentA).feedFinishedForMe == nil)
    }

    @Test func theOtherParentIsCalledByName() {
        let home = facts(finishedForA(), me: parentA)
        #expect(home.name(parentB) == "B")
        #expect(home.name(parentA) == "you")
        #expect(home.otherName == "B")
    }

    /// Both parents tap Start feed 2 seconds apart, before the phones sync: Home shows the first
    /// feed as the running one and counts one feed (the user's choice, 15 Nov 2026).
    @Test func aFeedLoggedOnBothPhonesShowsOnce() {
        var data = HouseholdData()
        let first = data.startFeed(babyID: "baby-1", side: .left, by: parentA, timeZoneID: "Europe/London", now: start)
        data.startFeed(babyID: "baby-1", side: .right, by: parentB, timeZoneID: "Europe/London", now: start.addingTimeInterval(2))
        for me in [parentA, parentB] {
            let home = facts(data, me: me, minutesAfterStart: 5)
            #expect(home.feedInProgress?.id == first)
            #expect(home.totals.feeds == 1)
            #expect(home.chart.count == 1)
        }
    }
}
