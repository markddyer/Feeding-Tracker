import Foundation
import Testing
@testable import FeedingCore

/// The Apple Watch app (the user's choices of 16 Nov 2026): what the phone tells the watch, and
/// the watch's taps applied on the phone.
@Suite("Watch")
struct WatchStateTests {
    let now = at(2026, 11, 16, 4, 40)
    let names: [MemberID: String] = [parentA: "Alex", parentB: "Sam"]
    let colours: [MemberID: String] = [parentA: "lavender", parentB: "teal"]

    func household() -> HouseholdData {
        var data = HouseholdData()
        data.put(PlainRecord(type: .baby, name: baby, modifiedAt: now,
                             payload: try? PayloadCoder.encode(BabyPayload(name: "Baby", birthDate: date("2026-11-04")))))
        return data
    }

    func state(_ data: HouseholdData, me: MemberID = parentA, bottleOnly: Bool = false, at time: Date? = nil) -> WatchState {
        data.watchState(me: me, names: names, colours: colours, bottleOnly: bottleOnly, lookSetting: .automatic, now: time ?? now)
    }

    func request(_ command: WatchCommand, at time: Date) -> WatchRequest {
        WatchRequest(command: command, at: time)
    }

    // MARK: What the phone sends

    @Test func beforeThereIsABabyTheWatchAsksForSetUp() {
        let state = state(HouseholdData())
        #expect(!state.setUp)
        #expect(state.glance == nil)
    }

    @Test func idleShowsTheLastFeedAndItsWindow() throws {
        var data = household()
        let start = at(2026, 11, 16, 3, 0)
        data.add(kind: .feed, babyID: baby, startedAt: start, endedAt: start.addingTimeInterval(20 * 60),
                 payload: breast(.left), by: parentB, timeZoneID: "Europe/London", now: start)
        let state = state(data)
        #expect(state.setUp)
        #expect(state.running == nil)
        #expect(state.lastFeedStart == start)
        #expect(state.previousFeedStart == start)
        #expect(state.nextSide == .right)
        let window = try #require(state.feedWindow)
        #expect(window.opensAt == start.addingTimeInterval(2 * 3600))
        #expect(state.glance?.windowCloses == window.closesAt)
        #expect(state.myColour == "lavender")
    }

    @Test func aRunningFeedShowsWhoStartedItAndTheSide() throws {
        var data = household()
        let start = at(2026, 11, 16, 4, 28)
        let id = data.startFeed(babyID: baby, side: .left, by: parentB, timeZoneID: "Europe/London", now: start)
        let mine = state(data, me: parentB)
        #expect(mine.running?.id == id)
        #expect(mine.running?.mine == true)
        #expect(mine.running?.side == .left)
        let theirs = state(data, me: parentA)
        let running = try #require(theirs.running)
        #expect(!running.mine)
        #expect(running.byName == "Sam")
        #expect(running.byColour == "teal")
        #expect(theirs.glance?.runningSince == start)
    }

    @Test func theCrownStartsAtTheLastBottlesAmount() {
        var data = household()
        let start = at(2026, 11, 16, 1, 0)
        data.add(kind: .feed, babyID: baby, startedAt: start, endedAt: start.addingTimeInterval(900),
                 payload: bottles((.formula, 90)), by: parentA, timeZoneID: "Europe/London", now: start)
        data.add(kind: .feed, babyID: baby, startedAt: start.addingTimeInterval(3600), endedAt: start.addingTimeInterval(4500),
                 payload: bottles((.expressed, 60)), by: parentA, timeZoneID: "Europe/London", now: start)
        let state = state(data, bottleOnly: true)
        #expect(state.bottleOnly)
        #expect(state.startAmount(for: .formula) == 90)
        #expect(state.startAmount(for: .expressed) == 60)
        #expect(state.lastMilk == .expressed)
    }

    // MARK: Taps from the watch, on the phone

    @Test func startUsesTheWatchsIDsAndTheTimeOfTheTap() throws {
        var data = household()
        let tap = now.addingTimeInterval(-90)
        let changed = data.applyWatch(request(.start(feedID: "w-feed", bottle: .formula, bottleID: "w-bottle"), at: tap),
                                      babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(changed)
        let running = try #require(data.feedInProgress(babyID: baby))
        #expect(running.id == "w-feed")
        #expect(running.event.startedAt == tap)
        #expect(running.payload?.feed?.bottles.map(\.id) == ["w-bottle"])
        // Sent at once: no Undo bar on the watch.
        #expect(data.eventsToUpload(now: tap).count == 1)
    }

    @Test func aRequestThatArrivesTwiceChangesNothingTheSecondTime() {
        var data = household()
        let start = request(.start(feedID: "w-feed", bottle: nil, bottleID: "b"), at: now)
        let changed1 = data.applyWatch(start, babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(changed1)
        let finish = request(.finish(feedID: "w-feed"), at: now.addingTimeInterval(600))
        let changed2 = data.applyWatch(finish, babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(changed2)
        // The start again, after the finish: no second feed.
        let changed3 = data.applyWatch(start, babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(!changed3)
        let changed4 = data.applyWatch(finish, babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(!changed4)
        #expect(data.events.count == 1)
        #expect(data.feedInProgress(babyID: baby) == nil)
    }

    @Test func startDoesNothingWhileTheOtherParentsFeedRuns() {
        var data = household()
        data.startFeed(babyID: baby, side: nil, by: parentB, timeZoneID: "Europe/London", now: now.addingTimeInterval(-300))
        let changed = data.applyWatch(request(.start(feedID: "w-feed", bottle: nil, bottleID: "b"), at: now),
                                      babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(!changed)
        #expect(data.events["w-feed"] == nil)
    }

    /// A start kept while the phone was out of reach, from before a feed logged since, would show
    /// a feed running for hours.
    @Test func aLateStartFromBeforeANewerFeedIsDropped() {
        var data = household()
        let tap = at(2026, 11, 16, 3, 0)
        let later = at(2026, 11, 16, 3, 10)
        data.add(kind: .feed, babyID: baby, startedAt: later, endedAt: later.addingTimeInterval(1200),
                 payload: breast(.left), by: parentB, timeZoneID: "Europe/London", now: later)
        let changed = data.applyWatch(request(.start(feedID: "w-feed", bottle: nil, bottleID: "b"), at: tap),
                                      babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(!changed)
        #expect(data.feedInProgress(babyID: baby) == nil)
    }

    @Test func switchSideOnlyOnThisParentsOwnRunningFeed() throws {
        var data = household()
        let theirs = data.startFeed(babyID: baby, side: .left, by: parentB, timeZoneID: "Europe/London", now: now)
        let changed5 = data.applyWatch(request(.switchSide(feedID: theirs, side: .right), at: now.addingTimeInterval(60)),
                                 babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(!changed5)
        let changed6 = data.applyWatch(request(.switchSide(feedID: theirs, side: .right), at: now.addingTimeInterval(60)),
                                babyID: baby, by: parentB, timeZoneID: "Europe/London")
        #expect(changed6)
        // The same side again changes nothing.
        let changed7 = data.applyWatch(request(.switchSide(feedID: theirs, side: .right), at: now.addingTimeInterval(90)),
                                 babyID: baby, by: parentB, timeZoneID: "Europe/London")
        #expect(!changed7)
        let sides = try #require(data.events[theirs]?.snapshot.payload?.feed?.breast.map(\.side))
        #expect(sides == [.left, .right])
    }

    /// "Finish for Sam" from the watch, as on the phone.
    @Test func finishWorksOnTheOtherParentsFeed() throws {
        var data = household()
        let id = data.startFeed(babyID: baby, side: nil, by: parentB, timeZoneID: "Europe/London", now: now)
        let end = now.addingTimeInterval(1500)
        let changed8 = data.applyWatch(request(.finish(feedID: id), at: end), babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(changed8)
        #expect(data.events[id]?.event.endedAt == end)
        #expect(data.events[id]?.snapshot.payload?.stamp(.endedAt)?.by == parentA)
    }

    /// A finish for a feed that has already finished never finishes a newer feed instead.
    @Test func finishOnlyFinishesTheFeedTheWatchSaw() {
        var data = household()
        let first = data.startFeed(babyID: baby, side: nil, by: parentB, timeZoneID: "Europe/London", now: now)
        data.finishFeed(first, by: parentB, now: now.addingTimeInterval(600))
        let second = data.startFeed(babyID: baby, side: nil, by: parentB, timeZoneID: "Europe/London", now: now.addingTimeInterval(900))
        let changed9 = data.applyWatch(request(.finish(feedID: first), at: now.addingTimeInterval(1000)),
                                 babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(!changed9)
        #expect(data.events[second]?.event.endedAt == nil)
    }

    /// The watch's clock set back, or a tap that reached the phone out of order: a feed never
    /// ends before it started.
    @Test func aFinishTimedBeforeTheStartEndsAtTheStart() {
        var data = household()
        let id = data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: "Europe/London", now: now)
        let changed10 = data.applyWatch(request(.finish(feedID: id), at: now.addingTimeInterval(-120)),
                                babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(changed10)
        #expect(data.events[id]?.event.endedAt == now)
    }

    /// Across the clocks going back (02:00 BST on 25 Oct 2026 in London), the feed lasts the real
    /// time between the two taps, though the wall clock reads 01:50 at the start and 01:30 at the end.
    @Test func aFeedAcrossTheClocksGoingBackKeepsItsRealLength() throws {
        var data = household()
        let start = at(2026, 10, 25, 0, 50, in: utc)
        let end = start.addingTimeInterval(40 * 60)
        let changed11 = data.applyWatch(request(.start(feedID: "f", bottle: nil, bottleID: "b"), at: start),
                                babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(changed11)
        let changed12 = data.applyWatch(request(.finish(feedID: "f"), at: end), babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(changed12)
        let length = try #require(data.events["f"]?.event.endedAt).timeIntervalSince(start)
        #expect(abs(length - 40 * 60) < 0.001)
    }

    @Test func theAmountGoesOnTheBottleTheWatchStarted() throws {
        var data = household()
        _ = data.applyWatch(request(.start(feedID: "f", bottle: .expressed, bottleID: "b"), at: now),
                            babyID: baby, by: parentA, timeZoneID: "Europe/London")
        _ = data.applyWatch(request(.finish(feedID: "f"), at: now.addingTimeInterval(900)),
                            babyID: baby, by: parentA, timeZoneID: "Europe/London")
        let save = request(.setAmount(feedID: "f", bottleID: "b", ml: 75), at: now.addingTimeInterval(920))
        let changed13 = data.applyWatch(save, babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(changed13)
        let changed14 = data.applyWatch(save, babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(!changed14)
        let bottle = try #require(data.events["f"]?.snapshot.payload?.feed?.bottles.first)
        #expect(bottle.ml == 75)
        #expect(bottle.milk == .expressed)
    }

    @Test func discardRemovesOnlyThisParentsOwnFeed() {
        var data = household()
        let theirs = data.startFeed(babyID: baby, side: nil, by: parentB, timeZoneID: "Europe/London", now: now)
        let changed15 = data.applyWatch(request(.discard(feedID: theirs), at: now), babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(!changed15)
        #expect(data.feedInProgress(babyID: baby)?.id == theirs)
        let changed16 = data.applyWatch(request(.discard(feedID: theirs), at: now), babyID: baby, by: parentB, timeZoneID: "Europe/London")
        #expect(changed16)
        #expect(data.feedInProgress(babyID: baby) == nil)
        // Hidden, never removed from iCloud.
        #expect(data.events[theirs]?.event.deletedAt != nil)
    }

    // MARK: The watch shows a tap at once

    @Test func theWatchShowsItsOwnTapsBeforeThePhoneReplies() throws {
        let start = at(2026, 11, 16, 1, 0)
        var data = household()
        data.add(kind: .feed, babyID: baby, startedAt: start, endedAt: start.addingTimeInterval(900),
                 payload: breast(.left), by: parentA, timeZoneID: "Europe/London", now: start)
        let idle = state(data)

        let started = idle.applying(request(.start(feedID: "f", bottle: nil, bottleID: "b"), at: now))
        let running = try #require(started.running)
        #expect(running.mine && running.id == "f" && running.startedAt == now)
        #expect(started.lastFeedStart == now)
        #expect(started.previousFeedStart == start)

        let switched = started.applying(request(.switchSide(feedID: "f", side: .right), at: now.addingTimeInterval(60)))
        #expect(switched.running?.side == .right)

        let finished = switched.applying(request(.finish(feedID: "f"), at: now.addingTimeInterval(600)))
        #expect(finished.running == nil)
        #expect(finished.lastFeedStart == now)
        #expect(finished.nextSide == .left)

        // Discard puts the last feed back as it was.
        let discarded = started.applying(request(.discard(feedID: "f"), at: now.addingTimeInterval(30)))
        #expect(discarded.running == nil)
        #expect(discarded.lastFeedStart == start)
    }

    @Test func aStartWhileAFeedRunsChangesNothingOnTheWatch() {
        var data = household()
        data.startFeed(babyID: baby, side: nil, by: parentB, timeZoneID: "Europe/London", now: now)
        let before = state(data)
        let after = before.applying(request(.start(feedID: "f", bottle: nil, bottleID: "b"), at: now.addingTimeInterval(60)))
        #expect(after == before)
    }

    @Test func theStateAndATapSurviveTheTrip() throws {
        var data = household()
        data.startFeed(babyID: baby, side: .left, bottle: nil, by: parentA, timeZoneID: "Europe/London", now: now)
        let sent = state(data)
        let state = try #require(WatchCoding.decode(WatchState.self, from: WatchCoding.encode(sent)))
        #expect(state == sent)
        let tap = request(.setAmount(feedID: "f", bottleID: "b", ml: 120), at: now)
        #expect(WatchCoding.decode(WatchRequest.self, from: try WatchCoding.encode(tap)) == tap)
    }

    @Test func thePhoneSendsAgainOnlyWhenSomethingShownChanged() {
        let data = household()
        let first = state(data, at: now)
        let second = state(data, at: now.addingTimeInterval(60))
        #expect(first != second)
        #expect(first.content == second.content)
    }

    // MARK: Start feed on the watch face

    /// The user's choice of 16 Nov 2026: a bottle-only watch asks "Formula or expressed?".
    @Test func theWatchFaceStartAsksABottleOnlyParentWhichMilk() {
        #expect(state(household(), bottleOnly: true).faceStart == .askMilk)
    }

    /// Any other parent: the feed starts at once, as Start feed in the app does.
    @Test func theWatchFaceStartStartsAtOnceForOtherParents() {
        #expect(state(household(), bottleOnly: false).faceStart == .startNow)
    }

    @Test func theWatchFaceStartShowsAFeedAlreadyRunning() {
        var data = household()
        data.startFeed(babyID: baby, side: nil, by: parentB, timeZoneID: "Europe/London", now: now)
        #expect(state(data, bottleOnly: true).faceStart == .showRunning)
    }

    @Test func theWatchFaceStartWaitsForASetUpPhone() {
        #expect(state(HouseholdData()).faceStart == .notReady)
    }

    /// Answered a minute after the tap: the feed starts at the tap, with the milk chosen.
    @Test func aFeedStartedFromTheFaceStartsAtTheTap() throws {
        var data = household()
        let tap = now
        let changed = data.applyWatch(WatchRequest(command: .start(feedID: "f", bottle: .expressed, bottleID: "b"), at: tap),
                                      babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(changed)
        let running = try #require(data.feedInProgress(babyID: baby))
        #expect(running.event.startedAt == tap)
        #expect(running.payload?.feed?.bottles.map(\.milk) == [.expressed])
    }

    // MARK: What the watch keeps

    /// A tap kept while the phone was out of reach stays on screen when an older state arrives.
    @Test func waitingTapsStayOnTopOfThePhonesState() throws {
        let idle = state(household())
        var saved = WatchSaved(phone: idle)
        saved.pending.append(request(.start(feedID: "f", bottle: nil, bottleID: "b"), at: now))
        #expect(saved.shown?.running?.id == "f")
        var later = idle
        later.madeAt = now.addingTimeInterval(5)
        let taken = saved.receive(later)
        #expect(taken)
        #expect(saved.shown?.running?.id == "f")
    }

    /// A tap stops waiting once the phone says it has handled it, whatever the result.
    @Test func aTapStopsWaitingOnceThePhoneHasHandledIt() {
        var saved = WatchSaved(phone: state(household()))
        let tap = request(.start(feedID: "f", bottle: nil, bottleID: "b"), at: now)
        let other = request(.finish(feedID: "g"), at: now)
        saved.pending = [tap, other]
        let handled = household().watchState(me: parentA, names: names, colours: colours, bottleOnly: false,
                                             lookSetting: .automatic, handled: [tap.id], now: now.addingTimeInterval(2))
        let taken = saved.receive(handled)
        #expect(taken)
        #expect(saved.pending == [other])
    }

    @Test func anOlderStateFromThePhoneIsIgnored() {
        let newer = state(household(), at: now)
        let older = state(household(), at: now.addingTimeInterval(-60))
        var saved = WatchSaved(phone: newer)
        let taken = saved.receive(older)
        #expect(!taken)
        #expect(saved.phone?.madeAt == now)
    }

    @Test func tapsMoreThanADayOldAreForgotten() {
        var saved = WatchSaved(phone: state(household()))
        saved.pending = [request(.finish(feedID: "old"), at: now.addingTimeInterval(-25 * 3600)),
                         request(.finish(feedID: "new"), at: now.addingTimeInterval(-60))]
        saved.dropStale(now: now)
        #expect(saved.pending.map(\.command) == [.finish(feedID: "new")])
    }

    /// Night on the watch follows the household's hours; "Match iPhone" does too, as the watch has
    /// no Dark Mode of its own.
    @Test func theWatchLookFollowsTheHouseholdsHours() {
        var state = state(household())
        #expect(state.look(at: at(2026, 11, 16, 3, 0)) == .night)
        #expect(state.look(at: at(2026, 11, 16, 12, 0)) == .day)
        state.lookSetting = .matchPhone
        #expect(state.look(at: at(2026, 11, 16, 22, 0)) == .night)
        state.lookSetting = .alwaysDay
        #expect(state.look(at: at(2026, 11, 16, 3, 0)) == .day)
    }
}
