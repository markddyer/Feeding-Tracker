import Foundation
import Testing
@testable import FeedingCore

// Sleep, nappies, growth and medicine (`docs/planning/06-more-than-feeds.md`).

/// A sleep from `start`, ended at `end` (nil while asleep).
func sleepEvent(_ start: Date, _ end: Date? = nil, id: String = UUID().uuidString, babyID: String = baby,
                by: MemberID = parentA, deletedAt: Date? = nil, timeZoneID: String = "Europe/London") -> EventSnapshot {
    EventSnapshot(
        event: Event(id: id, babyID: babyID, kind: .sleep, startedAt: start, endedAt: end, timeZoneID: timeZoneID,
                     loggedBy: by, createdAt: start, modifiedAt: start, deletedAt: deletedAt),
        payload: EventPayload())
}

func nappyEvent(_ at: Date, wee: Bool = true, poo: Bool = false, id: String = UUID().uuidString, by: MemberID = parentA,
                deletedAt: Date? = nil) -> EventSnapshot {
    snapshot(at, id: id, kind: .nappy, by: by, deletedAt: deletedAt, payload: EventPayload(nappy: NappyDetails(wee: wee, poo: poo)))
}

@Suite("More than feeds: payloads")
struct MoreThanFeedsPayloadTests {
    let start = at(2026, 11, 17, 10, 0)

    @Test func eachNewKindRoundTripsAsVersionTwo() throws {
        let payloads = [
            EventPayload(nappy: NappyDetails(wee: true, poo: true, colour: .yellow, consistency: .loose)),
            EventPayload(nappy: NappyDetails(wee: true, poo: false)),
            EventPayload(growth: GrowthDetails(weightGrams: 3850, lengthMM: 525, headMM: 360)),
            EventPayload(growth: GrowthDetails(weightGrams: 3850)),
            EventPayload(medicine: MedicineDetails(name: "Vitamin D", amount: "1 drop"), note: "With the morning feed"),
            EventPayload(medicine: MedicineDetails(name: "Vitamin D")),
        ]
        for payload in payloads {
            #expect(payload.v == 2)
            #expect(PayloadCoder.decode(EventPayload.self, from: try PayloadCoder.encode(payload)) == payload)
        }
    }

    /// A feed, a pumping session and a sleep have no version 2 details, so they are still written
    /// as version 1, and a phone on an older build reads them as before.
    @Test func feedsPumpingAndSleepsStayVersionOne() throws {
        for payload in [breast(.left), EventPayload(pump: PumpDetails(side: .left)), EventPayload(), EventPayload(note: "x")] {
            #expect(payload.v == 1)
            #expect(String(decoding: try PayloadCoder.encode(payload), as: UTF8.self).contains(#""v":1"#))
        }
        var data = HouseholdData()
        let id = data.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: "Europe/London", now: start)
        let saved = try #require(data.events[id]?.event.payload)
        #expect(String(decoding: saved, as: UTF8.self).contains(#""v":1"#))
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: "Europe/London", now: start)
        #expect(data.events[sleep]?.snapshot.payload?.v == 1)
    }

    @Test func addingANewDetailRaisesTheVersionAndItNeverGoesDown() {
        var payload = EventPayload(note: "x")
        #expect(payload.v == 1)
        payload.nappy = NappyDetails(wee: true, poo: false)
        #expect(payload.v == 2)
        payload.nappy = nil
        #expect(payload.v == 2)
    }

    @Test func aVersionOnePayloadReadsWithNoNewDetails() {
        let decoded = PayloadCoder.decode(EventPayload.self, from: Data(#"{"v":1,"note":"hi","stamps":{}}"#.utf8))
        #expect(decoded?.note == "hi")
        #expect(decoded?.nappy == nil)
        #expect(decoded?.growth == nil)
        #expect(decoded?.medicine == nil)
    }

    @Test func aNappyWithNoColourOrConsistencyReadsThemAsNotGiven() throws {
        let json = #"{"v":2,"nappy":{"poo":true,"wee":false},"stamps":{}}"#
        let nappy = try #require(PayloadCoder.decode(EventPayload.self, from: Data(json.utf8))?.nappy)
        #expect(nappy == NappyDetails(wee: false, poo: true))
        #expect(nappy.colour == nil)
        #expect(nappy.consistency == nil)
    }

    /// A colour or consistency from a newer app version is kept, and saved back unchanged.
    @Test func anUnknownColourOrConsistencySurvives() throws {
        // Sorted keys, as `PayloadCoder` writes them, so the bytes can be compared.
        let json = #"{"nappy":{"colour":"orange","consistency":"seedy","poo":true,"wee":false},"stamps":{},"v":2}"#
        let decoded = try #require(PayloadCoder.decode(EventPayload.self, from: Data(json.utf8)))
        #expect(decoded.nappy?.colour == PooColour(rawValue: "orange"))
        #expect(decoded.nappy?.consistency == PooConsistency(rawValue: "seedy"))
        #expect(!PooColour.known.contains(PooColour(rawValue: "orange")))
        #expect(String(decoding: try PayloadCoder.encode(decoded), as: UTF8.self) == json)
    }

    @Test func theOffersAreInOrder() {
        #expect(PooColour.known.map(\.rawValue) == ["brown", "yellow", "green", "other"])
        #expect(PooConsistency.known.map(\.rawValue) == ["liquid", "loose", "firm"])
    }

    @Test func eachKindIsStampedWithItsOwnFields() {
        let shared: Set<EventField> = [.startedAt, .endedAt, .deletedAt, .note]
        #expect(EventField.fields(for: .feed) == shared.union([.breast, .bottles]))
        #expect(EventField.fields(for: .sleep) == shared)
        #expect(EventField.fields(for: .nappy) == shared.union([.nappy, .pooColour, .pooConsistency]))
        #expect(EventField.fields(for: .growth) == shared.union([.weight, .length, .head]))
        #expect(EventField.fields(for: .medicine) == shared.union([.medicine]))
        #expect(EventField.fields(for: "a-newer-kind") == Set(EventField.allCases))

        var data = HouseholdData()
        let id = data.addNappy(babyID: baby, wee: false, poo: true, by: parentA, timeZoneID: "Europe/London", now: start)
        #expect(data.events[id]?.changedFields == EventField.fields(for: .nappy))
        #expect(data.events[id]?.snapshot.payload?.stamp(.pooColour) == FieldStamp(at: start, by: parentA))
        #expect(data.events[id]?.snapshot.payload?.stamp(.breast) == nil)
    }
}

@Suite("More than feeds: merging two phones' edits")
struct MoreThanFeedsMergeTests {
    let start = at(2026, 11, 17, 10, 0)

    func stamped(_ snapshot: EventSnapshot, _ fields: [EventField], at time: Date, by member: MemberID,
                 edit: (inout EventSnapshot) -> Void) -> EventSnapshot {
        var copy = snapshot
        edit(&copy)
        for field in fields { copy.payload?.setStamp(field, FieldStamp(at: time, by: member)) }
        copy.event.modifiedAt = time
        return copy
    }

    var nappy: EventSnapshot { nappyEvent(start, wee: false, poo: true, id: "n1") }
    var growth: EventSnapshot {
        snapshot(start, id: "g1", kind: .growth, payload: EventPayload(growth: GrowthDetails(weightGrams: 3800)))
    }

    /// Parent A adds the colour while Parent B adds the consistency to an old copy: both are kept,
    /// whichever phone merges.
    @Test func aColourOnOnePhoneAndAConsistencyOnTheOtherAreBothKept() {
        let byA = stamped(nappy, [.pooColour], at: at(2026, 11, 17, 10, 2), by: parentA) { $0.payload?.nappy?.colour = .yellow }
        let byB = stamped(nappy, [.pooConsistency], at: at(2026, 11, 17, 10, 3), by: parentB) {
            $0.payload?.nappy?.consistency = .loose
        }
        for result in [merge(local: byA, server: byB, changedLocally: [.pooColour]),
                       merge(local: byB, server: byA, changedLocally: [.pooConsistency])] {
            #expect(result.snapshot.payload?.nappy == NappyDetails(wee: false, poo: true, colour: .yellow, consistency: .loose))
        }
    }

    @Test func theLaterColourWins() {
        let server = stamped(nappy, [.pooColour], at: at(2026, 11, 17, 10, 5), by: parentB) { $0.payload?.nappy?.colour = .green }
        let earlier = stamped(nappy, [.pooColour], at: at(2026, 11, 17, 10, 4), by: parentA) { $0.payload?.nappy?.colour = .brown }
        let later = stamped(nappy, [.pooColour], at: at(2026, 11, 17, 10, 6), by: parentA) { $0.payload?.nappy?.colour = .brown }
        #expect(merge(local: earlier, server: server, changedLocally: [.pooColour]).snapshot.payload?.nappy?.colour == .green)
        #expect(merge(local: later, server: server, changedLocally: [.pooColour]).snapshot.payload?.nappy?.colour == .brown)
    }

    /// A correction from poo to both keeps the colour the other phone added.
    @Test func weeAndPooMergeApartFromTheDetails() {
        let server = stamped(nappy, [.pooColour], at: at(2026, 11, 17, 10, 2), by: parentB) { $0.payload?.nappy?.colour = .yellow }
        let local = stamped(nappy, [.nappy], at: at(2026, 11, 17, 10, 3), by: parentA) { $0.payload?.nappy?.wee = true }
        let result = merge(local: local, server: server, changedLocally: [.nappy])
        #expect(result.snapshot.payload?.nappy == NappyDetails(wee: true, poo: true, colour: .yellow))
        #expect(result.applied == [.nappy])
    }

    @Test func consistencyAlsoMergesOnItsOwn() {
        let server = stamped(nappy, [.pooConsistency], at: at(2026, 11, 17, 10, 5), by: parentB) {
            $0.payload?.nappy?.consistency = .firm
        }
        let later = stamped(nappy, [.pooConsistency], at: at(2026, 11, 17, 10, 6), by: parentA) {
            $0.payload?.nappy?.consistency = .liquid
        }
        #expect(merge(local: later, server: server, changedLocally: [.pooConsistency]).snapshot.payload?.nappy?.consistency == .liquid)
    }

    @Test func anUnknownColourSurvivesAMerge() {
        let server = stamped(nappy, [.pooColour], at: at(2026, 11, 17, 10, 2), by: parentB) {
            $0.payload?.nappy?.colour = PooColour(rawValue: "orange")
        }
        let local = stamped(nappy, [.pooConsistency], at: at(2026, 11, 17, 10, 3), by: parentA) { $0.payload?.nappy?.consistency = .loose }
        let result = merge(local: local, server: server, changedLocally: [.pooConsistency])
        #expect(result.snapshot.payload?.nappy?.colour?.rawValue == "orange")
        #expect(result.snapshot.payload?.nappy?.consistency == .loose)
    }

    /// One parent adds the head while the other corrects the weight: both are kept.
    @Test func eachGrowthMeasurementMergesOnItsOwn() {
        let byA = stamped(growth, [.head], at: at(2026, 11, 17, 10, 2), by: parentA) { $0.payload?.growth?.headMM = 360 }
        let byB = stamped(growth, [.weight], at: at(2026, 11, 17, 10, 3), by: parentB) { $0.payload?.growth?.weightGrams = 3850 }
        let result = merge(local: byA, server: byB, changedLocally: [.head])
        #expect(result.snapshot.payload?.growth == GrowthDetails(weightGrams: 3850, headMM: 360))
        let length = stamped(growth, [.length], at: at(2026, 11, 17, 10, 4), by: parentA) { $0.payload?.growth?.lengthMM = 525 }
        #expect(merge(local: length, server: byB, changedLocally: [.length]).snapshot.payload?.growth
            == GrowthDetails(weightGrams: 3850, lengthMM: 525))
    }

    @Test func theLaterMedicineWins() {
        let base = snapshot(start, id: "m1", kind: .medicine, payload: EventPayload(medicine: MedicineDetails(name: "Vitamin D")))
        let server = stamped(base, [.medicine], at: at(2026, 11, 17, 10, 2), by: parentB) {
            $0.payload?.medicine?.amount = "1 drop"
        }
        let later = stamped(base, [.medicine], at: at(2026, 11, 17, 10, 3), by: parentA) {
            $0.payload?.medicine?.amount = "2 drops"
        }
        #expect(merge(local: later, server: server, changedLocally: [.medicine]).snapshot.payload?.medicine?.amount == "2 drops")
        #expect(merge(local: server, server: later, changedLocally: [.medicine]).snapshot.payload?.medicine?.amount == "2 drops")
    }

    /// A merge never gives a feed nappy or growth details, which would raise its version and hide
    /// its sides and bottles from a phone on an older build.
    @Test func aFeedNeverGainsNewDetailsInAMerge() {
        let feed = snapshot(start, id: "f1", payload: breast(.left))
        let local = stamped(feed, [.nappy, .pooColour, .weight, .medicine], at: at(2026, 11, 17, 10, 2), by: parentA) { _ in }
        let result = merge(local: local, server: feed, changedLocally: [.nappy, .pooColour, .weight, .medicine])
        #expect(result.snapshot.payload?.nappy == nil)
        #expect(result.snapshot.payload?.growth == nil)
        #expect(result.snapshot.payload?.medicine == nil)
        #expect(result.snapshot.payload?.v == 1)
    }

    @Test func eachDetailIsFoundAsItsOwnChange() {
        var after = nappy
        after.payload?.nappy?.colour = .green
        #expect(EventSnapshot.changedFields(from: nappy, to: after) == [.pooColour])
        after.payload?.nappy?.consistency = .firm
        #expect(EventSnapshot.changedFields(from: nappy, to: after) == [.pooColour, .pooConsistency])
        after.payload?.nappy?.wee = true
        #expect(EventSnapshot.changedFields(from: nappy, to: after) == [.nappy, .pooColour, .pooConsistency])

        var grown = growth
        grown.payload?.growth?.lengthMM = 525
        #expect(EventSnapshot.changedFields(from: growth, to: grown) == [.length])
    }

    /// The whole path on one phone: the nappy is saved, sent, its colour added here, and iCloud's
    /// copy arrives with the other phone's consistency. Both are kept and sent again.
    @Test func aSaveClashKeepsBothPhonesDetails() throws {
        var data = HouseholdData()
        let id = data.addNappy(id: "n1", babyID: baby, wee: false, poo: true, by: parentA, timeZoneID: "Europe/London", now: start)
        data.didUploadEvent(id, sentRevision: 1, systemFields: Data([1]), serverCreatedAt: start)
        // iCloud's copy: the one sent, with the other phone's consistency added.
        var server = try #require(data.events[id]?.snapshot)
        data.edit(id, by: parentA, now: at(2026, 11, 17, 10, 2)) { $0.payload?.nappy?.colour = .yellow }
        #expect(data.events[id]?.changedFields == [.pooColour])

        server.payload?.nappy?.consistency = .loose
        server.payload?.setStamp(.pooConsistency, FieldStamp(at: at(2026, 11, 17, 10, 3), by: parentB))
        let outcome = data.receiveEvent(try server.encoded(), systemFields: Data([2]))
        #expect(outcome == .merged(applied: [.pooColour], overruled: []))
        #expect(data.events[id]?.snapshot.payload?.nappy == NappyDetails(wee: false, poo: true, colour: .yellow, consistency: .loose))
        #expect(data.events[id]?.needsUpload == true)
    }
}

@Suite("More than feeds: logging")
struct MoreThanFeedsStoreTests {
    let t0 = at(2026, 11, 17, 10, 0)
    let zone = "Europe/London"

    @Test func oneSleepRunsAtATime() {
        var data = HouseholdData()
        let first = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0)
        let again = data.startSleep(babyID: baby, by: parentB, timeZoneID: zone, now: t0.addingTimeInterval(60))
        #expect(again == first)
        #expect(data.events.count == 1)
        #expect(data.sleepInProgress(babyID: baby, now: t0)?.id == first)
    }

    @Test func wokeUpEndsTheSleep() throws {
        var data = HouseholdData()
        let id = data.startSleep(babyID: baby, startedAt: t0.addingTimeInterval(.minutes(-10)), by: parentA, timeZoneID: zone, now: t0)
        #expect(data.events[id]?.event.startedAt == t0.addingTimeInterval(.minutes(-10)))
        let woke = t0.addingTimeInterval(.hours(1))
        let ended = data.endSleep(babyID: baby, by: parentB, now: woke)
        #expect(ended == [id])
        let sleep = try #require(data.events[id])
        #expect(sleep.event.endedAt == woke)
        #expect(sleep.snapshot.payload?.stamp(.endedAt) == FieldStamp(at: woke, by: parentB))
        #expect(data.sleepInProgress(babyID: baby, now: woke) == nil)
        let endedAgain = data.endSleep(babyID: baby, by: parentB, now: woke)
        #expect(endedAgain.isEmpty)
    }

    /// "Woke up about 20 minutes ago" on a sleep that began 5 minutes ago ends it where it began.
    @Test func aSleepNeverEndsBeforeItBegan() {
        var data = HouseholdData()
        let id = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0)
        let now = t0.addingTimeInterval(.minutes(5))
        data.endSleep(babyID: baby, at: now.addingTimeInterval(.minutes(-20)), by: parentA, now: now)
        #expect(data.events[id]?.event.endedAt == t0)
    }

    /// Each phone tapped "Fell asleep" before seeing the other's: one "Woke up" ends both.
    @Test func wokeUpEndsASleepStartedOnEachPhone() throws {
        var data = HouseholdData()
        let mine = data.startSleep(id: "s-a", babyID: baby, by: parentA, timeZoneID: zone, now: t0)
        let theirs = sleepEvent(t0.addingTimeInterval(60), id: "s-b", by: parentB)
        data.receiveEvent(try theirs.encoded(), systemFields: Data([1]))
        let ended = data.endSleep(babyID: baby, by: parentA, now: t0.addingTimeInterval(.hours(1)))
        #expect(Set(ended) == [mine, "s-b"])
        #expect(data.events.values.allSatisfy { $0.event.endedAt == t0.addingTimeInterval(.hours(1)) })
    }

    @Test func aNappyIsSavedAtOnceAndItsDetailsComeLater() throws {
        var data = HouseholdData()
        let id = data.addNappy(babyID: baby, wee: true, poo: true, by: parentA, timeZoneID: zone, now: t0)
        #expect(data.events[id]?.event.kind == .nappy)
        #expect(data.events[id]?.snapshot.payload?.nappy == NappyDetails(wee: true, poo: true))
        data.edit(id, by: parentA, now: t0.addingTimeInterval(30)) {
            $0.payload?.nappy?.colour = .yellow
            $0.payload?.nappy?.consistency = .loose
        }
        let nappy = try #require(data.events[id]?.snapshot.payload?.nappy)
        #expect(nappy.colour == .yellow)
        #expect(nappy.consistency == .loose)
        let undone = data.undoAdd(id, now: t0.addingTimeInterval(5))
        #expect(undone)
    }

    @Test func aGrowthEntryNeedsAMeasurement() {
        var data = HouseholdData()
        let empty = data.addGrowth(babyID: baby, GrowthDetails(), by: parentA, timeZoneID: zone, now: t0)
        #expect(empty == nil)
        #expect(data.events.isEmpty)
        let id = data.addGrowth(babyID: baby, GrowthDetails(weightGrams: 3850), by: parentA, timeZoneID: zone, now: t0)
        #expect(id.flatMap { data.events[$0]?.snapshot.payload?.growth?.weightGrams } == 3850)
    }

    @Test func aMedicineKeepsItsNameAndAmount() {
        var data = HouseholdData()
        let id = data.addMedicine(babyID: baby, MedicineDetails(name: "Vitamin D", amount: "1 drop"), by: parentA,
                                  timeZoneID: zone, now: t0)
        #expect(data.events[id]?.event.kind == .medicine)
        #expect(data.events[id]?.snapshot.payload?.medicine == MedicineDetails(name: "Vitamin D", amount: "1 drop"))
    }
}

@Suite("More than feeds: the alerts count feeds only")
struct MoreThanFeedsAlertTests {
    func others(around feedStart: Date) -> [Event] {
        let later = { (minutes: Double) in feedStart.addingTimeInterval(.minutes(minutes)) }
        var growth = feed(later(200), kind: .growth)
        growth.payload = try? PayloadCoder.encode(EventPayload(growth: GrowthDetails(weightGrams: 3850)))
        var ended = feed(later(30), kind: .sleep)
        ended.endedAt = later(90)
        return [
            ended,
            // Asleep since just before the window closes, with no end: it must not pause anything.
            feed(later(235), kind: .sleep),
            feed(later(60), kind: .nappy), feed(later(239), kind: .nappy), feed(later(260), kind: .nappy),
            growth,
            feed(later(120), kind: .medicine),
            feed(later(245), kind: .sleep, deletedAt: later(246)),
            feed(later(250), kind: "a-newer-kind"),
        ]
    }

    /// By day and at night (Parent A is on duty on the night of 15 Nov), every alert is the same,
    /// at the same time, with or without sleep, nappies, growth and medicine.
    @Test(arguments: [at(2026, 11, 14, 10, 0), at(2026, 11, 15, 22, 0), at(2026, 11, 16, 1, 30)])
    func theSameAlertsWithOrWithoutTheOtherKinds(_ lastFeed: Date) {
        let feeds = [feed(lastFeed.addingTimeInterval(.hours(-3))), feed(lastFeed)]
        for now in [lastFeed.addingTimeInterval(.minutes(5)), lastFeed.addingTimeInterval(.minutes(238))] {
            let plain = run(feeds, now: now)
            let mixed = run(feeds + others(around: lastFeed), now: now)
            #expect(!plain.isEmpty)
            #expect(mixed == plain)
            #expect(mixed.allSatisfy { $0.lastFeedStart == lastFeed })
        }
    }

    @Test func aBabyWithOnlySleepsAndNappiesHasNoAlerts() {
        let now = at(2026, 11, 14, 10, 5)
        #expect(run(others(around: at(2026, 11, 14, 10, 0)), now: now).isEmpty)
    }

    @Test func theFeedFactsIgnoreTheOtherKinds() {
        let now = at(2026, 11, 14, 18, 0)
        let feeds = [snapshot(at(2026, 11, 14, 8), payload: bottles((.formula, 60))),
                     snapshot(at(2026, 11, 14, 11), by: parentB, payload: breast(.left))]
        let others = [sleepEvent(at(2026, 11, 14, 9), at(2026, 11, 14, 10)), sleepEvent(at(2026, 11, 14, 12)),
                      nappyEvent(at(2026, 11, 14, 11, 1), by: parentA), nappyEvent(at(2026, 11, 14, 11, 2), by: parentB),
                      snapshot(at(2026, 11, 14, 13), kind: .medicine, payload: EventPayload(medicine: MedicineDetails(name: "Vitamin D")))]
        let mixed = feeds + others
        #expect(summarise(mixed, babyID: baby, from: at(2026, 11, 14, 0), to: now) == summarise(feeds, babyID: baby, from: at(2026, 11, 14, 0), to: now))
        #expect(graphDays(mixed, babyID: baby, timeZone: london, range: .week, now: now) == graphDays(feeds, babyID: baby, timeZone: london, range: .week, now: now))
        #expect(dayChart(mixed, babyID: baby, now: now) == dayChart(feeds, babyID: baby, now: now))
        #expect(suggestedNextSide(mixed, babyID: baby, now: now) == .right)
        // Two nappies a minute apart, one on each phone, are not one feed logged twice.
        #expect(duplicateFeeds(mixed.map(\.event)).isEmpty)
        var data = HouseholdData()
        data.startSleep(babyID: baby, by: parentA, timeZoneID: "Europe/London", now: now)
        #expect(data.feedInProgress(babyID: baby) == nil)
    }
}

@Suite("More than feeds: Home's tiles")
struct SleepAndNappyTileTests {
    let now = at(2026, 11, 17, 11, 25)

    @Test func asleepAwakeOrNotLogged() {
        #expect(sleepState([], babyID: baby, now: now) == .notLogged)
        #expect(sleepState([sleepEvent(at(2026, 11, 17, 10, 5), id: "s1")], babyID: baby, now: now)
            == .asleep(id: "s1", since: at(2026, 11, 17, 10, 5)))
        #expect(sleepState([sleepEvent(at(2026, 11, 17, 8), at(2026, 11, 17, 10, 45))], babyID: baby, now: now)
            == .awake(since: at(2026, 11, 17, 10, 45)))
    }

    /// The sleep that started last decides, so a sleep left running on an offline phone doesn't
    /// keep Home saying "Asleep" after a later sleep ended.
    @Test func theSleepStartedLastDecides() {
        let stranded = sleepEvent(at(2026, 11, 17, 8), id: "old")
        let later = sleepEvent(at(2026, 11, 17, 8, 2), at(2026, 11, 17, 9), id: "new", by: parentB)
        #expect(sleepState([stranded, later], babyID: baby, now: now) == .awake(since: at(2026, 11, 17, 9)))
    }

    @Test func deletedFutureAndOtherBabiesSleepsAreLeftOut() {
        let events = [
            sleepEvent(at(2026, 11, 17, 8), at(2026, 11, 17, 9)),
            sleepEvent(at(2026, 11, 17, 10), deletedAt: at(2026, 11, 17, 10, 1)),
            sleepEvent(at(2026, 11, 17, 10, 30), babyID: "other-baby"),
            // The clock was set back: this sleep seems to start in 20 minutes.
            sleepEvent(at(2026, 11, 17, 11, 45)),
        ]
        #expect(sleepState(events, babyID: baby, now: now) == .awake(since: at(2026, 11, 17, 9)))
    }

    /// The clock was set back after "Woke up": the end seems to be in the future, so the baby
    /// still counts as asleep until then.
    @Test func anEndAfterNowStillCountsAsAsleep() {
        let events = [sleepEvent(at(2026, 11, 17, 10), at(2026, 11, 17, 11, 40), id: "s1")]
        #expect(sleepState(events, babyID: baby, now: now) == .asleep(id: "s1", since: at(2026, 11, 17, 10)))
    }

    @Test func theLastNappy() {
        #expect(lastNappy([], babyID: baby, now: now) == nil)
        let events = [
            nappyEvent(at(2026, 11, 17, 9), wee: true, poo: false, id: "n1"),
            nappyEvent(at(2026, 11, 17, 10, 45), wee: true, poo: true, id: "n2"),
            nappyEvent(at(2026, 11, 17, 11), id: "deleted", deletedAt: at(2026, 11, 17, 11, 1)),
            nappyEvent(at(2026, 11, 17, 11, 50), id: "future"),
        ]
        let last = lastNappy(events, babyID: baby, now: now)
        #expect(last?.id == "n2")
        #expect(last?.at == at(2026, 11, 17, 10, 45))
        #expect(last?.wee == true)
        #expect(last?.poo == true)
    }

    /// A nappy from a newer app, whose details this app can't read, is still the last change.
    @Test func aNappyWithUnreadableDetailsStillCounts() {
        let unreadable = snapshot(at(2026, 11, 17, 11), id: "n3", kind: .nappy, payload: nil)
        let last = lastNappy([nappyEvent(at(2026, 11, 17, 9)), unreadable], babyID: baby, now: now)
        #expect(last?.id == "n3")
        #expect(last?.details == nil)
        #expect(last?.wee == false)
        #expect(last?.poo == false)
    }
}

@Suite("More than feeds: the daily rhythm report")
struct RhythmTests {
    func day(_ days: [RhythmDay], _ string: String) -> RhythmDay? { days.first { $0.date == date(string) } }

    func rows(_ events: [EventSnapshot], now: Date, timeZone: TimeZone = london, hours: DayHours = .standard,
              range: GraphRange = .week) -> [RhythmDay] {
        rhythmDays(events, babyID: baby, timeZone: timeZone, dayHours: hours, range: range, now: now)
    }

    /// Rows run midnight to midnight (the users' choice D), so a night is split across two rows.
    @Test func aNightIsSplitAtMidnight() throws {
        let events = [sleepEvent(at(2026, 11, 14, 22), at(2026, 11, 15, 2), id: "s1")]
        let days = rows(events, now: at(2026, 11, 15, 9))
        #expect(days.map(\.date) == [date("2026-11-14"), date("2026-11-15")])
        let evening = try #require(day(days, "2026-11-14"))
        let morning = try #require(day(days, "2026-11-15"))
        #expect(evening.start == at(2026, 11, 14, 0))
        #expect(evening.end == at(2026, 11, 15, 0))
        #expect(evening.sleeps == [RhythmSleep(id: "s1", start: at(2026, 11, 14, 22), end: at(2026, 11, 15, 0),
                                               fromDayBefore: false, intoNextDay: true, running: false)])
        #expect(morning.sleeps == [RhythmSleep(id: "s1", start: at(2026, 11, 15, 0), end: at(2026, 11, 15, 2),
                                               fromDayBefore: true, intoNextDay: false, running: false)])
        #expect(evening.nightSleepSeconds == .hours(2))
        #expect(morning.nightSleepSeconds == .hours(2))
        #expect(evening.daySleepSeconds == 0)
        #expect(!evening.isToday)
        #expect(morning.isToday)
    }

    /// Night is the household's night hours: 21:00 to 07:00 by default.
    @Test func sleepIsSplitAtNineAtNightAndSevenInTheMorning() throws {
        let events = [sleepEvent(at(2026, 11, 14, 20), at(2026, 11, 14, 22)),
                      sleepEvent(at(2026, 11, 14, 6, 30), at(2026, 11, 14, 8))]
        let row = try #require(day(rows(events, now: at(2026, 11, 14, 23)), "2026-11-14"))
        #expect(row.nightSleepSeconds == .hours(1.5))
        #expect(row.daySleepSeconds == .hours(2))
        #expect(row.sleepSeconds == .hours(3.5))

        let hours = DayHours(dayStart: time("06:00"), nightStart: time("20:00"))
        let shifted = try #require(day(rows(events, now: at(2026, 11, 14, 23), hours: hours), "2026-11-14"))
        #expect(shifted.nightSleepSeconds == .hours(2))
        #expect(shifted.daySleepSeconds == .hours(1.5))
    }

    @Test func aRunningSleepRunsToNow() throws {
        let now = at(2026, 11, 17, 11, 25)
        let events = [sleepEvent(at(2026, 11, 17, 10, 5), id: "s1")]
        let row = try #require(rows(events, now: now).last)
        #expect(row.isToday)
        #expect(row.sleeps == [RhythmSleep(id: "s1", start: at(2026, 11, 17, 10, 5), end: now,
                                           fromDayBefore: false, intoNextDay: false, running: true)])
        #expect(row.daySleepSeconds == .minutes(80))
    }

    /// Each phone tapped "Fell asleep": the overlap counts once.
    @Test func sleepsLoggedOnBothPhonesCountOnce() throws {
        let events = [sleepEvent(at(2026, 11, 14, 13), at(2026, 11, 14, 15)),
                      sleepEvent(at(2026, 11, 14, 13, 1), at(2026, 11, 14, 15), by: parentB),
                      sleepEvent(at(2026, 11, 14, 14), at(2026, 11, 14, 14, 30))]
        let row = try #require(day(rows(events, now: at(2026, 11, 14, 18)), "2026-11-14"))
        #expect(row.sleeps.count == 3)
        #expect(row.daySleepSeconds == .hours(2))
    }

    /// A sleep left running on one phone stops where the next sleep began, not at now.
    @Test func aStrandedSleepStopsWhereTheNextBegan() throws {
        let events = [sleepEvent(at(2026, 11, 14, 13), id: "stranded"),
                      sleepEvent(at(2026, 11, 14, 13, 5), at(2026, 11, 14, 14), id: "next", by: parentB)]
        let row = try #require(day(rows(events, now: at(2026, 11, 14, 18)), "2026-11-14"))
        let stranded = try #require(row.sleeps.first { $0.id == "stranded" })
        #expect(stranded.end == at(2026, 11, 14, 13, 5))
        #expect(!stranded.running)
        #expect(row.daySleepSeconds == .hours(1))
    }

    @Test func weesPoosAndFeedsOnTheirDay() throws {
        let events = [
            nappyEvent(at(2026, 11, 14, 8), wee: true, poo: false),
            nappyEvent(at(2026, 11, 14, 11), wee: true, poo: true),
            nappyEvent(at(2026, 11, 14, 14), wee: false, poo: true),
            nappyEvent(at(2026, 11, 14, 16), wee: false, poo: false),
            nappyEvent(at(2026, 11, 14, 17), deletedAt: at(2026, 11, 14, 17, 1)),
            nappyEvent(at(2026, 11, 15, 0, 0), wee: true, poo: false),
            snapshot(at(2026, 11, 14, 9), payload: breast(.left)),
            snapshot(at(2026, 11, 14, 23, 59), payload: bottles((.formula, 60))),
        ]
        let days = rows(events, now: at(2026, 11, 15, 9))
        let first = try #require(day(days, "2026-11-14"))
        #expect(first.nappies.count == 4)
        #expect(first.wees == 2)
        #expect(first.poos == 2)
        #expect(first.feeds.map(\.startedAt) == [at(2026, 11, 14, 9), at(2026, 11, 14, 23, 59)])
        #expect(first.feeds.map(\.breast) == [true, false])
        #expect(day(days, "2026-11-15")?.wees == 1)
        #expect(day(days, "2026-11-15")?.feeds.isEmpty == true)
    }

    @Test func rowsEndTodayAndStartNoEarlierThanTheFirstEntry() {
        let now = at(2026, 11, 15, 12)
        let events = [nappyEvent(at(2026, 11, 1, 10)), sleepEvent(at(2026, 11, 15, 10), at(2026, 11, 15, 11)),
                      // Pumping isn't on the report, so it doesn't start the rows.
                      snapshot(at(2026, 10, 1, 10), kind: .pump, payload: EventPayload(pump: PumpDetails(side: .both)))]
        let week = rows(events, now: now)
        #expect(week.count == 7)
        #expect(week.first?.date == date("2026-11-09"))
        #expect(week.filter(\.isToday).map(\.date) == [date("2026-11-15")])
        #expect(rows(events, now: now, range: .all).first?.date == date("2026-11-01"))
        #expect(rows([], now: now).isEmpty)
    }

    /// 25 Oct 2026: the UK's clocks go back at 02:00, so the row is 25 hours long, and a sleep from
    /// midnight to 07:00 on the clock lasted 8 real hours.
    @Test func whenTheClocksGoBackTheRowIs25HoursLong() throws {
        let events = [sleepEvent(at(2026, 10, 25, 0, 0), at(2026, 10, 25, 7, 0))]
        let row = try #require(day(rows(events, now: at(2026, 10, 25, 12)), "2026-10-25"))
        #expect(row.end.timeIntervalSince(row.start) == .hours(25))
        #expect(row.nightSleepSeconds == .hours(8))
        #expect(row.daySleepSeconds == 0)
    }

    /// 29 Mar 2026: the UK's clocks go forward at 01:00, so the row is 23 hours long, and a sleep
    /// from midnight to 07:00 on the clock lasted 6 real hours.
    @Test func whenTheClocksGoForwardTheRowIs23HoursLong() throws {
        let events = [sleepEvent(at(2026, 3, 29, 0, 0), at(2026, 3, 29, 7, 0))]
        let row = try #require(day(rows(events, now: at(2026, 3, 29, 12)), "2026-03-29"))
        #expect(row.end.timeIntervalSince(row.start) == .hours(23))
        #expect(row.nightSleepSeconds == .hours(6))
    }

    /// India is 5½ hours ahead of UTC: its midnight is 18:30 UTC.
    @Test func aHalfHourTimeZoneSplitsRowsAtItsOwnMidnight() throws {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let events = [sleepEvent(at(2026, 11, 14, 18, 0, in: utc), at(2026, 11, 14, 19, 0, in: utc))]
        let days = rows(events, now: at(2026, 11, 15, 6, in: utc), timeZone: kolkata)
        let second = try #require(day(days, "2026-11-15"))
        #expect(second.start == at(2026, 11, 14, 18, 30, in: utc))
        #expect(day(days, "2026-11-14")?.nightSleepSeconds == .minutes(30))
        #expect(second.nightSleepSeconds == .minutes(30))
    }

    /// A phone abroad logs in its own time zone, but the rows are the household's days.
    @Test func whileTravellingRowsStayTheHouseholds() throws {
        // 03:00 to 05:00 in London is 22:00 to 00:00 on 14 Nov in New York.
        let away = sleepEvent(at(2026, 11, 15, 3), at(2026, 11, 15, 5), timeZoneID: "America/New_York")
        let days = rows([away], now: at(2026, 11, 15, 9))
        #expect(days.map(\.date) == [date("2026-11-15")])
        #expect(days.first?.nightSleepSeconds == .hours(2))
    }

    /// The phone's clock was set back: an end after now is cut to now, and anything starting
    /// after now is left out.
    @Test func whenTheClockIsSetBackNothingRunsPastNow() throws {
        let now = at(2026, 11, 15, 10)
        let events = [sleepEvent(at(2026, 11, 15, 9), at(2026, 11, 15, 11)),
                      sleepEvent(at(2026, 11, 15, 10, 30), at(2026, 11, 15, 10, 45)),
                      nappyEvent(at(2026, 11, 15, 10, 20))]
        let row = try #require(rows(events, now: now).last)
        #expect(row.sleeps.map(\.end) == [now])
        #expect(row.daySleepSeconds == .hours(1))
        #expect(row.nappies.isEmpty)
    }

    @Test func nightAndDayAlwaysAddUpToTheRealTime() {
        let hours = DayHours.standard
        let spans: [(Date, Date)] = [
            (at(2026, 11, 14, 18), at(2026, 11, 16, 9, 17)),
            (at(2026, 10, 24, 20, 59, 30), at(2026, 10, 25, 7, 0, 30)),
            (at(2026, 3, 28, 23), at(2026, 3, 29, 8)),
        ]
        for (from, to) in spans {
            let split = hours.nightAndDaySeconds(from: from, to: to, in: london)
            #expect(split.night + split.day == to.timeIntervalSince(from))
        }
        let noNight = DayHours(dayStart: time("07:00"), nightStart: time("07:00"))
        #expect(noNight.nightAndDaySeconds(from: at(2026, 11, 14, 0), to: at(2026, 11, 15, 0), in: london).day == .hours(24))
    }
}

@Suite("More than feeds: a feed during a sleep (choice O)")
struct FeedDuringSleepTests {
    let t0 = at(2026, 11, 17, 3, 0)
    let zone = "Europe/London"

    @Test func startFeedEndsTheRunningSleep() throws {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-2)))
        data.startFeed(babyID: baby, side: .left, by: parentB, timeZoneID: zone, now: t0)
        let ended = try #require(data.events[sleep])
        #expect(ended.event.endedAt == t0)
        #expect(ended.snapshot.payload?.stamp(.endedAt) == FieldStamp(at: t0, by: parentB))
        #expect(data.sleepInProgress(babyID: baby, now: t0) == nil)
    }

    @Test func startFeedWithNoSleepChangesNoSleep() {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-3)))
        data.endSleep(babyID: baby, by: parentA, now: t0.addingTimeInterval(.hours(-1)))
        data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: zone, now: t0)
        #expect(data.events[sleep]?.event.endedAt == t0.addingTimeInterval(.hours(-1)))
    }

    @Test func anotherBabysSleepRunsOn() {
        var data = HouseholdData()
        let other = data.startSleep(babyID: "other-baby", by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-1)))
        data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: zone, now: t0)
        #expect(data.events[other]?.event.endedAt == nil)
    }

    @Test func quickStartFromTheLockScreenEndsTheSleepAndSendsItAtOnce() throws {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-1)))
        data.events[sleep]?.uploadNotBefore = nil
        _ = data.quickStartFeed(babyID: baby, by: parentA, timeZoneID: zone, now: t0)
        #expect(data.events[sleep]?.event.endedAt == t0)
        #expect(data.eventsToUpload(now: t0).contains { $0.event.id == sleep })
    }

    @Test func aWatchStartEndsTheSleepAtTheTap() throws {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-1)))
        let tap = t0.addingTimeInterval(-90)
        let changed = data.applyWatch(WatchRequest(command: .start(feedID: "f", bottle: nil, bottleID: "b"), at: tap),
                                      babyID: baby, by: parentA, timeZoneID: zone)
        #expect(changed)
        #expect(data.events[sleep]?.event.endedAt == tap)
    }

    /// A watch tap kept while the phone was out of reach: a sleep that began after the tap is
    /// left alone.
    @Test func aLateWatchStartLeavesALaterSleepAlone() {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0)
        let tap = t0.addingTimeInterval(.minutes(-5))
        data.applyWatch(WatchRequest(command: .start(feedID: "f", bottle: nil, bottleID: "b"), at: tap),
                        babyID: baby, by: parentA, timeZoneID: zone)
        #expect(data.events[sleep]?.event.endedAt == nil)
    }

    /// The alarms count feeds only: the feed that ended the sleep sets them, as any feed does.
    @Test func theAlertsFollowTheFeedNotTheSleep() {
        var withSleep = HouseholdData()
        withSleep.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-2)))
        withSleep.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: zone, now: t0)
        var without = HouseholdData()
        without.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: zone, now: t0)
        #expect(withSleep.allEvents.latestFeedStart(babyID: baby, now: t0) == without.allEvents.latestFeedStart(babyID: baby, now: t0))
    }

    @Test func stopDiscardPutsTheSleepBack() {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-2)))
        let feed = data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: zone, now: t0)
        let discarded = data.discardFeed(feed, by: parentA, now: t0.addingTimeInterval(5))
        #expect(discarded)
        #expect(data.events[feed] == nil)
        #expect(data.events[sleep]?.event.endedAt == nil)
        #expect(data.sleepInProgress(babyID: baby, now: t0.addingTimeInterval(5))?.id == sleep)
    }

    /// After the undo window the feed is hidden, not removed, and the sleep still comes back.
    @Test func aLateDiscardHidesTheFeedAndPutsTheSleepBack() throws {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-2)))
        let feed = data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: zone, now: t0)
        let later = t0.addingTimeInterval(.minutes(3))
        let discarded = data.discardFeed(feed, by: parentA, now: later)
        #expect(discarded)
        #expect(data.events[feed]?.event.deletedAt == later)
        #expect(data.events[sleep]?.event.endedAt == nil)
    }

    /// A sleep that ended by Woke up, not by the feed, stays ended.
    @Test func discardLeavesASleepEndedByWokeUp() {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-2)))
        data.endSleep(babyID: baby, by: parentA, now: t0.addingTimeInterval(.minutes(-10)))
        let feed = data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: zone, now: t0)
        data.discardFeed(feed, by: parentA, now: t0.addingTimeInterval(5))
        #expect(data.events[sleep]?.event.endedAt == t0.addingTimeInterval(.minutes(-10)))
    }

    /// The baby fell asleep again after the feed began: the newer sleep stays the only one running.
    @Test func discardLeavesTheOldSleepWhenANewOneRuns() {
        var data = HouseholdData()
        let old = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-2)))
        let feed = data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: zone, now: t0)
        let new = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.minutes(20)))
        data.discardFeed(feed, by: parentA, now: t0.addingTimeInterval(.minutes(25)))
        #expect(data.events[old]?.event.endedAt == t0)
        #expect(data.events[new]?.event.endedAt == nil)
    }

    @Test func aWatchDiscardPutsTheSleepBack() {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(.hours(-1)))
        data.applyWatch(WatchRequest(command: .start(feedID: "f", bottle: nil, bottleID: "b"), at: t0),
                        babyID: baby, by: parentA, timeZoneID: zone)
        let changed = data.applyWatch(WatchRequest(command: .discard(feedID: "f"), at: t0.addingTimeInterval(30)),
                                      babyID: baby, by: parentA, timeZoneID: zone)
        #expect(changed)
        #expect(data.events[sleep]?.event.endedAt == nil)
    }
}

@Suite("More than feeds: entries that arrive late (Codex review)")
struct LateSleepTests {
    let t0 = at(2026, 11, 17, 9, 0)
    let zone = "Europe/London"

    /// Parent A logged Fell asleep with no signal; Parent B started a feed meanwhile.
    @Test func aSleepStillRunningEndsAtTheNextFeed() throws {
        var data = HouseholdData()
        let theirs = sleepEvent(t0, id: "s", by: parentA)
        data.receiveEvent(try theirs.encoded(), systemFields: Data([1]))
        data.add(kind: .feed, babyID: baby, startedAt: t0.addingTimeInterval(.hours(1)), endedAt: nil,
                 payload: EventPayload(feed: FeedDetails()), by: parentB, timeZoneID: zone, now: t0.addingTimeInterval(.hours(1)))
        let now = t0.addingTimeInterval(.hours(2))
        #expect(data.endSleepsInterruptedByFeeds(by: parentB, now: now) == ["s"])
        #expect(data.events["s"]?.event.endedAt == t0.addingTimeInterval(.hours(1)))
        #expect(data.endSleepsInterruptedByFeeds(by: parentB, now: now).isEmpty)
    }

    @Test func aSleepAfterTheLastFeedRunsOn() {
        var data = HouseholdData()
        data.add(kind: .feed, babyID: baby, startedAt: t0, endedAt: t0.addingTimeInterval(1200),
                 payload: EventPayload(feed: FeedDetails()), by: parentA, timeZoneID: zone, now: t0)
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(1800))
        #expect(data.endSleepsInterruptedByFeeds(by: parentA, now: t0.addingTimeInterval(.hours(1))).isEmpty)
        #expect(data.events[sleep]?.event.endedAt == nil)
    }

    @Test func aDeletedFeedOrAnotherBabysFeedEndsNothing() {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0)
        let removed = data.add(kind: .feed, babyID: baby, startedAt: t0.addingTimeInterval(600), endedAt: nil,
                               payload: EventPayload(feed: FeedDetails()), by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(600))
        data.delete(removed, by: parentA, now: t0.addingTimeInterval(700))
        data.add(kind: .feed, babyID: "other-baby", startedAt: t0.addingTimeInterval(900), endedAt: nil,
                 payload: EventPayload(feed: FeedDetails()), by: parentA, timeZoneID: zone, now: t0.addingTimeInterval(900))
        #expect(data.endSleepsInterruptedByFeeds(by: parentA, now: t0.addingTimeInterval(1800)).isEmpty)
        #expect(data.events[sleep]?.event.endedAt == nil)
    }

    /// The other parent corrected the feed's start before this one tapped Stop · discard.
    @Test func discardStillPutsTheSleepBackAfterTheStartWasCorrected() {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0)
        let feedStart = t0.addingTimeInterval(.hours(1))
        let feed = data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: zone, now: feedStart)
        data.edit(feed, by: parentB, now: feedStart.addingTimeInterval(120)) { $0.event.startedAt = feedStart.addingTimeInterval(-300) }
        data.discardFeed(feed, by: parentA, now: feedStart.addingTimeInterval(180))
        #expect(data.events[sleep]?.event.endedAt == nil)
    }

    /// A sleep whose end someone changed by hand stays as they left it.
    @Test func discardLeavesAnEndChangedByHand() {
        var data = HouseholdData()
        let sleep = data.startSleep(babyID: baby, by: parentA, timeZoneID: zone, now: t0)
        let feedStart = t0.addingTimeInterval(.hours(1))
        let feed = data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: zone, now: feedStart)
        data.edit(sleep, by: parentB, now: feedStart.addingTimeInterval(60)) { $0.event.endedAt = feedStart.addingTimeInterval(-600) }
        data.discardFeed(feed, by: parentA, now: feedStart.addingTimeInterval(120))
        #expect(data.events[sleep]?.event.endedAt == feedStart.addingTimeInterval(-600))
    }
}

@Suite("More than feeds: the medicine list")
struct MedicineListTests {
    let t0 = at(2026, 11, 17, 8, 0)

    @Test func itStartsWithVitaminD() {
        #expect(HouseholdData().medicines == ["Vitamin D"])
    }

    @Test func namesAreTrimmedAndRepeatsLeftOut() {
        var data = HouseholdData()
        data.setMedicines(["Vitamin D", "  Infant paracetamol ", "", "vitamin d"], now: t0)
        #expect(data.medicines == ["Vitamin D", "Infant paracetamol"])
    }

    @Test func anEmptyListStaysEmpty() {
        var data = HouseholdData()
        data.setMedicines([], now: t0)
        #expect(data.medicines.isEmpty)
    }

    @Test func lastGivenIsTheLatestOfThatName() {
        var data = HouseholdData()
        data.addMedicine(babyID: baby, MedicineDetails(name: "Vitamin D"), at: t0.addingTimeInterval(.hours(-24)),
                         by: parentA, timeZoneID: "Europe/London", now: t0)
        data.addMedicine(babyID: baby, MedicineDetails(name: "vitamin D"), at: t0, by: parentB, timeZoneID: "Europe/London", now: t0)
        let removed = data.addMedicine(babyID: baby, MedicineDetails(name: "Vitamin D"), at: t0.addingTimeInterval(60),
                                       by: parentB, timeZoneID: "Europe/London", now: t0.addingTimeInterval(60))
        data.delete(removed, by: parentB, now: t0.addingTimeInterval(120))
        #expect(data.lastGiven("Vitamin D", babyID: baby, now: t0.addingTimeInterval(.hours(1))) == t0)
        #expect(data.lastGiven("Infant paracetamol", babyID: baby, now: t0) == nil)
    }
}
