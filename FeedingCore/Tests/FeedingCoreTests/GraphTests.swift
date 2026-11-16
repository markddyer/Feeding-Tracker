import Foundation
import Testing
@testable import FeedingCore

@Suite("Graphs")
struct GraphTests {
    func feedWith(_ start: Date, breast: [BreastSegment] = [], bottles: [Bottle] = [],
                  deletedAt: Date? = nil, babyID: String = baby) -> EventSnapshot {
        snapshot(start, babyID: babyID, deletedAt: deletedAt, payload: EventPayload(feed: FeedDetails(breast: breast, bottles: bottles)))
    }

    func day(_ days: [GraphDay], _ string: String) -> GraphDay? { days.first { $0.date == date(string) } }

    @Test func itCountsEachKindPerDay() {
        let events = [
            feedWith(at(2026, 11, 14, 8), breast: [BreastSegment(side: .left, durationSeconds: 600),
                                                    BreastSegment(side: .right, durationSeconds: 300)],
                     bottles: [Bottle(milk: .formula, ml: 60)]),
            feedWith(at(2026, 11, 14, 11), bottles: [Bottle(milk: .expressed, ml: 90), Bottle(milk: .formula)]),
            snapshot(at(2026, 11, 14, 13), kind: .pump, payload: EventPayload(pump: PumpDetails(side: .both, leftML: 50, rightML: 40))),
            feedWith(at(2026, 11, 15, 2), bottles: [Bottle(milk: .formula, ml: 30)]),
        ]
        let days = graphDays(events, babyID: baby, timeZone: london, range: .week, now: at(2026, 11, 15, 12))
        #expect(days.map(\.date) == [date("2026-11-14"), date("2026-11-15")])
        let first = day(days, "2026-11-14")
        #expect(first?.feeds == 2)
        #expect(first?.formulaML == 60)
        #expect(first?.expressedML == 90)
        #expect(first?.bottleML == 150)
        #expect(first?.leftSeconds == 600)
        #expect(first?.rightSeconds == 300)
        #expect(first?.pumpSessions == 1)
        #expect(first?.pumpedML == 90)
        #expect(first?.isToday == false)
        #expect(day(days, "2026-11-15")?.formulaML == 30)
        #expect(day(days, "2026-11-15")?.isToday == true)
    }

    @Test func aFeedCountsOnTheDayItStarted() {
        let events = [feedWith(at(2026, 11, 14, 23, 59)), feedWith(at(2026, 11, 15, 0, 0))]
        let days = graphDays(events, babyID: baby, timeZone: london, range: .week, now: at(2026, 11, 15, 9))
        #expect(day(days, "2026-11-14")?.feeds == 1)
        #expect(day(days, "2026-11-15")?.feeds == 1)
    }

    /// Days run from midnight, not from the 21:00 start of the night rota.
    @Test func aFeedAfterNineAtNightIsStillThatDay() {
        let events = [feedWith(at(2026, 11, 14, 21, 30)), feedWith(at(2026, 11, 15, 1))]
        let days = graphDays(events, babyID: baby, timeZone: london, range: .week, now: at(2026, 11, 15, 9))
        #expect(day(days, "2026-11-14")?.feeds == 1)
        #expect(day(days, "2026-11-15")?.feeds == 1)
    }

    @Test func eachRangeEndsTodayAndStartsNoEarlierThanTheFirstFeed() {
        let events = [feedWith(at(2026, 11, 1, 10)), feedWith(at(2026, 11, 15, 10))]
        let now = at(2026, 11, 15, 12)
        let week = graphDays(events, babyID: baby, timeZone: london, range: .week, now: now)
        #expect(week.first?.date == date("2026-11-09"))
        #expect(week.last?.date == date("2026-11-15"))
        #expect(week.count == 7)
        #expect(week.filter(\.isToday).map(\.date) == [date("2026-11-15")])
        let fourWeeks = graphDays(events, babyID: baby, timeZone: london, range: .fourWeeks, now: now)
        #expect(fourWeeks.first?.date == date("2026-11-01"))
        #expect(fourWeeks.count == 15)
        #expect(graphDays(events, babyID: baby, timeZone: london, range: .all, now: now).count == 15)
        #expect(graphDays([], babyID: baby, timeZone: london, range: .all, now: now).isEmpty)
    }

    @Test func aGapIsKeptUnderTheDayTheNextFeedStarted() {
        let events = [feedWith(at(2026, 11, 8, 22)), feedWith(at(2026, 11, 9, 1)), feedWith(at(2026, 11, 9, 4, 30)),
                      feedWith(at(2026, 11, 9, 7)), feedWith(at(2026, 11, 15, 7))]
        let days = graphDays(events, babyID: baby, timeZone: london, range: .week, now: at(2026, 11, 15, 12))
        // 8 Nov is before this week, but its feed still starts the first gap of 9 Nov.
        let ninth = day(days, "2026-11-09")
        #expect(ninth?.gaps == [.hours(3), .hours(3.5), .hours(2.5)])
        #expect(ninth?.shortestGap == .hours(2.5))
        #expect(ninth?.longestGap == .hours(3.5))
        #expect(ninth?.middleGap == .hours(3))
        #expect(day(days, "2026-11-15")?.gaps == [.hours(144)])
        #expect(day(days, "2026-11-12")?.middleGap == nil)
    }

    @Test func theMiddleOfAnEvenNumberOfGapsIsHalfwayBetweenTheTwoMiddleOnes() {
        var day = GraphDay(date: date("2026-11-15"), isToday: false)
        day.gaps = [.hours(1), .hours(3), .hours(2), .hours(10)]
        #expect(day.middleGap == .hours(2.5))
    }

    @Test func deletedFeedsOtherBabiesAndFutureFeedsAreLeftOut() {
        let now = at(2026, 11, 15, 11)
        let events = [
            feedWith(at(2026, 11, 15, 8), bottles: [Bottle(milk: .formula, ml: 60)]),
            feedWith(at(2026, 11, 15, 9), bottles: [Bottle(milk: .formula, ml: 70)], deletedAt: now),
            feedWith(at(2026, 11, 15, 9, 30), bottles: [Bottle(milk: .formula, ml: 80)], babyID: "other-baby"),
            // The phone's clock was set back: this feed now seems to start an hour from now.
            feedWith(at(2026, 11, 15, 12), bottles: [Bottle(milk: .formula, ml: 90)]),
            // A feed from a newer app, whose details this app can't read, still counts as a feed.
            snapshot(at(2026, 11, 15, 10), payload: nil),
        ]
        let days = graphDays(events, babyID: baby, timeZone: london, range: .week, now: now)
        #expect(days.count == 1)
        #expect(days.first?.feeds == 2)
        #expect(days.first?.formulaML == 60)
        #expect(days.first?.gaps == [.hours(2)])
    }

    /// 25 Oct 2026: the UK's clocks go back at 02:00, so the day is 25 hours long.
    @Test func whenTheClocksGoBackTheGapIsTheRealTime() {
        let before = at(2026, 10, 25, 0, 30)               // 00:30 BST
        let after = at(2026, 10, 25, 3, 0)                 // 03:00 GMT, 3½ hours later
        let late = at(2026, 10, 25, 23, 30)                // still 25 Oct
        let events = [feedWith(before), feedWith(after), feedWith(late)]
        let days = graphDays(events, babyID: baby, timeZone: london, range: .week, now: at(2026, 10, 26, 9))
        let day25 = day(days, "2026-10-25")
        #expect(day25?.feeds == 3)
        #expect(day25?.gaps.first == .hours(3.5))
        #expect(day(days, "2026-10-26")?.feeds == 0)
    }

    /// 29 Mar 2026: the UK's clocks go forward at 01:00, so the day is 23 hours long.
    @Test func whenTheClocksGoForwardTheGapIsTheRealTime() {
        let events = [feedWith(at(2026, 3, 29, 0, 30)), feedWith(at(2026, 3, 29, 3, 0))]
        let days = graphDays(events, babyID: baby, timeZone: london, range: .week, now: at(2026, 3, 29, 9))
        #expect(days.map(\.date) == [date("2026-03-29")])
        #expect(days.first?.gaps == [.hours(1.5)])
    }

    /// India is 5½ hours ahead of UTC: its midnight is 18:30 UTC.
    @Test func aHalfHourTimeZoneSplitsDaysAtItsOwnMidnight() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let events = [feedWith(at(2026, 11, 14, 18, 15, in: utc)), feedWith(at(2026, 11, 14, 18, 45, in: utc))]
        let days = graphDays(events, babyID: baby, timeZone: kolkata, range: .week, now: at(2026, 11, 15, 6, in: utc))
        #expect(day(days, "2026-11-14")?.feeds == 1)
        #expect(day(days, "2026-11-15")?.feeds == 1)
    }

    /// A phone abroad logs in its own time zone, but the days are the household's.
    @Test func whileTravellingDaysStayTheHouseholds() {
        let start = at(2026, 11, 15, 3)                    // 03:00 in London; 22:00 on 14 Nov in New York
        let away = EventSnapshot(
            event: Event(id: "away", babyID: baby, kind: .feed, startedAt: start, timeZoneID: "America/New_York",
                         loggedBy: parentA, createdAt: start, modifiedAt: start),
            payload: EventPayload())
        let days = graphDays([away], babyID: baby, timeZone: london, range: .week, now: at(2026, 11, 15, 9))
        #expect(days.map(\.date) == [date("2026-11-15")])
        #expect(days.first?.feeds == 1)
    }

    @Test func aSideStillRunningAddsNoMinutes() {
        let events = [feedWith(at(2026, 11, 15, 8), breast: [BreastSegment(side: .left, durationSeconds: 480),
                                                             BreastSegment(side: .right, durationSeconds: nil)])]
        let days = graphDays(events, babyID: baby, timeZone: london, range: .week, now: at(2026, 11, 15, 8, 12))
        #expect(days.first?.leftSeconds == 480)
        #expect(days.first?.rightSeconds == 0)
    }
}
