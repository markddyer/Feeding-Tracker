import Foundation
import Testing
@testable import FeedingCore

// "Who does what" (`docs/planning/09-who-does-what.md`): the stored "done by" and "got up", their
// stamps and their merge (engineering review E1, D2 A and D8 A; E3, D9 A).

@Suite("Who does what: stored details")
struct DoneByTests {
    let start = at(2026, 11, 20, 3, 0)

    // MARK: The record

    @Test func anEntryFromAFileWithoutTheNewFieldsReadsWithNoneSet() throws {
        let old = Event(id: "e1", babyID: baby, kind: .nappy, startedAt: start, timeZoneID: "Europe/London",
                        loggedBy: parentA, createdAt: start, modifiedAt: start)
        let json = try JSONEncoder().encode(old)
        let text = String(decoding: json, as: UTF8.self)
        #expect(!text.contains("doneBy") && !text.contains("wakeID") && !text.contains("gotUp"))
        let read = try JSONDecoder().decode(Event.self, from: json)
        #expect(read.doneBy == nil && read.wakeID == nil && read.gotUpBy == nil && read.gotUpFor == nil)
    }

    @Test func theNewFieldsRoundTripThroughTheFile() throws {
        var sleep = sleepEvent(start, start.addingTimeInterval(.hours(1))).event
        sleep.doneBy = parentB
        sleep.wakeID = "wake-1"
        sleep.gotUpBy = parentA
        sleep.gotUpFor = "wake-1"
        let read = try JSONDecoder().decode(Event.self, from: JSONEncoder().encode(sleep))
        #expect(read == sleep)
    }

    @Test func aSleepsEndingIsItsWakeUpIDOrOneMadeFromItsEnd() {
        let end = start.addingTimeInterval(.hours(1))
        var sleep = sleepEvent(start, end, id: "s1").event
        let millis = Int64((end.timeIntervalSince1970 * 1000).rounded())
        #expect(sleep.endingID == "end:s1:\(millis)")
        sleep.wakeID = "wake-1"
        #expect(sleep.endingID == "wake-1:\(millis)")
        sleep.endedAt = nil
        #expect(sleep.endingID == nil)
    }

    // MARK: Which kinds

    @Test func theKindsThatCountAsWork() {
        for kind in [EventKind.feed, .pump, .sleep, .nappy, .medicine, .bath] { #expect(kind.countsAsWork) }
        for kind in [EventKind.growth, .milestone, "future-kind"] { #expect(!kind.countsAsWork) }
    }

    /// The one list of every kind (History's "All" reads it): each kind once, all eight, and
    /// never a kind from a newer build.
    @Test func theListOfEveryKind() {
        #expect(Set(EventKind.known).count == EventKind.known.count)
        #expect(Set(EventKind.known) == [.feed, .pump, .sleep, .nappy, .growth, .medicine, .milestone, .bath])
        #expect(!EventKind.known.contains("future-kind"))
    }

    @Test func aBathHasOnlyTheSharedFieldsAndNoKindIsStampedWithWhoDidIt() {
        #expect(EventField.fields(for: .bath) == [.startedAt, .endedAt, .deletedAt, .note])
        #expect(EventField.fields(for: "future-kind").isDisjoint(with: EventField.onlyWhenSet))
        for kind in [EventKind.feed, .pump, .sleep, .nappy, .growth, .medicine, .milestone, .bath] {
            #expect(EventField.fields(for: kind).isDisjoint(with: EventField.onlyWhenSet))
        }
    }

    // MARK: Stamped only with a value

    @Test func aNewEntryWithNoChoiceHasNoDoneByStamp() throws {
        var data = HouseholdData()
        let id = data.addNappy(babyID: baby, wee: true, poo: false, by: parentA, timeZoneID: "Europe/London", now: start)
        let stored = try #require(data.events[id])
        #expect(stored.event.doneBy == nil)
        #expect(stored.snapshot.payload?.stamp(.doneBy) == nil)
        #expect(!stored.changedFields.contains(.doneBy))
    }

    @Test func aChoiceGivenAtTheStartIsStoredAndStamped() throws {
        var data = HouseholdData()
        let id = data.add(kind: .feed, babyID: baby, startedAt: start, payload: EventPayload(feed: FeedDetails()),
                          by: parentA, doneBy: parentB, timeZoneID: "Europe/London", now: start)
        let stored = try #require(data.events[id])
        #expect(stored.event.doneBy == parentB)
        #expect(stored.snapshot.payload?.stamp(.doneBy) == FieldStamp(at: start, by: parentA))
        #expect(stored.changedFields.contains(.doneBy))
    }

    @Test func aKindThatIsNotWorkTakesNoDoneBy() throws {
        var data = HouseholdData()
        let id = data.add(kind: .growth, babyID: baby, startedAt: start, payload: EventPayload(growth: GrowthDetails(weightGrams: 3900)),
                          by: parentA, doneBy: parentB, timeZoneID: "Europe/London", now: start)
        let stored = try #require(data.events[id])
        #expect(stored.event.doneBy == nil)
        #expect(stored.snapshot.payload?.stamp(.doneBy) == nil)
        let changed1 = data.setDoneBy(id, to: parentB, by: parentA, now: start)
        #expect(!changed1)
    }

    @Test func aParentsChoiceIsStoredWithItsStamp() throws {
        var data = HouseholdData()
        let id = data.addNappy(babyID: baby, wee: true, poo: true, by: parentA, timeZoneID: "Europe/London", now: start)
        let later = start.addingTimeInterval(5)
        let changed2 = data.setDoneBy(id, to: parentB, by: parentA, now: later)
        #expect(changed2)
        let stored = try #require(data.events[id])
        #expect(stored.event.doneBy == parentB)
        #expect(stored.snapshot.payload?.stamp(.doneBy) == FieldStamp(at: later, by: parentA))
        #expect(stored.changedFields.contains(.doneBy))
        // The same choice again changes nothing, and still reports success.
        let changed3 = data.setDoneBy(id, to: parentB, by: parentB, now: later.addingTimeInterval(5))
        #expect(changed3)
        #expect(data.events[id]?.snapshot.payload?.stamp(.doneBy) == FieldStamp(at: later, by: parentA))
    }

    // MARK: "Got up"

    @Test func gotUpNeedsAnEndedSleepAndBelongsToItsEnding() throws {
        var data = HouseholdData()
        let id = data.startSleep(babyID: baby, by: parentA, timeZoneID: "Europe/London", now: start)
        let changed4 = data.setGotUp(id, to: parentB, by: parentB, now: start.addingTimeInterval(60))
        #expect(!changed4)

        let woke = start.addingTimeInterval(.hours(2))
        data.endSleep(babyID: baby, by: parentA, now: woke)
        let changed5 = data.setGotUp(id, to: parentB, by: parentB, now: woke.addingTimeInterval(5))
        #expect(changed5)
        let ended = try #require(data.events[id]?.event)
        #expect(ended.gotUpFor == ended.endingID)
        #expect(ended.validGotUp == parentB)

        // Change time moves the end but keeps the wake-up, so "got up" moves with it (D8 A).
        data.edit(id, by: parentA, now: woke.addingTimeInterval(60)) {
            $0.event.endedAt = woke.addingTimeInterval(-.minutes(10))
        }
        #expect(data.events[id]?.event.validGotUp == parentB)

        // Reopened and ended again: a new wake-up, so the old "got up" is left behind; the new
        // ending's own "got up" is who ended it.
        data.edit(id, by: parentA, now: woke.addingTimeInterval(120)) { $0.event.endedAt = nil }
        #expect(data.events[id]?.event.wakeID == nil)
        data.endSleep(babyID: baby, by: parentA, now: woke.addingTimeInterval(180))
        let again = try #require(data.events[id]?.event)
        #expect(again.wakeID != ended.wakeID)
        #expect(again.validGotUp == parentA)
    }

    /// A sleep ended before wake-up IDs existed: a "got up" given for it belongs to its end time.
    /// An end this build changes takes it along (Codex review, 21 Nov 2026); one an older build
    /// changes leaves it behind.
    @Test func anOldSleepsGotUpBelongsToItsEndTime() throws {
        var data = HouseholdData()
        let woke = start.addingTimeInterval(.hours(1))
        let old = sleepEvent(start, woke, id: "old").event
        data.events["old"] = StoredEvent(event: try EventSnapshot(event: old, payload: EventPayload()).encoded(),
                                         changedFields: [], needsUpload: false, systemFields: Data([1]), localRevision: 1)
        let changed = data.setGotUp("old", to: parentB, by: parentA, now: woke.addingTimeInterval(60))
        #expect(changed)
        #expect(data.events["old"]?.event.validGotUp == parentB)
        #expect(data.events["old"]?.event.wakeID == nil)
        data.edit("old", by: parentA, now: woke.addingTimeInterval(120)) { $0.event.endedAt = woke.addingTimeInterval(-60) }
        #expect(data.events["old"]?.event.validGotUp == parentB, "moved with the end changed here")
        // An older build changes the end and knows nothing of "got up".
        var older = try #require(data.events["old"]?.event)
        older.endedAt = woke.addingTimeInterval(-300)
        data.receiveEvent(older, systemFields: Data([2]))
        #expect(data.events["old"]?.event.validGotUp == nil, "left behind")
    }

    @Test func gotUpChosenForOneEndingIsNotGivenToALaterOne() throws {
        // Codex review, 21 Nov 2026: an editor (or the Undo card) chose for the ending it showed.
        var data = HouseholdData()
        let woke = start.addingTimeInterval(.hours(1))
        data.add(id: "s", kind: .sleep, babyID: baby, startedAt: start, payload: EventPayload(), by: parentA,
                 timeZoneID: "Europe/London", now: start)
        data.endSleep(babyID: baby, at: woke, by: parentA, now: woke)
        let shown = try #require(data.events["s"]?.event.endingID)
        let stale = data.setGotUp("s", to: parentB, for: "another-ending", by: parentA, now: woke.addingTimeInterval(60))
        #expect(!stale)
        #expect(data.events["s"]?.event.validGotUp == parentA)
        let fresh = data.setGotUp("s", to: parentB, for: shown, by: parentA, now: woke.addingTimeInterval(60))
        #expect(fresh)
        #expect(data.events["s"]?.event.validGotUp == parentB)
    }

    @Test func gotUpIsOnlyForSleeps() throws {
        var data = HouseholdData()
        let id = data.addNappy(babyID: baby, wee: true, poo: false, by: parentA, timeZoneID: "Europe/London", now: start)
        let changed6 = data.setGotUp(id, to: parentA, by: parentA, now: start)
        #expect(!changed6)
    }

    // MARK: Merging

    func stamped(_ snapshot: EventSnapshot, _ field: EventField, at time: Date, by member: MemberID,
                 edit: (inout EventSnapshot) -> Void) -> EventSnapshot {
        var copy = snapshot
        edit(&copy)
        copy.payload?.setStamp(field, FieldStamp(at: time, by: member))
        copy.event.modifiedAt = time
        return copy
    }

    @Test func theLaterDoneByWinsInEitherOrder() {
        let base = nappyEvent(start, id: "n1")
        let byA = stamped(base, .doneBy, at: start.addingTimeInterval(10), by: parentA) { $0.event.doneBy = parentA }
        let byB = stamped(base, .doneBy, at: start.addingTimeInterval(20), by: parentB) { $0.event.doneBy = parentB }
        let onPhoneA = merge(local: byA, server: byB, changedLocally: [.doneBy])
        let onPhoneB = merge(local: byB, server: byA, changedLocally: [.doneBy])
        #expect(onPhoneA.snapshot.event.doneBy == parentB)
        #expect(onPhoneA.overruled == [.doneBy])
        #expect(onPhoneB.snapshot.event.doneBy == parentB)
        #expect(onPhoneB.applied == [.doneBy])
        #expect(onPhoneB.snapshot.payload?.stamp(.doneBy)?.by == parentB)
    }

    @Test func theEndAndItsWakeUpIDMergeAsOne() {
        let base = sleepEvent(start, id: "s1")
        let woke = start.addingTimeInterval(.hours(2))
        let local = stamped(base, .endedAt, at: woke, by: parentA) {
            $0.event.endedAt = woke
            $0.event.wakeID = "wake-A"
        }
        let result = merge(local: local, server: base, changedLocally: [.endedAt])
        #expect(result.snapshot.event.endedAt == woke)
        #expect(result.snapshot.event.wakeID == "wake-A")
    }

    /// A late correction meant for an earlier ending never replaces the current ending's "got up".
    @Test func aGotUpForAnEarlierEndingGivesWayToTheCurrentOne() {
        let first = start.addingTimeInterval(.hours(1))
        let second = start.addingTimeInterval(.hours(2))
        let base = sleepEvent(start, id: "s1")
        // iCloud: ended at the first wake-up, with Parent B's later correction for that ending.
        var server = stamped(base, .endedAt, at: first, by: parentB) {
            $0.event.endedAt = first
            $0.event.wakeID = "wake-1"
        }
        server = stamped(server, .gotUp, at: second.addingTimeInterval(600), by: parentB) {
            $0.event.gotUpBy = parentB
            $0.event.gotUpFor = $0.event.endingID
        }
        // This phone: reopened and ended again at the second wake-up, Parent A got up.
        var local = stamped(base, .endedAt, at: second, by: parentA) {
            $0.event.endedAt = second
            $0.event.wakeID = "wake-2"
        }
        local = stamped(local, .gotUp, at: second, by: parentA) {
            $0.event.gotUpBy = parentA
            $0.event.gotUpFor = $0.event.endingID
        }
        let result = merge(local: local, server: server, changedLocally: [.endedAt, .gotUp])
        #expect(result.snapshot.event.wakeID == "wake-2")
        #expect(result.snapshot.event.validGotUp == parentA)
        #expect(result.applied.contains(.gotUp))
        #expect(!result.overruled.contains(.gotUp))
    }

    @Test func aGotUpForTheMergedEndingIsKeptOverALaterMismatchedOne() {
        let woke = start.addingTimeInterval(.hours(1))
        var server = stamped(sleepEvent(start, id: "s1"), .endedAt, at: woke, by: parentB) {
            $0.event.endedAt = woke
            $0.event.wakeID = "wake-1"
        }
        server = stamped(server, .gotUp, at: woke, by: parentB) {
            $0.event.gotUpBy = parentB
            $0.event.gotUpFor = $0.event.endingID
        }
        // This phone holds a stale "got up" for an ending iCloud no longer has, stamped later.
        let local = stamped(server, .gotUp, at: woke.addingTimeInterval(300), by: parentA) {
            $0.event.gotUpBy = parentA
            $0.event.gotUpFor = "wake-0"
        }
        let result = merge(local: local, server: server, changedLocally: [.gotUp])
        #expect(result.snapshot.event.validGotUp == parentB)
        #expect(result.overruled.contains(.gotUp))
        #expect(!result.applied.contains(.gotUp))
    }

    // MARK: Older builds

    /// Stamps are read by name, so an older build that knows no "doneBy" field keeps its stamp.
    @Test func aStampNameThisBuildDoesNotKnowIsKept() throws {
        var payload = EventPayload(nappy: NappyDetails(wee: true, poo: false))
        payload.stamps["fieldFromANewerBuild"] = FieldStamp(at: start, by: parentB)
        let read = try #require(PayloadCoder.decode(EventPayload.self, from: try PayloadCoder.encode(payload)))
        #expect(read.stamps["fieldFromANewerBuild"] == FieldStamp(at: start, by: parentB))
        let again = try #require(PayloadCoder.decode(EventPayload.self, from: try PayloadCoder.encode(read)))
        #expect(again.stamps["fieldFromANewerBuild"] == FieldStamp(at: start, by: parentB))
    }

    @Test func storingWhoDidItKeepsTheDetailsVersion() throws {
        var data = HouseholdData()
        let id = data.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: "Europe/London", now: start)
        let changed7 = data.setDoneBy(id, to: parentB, by: parentA, now: start.addingTimeInterval(5))
        #expect(changed7)
        let payload = try #require(data.events[id]?.snapshot.payload)
        #expect(payload.v == 1)
    }

    // MARK: Alerts never read it

    @Test func alertsAreTheSameWithWhoDidItAndBaths() {
        let feedStart = at(2026, 11, 20, 1, 0)
        let now = at(2026, 11, 20, 1, 30)
        let plain = feed(feedStart, id: "f1")
        var chosen = plain
        chosen.doneBy = parentB
        let bath = Event(id: "b1", babyID: baby, kind: .bath, startedAt: at(2026, 11, 20, 1, 20), timeZoneID: "Europe/London",
                         loggedBy: parentB, createdAt: now, modifiedAt: now, doneBy: parentB)
        let expected = summary(run([plain], now: now))
        #expect(summary(run([chosen], now: now)) == expected)
        #expect(summary(run([plain, bath], now: now)) == expected)
    }
}

@Suite("Who does what: wake-ups")
struct WakeUpTests {
    let start = at(2026, 11, 20, 1, 0)
    let zone = "Europe/London"

    /// A second sleep running at once, as when each phone tapped "Fell asleep".
    func secondSleep(_ data: inout HouseholdData, at time: Date, babyID: String = baby, by member: MemberID = parentB) -> String {
        data.add(kind: .sleep, babyID: babyID, startedAt: time, payload: EventPayload(), by: member, timeZoneID: zone, now: time)
    }

    func lateFeed(_ data: inout HouseholdData, at time: Date, babyID: String = baby, by member: MemberID = parentB) -> String {
        data.add(kind: .feed, babyID: babyID, startedAt: time, payload: EventPayload(feed: FeedDetails()), by: member,
                 timeZoneID: zone, now: time)
    }

    @Test func oneWokeUpEndingTwoSleepsIsOneWakeUp() throws {
        var data = HouseholdData()
        let first = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: start)
        let second = secondSleep(&data, at: start.addingTimeInterval(60))
        let ended = data.endSleep(babyID: baby, by: parentB, now: start.addingTimeInterval(.hours(2)))
        #expect(Set(ended) == [first, second])
        let a = try #require(data.events[first]?.event)
        let b = try #require(data.events[second]?.event)
        #expect(a.wakeID != nil && a.wakeID == b.wakeID)
        #expect(a.validGotUp == parentB && b.validGotUp == parentB)
    }

    @Test func theSwapChangesEverySleepOfTheWakeUp() throws {
        var data = HouseholdData()
        let first = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: start)
        let second = secondSleep(&data, at: start.addingTimeInterval(60))
        let woke = start.addingTimeInterval(.hours(2))
        data.endSleep(babyID: baby, by: parentB, now: woke)
        let swapped = data.setGotUp(first, to: parentA, by: parentB, now: woke.addingTimeInterval(3))
        #expect(swapped)
        #expect(data.events[first]?.event.validGotUp == parentA)
        #expect(data.events[second]?.event.validGotUp == parentA)
    }

    @Test func startFeedGivesTheSleepTheFeedsWakeUp() throws {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: start)
        let feed = data.startFeed(babyID: baby, side: .left, by: parentB, timeZoneID: zone, now: start.addingTimeInterval(.hours(1)))
        let ended = try #require(data.events[sleep]?.event)
        #expect(ended.wakeID == HouseholdData.feedWakeID(feed))
        #expect(ended.validGotUp == parentB)
    }

    /// The late-feed rule runs on either phone: the feed's logger got up, and each feed is its own
    /// wake-up, for each baby.
    @Test func theLateFeedRuleNeverJoinsTwoFeedsOrTwoBabies() throws {
        var data = HouseholdData()
        let sleep1 = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: start)
        let sleep2 = secondSleep(&data, at: start, babyID: "baby-2", by: parentA)
        let feed1 = lateFeed(&data, at: start.addingTimeInterval(.hours(1)))
        let feed2 = lateFeed(&data, at: start.addingTimeInterval(.hours(1)), babyID: "baby-2")
        data.endSleepsInterruptedByFeeds(by: parentA, now: start.addingTimeInterval(.hours(2)))
        let one = try #require(data.events[sleep1]?.event)
        let two = try #require(data.events[sleep2]?.event)
        #expect(one.wakeID == HouseholdData.feedWakeID(feed1))
        #expect(two.wakeID == HouseholdData.feedWakeID(feed2))
        #expect(one.validGotUp == parentB && two.validGotUp == parentB)
    }

    /// A sleep that reaches this phone after the rule ran for the same feed joins the same wake-up.
    @Test func oneFeedEndingSleepsInTwoPassesIsOneWakeUp() throws {
        var data = HouseholdData()
        let first = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: start)
        let feed = lateFeed(&data, at: start.addingTimeInterval(.hours(1)))
        data.endSleepsInterruptedByFeeds(by: parentA, now: start.addingTimeInterval(.hours(2)))
        let second = secondSleep(&data, at: start.addingTimeInterval(60))
        data.endSleepsInterruptedByFeeds(by: parentA, now: start.addingTimeInterval(.hours(3)))
        #expect(data.events[first]?.event.wakeID == HouseholdData.feedWakeID(feed))
        #expect(data.events[second]?.event.wakeID == HouseholdData.feedWakeID(feed))
    }

    /// The sleep's editor ("Still asleep" off) ends it with a wake-up of its own.
    @Test func anEndFromTheEditorGetsItsOwnWakeUp() throws {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: start)
        data.edit(sleep, by: parentB, now: start.addingTimeInterval(.hours(2))) {
            $0.event.endedAt = start.addingTimeInterval(.hours(2))
        }
        let ended = try #require(data.events[sleep]?.event)
        #expect(ended.wakeID != nil)
        #expect(ended.validGotUp == parentB)
    }

    @Test func discardTakesTheWakeUpAwayWithTheEnd() throws {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: start)
        let feed = data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: zone, now: start.addingTimeInterval(.hours(1)))
        data.discardFeed(feed, by: parentA, now: start.addingTimeInterval(.hours(1) + 30))
        let reopened = try #require(data.events[sleep]?.event)
        #expect(reopened.endedAt == nil && reopened.wakeID == nil && reopened.validGotUp == nil)
    }

    /// A Woke up tapped by hand after a feed: discarding that feed leaves the sleep ended.
    @Test func discardNeverReopensASleepAnotherWakeUpEnded() throws {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: start)
        let feedTime = start.addingTimeInterval(.hours(1))
        data.endSleep(babyID: baby, by: parentA, now: feedTime)
        let feed = data.add(kind: .feed, babyID: baby, startedAt: feedTime, payload: EventPayload(feed: FeedDetails()),
                            by: parentA, timeZoneID: zone, now: feedTime)
        data.discardFeed(feed, by: parentA, now: feedTime.addingTimeInterval(30))
        #expect(data.events[sleep]?.event.endedAt == feedTime)
    }
}

@Suite("Who does what: values an older build dropped")
struct MissingWhoValueTests {
    let start = at(2026, 11, 20, 3, 0)
    let zone = "Europe/London"

    /// What an older build leaves in the file: the details (with their stamps) kept as they were,
    /// the record fields it doesn't know gone.
    func droppedByAnOlderBuild(_ data: inout HouseholdData, _ id: String) {
        guard var stored = data.events[id] else { return }
        stored.event.doneBy = nil
        stored.event.wakeID = nil
        stored.event.gotUpBy = nil
        stored.event.gotUpFor = nil
        data.events[id] = stored
    }

    @Test func entriesWithAStampAndNoValueAreListed() throws {
        var data = HouseholdData()
        let nappy = data.addNappy(babyID: baby, wee: true, poo: false, by: parentA, timeZoneID: zone, now: start)
        let plain = data.addNappy(babyID: baby, wee: true, poo: false, by: parentA, timeZoneID: zone, now: start)
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: start)
        let chosen = data.setDoneBy(nappy, to: parentB, by: parentA, now: start.addingTimeInterval(5))
        #expect(chosen)
        data.endSleep(babyID: baby, by: parentB, now: start.addingTimeInterval(.hours(1)))
        #expect(data.entriesMissingWhoValues.isEmpty)

        droppedByAnOlderBuild(&data, nappy)
        droppedByAnOlderBuild(&data, sleep)
        droppedByAnOlderBuild(&data, plain)
        #expect(data.entriesMissingWhoValues == [nappy, sleep].sorted())
    }

    @Test func anEntryIsCheckedOnceAndOneThatGotItsValueBackLeavesTheNote() throws {
        var data = HouseholdData()
        let nappy = data.addNappy(babyID: baby, wee: true, poo: false, by: parentA, timeZoneID: zone, now: start)
        let other = data.addNappy(babyID: baby, wee: false, poo: true, by: parentA, timeZoneID: zone, now: start)
        data.setDoneBy(nappy, to: parentB, by: parentA, now: start.addingTimeInterval(5))
        data.setDoneBy(other, to: parentB, by: parentA, now: start.addingTimeInterval(5))
        droppedByAnOlderBuild(&data, nappy)
        droppedByAnOlderBuild(&data, other)

        // iCloud has the value for one (it comes back), and none for the other.
        data.events[other]?.event.doneBy = parentB
        data.noteWhoValuesFetched([nappy, other])
        #expect(data.whoValuesChecked == [nappy])
        #expect(data.entriesMissingWhoValues.isEmpty)
    }

    @Test func theCheckedListSurvivesTheFile() throws {
        var data = HouseholdData()
        let nappy = data.addNappy(babyID: baby, wee: true, poo: false, by: parentA, timeZoneID: zone, now: start)
        data.setDoneBy(nappy, to: parentB, by: parentA, now: start.addingTimeInterval(5))
        droppedByAnOlderBuild(&data, nappy)
        data.noteWhoValuesFetched([nappy])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let read = try decoder.decode(HouseholdData.self, from: encoder.encode(data))
        #expect(read.whoValuesChecked == [nappy])
        #expect(read.keptParts.isEmpty)
    }
}
