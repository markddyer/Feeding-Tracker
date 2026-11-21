import Foundation
import Testing
@testable import FeedingCore

/// Starting and finishing a feed from outside the app (the user's choice of 16 Nov 2026: a
/// control, the Action Button and Siri), and what the Lock Screen widget shows.
@Suite("Feeds from outside the app")
struct QuickFeedTests {
    let now = at(2026, 11, 16, 3, 0)

    func household() -> HouseholdData {
        var data = HouseholdData()
        data.put(PlainRecord(type: .baby, name: baby, modifiedAt: now,
                             payload: try? PayloadCoder.encode(BabyPayload(name: "Baby", birthDate: date("2026-11-04")))))
        return data
    }

    @Test func startStartsAFeedWithNothingChosen() throws {
        var data = household()
        let result = data.quickStartFeed(babyID: baby, by: parentA, timeZoneID: "Europe/London", now: now)
        guard case .started(let id, let at, let bottle) = result else { Issue.record("\(result)"); return }
        #expect(at == now)
        #expect(bottle == nil)
        let running = try #require(data.feedInProgress(babyID: baby))
        #expect(running.id == id)
        #expect(running.event.loggedBy == parentA)
        let details = try #require(running.payload?.feed)
        #expect(details.breast.isEmpty && details.bottles.isEmpty)
    }

    /// A bottle-only parent's "Formula" button starts a formula bottle, as Start feed does in the app.
    @Test func aButtonCanNameTheBottle() throws {
        var data = household()
        let result = data.quickStartFeed(babyID: baby, bottle: .formula, by: parentA, timeZoneID: "Europe/London", now: now)
        guard case .started(_, _, .formula) = result else { Issue.record("\(result)"); return }
        let running = try #require(data.feedInProgress(babyID: baby))
        #expect(running.payload?.feed?.bottles.map(\.milk) == [.formula])
        #expect(running.payload?.feed?.bottles.first?.ml == nil)
    }

    /// No Undo bar outside the app, so the feed goes to the other phone at once.
    @Test func aQuickStartIsSentAtOnce() throws {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, by: parentA, timeZoneID: "Europe/London", now: now)
        #expect(data.eventsToUpload(now: now).count == 1)
    }

    @Test func startDoesNothingWhileAFeedRuns() throws {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, by: parentB, timeZoneID: "Europe/London", now: now)
        let result = data.quickStartFeed(babyID: baby, by: parentA, timeZoneID: "Europe/London", now: now.addingTimeInterval(60))
        guard case .alreadyRunning(let running) = result else { Issue.record("\(result)"); return }
        #expect(running.event.loggedBy == parentB)
        #expect(data.events.count == 1)
    }

    @Test func finishFinishesTheRunningFeedWhoeverStartedIt() throws {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, by: parentB, timeZoneID: "Europe/London", now: now)
        let end = now.addingTimeInterval(25 * 60)
        let result = data.quickFinishFeed(babyID: baby, by: parentA, now: end)
        guard case .finished(let feed) = result else { Issue.record("\(result)"); return }
        #expect(feed.event.endedAt == end)
        #expect(feed.event.loggedBy == parentB)
        #expect(feed.payload?.stamp(.endedAt)?.by == parentA)
        #expect(data.feedInProgress(babyID: baby) == nil)
        #expect(data.eventsToUpload(now: end).count == 1)
    }

    @Test func finishWithNothingRunningChangesNothing() {
        var data = household()
        let before = data
        #expect(data.quickFinishFeed(babyID: baby, by: parentA, now: now) == .nothingRunning)
        #expect(data == before)
    }

    // MARK: The Lock Screen widget

    @Test func theGlanceShowsTheLastFeedAndItsWindow() throws {
        var data = household()
        let start = at(2026, 11, 16, 1, 0)
        _ = data.add(kind: .feed, babyID: baby, startedAt: start, endedAt: start.addingTimeInterval(1200),
                     payload: EventPayload(feed: FeedDetails()), by: parentA, timeZoneID: "Europe/London", now: start)
        let glance = try #require(data.glance(now: now))
        #expect(glance.lastFeedStart == start)
        #expect(glance.runningSince == nil)
        #expect(glance.windowOpens == start.addingTimeInterval(2 * 3600))
        #expect(glance.windowCloses == start.addingTimeInterval(4 * 3600))
        #expect(glance.windowProgress(at: now) == 0.5)
        #expect(glance.timeZoneID == "Europe/London")
    }

    @Test func theGlanceShowsARunningFeed() throws {
        var data = household()
        _ = data.quickStartFeed(babyID: baby, by: parentB, timeZoneID: "Europe/London", now: now)
        let glance = try #require(data.glance(now: now.addingTimeInterval(600)))
        #expect(glance.runningSince == now)
        #expect(glance.lastFeedStart == now)
    }

    @Test func noBabyMeansNoGlanceAndNoFeedsMeansNoWindow() throws {
        #expect(HouseholdData().glance(now: now) == nil)
        let glance = try #require(household().glance(now: now))
        #expect(glance.lastFeedStart == nil && glance.windowCloses == nil)
        #expect(glance.windowProgress(at: now) == 0)
    }

    @Test func deletedFeedsAreNotShown() throws {
        var data = household()
        let start = at(2026, 11, 16, 1, 0)
        let id = data.add(kind: .feed, babyID: baby, startedAt: start, endedAt: start.addingTimeInterval(1200),
                          payload: EventPayload(feed: FeedDetails()), by: parentA, timeZoneID: "Europe/London", now: start)
        data.delete(id, by: parentA, now: start.addingTimeInterval(1300))
        #expect(try #require(data.glance(now: now)).lastFeedStart == nil)
    }
}

@Suite("Quick finish refused (who does what, A2)")
struct QuickFinishRefusedTests {
    /// A running feed whose details a newer app version wrote: this phone can't finish it, and says so.
    @Test func aFeedThisBuildCantReadIsNotFinishedAndSaysSo() throws {
        var data = HouseholdData()
        let start = at(2026, 11, 20, 2, 0)
        let id = data.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: "Europe/London", now: start)
        var stored = try #require(data.events[id])
        stored.event.payload = Data(#"{"v":99,"stamps":{}}"#.utf8)
        data.events[id] = stored
        let result = data.quickFinishFeed(babyID: baby, by: parentA, now: start.addingTimeInterval(600))
        guard case .couldNotFinish(let feed) = result else {
            Issue.record("expected couldNotFinish, got \(result)")
            return
        }
        #expect(feed.id == id)
        #expect(data.events[id]?.event.endedAt == nil)
    }
}
