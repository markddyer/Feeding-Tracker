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

    /// The same Start can arrive twice: as a message, and later as the transfer the watch kept. Turned
    /// down the first time because another feed ran, it must not start a feed when it arrives again
    /// after that feed has finished: the feed would start at the old tap and move the alarms later.
    @Test func aStartTurnedDownIsNotAppliedWhenItArrivesAgain() {
        var data = household()
        var log = WatchTapLog()
        let other = data.startFeed(babyID: baby, side: nil, by: parentB, timeZoneID: "Europe/London",
                                   now: now.addingTimeInterval(-300))
        let start = request(.start(feedID: "w-feed", bottle: nil, bottleID: "b"), at: now)
        let new = log.firstSight(of: start.id)
        #expect(new)
        let first = data.applyWatch(start, babyID: baby, by: parentA, timeZoneID: "Europe/London")
        #expect(!first)
        _ = data.finishFeed(other, by: parentB, now: now.addingTimeInterval(600))
        // The kept copy arrives: the phone has seen it, so it isn't applied.
        let again = log.firstSight(of: start.id)
        #expect(!again)
        #expect(data.events["w-feed"] == nil)
        #expect(data.feedInProgress(babyID: baby) == nil)
    }

    /// A side switch arriving again must not undo a newer one.
    @Test func anOldSideSwitchArrivingAgainIsNotApplied() {
        var log = WatchTapLog()
        let left = request(.switchSide(feedID: "f", side: .left), at: now)
        let right = request(.switchSide(feedID: "f", side: .right), at: now.addingTimeInterval(60))
        let sawLeft = log.firstSight(of: left.id)
        let sawRight = log.firstSight(of: right.id)
        let leftAgain = log.firstSight(of: left.id)
        #expect(sawLeft)
        #expect(sawRight)
        #expect(!leftAgain)
    }

    @Test func thePhoneRemembersManyTapsAndTellsTheWatchTheLatest() {
        var log = WatchTapLog()
        for number in 0..<250 { _ = log.firstSight(of: "tap-\(number)") }
        #expect(log.ids.count == WatchTapLog.kept)
        #expect(log.ids.last == "tap-249")
        #expect(log.latest.count == WatchTapLog.told)
        #expect(log.latest.first == "tap-220")
        // Still remembered, though no longer told to the watch.
        let old = log.firstSight(of: "tap-100")
        #expect(!old)
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
        #expect(state(HouseholdData()).faceButton == .notReady)
    }

    /// The user's choice of 16 Nov 2026: while this parent's feed runs, the watch face shows its
    /// timer, and a tap finishes it.
    @Test func whileMyFeedRunsTheWatchFaceFinishesIt() {
        #expect(state(household(), bottleOnly: true).faceButton == .start)
        var data = household()
        let id = data.startFeed(babyID: baby, side: nil, bottle: .formula, by: parentA, timeZoneID: "Europe/London", now: now)
        let watch = state(data, bottleOnly: true, at: now.addingTimeInterval(600))
        #expect(watch.faceButton == .finish(feedID: id, since: now))
        #expect(watch.finishFromFace(feedID: id)?.bottles.map(\.milk) == [.formula])
        // A face a little behind, naming a feed that is no longer the one running, finishes nothing.
        #expect(watch.finishFromFace(feedID: "an-older-feed") == nil)
    }

    /// The other parent's feed: the face shows their timer, but a tap only opens the app.
    @Test func whileTheOtherParentsFeedRunsTheWatchFaceOnlyOpensTheApp() {
        var data = household()
        let id = data.startFeed(babyID: baby, side: .left, by: parentB, timeZoneID: "Europe/London", now: now)
        let watch = state(data)
        #expect(watch.faceButton == .others(feedID: id, since: now, name: "Sam"))
        #expect(watch.finishFromFace(feedID: id) == nil)
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
        let taken = saved.receive(later, now: now.addingTimeInterval(5))
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
        let taken = saved.receive(handled, now: now.addingTimeInterval(2))
        #expect(taken)
        #expect(saved.pending == [other])
    }

    @Test func anOlderStateFromThePhoneIsIgnored() {
        let newer = state(household(), at: now)
        let older = state(household(), at: now.addingTimeInterval(-60))
        var saved = WatchSaved(phone: newer)
        let taken = saved.receive(older, now: now.addingTimeInterval(1))
        #expect(!taken)
        #expect(saved.phone?.madeAt == now)
    }

    /// The clock set back an hour (the watch takes its time from the phone): the phone's new states
    /// are made "earlier" than the one held, and must still be taken, with their acknowledgements.
    @Test func afterTheClockIsSetBackTheWatchStillTakesThePhonesNews() {
        var saved = WatchSaved(phone: state(household(), at: now))
        let tap = request(.finish(feedID: "g"), at: now)
        saved.pending = [tap]
        let clock = now.addingTimeInterval(-3600 + 10)
        let after = household().watchState(me: parentA, names: names, colours: colours, bottleOnly: false,
                                           lookSetting: .automatic, handled: [tap.id], now: clock)
        let taken = saved.receive(after, now: clock)
        #expect(taken)
        #expect(saved.phone?.madeAt == clock)
        #expect(saved.pending.isEmpty)
        // Out of order again on the new clock: the older one is still turned down.
        let older = state(household(), at: clock.addingTimeInterval(-5))
        let late = saved.receive(older, now: clock.addingTimeInterval(1))
        #expect(!late)
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

/// Page two of the watch app and the watch face's Sleep and Nappy pieces (`06-more-than-feeds.md`,
/// pick I, 17 Nov 2026): what the phone tells the watch, and the watch's taps applied on the phone.
@Suite("Watch: sleep and nappies")
struct WatchSleepNappyTests {
    let now = at(2026, 11, 17, 3, 0)
    let zone = "Europe/London"

    func household() -> HouseholdData {
        var data = HouseholdData()
        data.put(PlainRecord(type: .baby, name: baby, modifiedAt: now,
                             payload: try? PayloadCoder.encode(BabyPayload(name: "Baby", birthDate: date("2026-11-04")))))
        return data
    }

    func state(_ data: HouseholdData, at time: Date? = nil) -> WatchState {
        data.watchState(me: parentA, names: [parentA: "Alex", parentB: "Sam"], colours: [:], bottleOnly: false,
                        lookSetting: .automatic, now: time ?? now)
    }

    @discardableResult
    func apply(_ data: inout HouseholdData, _ command: WatchCommand, at time: Date, id: String = UUID().uuidString) -> Bool {
        data.applyWatch(WatchRequest(id: id, command: command, at: time), babyID: baby, by: parentA, timeZoneID: zone)
    }

    // MARK: What the phone sends

    @Test func noSleepOrNappyYet() {
        let state = state(household())
        #expect(state.sleep == nil)
        #expect(state.lastNappy == nil)
    }

    @Test func asleepShowsTheRunningSleep() throws {
        var data = household()
        let id = data.startSleep(babyID: baby, startedAt: now.addingTimeInterval(-80 * 60), by: parentB, timeZoneID: zone, now: now)
        let sleep = try #require(state(data).sleep)
        #expect(sleep == WatchSleep(id: id, start: now.addingTimeInterval(-80 * 60)))
        #expect(sleep.asleep)
        #expect(sleep.since == now.addingTimeInterval(-80 * 60))
    }

    @Test func awakeShowsWhenTheLastSleepEnded() throws {
        var data = household()
        data.startSleep(babyID: baby, startedAt: now.addingTimeInterval(-3 * 3600), by: parentA, timeZoneID: zone, now: now)
        data.endSleep(babyID: baby, at: now.addingTimeInterval(-3600), by: parentA, now: now)
        let sleep = try #require(state(data).sleep)
        #expect(!sleep.asleep)
        #expect(sleep.since == now.addingTimeInterval(-3600))
    }

    /// An end after now (the clock set back) still counts as asleep, as on Home.
    @Test func anEndAfterNowStillShowsAsleep() throws {
        var data = household()
        data.startSleep(babyID: baby, startedAt: now.addingTimeInterval(-3600), by: parentA, timeZoneID: zone, now: now)
        data.endSleep(babyID: baby, at: now.addingTimeInterval(-60), by: parentA, now: now)
        let earlier = now.addingTimeInterval(-30 * 60)
        #expect(try #require(state(data, at: earlier).sleep).asleep)
    }

    @Test func theLastNappyWithWeeAndPoo() throws {
        var data = household()
        data.addNappy(babyID: baby, wee: true, poo: false, at: now.addingTimeInterval(-3 * 3600), by: parentA, timeZoneID: zone, now: now)
        let id = data.addNappy(babyID: baby, wee: true, poo: true, at: now.addingTimeInterval(-40 * 60), by: parentB,
                               timeZoneID: zone, now: now)
        #expect(state(data).lastNappy == WatchNappy(id: id, at: now.addingTimeInterval(-40 * 60), wee: true, poo: true))
    }

    /// The new fields are optional: a state from an older phone still reads, with no sleep or nappy.
    @Test func anOlderStateStillReads() throws {
        var old = state(household())
        old.version = 1
        var json = try JSONSerialization.jsonObject(with: try WatchCoding.encode(old)) as! [String: Any]
        json["sleep"] = nil
        json["lastNappy"] = nil
        let data = try JSONSerialization.data(withJSONObject: json)
        let read = try #require(WatchCoding.decode(WatchState.self, from: data))
        #expect(read.sleep == nil)
        #expect(read.lastNappy == nil)
        #expect(read.setUp)
    }

    @Test func theNewTapsSurviveTheTrip() throws {
        for command in [WatchCommand.fellAsleep(sleepID: "s"), .wokeUp(sleepID: "s"), .nappy(nappyID: "n", wee: false, poo: true)] {
            let request = WatchRequest(command: command, at: now)
            #expect(WatchCoding.decode(WatchRequest.self, from: try WatchCoding.encode(request)) == request)
        }
        var state = state(household())
        state.sleep = WatchSleep(id: "s", start: now, end: now.addingTimeInterval(60))
        state.lastNappy = WatchNappy(id: "n", at: now, wee: true, poo: true)
        #expect(WatchCoding.decode(WatchState.self, from: try WatchCoding.encode(state)) == state)
    }

    // MARK: The watch's taps on the phone

    @Test func fellAsleepStartsASleepAtTheTapAndSendsItAtOnce() throws {
        var data = household()
        let tap = now.addingTimeInterval(-90)
        #expect(apply(&data, .fellAsleep(sleepID: "s"), at: tap))
        let sleep = try #require(data.events["s"])
        #expect(sleep.event.kind == .sleep)
        #expect(sleep.event.startedAt == tap)
        #expect(sleep.event.loggedBy == parentA)
        #expect(sleep.uploadNotBefore == nil)
        #expect(state(data).sleep == WatchSleep(id: "s", start: tap))
    }

    @Test func fellAsleepTwiceAddsOneSleep() {
        var data = household()
        #expect(apply(&data, .fellAsleep(sleepID: "s"), at: now))
        #expect(!apply(&data, .fellAsleep(sleepID: "s"), at: now))
        #expect(data.events.count == 1)
    }

    @Test func fellAsleepWhileASleepRunsChangesNothing() {
        var data = household()
        data.startSleep(babyID: baby, startedAt: now.addingTimeInterval(-3600), by: parentB, timeZoneID: zone, now: now)
        #expect(!apply(&data, .fellAsleep(sleepID: "s"), at: now))
        #expect(data.events["s"] == nil)
    }

    /// A tap kept while the phone was out of reach, from before a sleep logged since.
    @Test func aLateFellAsleepFromBeforeALaterSleepChangesNothing() {
        var data = household()
        data.startSleep(babyID: baby, startedAt: now.addingTimeInterval(-30 * 60), by: parentB, timeZoneID: zone, now: now)
        data.endSleep(babyID: baby, at: now.addingTimeInterval(-10 * 60), by: parentB, now: now)
        #expect(!apply(&data, .fellAsleep(sleepID: "s"), at: now.addingTimeInterval(-60 * 60)))
        #expect(data.events["s"] == nil)
    }

    @Test func wokeUpEndsTheSleepAtTheTap() throws {
        var data = household()
        let id = data.startSleep(babyID: baby, startedAt: now.addingTimeInterval(-3600), by: parentB, timeZoneID: zone, now: now)
        data.events[id]?.uploadNotBefore = nil
        let tap = now.addingTimeInterval(-2 * 60)
        #expect(apply(&data, .wokeUp(sleepID: id), at: tap))
        let sleep = try #require(data.events[id])
        #expect(sleep.event.endedAt == tap)
        #expect(sleep.snapshot.payload?.stamp(.endedAt)?.by == parentA)
        #expect(data.eventsToUpload(now: now).contains { $0.event.id == id })
        #expect(state(data).sleep?.asleep == false)
    }

    @Test func wokeUpWithNoSleepRunningChangesNothing() {
        var data = household()
        let id = data.startSleep(babyID: baby, startedAt: now.addingTimeInterval(-3600), by: parentB, timeZoneID: zone, now: now)
        data.endSleep(babyID: baby, at: now.addingTimeInterval(-600), by: parentB, now: now)
        #expect(!apply(&data, .wokeUp(sleepID: id), at: now))
        #expect(data.events[id]?.event.endedAt == now.addingTimeInterval(-600))
        #expect(!apply(&data, .wokeUp(sleepID: "unknown"), at: now))
    }

    /// A late Woke up never ends a sleep that began after the tap.
    @Test func aLateWokeUpLeavesALaterSleepAlone() {
        var data = household()
        let first = data.startSleep(babyID: baby, startedAt: now.addingTimeInterval(-3 * 3600), by: parentB, timeZoneID: zone, now: now)
        data.endSleep(babyID: baby, at: now.addingTimeInterval(-2 * 3600), by: parentB, now: now)
        let second = data.startSleep(babyID: baby, startedAt: now.addingTimeInterval(-3600), by: parentB, timeZoneID: zone, now: now)
        #expect(!apply(&data, .wokeUp(sleepID: first), at: now.addingTimeInterval(-150 * 60)))
        #expect(data.events[second]?.event.endedAt == nil)
    }

    @Test func aNappyIsSavedAtTheTapAndSentAtOnce() throws {
        var data = household()
        let tap = now.addingTimeInterval(-60)
        #expect(apply(&data, .nappy(nappyID: "n", wee: true, poo: true), at: tap))
        let nappy = try #require(data.events["n"])
        #expect(nappy.event.kind == .nappy)
        #expect(nappy.event.startedAt == tap)
        #expect(nappy.snapshot.payload?.nappy == NappyDetails(wee: true, poo: true))
        #expect(nappy.uploadNotBefore == nil)
        #expect(!apply(&data, .nappy(nappyID: "n", wee: true, poo: true), at: tap))
        #expect(data.events.count == 1)
    }

    /// The alarms count feeds only: a sleep or a nappy from the watch moves no feed time.
    @Test func sleepAndNappyTapsLeaveTheFeedFactsAlone() {
        var data = household()
        let feed = now.addingTimeInterval(-2 * 3600)
        data.add(kind: .feed, babyID: baby, startedAt: feed, endedAt: feed.addingTimeInterval(1200), payload: breast(.left),
                 by: parentA, timeZoneID: zone, now: feed)
        apply(&data, .fellAsleep(sleepID: "s"), at: now.addingTimeInterval(-3600))
        apply(&data, .nappy(nappyID: "n", wee: true, poo: false), at: now.addingTimeInterval(-30 * 60))
        apply(&data, .wokeUp(sleepID: "s"), at: now)
        let state = state(data)
        #expect(state.lastFeedStart == feed)
        #expect(state.running == nil)
    }

    // MARK: On the watch, before the phone replies

    @Test func theWatchShowsFellAsleepWokeUpAndANappyAtOnce() throws {
        let base = state(household())
        let asleep = base.applying(WatchRequest(command: .fellAsleep(sleepID: "s"), at: now))
        #expect(asleep.sleep == WatchSleep(id: "s", start: now))
        let awake = asleep.applying(WatchRequest(command: .wokeUp(sleepID: "s"), at: now.addingTimeInterval(600)))
        #expect(awake.sleep == WatchSleep(id: "s", start: now, end: now.addingTimeInterval(600)))
        let nappy = awake.applying(WatchRequest(command: .nappy(nappyID: "n", wee: false, poo: true), at: now.addingTimeInterval(700)))
        #expect(nappy.lastNappy == WatchNappy(id: "n", at: now.addingTimeInterval(700), wee: false, poo: true))
    }

    @Test func theWatchIgnoresTapsThatChangeNothing() {
        var base = state(household())
        base.sleep = WatchSleep(id: "s", start: now)
        #expect(base.applying(WatchRequest(command: .fellAsleep(sleepID: "t"), at: now.addingTimeInterval(60))) == base)
        #expect(base.applying(WatchRequest(command: .wokeUp(sleepID: "other"), at: now.addingTimeInterval(60))) == base)
        var notSetUp = WatchState(madeAt: now, setUp: false)
        notSetUp.sleep = nil
        #expect(notSetUp.applying(WatchRequest(command: .fellAsleep(sleepID: "t"), at: now)).sleep == nil)
        // An older nappy arriving after a newer one leaves the newer one shown.
        base.lastNappy = WatchNappy(id: "new", at: now, wee: true, poo: false)
        #expect(base.applying(WatchRequest(command: .nappy(nappyID: "old", wee: false, poo: true), at: now.addingTimeInterval(-60)))
            .lastNappy?.id == "new")
    }

    /// Start feed ends the sleep shown, and Stop · discard puts it back, as on the phone.
    @Test func startFeedEndsTheShownSleepAndDiscardPutsItBack() throws {
        var base = state(household())
        base.sleep = WatchSleep(id: "s", start: now.addingTimeInterval(-3600))
        let feeding = base.applying(WatchRequest(command: .start(feedID: "f", bottle: nil, bottleID: "b"), at: now))
        #expect(feeding.sleep == WatchSleep(id: "s", start: now.addingTimeInterval(-3600), end: now))
        let discarded = feeding.applying(WatchRequest(command: .discard(feedID: "f"), at: now.addingTimeInterval(20)))
        #expect(discarded.sleep == WatchSleep(id: "s", start: now.addingTimeInterval(-3600)))
        // Finish leaves the sleep ended.
        let finished = feeding.applying(WatchRequest(command: .finish(feedID: "f"), at: now.addingTimeInterval(900)))
        #expect(finished.sleep?.asleep == false)
    }

    /// The watch's guess matches what the phone then sends back, for the same taps.
    @Test func theWatchsGuessMatchesThePhone() throws {
        var data = household()
        let sleep = data.startSleep(babyID: baby, startedAt: now.addingTimeInterval(-3600), by: parentB, timeZoneID: zone, now: now)
        let taps = [
            WatchRequest(command: .start(feedID: "f", bottle: nil, bottleID: "b"), at: now),
            WatchRequest(command: .discard(feedID: "f"), at: now.addingTimeInterval(20)),
            WatchRequest(command: .wokeUp(sleepID: sleep), at: now.addingTimeInterval(60)),
            WatchRequest(command: .nappy(nappyID: "n", wee: true, poo: false), at: now.addingTimeInterval(120)),
        ]
        let guess = taps.reduce(state(data)) { $0.applying($1) }
        for tap in taps { data.applyWatch(tap, babyID: baby, by: parentA, timeZoneID: zone) }
        let phone = state(data, at: now.addingTimeInterval(180))
        #expect(guess.sleep == phone.sleep)
        #expect(guess.lastNappy == phone.lastNappy)
    }

    @Test func aTapOnTheSleepPieceSendsWokeUpOrFellAsleep() {
        var state = state(household())
        #expect(state.sleepTap(newID: "new") == .fellAsleep(sleepID: "new"))
        state.sleep = WatchSleep(id: "s", start: now)
        #expect(state.sleepTap(newID: "new") == .wokeUp(sleepID: "s"))
        state.sleep?.end = now.addingTimeInterval(60)
        #expect(state.sleepTap(newID: "new") == .fellAsleep(sleepID: "new"))
        #expect(WatchState(madeAt: now, setUp: false).sleepTap() == nil)
    }
}
