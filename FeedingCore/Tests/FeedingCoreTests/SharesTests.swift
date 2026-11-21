import Foundation
import Testing
@testable import FeedingCore

// "Who does what": the one answer sheet (`Insights/Shares.swift`, engineering review A4, D5 A).

/// An entry for the answer sheet. A "done by" given here is stamped at `stampedAt` (or its start).
func shareEntry(_ kind: EventKind, _ start: Date, end: Date? = nil, id: String = UUID().uuidString, by: MemberID = parentA,
                doneBy: MemberID? = nil, stampedAt: Date? = nil, payload: EventPayload? = EventPayload(),
                babyID: String = baby, deletedAt: Date? = nil, created: Date? = nil,
                wakeID: String? = nil, gotUpBy: MemberID? = nil) -> EventSnapshot {
    var payload = payload
    if doneBy != nil { payload?.setStamp(.doneBy, FieldStamp(at: stampedAt ?? start, by: by)) }
    if gotUpBy != nil { payload?.setStamp(.gotUp, FieldStamp(at: end ?? start, by: by)) }
    if let end { payload?.setStamp(.endedAt, FieldStamp(at: end, by: by)) }
    var event = Event(id: id, babyID: babyID, kind: kind, startedAt: start, endedAt: end, timeZoneID: "Europe/London",
                      loggedBy: by, createdAt: created ?? start, modifiedAt: start, deletedAt: deletedAt, doneBy: doneBy,
                      wakeID: wakeID, gotUpBy: gotUpBy)
    // A "got up" given for this ending.
    if gotUpBy != nil { event.gotUpFor = event.endingID }
    return EventSnapshot(event: event, payload: payload)
}

func breastFeed(_ start: Date, seconds: [Int?] = [600], end: Date? = nil, id: String = UUID().uuidString,
                by: MemberID = parentA, doneBy: MemberID? = nil, stampedAt: Date? = nil, created: Date? = nil) -> EventSnapshot {
    let sides = seconds.enumerated().map { BreastSegment(side: $0.offset.isMultiple(of: 2) ? .left : .right, durationSeconds: $0.element) }
    return shareEntry(.feed, start, end: end ?? start.addingTimeInterval(.minutes(30)), id: id, by: by, doneBy: doneBy,
                      stampedAt: stampedAt, payload: EventPayload(feed: FeedDetails(breast: sides)), created: created)
}

func bottleFeed(_ start: Date, end: Date? = nil, id: String = UUID().uuidString, by: MemberID = parentA) -> EventSnapshot {
    shareEntry(.feed, start, end: end ?? start.addingTimeInterval(.minutes(15)), id: id, by: by,
               payload: EventPayload(feed: FeedDetails(bottles: [Bottle(milk: .formula, ml: 90)])))
}

func wee(_ start: Date, id: String = UUID().uuidString, by: MemberID = parentA, poo: Bool = false) -> EventSnapshot {
    shareEntry(.nappy, start, id: id, by: by, payload: EventPayload(nappy: NappyDetails(wee: true, poo: poo)))
}

func sheet(_ snapshots: [EventSnapshot], breastfeeder: Breastfeeder? = nil, distinct: Set<Set<String>> = [],
           dayHours: DayHours = .standard, zone: TimeZone = london, now: Date) -> WhoDidIt {
    WhoDidIt(snapshots, babyID: baby, breastfeeder: breastfeeder, confirmedDistinct: distinct, dayHours: dayHours,
             timeZone: zone, now: now)
}

@Suite("Who does what: who did it")
struct WhoDidItRuleTests {
    let t = at(2026, 11, 18, 10, 0)
    var now: Date { t.addingTimeInterval(.hours(4)) }

    @Test func theStartingRule() {
        let nappy = wee(t, id: "n", by: parentB)
        let breast = breastFeed(t, id: "b", by: parentB)
        let bottle = bottleFeed(t.addingTimeInterval(.hours(1)), id: "f", by: parentB)
        let pump = shareEntry(.pump, t, end: t.addingTimeInterval(.minutes(20)), id: "p", by: parentB,
                              payload: EventPayload(pump: PumpDetails(side: .both)))
        let all = [nappy, breast, bottle, pump]

        let withA = sheet(all, breastfeeder: .member(parentA), now: now)
        #expect(withA.doneBy("n") == .init(member: parentB, saved: false))
        #expect(withA.doneBy("b") == .init(member: parentA, saved: false))
        #expect(withA.doneBy("f") == .init(member: parentB, saved: false))
        #expect(withA.doneBy("p") == .init(member: parentA, saved: false))

        for answer in [nil, Breastfeeder.nobody] {
            let byLogger = sheet(all, breastfeeder: answer, now: now)
            #expect(byLogger.doneBy("b")?.member == parentB)
            #expect(byLogger.doneBy("p")?.member == parentB)
        }
    }

    @Test func aStoredChoiceWinsAndSurvivesASettingChange() {
        // Stored as Parent A, which is also what the rule gives while Parent A breastfeeds.
        let feed = breastFeed(t, id: "b", by: parentB, doneBy: parentA)
        #expect(sheet([feed], breastfeeder: .member(parentA), now: now).doneBy("b") == .init(member: parentA, saved: true))
        #expect(sheet([feed], breastfeeder: .member(parentB), now: now).doneBy("b") == .init(member: parentA, saved: true))
        let plain = breastFeed(t, id: "c", by: parentB)
        #expect(sheet([plain], breastfeeder: .member(parentB), now: now).doneBy("c")?.member == parentB)
    }

    @Test func detailsThatCantBeReadCountForTheLoggerFromStartToEnd() {
        let unread = shareEntry(.feed, t, end: t.addingTimeInterval(.minutes(40)), id: "u", by: parentB, payload: nil)
        let s = sheet([unread], breastfeeder: .member(parentA), now: now)
        #expect(s.doneBy("u")?.member == parentB)
        #expect(s.entries(.feeds, range: .all).first?.seconds == .minutes(40))
    }

    @Test func kindsThatAreNotWorkAndLeftOutEntriesAreNotCounted() {
        let growth = shareEntry(.growth, t, id: "g", payload: EventPayload(growth: GrowthDetails(weightGrams: 4000)))
        let first = shareEntry(.milestone, t, id: "m", payload: EventPayload(milestone: MilestoneDetails(title: "Smile")))
        let deleted = wee(t, id: "d")
        var gone = deleted
        gone.event.deletedAt = t
        let other = shareEntry(.nappy, t, id: "o", payload: EventPayload(nappy: NappyDetails(wee: true, poo: false)), babyID: "baby-2")
        let future = wee(now.addingTimeInterval(60), id: "later")
        let s = sheet([growth, first, gone, other, future], now: now)
        #expect(s.items.isEmpty)
        #expect(s.doneBy("g") == nil && s.doneBy("m") == nil && s.doneBy("d") == nil && s.doneBy("o") == nil)
    }

    @Test func aMemberNoLongerInTheHouseholdKeepsTheirEntries() {
        let s = sheet([wee(t, id: "x", by: "someone-who-left")], now: now)
        #expect(s.facts(.all).tally(.nappies, "someone-who-left").count == 1)
    }
}

@Suite("Who does what: logged on both phones")
struct WhoDidItCopyTests {
    let t = at(2026, 11, 18, 10, 0)
    var now: Date { t.addingTimeInterval(.hours(4)) }

    @Test func aFeedOnBothPhonesCountsOnceForTheLaterStoredChoice() {
        let kept = breastFeed(t, id: "kept", by: parentA, doneBy: parentA, stampedAt: t.addingTimeInterval(60), created: t)
        let copy = breastFeed(t.addingTimeInterval(120), id: "copy", by: parentB, doneBy: parentB,
                              stampedAt: t.addingTimeInterval(300), created: t.addingTimeInterval(120))
        let s = sheet([kept, copy], now: now)
        #expect(s.facts(.all).total(.feeds).count == 1)
        #expect(s.hiddenCopies == ["copy"])
        #expect(s.doneBy("kept") == .init(member: parentB, saved: true))
        #expect(s.doneBy("copy") == s.doneBy("kept"))
        #expect(s.entries(.feeds, range: .all).first?.eventIDs == ["kept", "copy"])
    }

    @Test func withNoStoredChoiceAPairCountsByTheRuleOnTheEntryShown() {
        let kept = breastFeed(t, id: "kept", by: parentA, created: t)
        let copy = bottleFeed(t.addingTimeInterval(60), id: "copy", by: parentB)
        let s = sheet([kept, copy], breastfeeder: .member(parentB), now: now)
        #expect(s.doneBy("kept") == .init(member: parentB, saved: false))
    }

    @Test func theSameNappyOnBothPhonesCountsOnce() {
        let s = sheet([wee(t, id: "a", by: parentA), wee(t.addingTimeInterval(.minutes(3)), id: "b", by: parentB)], now: now)
        #expect(s.facts(.all).total(.nappies).count == 1)
        #expect(s.hiddenCopies == ["b"])
    }

    @Test(arguments: [
        ("different contents", 3.0, parentB, true, Set<Set<String>>()),
        ("same parent", 3.0, parentA, false, Set<Set<String>>()),
        ("six minutes apart", 6.0, parentB, false, Set<Set<String>>()),
        ("marked as two", 3.0, parentB, false, Set([Set(["a", "b"])])),
    ])
    func twoNappiesStayTwo(_ label: String, _ minutes: Double, _ second: MemberID, _ poo: Bool, _ distinct: Set<Set<String>>) {
        let s = sheet([wee(t, id: "a", by: parentA), wee(t.addingTimeInterval(.minutes(minutes)), id: "b", by: second, poo: poo)],
                      distinct: distinct, now: now)
        #expect(s.facts(.all).total(.nappies).count == 2, "\(label)")
    }

    @Test func medicinesPairOnlyWithTheSameName() {
        func dose(_ name: String, _ id: String, _ by: MemberID, _ offset: Double) -> EventSnapshot {
            shareEntry(.medicine, t.addingTimeInterval(.minutes(offset)), id: id, by: by,
                       payload: EventPayload(medicine: MedicineDetails(name: name)))
        }
        #expect(sheet([dose("Vitamin D", "a", parentA, 0), dose(" vitamin d", "b", parentB, 2)], now: now)
            .facts(.all).total(.medicines).count == 1)
        #expect(sheet([dose("Vitamin D", "a", parentA, 0), dose("Paracetamol", "b", parentB, 2)], now: now)
            .facts(.all).total(.medicines).count == 2)
    }

    @Test func sleepsAndBathsOnBothPhonesCountOnce() {
        let sleeps = [shareEntry(.sleep, t, id: "s1", by: parentA), shareEntry(.sleep, t.addingTimeInterval(60), id: "s2", by: parentB)]
        let baths = [shareEntry(.bath, t, id: "b1", by: parentA), shareEntry(.bath, t.addingTimeInterval(60), id: "b2", by: parentB)]
        let s = sheet(sleeps + baths, now: now)
        #expect(s.facts(.all).total(.settled).count == 1)
        #expect(s.facts(.all).total(.baths).count == 1)
    }
}

@Suite("Who does what: time")
struct WhoDidItTimeTests {
    let t = at(2026, 11, 18, 10, 0)
    var now: Date { t.addingTimeInterval(.hours(4)) }

    func seconds(_ snapshot: EventSnapshot, _ kind: ShareKind = .feeds) -> TimeInterval? {
        sheet([snapshot], now: now).entries(kind, range: .all).first?.seconds
    }

    @Test func eachCase() {
        #expect(seconds(breastFeed(t, seconds: [600, 300], end: t.addingTimeInterval(.hours(1)))) == 900)
        #expect(seconds(breastFeed(t, seconds: [600, nil], end: t.addingTimeInterval(.minutes(25)))) == .minutes(25))
        #expect(seconds(bottleFeed(t, end: t.addingTimeInterval(.minutes(12)))) == .minutes(12))
        #expect(seconds(shareEntry(.feed, t, payload: EventPayload(feed: FeedDetails()))) == nil)
        let pump = shareEntry(.pump, t, end: t.addingTimeInterval(.minutes(18)), payload: EventPayload(pump: PumpDetails(side: .left)))
        #expect(seconds(pump, .pumping) == .minutes(18))
        #expect(seconds(shareEntry(.sleep, t, end: t.addingTimeInterval(.hours(2))), .settled) == nil)
        #expect(seconds(shareEntry(.bath, t), .baths) == nil)
    }

    @Test func aRunningFeedCountsOnceWithNoTime() {
        let s = sheet([shareEntry(.feed, t, payload: EventPayload(feed: FeedDetails(breast: [BreastSegment(side: .left)])))], now: now)
        #expect(s.facts(.all).total(.feeds) == ShareTally(count: 1, seconds: 0))
    }
}

@Suite("Who does what: wake-ups")
struct WhoDidItWakeUpTests {
    let evening = at(2026, 11, 17, 20, 0)
    let now = at(2026, 11, 18, 9, 0)

    @Test func anEndAnOlderBuildChangedIsAWakeUpOfItsOwn() {
        // Codex review, 21 Nov 2026: an older build reopened s1 and ended it again; it kept the
        // wake-up ID and "got up" it doesn't know. That ending is its own wake-up, worked out.
        let end = at(2026, 11, 18, 3, 0)
        var s1 = shareEntry(.sleep, evening, end: end, id: "s1", by: parentA, wakeID: "w", gotUpBy: parentB)
        let s2 = shareEntry(.sleep, evening.addingTimeInterval(600), end: end, id: "s2", by: parentB, wakeID: "w", gotUpBy: parentB)
        s1.event.endedAt = at(2026, 11, 18, 4, 30)
        let s = sheet([s1, s2], now: now)
        #expect(s.entries(.gotUpAtNight, range: .all).count == 2)
        #expect(s.gotUp(sleep: "s1")?.saved == false)
        #expect(s.gotUp(sleep: "s2") == .init(member: parentB, saved: true))
    }

    @Test func aSleepLoggedOnBothPhonesIsOneWakeUp() {
        // Codex review: both phones logged the sleep, and each tapped Woke up; one wake-up counts.
        let kept = shareEntry(.sleep, evening, end: at(2026, 11, 18, 3, 0), id: "k", by: parentA, created: evening,
                              wakeID: "wa", gotUpBy: parentA)
        let copy = shareEntry(.sleep, evening.addingTimeInterval(120), end: at(2026, 11, 18, 3, 2), id: "c", by: parentB,
                              created: evening.addingTimeInterval(120), wakeID: "wb", gotUpBy: parentB)
        let s = sheet([kept, copy], now: now)
        #expect(s.hiddenCopies == ["c"])
        #expect(s.entries(.gotUpAtNight, range: .all).map(\.member) == [parentA])
        #expect(s.gotUp(sleep: "c") == s.gotUp(sleep: "k"))
    }

    @Test func aRunningSleepIsNeverACopyOfAnEndedOne() {
        // Codex review: hiding the running one would leave Home saying "awake".
        let ended = shareEntry(.sleep, evening, end: at(2026, 11, 18, 3, 0), id: "e", by: parentA, created: evening)
        let running = shareEntry(.sleep, evening.addingTimeInterval(120), id: "r", by: parentB,
                                 created: evening.addingTimeInterval(120))
        #expect(duplicateCareEntries([ended, running]).isEmpty)
        let bothEnded = shareEntry(.sleep, evening.addingTimeInterval(120), end: at(2026, 11, 18, 3, 1), id: "r", by: parentB,
                                   created: evening.addingTimeInterval(120))
        #expect(duplicateCareEntries([ended, bothEnded]).map(\.duplicate) == ["r"])
    }

    @Test func oneEndingIsOneWakeUpAtNightForWhoGotUp() {
        let end = at(2026, 11, 18, 3, 0)
        let s1 = shareEntry(.sleep, evening, end: end, id: "s1", by: parentA, wakeID: "w", gotUpBy: parentB)
        let s2 = shareEntry(.sleep, evening.addingTimeInterval(600), end: end, id: "s2", by: parentB, wakeID: "w", gotUpBy: parentB)
        let s = sheet([s1, s2], now: now)
        let wakeUps = s.entries(.gotUpAtNight, range: .all)
        #expect(wakeUps.count == 1)
        #expect(wakeUps.first?.member == parentB && wakeUps.first?.saved == true)
        #expect(wakeUps.first?.day == date("2026-11-17"))
        #expect(s.gotUp(sleep: "s2") == .init(member: parentB, saved: true))
    }

    @Test func aDaytimeWakeUpIsNotCounted() {
        let nap = shareEntry(.sleep, at(2026, 11, 18, 10, 0), end: at(2026, 11, 18, 11, 0), wakeID: "w", gotUpBy: parentA)
        #expect(sheet([nap], now: at(2026, 11, 18, 12, 0)).entries(.gotUpAtNight, range: .all).isEmpty)
    }

    @Test func anOldSleepsGotUpIsWorkedOut() {
        let end = at(2026, 11, 18, 2, 0)
        // Ended by a feed that started as it ended: the feed's logger.
        let sleep = shareEntry(.sleep, evening, end: end, id: "old", by: parentA)
        let feed = bottleFeed(end, by: parentB)
        #expect(sheet([sleep, feed], now: now).gotUp(sleep: "old") == .init(member: parentB, saved: false))
        // Otherwise the parent in the end's stamp.
        var byStamp = shareEntry(.sleep, evening, end: end, id: "old2", by: parentA)
        byStamp.payload?.setStamp(.endedAt, FieldStamp(at: end, by: parentB))
        #expect(sheet([byStamp], now: now).gotUp(sleep: "old2") == .init(member: parentB, saved: false))
    }

    @Test func aGotUpForAnotherEndingIsWorkedOutAgain() {
        var sleep = shareEntry(.sleep, evening, end: at(2026, 11, 18, 3, 0), id: "s", by: parentA, wakeID: "w2")
        sleep.event.gotUpBy = parentB
        sleep.event.gotUpFor = "w1"
        #expect(sheet([sleep], now: now).gotUp(sleep: "s")?.saved == false)
    }
}

@Suite("Who does what: days, nights and ranges")
struct WhoDidItDayTests {
    let now = at(2026, 11, 20, 9, 0)

    @Test func dayEntriesGoByDateAndNightLinesByTheEvening() {
        let late = wee(at(2026, 11, 17, 23, 30), id: "late")
        let small = wee(at(2026, 11, 18, 2, 0), id: "small")
        let s = sheet([late, small], now: now)
        #expect(s.entries(.nappies, range: .day(date("2026-11-17"))).map(\.eventIDs) == [["late"]])
        #expect(s.entries(.nappies, range: .day(date("2026-11-18"))).map(\.eventIDs) == [["small"]])
        #expect(s.entries(.nightNappies, range: .day(date("2026-11-17"))).count == 2)
        #expect(s.entries(.nightNappies, range: .day(date("2026-11-18"))).isEmpty)
    }

    @Test func theNineOClockBoundaryAndMidnight() {
        let s = sheet([wee(at(2026, 11, 18, 20, 59), id: "day"), wee(at(2026, 11, 18, 21, 0), id: "night"),
                       wee(at(2026, 11, 19, 0, 0), id: "midnight"), wee(at(2026, 11, 19, 7, 0), id: "morning")], now: now)
        #expect(s.entries(.nightNappies, range: .all).flatMap(\.eventIDs) == ["night", "midnight"])
        #expect(s.entries(.nappies, range: .day(date("2026-11-19"))).flatMap(\.eventIDs) == ["midnight", "morning"])
    }

    @Test func theLastDaysCountToday() {
        let s = sheet([wee(at(2026, 11, 14, 10, 0), id: "in"), wee(at(2026, 11, 13, 10, 0), id: "out")], now: now)
        #expect(s.entries(.nappies, range: .lastDays(7)).flatMap(\.eventIDs) == ["in"])
        #expect(s.entries(.nappies, range: .all).count == 2)
    }

    /// The clocks go back on 25 Oct 2026: the night is an hour longer and still one night.
    @Test func aNightWhenTheClocksGoBack() {
        let first = wee(Date(timeIntervalSince1970: 1_792_890_000), id: "first")   // 01:20 BST
        let second = wee(Date(timeIntervalSince1970: 1_792_893_600), id: "second") // 01:20 GMT, an hour later
        let s = sheet([first, second], now: at(2026, 10, 25, 9, 0))
        #expect(s.entries(.nightNappies, range: .day(date("2026-10-24"))).count == 2)
        let sleep = shareEntry(.sleep, at(2026, 10, 24, 22, 0), end: at(2026, 10, 25, 6, 0), wakeID: "w", gotUpBy: parentA)
        #expect(sheet([sleep], now: at(2026, 10, 25, 9, 0)).lastNight()?.sleptSeconds == .hours(9))
    }

    /// The clocks go forward on 29 Mar 2026: the night is an hour shorter.
    @Test func aNightWhenTheClocksGoForward() {
        let sleep = shareEntry(.sleep, at(2026, 3, 28, 22, 0), end: at(2026, 3, 29, 6, 0), wakeID: "w", gotUpBy: parentA)
        let s = sheet([sleep], now: at(2026, 3, 29, 9, 0))
        #expect(s.lastNight()?.sleptSeconds == .hours(7))
        #expect(s.lastNight()?.night == date("2026-03-28"))
    }

    @Test func aHalfHourTimeZone() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let entry = wee(at(2026, 11, 18, 21, 15, in: kolkata), id: "x")
        let s = sheet([entry], zone: kolkata, now: at(2026, 11, 19, 9, 0, in: kolkata))
        #expect(s.entries(.nightNappies, range: .day(date("2026-11-18"))).count == 1)
    }

    /// A phone abroad still counts on the household's clock.
    @Test func travelUsesTheHouseholdsClock() {
        var entry = wee(at(2026, 11, 18, 22, 0), id: "x")
        entry.event.timeZoneID = "America/New_York"
        #expect(sheet([entry], now: now).entries(.nightNappies, range: .day(date("2026-11-18"))).count == 1)
    }

    /// The clock set back: an entry that seems to start later than now is not counted yet.
    @Test func theClockSetBack() {
        #expect(sheet([wee(now.addingTimeInterval(.hours(1)))], now: now).items.isEmpty)
    }
}

@Suite("Who does what: the page and its lists")
struct WhoDidItFactsTests {
    let now = at(2026, 11, 20, 9, 0)

    @Test func eachNumberEqualsItsList() {
        var all: [EventSnapshot] = []
        for day in 14...19 {
            all.append(breastFeed(at(2026, 11, day, 2, 0), seconds: [600, 400], by: parentA))
            all.append(bottleFeed(at(2026, 11, day, 14, 0), by: parentB))
            all.append(wee(at(2026, 11, day, 23, 0), by: parentB))
            all.append(shareEntry(.bath, at(2026, 11, day, 18, 0), by: parentA))
        }
        let s = sheet(all, breastfeeder: .member(parentA), now: now)
        for range in [ShareRange.day(date("2026-11-16")), .lastDays(7), .all] {
            let facts = s.facts(range)
            for kind in ShareKind.allCases {
                for member in [parentA, parentB] {
                    let list = s.entries(kind, member: member, range: range)
                    #expect(facts.tally(kind, member).count == list.count)
                    #expect(facts.tally(kind, member).seconds == list.reduce(0) { $0 + ($1.seconds ?? 0) })
                }
            }
        }
        let week = s.facts(.lastDays(7))
        #expect(week.tally(.feeds, parentA) == ShareTally(count: 6, seconds: 6000))
        // The 02:00 feed on the 14th belongs to the night of the 13th (named by its evening), which
        // is outside the last 7 days; the six daytime counts go by calendar date.
        #expect(week.tally(.nightFeeds, parentA).count == 5)
        #expect(week.total(.baths).count == 6)
    }
}

@Suite("Who does what: last night")
struct LastNightTests {
    func sheetAt(_ now: Date, _ snapshots: [EventSnapshot], dayHours: DayHours = .standard) -> WhoDidIt {
        sheet(snapshots, dayHours: dayHours, now: now)
    }

    var night: [EventSnapshot] {
        [wee(at(2026, 11, 18, 23, 0), id: "n"),
         breastFeed(at(2026, 11, 19, 2, 0), id: "f", by: parentB),
         shareEntry(.sleep, at(2026, 11, 18, 21, 30), end: at(2026, 11, 19, 1, 55), id: "s", wakeID: "w", gotUpBy: parentB)]
    }

    @Test func theMorningShowsLastNightInOrder() throws {
        let card = try #require(sheetAt(at(2026, 11, 19, 7, 30), night).lastNight())
        #expect(card.night == date("2026-11-18"))
        #expect(card.items.map(\.kind) == [.nightNappies, .gotUpAtNight, .nightFeeds])
        #expect(card.sleptSeconds == .hours(4) + .minutes(25))
    }

    @Test func thereIsNoCardAfterMiddayAtNightOrWithNoNightHours() {
        #expect(sheetAt(at(2026, 11, 19, 12, 1), night).lastNight() == nil)
        #expect(sheetAt(at(2026, 11, 19, 23, 0), night).lastNight() == nil)
        let noNight = DayHours(dayStart: TimeOfDay(hour: 7)!, nightStart: TimeOfDay(hour: 7)!)
        #expect(sheetAt(at(2026, 11, 19, 8, 0), night, dayHours: noNight).lastNight() == nil)
        let lateMorning = DayHours(dayStart: TimeOfDay(hour: 12)!, nightStart: TimeOfDay(hour: 21)!)
        #expect(sheetAt(at(2026, 11, 19, 12, 30), night, dayHours: lateMorning).lastNight() == nil)
    }

    @Test func anyNightCanBeShownByItsEvening() {
        // The page's Day view (1A): the same night at any time later, and none for an evening to come.
        let later = sheetAt(at(2026, 11, 21, 15, 0), night)
        #expect(later.lastNight() == nil)
        #expect(later.night(date("2026-11-18")).items.map(\.kind) == [.nightNappies, .gotUpAtNight, .nightFeeds])
        #expect(later.night(date("2026-11-18")).sleptSeconds == .hours(4) + .minutes(25))
        #expect(later.night(date("2026-11-17")).items.isEmpty)
        #expect(later.night(date("2026-11-21")).items.isEmpty)
        #expect(later.evening(at: at(2026, 11, 19, 2, 0)) == date("2026-11-18"))
        #expect(later.evening(at: at(2026, 11, 19, 12, 0)) == nil)
    }

    @Test func anEmptyNightHasNoCard() {
        #expect(sheetAt(at(2026, 11, 19, 7, 30), [wee(at(2026, 11, 18, 15, 0))]).lastNight() == nil)
    }

    @Test func overlappingSleepsCountOnceAndARunningSleepCountsToTheNightsEnd() throws {
        let sleeps = [
            shareEntry(.sleep, at(2026, 11, 18, 22, 0), end: at(2026, 11, 19, 3, 0), id: "a", by: parentA, wakeID: "w1", gotUpBy: parentA),
            shareEntry(.sleep, at(2026, 11, 19, 1, 0), end: at(2026, 11, 19, 5, 0), id: "b", by: parentB, wakeID: "w2", gotUpBy: parentB),
        ]
        #expect(try #require(sheetAt(at(2026, 11, 19, 8, 0), sleeps).lastNight()).sleptSeconds == .hours(7))
        let running = [wee(at(2026, 11, 18, 23, 0)), shareEntry(.sleep, at(2026, 11, 19, 4, 0), id: "r")]
        #expect(try #require(sheetAt(at(2026, 11, 19, 8, 0), running).lastNight()).sleptSeconds == .hours(3))
    }
}

@Suite("Who does what: the household's answer sheet")
struct HouseholdWhoDidItTests {
    @Test func aNappyLoggedOnBothPhonesIsHiddenOnEveryScreenUntilTheyWereTwo() {
        // D11 C, D12 A: the copy logged second leaves the screens, as a feed's does.
        var data = HouseholdData()
        let t = at(2026, 11, 18, 10, 0)
        let kept = data.addNappy(babyID: baby, wee: true, poo: false, at: t, by: parentA, timeZoneID: "Europe/London", now: t)
        let copy = data.addNappy(babyID: baby, wee: true, poo: false, at: t.addingTimeInterval(120), by: parentB,
                                 timeZoneID: "Europe/London", now: t.addingTimeInterval(120))
        #expect(data.hiddenDuplicates(babyID: baby) == [copy])
        #expect(data.visibleSnapshots(babyID: baby).map(\.id) == [kept])
        data.markDistinct(kept, copy, by: parentB, now: t.addingTimeInterval(300))
        #expect(data.hiddenDuplicates(babyID: baby).isEmpty)
        #expect(Set(data.visibleSnapshots(babyID: baby).map(\.id)) == [kept, copy])
    }

    @Test func finishedByIsWhoTappedFinishNotWhoCorrectedTheTime() throws {
        // TD1, D10 C: the end set as it was tapped names the finisher; a correction doesn't.
        var data = HouseholdData()
        let start = at(2026, 11, 18, 10, 0)
        let feed = data.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: "Europe/London", now: start)
        #expect(data.events[feed]?.snapshot.finishedBy == nil, "running")
        data.finishFeed(feed, by: parentB, now: start.addingTimeInterval(900))
        #expect(data.events[feed]?.snapshot.finishedBy == parentB)
        data.edit(feed, by: parentA, now: start.addingTimeInterval(3600)) { $0.event.endedAt = start.addingTimeInterval(1200) }
        #expect(data.events[feed]?.snapshot.finishedBy == nil, "a later correction claims no finisher")
        let earlier = data.add(kind: .feed, babyID: baby, startedAt: start, endedAt: start.addingTimeInterval(600),
                               payload: EventPayload(feed: FeedDetails()), by: parentB, timeZoneID: "Europe/London",
                               now: start.addingTimeInterval(7200))
        #expect(data.events[earlier]?.snapshot.finishedBy == nil, "logged afterwards")
    }

    @Test func theSharedSettingDecidesBreastfeedsWithNoChoice() throws {
        var data = HouseholdData()
        let start = at(2026, 11, 18, 10, 0)
        #expect(data.breastfeeder == nil)
        let feed = data.startFeed(babyID: baby, side: .left, by: parentB, timeZoneID: "Europe/London", now: start)
        #expect(data.whoDidIt(babyID: baby, now: start).doneBy(feed)?.member == parentB)
        data.setBreastfeeder(.member(parentA), now: start)
        #expect(data.breastfeeder == .member(parentA))
        #expect(data.whoDidIt(babyID: baby, now: start).doneBy(feed) == .init(member: parentA, saved: false))
        data.setBreastfeeder(.nobody, now: start.addingTimeInterval(60))
        #expect(data.whoDidIt(babyID: baby, now: start).doneBy(feed)?.member == parentB)
    }
}
