import Foundation
import Testing
@testable import FeedingCore

@Suite("Plain dates and times of day")
struct PlainDateTests {
    @Test func parsesAndPrints() {
        #expect(date("2026-11-13").description == "2026-11-13")
        #expect(date("0999-01-02").description == "0999-01-02")
        #expect(TimeOfDay("21:00")!.description == "21:00")
        #expect(TimeOfDay("07:05")!.minutesSinceMidnight == 425)
    }

    @Test(arguments: ["2026-02-29", "2026-13-01", "2026-04-31", "2026-1-1", "26-01-01", "2026-01-01x", ""])
    func rejectsInvalidDates(_ string: String) {
        #expect(PlainDate(string) == nil)
    }

    @Test(arguments: ["24:00", "12:60", "7:00", "07-00", ""])
    func rejectsInvalidTimes(_ string: String) {
        #expect(TimeOfDay(string) == nil)
    }

    @Test func acceptsLeapDay() {
        #expect(PlainDate("2028-02-29") != nil)
        #expect(PlainDate("2000-02-29") != nil)
        #expect(PlainDate("2100-02-29") == nil)
    }

    @Test func dayArithmeticCrossesMonthsYearsAndLeapDays() {
        #expect(date("2026-12-31").adding(days: 1) == date("2027-01-01"))
        #expect(date("2028-02-28").adding(days: 1) == date("2028-02-29"))
        #expect(date("2028-03-01").adding(days: -1) == date("2028-02-29"))
        #expect(date("2027-01-01").days(since: date("2026-01-01")) == 365)
        #expect(date("2029-01-01").days(since: date("2028-01-01")) == 366)
        #expect(date("2026-11-01").days(since: date("2026-11-13")) == -12)
    }

    @Test func roundTripsEveryDayForThirtyYears() {
        var day = date("2020-01-01")
        for _ in 0..<(30 * 366) {
            #expect(PlainDate(day.description) == day)
            day = day.adding(days: 1)
        }
    }

    @Test func codableUsesPlainStrings() throws {
        let data = try JSONEncoder().encode([date("2026-11-13")])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-11-13\"]")
        #expect(try JSONDecoder().decode([PlainDate].self, from: data) == [date("2026-11-13")])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([PlainDate].self, from: Data("[\"2026-02-30\"]".utf8)) }
        #expect(try JSONDecoder().decode([TimeOfDay].self, from: JSONEncoder().encode([time("21:00")])) == [time("21:00")])
    }

    @Test func localDateDependsOnTheTimeZone() {
        let instant = at(2026, 11, 13, 23, 30, in: utc)
        #expect(PlainDate(instant, in: utc) == date("2026-11-13"))
        #expect(PlainDate(instant, in: TimeZone(identifier: "Asia/Kolkata")!) == date("2026-11-14"))
        #expect(PlainDate(instant, in: TimeZone(identifier: "America/New_York")!) == date("2026-11-13"))
    }
}

@Suite("Day and night")
struct DayHoursTests {
    let hours = DayHours.standard

    @Test func theNightStartsAt21AndIsNamedByItsFirstDate() {
        #expect(hours.period(at: at(2026, 11, 13, 20, 59, 59), in: london) == .day(date("2026-11-13")))
        #expect(hours.period(at: at(2026, 11, 13, 21, 0), in: london) == .night(date("2026-11-13")))
        #expect(hours.period(at: at(2026, 11, 13, 23, 59, 59), in: london) == .night(date("2026-11-13")))
    }

    @Test func midnightStaysInTheSameNight() {
        #expect(hours.period(at: at(2026, 11, 14, 0, 0), in: london) == .night(date("2026-11-13")))
        #expect(hours.period(at: at(2026, 11, 14, 6, 59, 59), in: london) == .night(date("2026-11-13")))
        #expect(hours.period(at: at(2026, 11, 14, 7, 0), in: london) == .day(date("2026-11-14")))
    }

    @Test func aNightThatDoesNotCrossMidnight() {
        let hours = DayHours(dayStart: time("06:00"), nightStart: time("00:30"))
        #expect(hours.period(at: at(2026, 11, 14, 0, 29), in: london) == .day(date("2026-11-14")))
        #expect(hours.period(at: at(2026, 11, 14, 0, 30), in: london) == .night(date("2026-11-14")))
        #expect(hours.period(at: at(2026, 11, 14, 6, 0), in: london) == .day(date("2026-11-14")))
        #expect(hours.nightEnding(on: date("2026-11-14")) == date("2026-11-14"))
        #expect(DayHours.standard.nightEnding(on: date("2026-11-14")) == date("2026-11-13"))
    }

    @Test func equalStartTimesMeanNoNight() {
        let hours = DayHours(dayStart: time("07:00"), nightStart: time("07:00"))
        #expect(hours.period(at: at(2026, 11, 14, 3, 0), in: london) == .day(date("2026-11-14")))
    }

    @Test func clocksGoingForwardInsideTheNight() {
        // 29 March 2026: 01:00 GMT becomes 02:00 BST. The night is 2 hours shorter in real time
        // but keeps its name and both ends.
        #expect(hours.period(at: at(2026, 3, 29, 0, 59, 59, in: utc), in: london) == .night(date("2026-03-28")))
        #expect(hours.period(at: at(2026, 3, 29, 1, 0, in: utc), in: london) == .night(date("2026-03-28")))
        #expect(hours.period(at: at(2026, 3, 29, 5, 59, in: utc), in: london) == .night(date("2026-03-28")))
        #expect(hours.period(at: at(2026, 3, 29, 6, 0, in: utc), in: london) == .day(date("2026-03-29")))
    }

    @Test func clocksGoingBackInsideTheNight() {
        // 25 October 2026: 02:00 BST becomes 01:00 GMT, so 01:30 happens twice. Both are the same night.
        let first = at(2026, 10, 25, 0, 30, in: utc)   // 01:30 BST
        let second = at(2026, 10, 25, 1, 30, in: utc)  // 01:30 GMT
        #expect(WallClock.reading(first, in: london).time == time("01:30"))
        #expect(WallClock.reading(second, in: london).time == time("01:30"))
        #expect(hours.period(at: first, in: london) == .night(date("2026-10-24")))
        #expect(hours.period(at: second, in: london) == .night(date("2026-10-24")))
        #expect(hours.period(at: at(2026, 10, 25, 7, 0, in: utc), in: london) == .day(date("2026-10-25")))
    }

    @Test(arguments: [("Asia/Kolkata", 15, 30), ("Australia/Adelaide", 10, 30)])
    func halfHourTimeZones(_ identifier: String, _ utcHour: Int, _ utcMinute: Int) {
        // 21:00 in Kolkata (UTC+5:30) is 15:30 UTC; in Adelaide in November (UTC+10:30) it is 10:30 UTC.
        let zone = TimeZone(identifier: identifier)!
        let nightStart = at(2026, 11, 13, utcHour, utcMinute, in: utc)
        #expect(hours.period(at: nightStart.addingTimeInterval(-1), in: zone) == .day(date("2026-11-13")))
        #expect(hours.period(at: nightStart, in: zone) == .night(date("2026-11-13")))
    }
}

@Suite("Rota and claims")
struct RotaTests {
    @Test func alternatesForwardsAndBackwards() {
        #expect(rotaFrom13Nov.scheduledOnDuty(night: date("2026-11-13")) == parentA)
        #expect(rotaFrom13Nov.scheduledOnDuty(night: date("2026-11-14")) == parentB)
        #expect(rotaFrom13Nov.scheduledOnDuty(night: date("2026-11-15")) == parentA)
        #expect(rotaFrom13Nov.scheduledOnDuty(night: date("2026-11-12")) == parentB)
        #expect(rotaFrom13Nov.scheduledOnDuty(night: date("2026-11-11")) == parentA)
        #expect(rotaFrom13Nov.scheduledOnDuty(night: date("2027-11-13")) == parentB) // 365 nights later
    }

    @Test func aClaimOverridesTheRotaForThatNightOnly() {
        let claim = NightClaim(night: date("2026-11-13"), member: parentB, claimedAt: at(2026, 11, 13, 18, 0))
        let roster = DutyRoster(rota: rotaFrom13Nov, claims: [claim])
        #expect(roster.onDuty(night: date("2026-11-13")) == parentB)
        #expect(roster.onDuty(night: date("2026-11-15")) == parentA)
        #expect(claim.recordName == "night-2026-11-13")
    }

    @Test func clashingClaimsResolveTheSameWayInAnyOrder() {
        let night = date("2026-11-13")
        let early = NightClaim(night: night, member: parentA, claimedAt: at(2026, 11, 13, 18, 0))
        let late = NightClaim(night: night, member: parentB, claimedAt: at(2026, 11, 13, 19, 0))
        #expect(DutyRoster(rota: rotaFrom13Nov, claims: [early, late]).onDuty(night: night) == parentB)
        #expect(DutyRoster(rota: rotaFrom13Nov, claims: [late, early]).onDuty(night: night) == parentB)

        let tieA = NightClaim(night: night, member: parentA, claimedAt: at(2026, 11, 13, 18, 0))
        let tieB = NightClaim(night: night, member: parentB, claimedAt: at(2026, 11, 13, 18, 0))
        #expect(DutyRoster(rota: rotaFrom13Nov, claims: [tieA, tieB]).onDuty(night: night) == parentA)
        #expect(DutyRoster(rota: rotaFrom13Nov, claims: [tieB, tieA]).onDuty(night: night) == parentA)
    }
}
