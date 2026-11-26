import Foundation
import Testing
@testable import FeedingCore

/// "Bottles through the day" (`docs/planning/14-bottles-through-the-day.md`): today's bottles so
/// far, the day before by the same clock time, and the 7 days before's average by that time.
@Suite("Bottles through the day")
struct BottlesThroughDayTests {
    func bottle(_ start: Date, _ ml: Int?, milk: MilkKind = .formula, breast: [BreastSegment] = [],
                deletedAt: Date? = nil, babyID: String = baby) -> EventSnapshot {
        snapshot(start, babyID: babyID, deletedAt: deletedAt,
                 payload: EventPayload(feed: FeedDetails(breast: breast, bottles: ml == nil && breast.count > 0 ? []
                                                                                  : [Bottle(milk: milk, ml: ml)])))
    }

    func through(_ events: [EventSnapshot], date: String? = nil, zone: TimeZone = london, now: Date) -> BottlesThroughDay? {
        bottlesThroughDay(events, babyID: baby, timeZone: zone, date: date.map { PlainDate($0)! }, now: now)
    }

    @Test func todayAddsUpAndTheDayBeforeIsReadAtTheSameClockTime() throws {
        let events = [
            bottle(at(2026, 11, 25, 2), 90), bottle(at(2026, 11, 25, 9), 100), bottle(at(2026, 11, 25, 15, 20), 110),
            bottle(at(2026, 11, 25, 15, 21), 120), bottle(at(2026, 11, 25, 22), 100),
            bottle(at(2026, 11, 26, 3), 80), bottle(at(2026, 11, 26, 8, 30), 120, milk: .expressed),
        ]
        let shown = try #require(through(events, now: at(2026, 11, 26, 15, 20)))
        #expect(shown.isToday)
        #expect(shown.date == date("2026-11-26"))
        #expect(shown.cutOff == 15 * 3600 + 20 * 60)
        #expect(shown.soFar == 200)
        #expect(shown.day.steps.map(\.total) == [80, 200], "a running total, formula and expressed together")
        // 15:20 exactly counts; 15:21 does not.
        #expect(shown.dayBeforeByCutOff == 300)
        #expect(shown.dayBefore?.whole == 520)
        #expect(shown.week.map(\.date) == [date("2026-11-25")], "no days before the first feed")
        #expect(shown.averageByCutOff == 300)
        #expect(shown.hasBottles)
    }

    @Test func theAverageIsOfTheSevenWholeDaysBefore() throws {
        // 100 ml at 06:00 on each of the 8 days before today, and 50 ml more at 06:00 on 18 Nov,
        // which is 8 days back, so it is left out.
        var events = (1...8).map { bottle(at(2026, 11, 26 - $0, 6), 100) }
        events.append(bottle(at(2026, 11, 18, 6, 30), 50))
        events.append(bottle(at(2026, 11, 25, 6, 10), 70))
        let shown = try #require(through(events, now: at(2026, 11, 26, 7)))
        #expect(shown.week.count == 7)
        #expect(shown.week.first?.date == date("2026-11-25"), "the day before first")
        #expect(shown.week.last?.date == date("2026-11-19"))
        #expect(shown.averageByCutOff == 110, "(7 × 100 + 70) ÷ 7")
        #expect(shown.average(by: 6 * 3600) == 100)
        #expect(shown.average(by: 5 * 3600) == 0)
        #expect(shown.averageSteps.map(\.clockSecond) == [0, 6 * 3600, 6 * 3600 + 600])
        #expect(shown.averageSteps.map(\.ml) == [0, 100, 110])
        #expect(shown.soFar == 0, "nothing yet today")
        #expect(shown.hasBottles)
    }

    @Test func aDayThatIsOverIsReadWhole() throws {
        let events = [bottle(at(2026, 11, 24, 23, 50), 90), bottle(at(2026, 11, 25, 1), 100),
                      bottle(at(2026, 11, 25, 23, 59), 80), bottle(at(2026, 11, 26, 0, 0), 60)]
        let shown = try #require(through(events, date: "2026-11-25", now: at(2026, 11, 26, 9)))
        #expect(!shown.isToday)
        #expect(shown.cutOff == 24 * 3600 - 1)
        #expect(shown.soFar == 180, "23:59 is that day; 00:00 is the next")
        #expect(shown.dayBeforeByCutOff == 90)
        #expect(shown.averageByCutOff == 90)
    }

    /// Days run from midnight, not from the 21:00 start of the night rota.
    @Test func aBottleAfterNineAtNightIsStillThatDay() throws {
        let events = [bottle(at(2026, 11, 25, 21, 30), 100), bottle(at(2026, 11, 26, 1), 90)]
        let shown = try #require(through(events, now: at(2026, 11, 26, 22)))
        #expect(shown.soFar == 90)
        #expect(shown.dayBefore?.whole == 100)
        #expect(shown.dayBeforeByCutOff == 100, "21:30 yesterday is before 22:00")
    }

    @Test func breastfeedsAndBottlesWithNoAmountAreCountedBesideIt() throws {
        let events = [
            bottle(at(2026, 11, 26, 2), nil, breast: [BreastSegment(side: .left, durationSeconds: 600),
                                                      BreastSegment(side: .right, durationSeconds: 480)]),
            // A breastfeed with a bottle top-up: both count.
            snapshot(at(2026, 11, 26, 5), payload: EventPayload(feed: FeedDetails(
                breast: [BreastSegment(side: .left, durationSeconds: 300)], bottles: [Bottle(milk: .expressed, ml: 40)]))),
            bottle(at(2026, 11, 26, 8), nil),
            // A side still running adds nothing yet.
            bottle(at(2026, 11, 26, 11), nil, breast: [BreastSegment(side: .right)]),
            // A feed from a newer app whose details this one can't read adds nothing.
            snapshot(at(2026, 11, 26, 12), payload: nil),
        ]
        let shown = try #require(through(events, now: at(2026, 11, 26, 13)))
        #expect(shown.soFar == 40)
        #expect(shown.breastFeeds == 3)
        #expect(shown.breastSeconds == 1380)
        #expect(shown.bottlesWithNoAmount == 1)
        // The bottle with no amount is a row, as on "Bottles each day", and adds nothing.
        #expect(shown.day.steps.map(\.ml) == [40, 0])
        #expect(shown.day.steps.map(\.total) == [40, 40])
    }

    /// A week whose only bottle has no amount still shows, so its amount can be added.
    @Test func aBottleWithNoAmountStillCountsAsABottle() throws {
        let shown = try #require(through([bottle(at(2026, 11, 25, 8), nil)], now: at(2026, 11, 26, 9)))
        #expect(shown.hasBottles)
        #expect(shown.dayBefore?.steps.count == 1)
        #expect(shown.dayBefore?.whole == 0)
    }

    @Test func deletedOtherBabiesPumpsAndFutureFeedsAreLeftOut() throws {
        let now = at(2026, 11, 26, 11)
        let events = [
            bottle(at(2026, 11, 26, 8), 60),
            bottle(at(2026, 11, 26, 9), 70, deletedAt: now),
            bottle(at(2026, 11, 26, 9, 30), 80, babyID: "other-baby"),
            snapshot(at(2026, 11, 26, 10), kind: .pump, payload: EventPayload(pump: PumpDetails(side: .both, leftML: 50, rightML: 40))),
            // The phone's clock was set back: this bottle now seems to start an hour from now.
            bottle(at(2026, 11, 26, 12), 90),
        ]
        let shown = try #require(through(events, now: now))
        #expect(shown.soFar == 60)
        #expect(shown.day.steps.count == 1)
    }

    @Test func nothingLoggedOrOutsideTheDaysGivesNothing() {
        let now = at(2026, 11, 26, 9)
        #expect(through([], now: now) == nil)
        let events = [bottle(at(2026, 11, 25, 9), 100)]
        #expect(through(events, date: "2026-11-24", now: now) == nil, "before the first feed")
        #expect(through(events, date: "2026-11-27", now: now) == nil, "after today")
        #expect(through(events, date: "2026-11-25", now: now)?.dayBefore == nil)
        #expect(through(events, date: "2026-11-25", now: now)?.averageByCutOff == nil)
        let breastOnly = [bottle(at(2026, 11, 26, 2), nil, breast: [BreastSegment(side: .left, durationSeconds: 600)])]
        #expect(through(breastOnly, now: now)?.hasBottles == false)
    }

    /// 29 Mar 2026: the UK's clocks go forward at 01:00, so the day is 23 hours long. The day after
    /// is read at the same clock time, not the same number of hours after midnight.
    @Test func whenTheClocksGoForwardTheSameClockTimeIsUsed() throws {
        let events = [bottle(at(2026, 3, 29, 0, 30), 90), bottle(at(2026, 3, 29, 9), 100),
                      bottle(at(2026, 3, 29, 10, 30), 80), bottle(at(2026, 3, 30, 3), 70)]
        let shown = try #require(through(events, now: at(2026, 3, 30, 10)))
        #expect(shown.dayBeforeByCutOff == 190, "by 10:00 on the clock, 10:30 left out")
        #expect(shown.dayBefore?.steps.map(\.clockSecond) == [1800, 9 * 3600, 10 * 3600 + 1800])
    }

    /// 25 Oct 2026: the UK's clocks go back at 02:00, so 01:30 happens twice. Both bottles count by
    /// their clock reading, and today's total so far has every bottle given by now.
    @Test func whenTheClocksGoBackBothHalfPastOnesCount() throws {
        let firstPass = at(2026, 10, 25, 0, 30).addingTimeInterval(3600)    // 01:30 BST
        let secondPass = firstPass.addingTimeInterval(3600)                  // 01:30 GMT
        let tenPast = firstPass.addingTimeInterval(3600 - 20 * 60)          // 01:10 GMT
        let events = [bottle(firstPass, 90), bottle(secondPass.addingTimeInterval(-3600 * 2), 50)]
        // At 01:10 the second time round, the first 01:30 bottle has happened.
        let early = try #require(through(events, now: tenPast))
        #expect(early.cutOff == 3600 + 600)
        #expect(early.soFar == 140)
        // On the line, the first 01:30 sits at now, so the line and the total agree.
        #expect(early.day.steps.map(\.clockSecond) == [1800, 3600 + 600])
        #expect(early.day.total(by: early.cutOff) == early.soFar)
        let both = [bottle(firstPass, 90), bottle(secondPass, 100)]
        let shown = try #require(through(both, now: at(2026, 10, 25, 9)))
        #expect(shown.day.steps.map(\.clockSecond) == [5400, 5400])
        #expect(shown.day.steps.map(\.total) == [90, 190], "the earlier one first")
        #expect(shown.day.total(by: 5400) == 190)
        // 01:30 the first time, then 01:00 the second time: the rows stay in the order they
        // happened, and the first moves back to 01:00 on the line.
        let oneAM = secondPass.addingTimeInterval(-1800)                     // 01:00 GMT
        let swapped = try #require(through([bottle(oneAM, 100), bottle(firstPass, 90)], now: at(2026, 10, 25, 9)))
        #expect(swapped.day.steps.map(\.ml) == [90, 100])
        #expect(swapped.day.steps.map(\.clockSecond) == [3600, 3600])
        #expect(swapped.day.steps.map(\.total) == [90, 190])
    }

    /// The household's time zone decides the day, wherever the phone is (travel).
    @Test func theHouseholdsTimeZoneDecidesTheDay() throws {
        // 23:30 in London is 00:30 in Paris.
        let events = [bottle(at(2026, 11, 25, 23, 30), 100), bottle(at(2026, 11, 26, 8), 90)]
        let now = at(2026, 11, 26, 9)
        let london = try #require(through(events, now: now))
        #expect(london.soFar == 90)
        #expect(london.dayBefore?.whole == 100)
        let paris = try #require(through(events, zone: TimeZone(identifier: "Europe/Paris")!, now: now))
        #expect(paris.soFar == 190)
        #expect(paris.dayBefore == nil)
    }

    /// A time zone 30 minutes off the hour: midnight is that zone's own.
    @Test func aHalfHourTimeZonesMidnightIsUsed() throws {
        let adelaide = TimeZone(identifier: "Australia/Adelaide")!
        let events = [bottle(at(2026, 11, 25, 23, 45, in: adelaide), 100), bottle(at(2026, 11, 26, 0, 15, in: adelaide), 90)]
        let shown = try #require(through(events, zone: adelaide, now: at(2026, 11, 26, 6, 30, in: adelaide)))
        #expect(shown.soFar == 90)
        #expect(shown.dayBefore?.whole == 100)
        #expect(shown.cutOff == 6 * 3600 + 1800)
        #expect(shown.dayBefore?.steps.first?.clockSecond == 23 * 3600 + 45 * 60)
    }
}
