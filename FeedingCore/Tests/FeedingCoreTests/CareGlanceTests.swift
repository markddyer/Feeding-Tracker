import Foundation
import Testing
@testable import FeedingCore

/// The Lock Screen's Sleep and nappy widget and the Control Center buttons (the users' choice F
/// and the settled controls, 17 Nov 2026).
@Suite("Sleep and nappy from outside the app")
struct CareGlanceTests {
    let now = at(2026, 11, 17, 11, 25)
    let zone = "Europe/London"

    func household() -> HouseholdData {
        var data = HouseholdData()
        data.put(PlainRecord(type: .baby, name: baby, modifiedAt: now,
                             payload: try? PayloadCoder.encode(BabyPayload(name: "Baby", birthDate: date("2026-11-04")))))
        return data
    }

    // MARK: What the widget shows

    @Test func nothingBeforeThereIsABaby() {
        #expect(HouseholdData().careGlance(now: now) == nil)
    }

    @Test func noSleepOrNappyLoggedYet() throws {
        let glance = try #require(household().careGlance(now: now))
        #expect(glance.sleep == .notLogged)
        #expect(!glance.isAsleep)
        #expect(glance.sleepSince == nil)
        #expect(glance.lastNappyAt == nil)
        #expect(glance.timeZoneID == "Europe/London")
    }

    @Test func asleepSinceItStarted() throws {
        var data = household()
        let started = now.addingTimeInterval(.minutes(-80))
        let id = data.startSleep(babyID: baby, startedAt: started, by: parentA, timeZoneID: zone, now: now)
        let glance = try #require(data.careGlance(now: now))
        #expect(glance.sleep == .asleep(id: id, since: started))
        #expect(glance.isAsleep)
        #expect(glance.sleepSince == started)
    }

    @Test func awakeSinceItEnded() throws {
        var data = household()
        data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: now.addingTimeInterval(.hours(-2)))
        let woke = now.addingTimeInterval(.minutes(-30))
        data.endSleep(babyID: baby, by: parentB, now: woke)
        let glance = try #require(data.careGlance(now: now))
        #expect(glance.sleep == .awake(since: woke))
        #expect(!glance.isAsleep)
        #expect(glance.sleepSince == woke)
    }

    /// Start feed ends a running sleep (the users' choice O): the widget then shows awake since
    /// the feed began.
    @Test func startFeedShowsAwakeSinceTheFeed() throws {
        var data = household()
        data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: now.addingTimeInterval(.hours(-2)))
        let feedStart = now.addingTimeInterval(.minutes(-10))
        _ = data.quickStartFeed(babyID: baby, by: parentA, timeZoneID: zone, now: feedStart)
        let glance = try #require(data.careGlance(now: now))
        #expect(glance.sleep == .awake(since: feedStart))
    }

    @Test func theLastNappyAndWhatItWas() throws {
        var data = household()
        data.addNappy(babyID: baby, wee: true, poo: false, at: now.addingTimeInterval(.hours(-2)), by: parentA,
                      timeZoneID: zone, now: now)
        let last = now.addingTimeInterval(.minutes(-40))
        data.addNappy(babyID: baby, wee: true, poo: true, at: last, by: parentB, timeZoneID: zone, now: now)
        let glance = try #require(data.careGlance(now: now))
        #expect(glance.lastNappyAt == last)
        #expect(glance.lastNappyWee && glance.lastNappyPoo)
    }

    @Test func aDeletedNappyIsLeftOut() throws {
        var data = household()
        let kept = now.addingTimeInterval(.hours(-1))
        data.addNappy(babyID: baby, wee: true, poo: false, at: kept, by: parentA, timeZoneID: zone, now: now)
        let removed = data.addNappy(babyID: baby, wee: false, poo: true, at: now.addingTimeInterval(.minutes(-5)),
                                    by: parentA, timeZoneID: zone, now: now)
        data.delete(removed, by: parentA, now: now)
        let glance = try #require(data.careGlance(now: now))
        #expect(glance.lastNappyAt == kept)
        #expect(glance.lastNappyWee && !glance.lastNappyPoo)
    }

    @Test func anotherBabysSleepAndNappyAreLeftOut() throws {
        var data = household()
        data.startSleep(babyID: "other-baby", by: parentA, timeZoneID: zone, now: now.addingTimeInterval(.hours(-1)))
        data.addNappy(babyID: "other-baby", wee: true, poo: true, by: parentA, timeZoneID: zone, now: now)
        let glance = try #require(data.careGlance(now: now))
        #expect(glance.sleep == .notLogged)
        #expect(glance.lastNappyAt == nil)
    }

    // MARK: The buttons

    @Test func fellAsleepStartsASleepAndSendsItAtOnce() throws {
        var data = household()
        let result = data.quickFellAsleep(babyID: baby, by: parentA, timeZoneID: zone, now: now)
        #expect(result == .fellAsleep(at: now))
        let running = try #require(data.sleepInProgress(babyID: baby, now: now))
        #expect(running.event.loggedBy == parentA)
        #expect(data.eventsToUpload(now: now).map(\.event.id) == [running.id])
    }

    @Test func fellAsleepWhileAsleepChangesNothing() {
        var data = household()
        let since = now.addingTimeInterval(.minutes(-20))
        data.startSleep(babyID: baby, startedAt: since, by: parentB, timeZoneID: zone, now: since)
        let before = data
        #expect(data.quickFellAsleep(babyID: baby, by: parentA, timeZoneID: zone, now: now) == .alreadyAsleep(since: since))
        #expect(data == before)
    }

    @Test func wokeUpEndsTheSleepWhoeverStartedIt() throws {
        var data = household()
        let since = now.addingTimeInterval(.minutes(-80))
        let id = data.startSleep(babyID: baby, startedAt: since, by: parentB, timeZoneID: zone, now: since)
        data.events[id]?.uploadNotBefore = since.addingTimeInterval(HouseholdData.undoWindow)
        let result = data.quickWokeUp(babyID: baby, by: parentA, now: now)
        #expect(result == .wokeUp(at: now, asleepFor: .minutes(80)))
        #expect(data.events[id]?.event.endedAt == now)
        #expect(data.eventsToUpload(now: now).map(\.event.id) == [id])
    }

    @Test func wokeUpWithNoSleepChangesNothing() {
        var data = household()
        data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: now.addingTimeInterval(.hours(-2)))
        data.endSleep(babyID: baby, by: parentA, now: now.addingTimeInterval(.hours(-1)))
        let before = data
        #expect(data.quickWokeUp(babyID: baby, by: parentA, now: now) == .notAsleep)
        #expect(data == before)
        var empty = household()
        #expect(empty.quickWokeUp(babyID: baby, by: parentA, now: now) == .notAsleep)
    }

    @Test(arguments: [(true, false), (false, true), (true, true)])
    func aNappyButtonLogsItsKindWithNoDetails(_ kind: (Bool, Bool)) throws {
        var data = household()
        let result = data.quickNappy(babyID: baby, wee: kind.0, poo: kind.1, by: parentA, timeZoneID: zone, now: now)
        #expect(result == .nappy(at: now, wee: kind.0, poo: kind.1))
        let saved = try #require(data.events.values.first)
        #expect(saved.event.kind == .nappy)
        #expect(saved.snapshot.payload?.nappy == NappyDetails(wee: kind.0, poo: kind.1))
        #expect(saved.snapshot.payload?.nappy?.colour == nil)
        #expect(saved.snapshot.payload?.nappy?.consistency == nil)
        #expect(saved.uploadNotBefore == nil)
    }

    @Test func aMedicineButtonLogsItsName() throws {
        var data = household()
        #expect(data.quickMedicine(babyID: baby, name: " Vitamin D ", by: parentA, timeZoneID: zone, now: now)
                == .medicine(at: now, name: "Vitamin D"))
        #expect(data.lastGiven("Vitamin D", babyID: baby, now: now) == now)
        #expect(data.events.values.allSatisfy { $0.uploadNotBefore == nil })
    }

    @Test func aBlankMedicineNameFallsBackToTheFirstOnTheList() {
        var data = household()
        data.setMedicines(["Infant paracetamol", "Vitamin D"], now: now)
        #expect(data.quickMedicine(babyID: baby, name: "  ", by: parentA, timeZoneID: zone, now: now)
                == .medicine(at: now, name: "Infant paracetamol"))
    }

    /// None of the buttons touches the feeds the alarms are worked out from.
    @Test func theButtonsNeverMoveTheLastFeed() {
        var data = household()
        data.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: zone, now: now.addingTimeInterval(.hours(-1)))
        _ = data.quickFinishFeed(babyID: baby, by: parentA, now: now.addingTimeInterval(.minutes(-30)))
        let before = data.glance(now: now)
        _ = data.quickFellAsleep(babyID: baby, by: parentA, timeZoneID: zone, now: now)
        _ = data.quickNappy(babyID: baby, wee: true, poo: true, by: parentA, timeZoneID: zone, now: now)
        _ = data.quickMedicine(babyID: baby, name: "Vitamin D", by: parentA, timeZoneID: zone, now: now)
        _ = data.quickWokeUp(babyID: baby, by: parentA, now: now.addingTimeInterval(60))
        #expect(data.glance(now: now) == before)
    }
}
