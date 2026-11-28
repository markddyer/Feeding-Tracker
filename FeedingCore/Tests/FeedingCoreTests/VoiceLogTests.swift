import Foundation
import Testing
@testable import FeedingCore

/// Hands-free logging with Siri (`docs/planning/15-hands-free-siri.md`): what Siri asks after
/// Finish, where a spoken bottle goes, and that the answers save as the watch's taps do.
@Suite("Logging by voice")
struct VoiceLogTests {
    let now = at(2026, 11, 26, 3, 0)

    func household() -> HouseholdData {
        var data = HouseholdData()
        data.put(PlainRecord(type: .baby, name: baby, modifiedAt: now,
                             payload: try? PayloadCoder.encode(BabyPayload(name: "Baby", birthDate: date("2026-11-04")))))
        return data
    }

    func tap(_ action: WatchAction, in data: inout HouseholdData, by member: MemberID = parentA, at time: Date) -> WatchOutcome {
        data.applyWatchAction(WatchActionRequest(action: action, at: time), babyID: baby, by: member,
                              timeZoneID: "Europe/London", now: time)
    }

    // MARK: What Siri asks

    @Test func aBottleWithNoAmountAsksItsAmount() {
        let details = FeedDetails(breast: [], bottles: [Bottle(id: "b1", milk: .formula, ml: nil)])
        #expect(VoiceLog.questions(for: details, bottleOnly: true) == [.amount(bottleID: "b1", milk: .formula)])
        #expect(VoiceLog.questions(for: details, bottleOnly: false) == [.amount(bottleID: "b1", milk: .formula)])
    }

    @Test func aBreastfeedWithNoSideAsksTheSides() {
        #expect(VoiceLog.questions(for: FeedDetails(), bottleOnly: false) == [.sides])
    }

    @Test func aBottleOnlyFeedWithNoBottleAsksTheMilk() {
        #expect(VoiceLog.questions(for: FeedDetails(), bottleOnly: true) == [.milkAndAmount])
    }

    /// A feed with its details asks nothing: anything more is added in the app.
    @Test func aFeedWithItsDetailsAsksNothing() {
        let measured = FeedDetails(breast: [], bottles: [Bottle(id: "b1", milk: .expressed, ml: 60)])
        #expect(VoiceLog.questions(for: measured, bottleOnly: false).isEmpty)
        let sided = FeedDetails(breast: [BreastSegment(side: .left)], bottles: [])
        #expect(VoiceLog.questions(for: sided, bottleOnly: false).isEmpty)
    }

    /// The last side given is the one the next-side suggestion reads.
    @Test func theSideOrderIsKept() {
        #expect(VoiceSides.leftThenRight.sides == [.left, .right])
        #expect(VoiceSides.rightThenLeft.sides == [.right, .left])
        #expect(VoiceSides.left.sides == [.left])
    }

    @Test func amountsAreFiveToThreeHundred() {
        #expect(!VoiceLog.isAmount(0))
        #expect(!VoiceLog.isAmount(4))
        #expect(VoiceLog.isAmount(5))
        #expect(VoiceLog.isAmount(300))
        #expect(!VoiceLog.isAmount(301))
    }

    // MARK: Saving the answers, as the watch's taps

    /// Finish, then "left then right": the sides are saved in that order, so the next side
    /// suggested is the left.
    @Test func spokenSidesSaveInOrder() throws {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, by: parentA, timeZoneID: "Europe/London", now: now)
        let end = now.addingTimeInterval(25 * 60)
        guard case .finished(let feed) = data.quickFinishFeed(babyID: baby, by: parentA, now: end) else {
            Issue.record("not finished"); return
        }
        for side in VoiceSides.leftThenRight.sides {
            #expect(tap(.addSide(feedID: feed.id, side: side), in: &data, at: end) == .applied)
        }
        let saved = try #require(data.events[feed.id]?.snapshot.payload?.feed)
        #expect(saved.breast.map(\.side) == [.left, .right])
        #expect(suggestedNextSide(data.snapshots, babyID: baby, now: end) == .left)
    }

    /// A formula feed: the amount said and confirmed goes on its bottle.
    @Test func aSpokenAmountGoesOnTheBottle() throws {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, bottle: .formula, by: parentA, timeZoneID: "Europe/London", now: now)
        let end = now.addingTimeInterval(20 * 60)
        guard case .finished(let feed) = data.quickFinishFeed(babyID: baby, by: parentA, now: end) else {
            Issue.record("not finished"); return
        }
        let questions = VoiceLog.questions(for: try #require(feed.payload?.feed), bottleOnly: true)
        guard case .amount(let bottleID, .formula) = questions.first else { Issue.record("\(questions)"); return }
        #expect(tap(.amount(feedID: feed.id, bottleID: bottleID, ml: 90), in: &data, at: end) == .applied)
        #expect(data.events[feed.id]?.snapshot.payload?.feed?.bottles.first?.ml == 90)
        #expect(bottlesThroughDay(data.snapshots, babyID: baby, timeZone: TimeZone(identifier: "Europe/London")!,
                                  date: PlainDate(end, in: TimeZone(identifier: "Europe/London")!), now: end)?.soFar == 90)
    }

    // MARK: Where "Add a bottle" goes

    @Test func aBottleGoesOnMyRunningFeed() {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, by: parentA, timeZoneID: "Europe/London", now: now)
        let feeds = data.voiceFeeds(babyID: baby, by: parentA, now: now.addingTimeInterval(300))
        let target = VoiceLog.bottleTarget(running: feeds.running, last: feeds.last, milk: .formula, now: now.addingTimeInterval(300))
        #expect(target == .feed(id: feeds.running!.id))
    }

    @Test func notOnTheOtherParentsRunningFeed() {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, by: parentB, timeZoneID: "Europe/London", now: now)
        let feeds = data.voiceFeeds(babyID: baby, by: parentA, now: now)
        #expect(VoiceLog.bottleTarget(running: feeds.running, last: feeds.last, milk: .formula, now: now) == .runningNotMine)
    }

    @Test func notTwiceOnARunningFeed() {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, bottle: .formula, by: parentA, timeZoneID: "Europe/London", now: now)
        let feeds = data.voiceFeeds(babyID: baby, by: parentA, now: now)
        #expect(VoiceLog.bottleTarget(running: feeds.running, last: feeds.last, milk: .expressed, now: now)
                == .runningHasBottle(feedID: feeds.running!.id))
    }

    /// The last feed takes a bottle for 2 hours after it finished, and only a milk it hasn't got.
    @Test func theLastFeedTakesABottleForTwoHours() throws {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, by: parentB, timeZoneID: "Europe/London", now: now)
        let end = now.addingTimeInterval(30 * 60)
        guard case .finished(let feed) = data.quickFinishFeed(babyID: baby, by: parentB, now: end) else {
            Issue.record("not finished"); return
        }
        let soon = end.addingTimeInterval(110 * 60)
        var feeds = data.voiceFeeds(babyID: baby, by: parentA, now: soon)
        #expect(VoiceLog.bottleTarget(running: feeds.running, last: feeds.last, milk: .formula, now: soon) == .feed(id: feed.id))
        #expect(tap(.addBottle(feedID: feed.id, bottleID: "voice-1", milk: .formula, ml: 60), in: &data, at: soon) == .applied)

        feeds = data.voiceFeeds(babyID: baby, by: parentA, now: soon)
        #expect(VoiceLog.bottleTarget(running: feeds.running, last: feeds.last, milk: .formula, now: soon)
                == .alreadyHas(feedID: feed.id))
        #expect(VoiceLog.bottleTarget(running: feeds.running, last: feeds.last, milk: .expressed, now: soon) == .feed(id: feed.id))

        let late = end.addingTimeInterval(121 * 60)
        #expect(VoiceLog.bottleTarget(running: feeds.running, last: feeds.last, milk: .expressed, now: late) == .noFeed)
    }

    @Test func noFeedNoBottle() {
        let data = household()
        let feeds = data.voiceFeeds(babyID: baby, by: parentA, now: now)
        #expect(VoiceLog.bottleTarget(running: feeds.running, last: feeds.last, milk: .formula, now: now) == .noFeed)
    }

    /// "Breastfeed (Sam)" on a bottle-only phone asks its sides, not a milk (Codex review, 7).
    @Test func aBreastfeedOnABottleOnlyPhoneAsksItsSides() throws {
        var data = household()
        data.setBreastfeeder(.member(parentB), now: now)
        let id = data.startFeed(babyID: baby, side: nil, bottle: nil, by: parentA, timeZoneID: "Europe/London", now: now)
        _ = data.setDoneBy(id, to: parentB, by: parentA, now: now)
        guard case .finished(let feed) = data.quickFinishFeed(babyID: baby, by: parentA, now: now.addingTimeInterval(1200)) else {
            Issue.record("not finished"); return
        }
        #expect(data.voiceQuestions(for: feed, bottleOnly: true) == [.sides])
        // Without the breastfeeder's name on it, a bottle-only phone asks the milk.
        var other = household()
        _ = other.quickStartFeed(babyID: baby, by: parentA, timeZoneID: "Europe/London", now: now)
        guard case .finished(let plain) = other.quickFinishFeed(babyID: baby, by: parentA, now: now.addingTimeInterval(1200)) else {
            Issue.record("not finished"); return
        }
        #expect(other.voiceQuestions(for: plain, bottleOnly: true) == [.milkAndAmount])
    }

    /// Siri fills only an empty amount: one saved meanwhile is seen, and kept (Codex review, 2).
    @Test func anAmountSavedMeanwhileIsSeen() throws {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, bottle: .formula, by: parentA, timeZoneID: "Europe/London", now: now)
        let end = now.addingTimeInterval(1200)
        guard case .finished(let feed) = data.quickFinishFeed(babyID: baby, by: parentA, now: end) else {
            Issue.record("not finished"); return
        }
        let bottleID = try #require(feed.payload?.feed?.bottles.first?.id)
        #expect(data.voiceAmountGap(feedID: feed.id, bottleID: bottleID) == (true, nil))
        _ = tap(.amount(feedID: feed.id, bottleID: bottleID, ml: 60), in: &data, by: parentB, at: end)
        #expect(data.voiceAmountGap(feedID: feed.id, bottleID: bottleID) == (true, 60))
        #expect(data.voiceAmountGap(feedID: feed.id, bottleID: "gone").present == false)
    }

    /// A deleted feed is never the last feed.
    @Test func aDeletedFeedIsSkipped() {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, by: parentA, timeZoneID: "Europe/London", now: now)
        let end = now.addingTimeInterval(20 * 60)
        guard case .finished(let feed) = data.quickFinishFeed(babyID: baby, by: parentA, now: end) else {
            Issue.record("not finished"); return
        }
        data.delete(feed.id, by: parentA, now: end.addingTimeInterval(60))
        let feeds = data.voiceFeeds(babyID: baby, by: parentA, now: end.addingTimeInterval(120))
        #expect(feeds.last == nil)
    }
}
