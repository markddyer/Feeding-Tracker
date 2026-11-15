import Foundation
import Testing
@testable import FeedingCore

@Suite("The greeting")
struct PartOfDayTests {
    @Test(arguments: [
        (0, 0, PartOfDay.night), (6, 59, .night), (7, 0, .morning), (11, 59, .morning), (12, 0, .afternoon),
        (16, 59, .afternoon), (17, 0, .evening), (20, 59, .evening), (21, 0, .night), (23, 59, .night),
    ])
    func standardHours(_ hour: Int, _ minute: Int, _ expected: PartOfDay) {
        #expect(DayHours.standard.partOfDay(at: at(2026, 11, 14, hour, minute), in: london) == expected)
    }

    @Test func itFollowsTheRotaHours() {
        let hours = DayHours(dayStart: time("13:00"), nightStart: time("23:00"))
        #expect(hours.partOfDay(at: at(2026, 11, 14, 12, 59), in: london) == .night)
        #expect(hours.partOfDay(at: at(2026, 11, 14, 13, 0), in: london) == .afternoon)
        #expect(hours.partOfDay(at: at(2026, 11, 14, 22, 59), in: london) == .evening)
        #expect(hours.partOfDay(at: at(2026, 11, 14, 23, 0), in: london) == .night)
    }

    @Test func itReadsTheHouseholdClock() {
        // 20:30 in London is 02:00 the next day in Kolkata, a half-hour zone.
        let instant = at(2026, 11, 14, 20, 30)
        #expect(DayHours.standard.partOfDay(at: instant, in: london) == .evening)
        #expect(DayHours.standard.partOfDay(at: instant, in: TimeZone(identifier: "Asia/Kolkata")!) == .night)
    }

    @Test func clockChangesInBothDirections() {
        // UK clocks go forward on 29 Mar 2026 and back on 25 Oct 2026.
        #expect(DayHours.standard.partOfDay(at: at(2026, 3, 29, 6, 59), in: london) == .night)
        #expect(DayHours.standard.partOfDay(at: at(2026, 3, 29, 7, 0), in: london) == .morning)
        #expect(DayHours.standard.partOfDay(at: at(2026, 10, 25, 6, 59), in: london) == .night)
        #expect(DayHours.standard.partOfDay(at: at(2026, 10, 25, 12, 0), in: london) == .afternoon)
    }
}

@Suite("The baby's age")
struct AgeTests {
    func baby(born: String?) -> BabyPayload {
        BabyPayload(name: "Baby", birthDate: born.map(date))
    }

    @Test func theDayOfBirthIsDayZero() {
        #expect(baby(born: "2026-11-14").ageInDays(at: at(2026, 11, 14, 0, 0), in: london) == 0)
        #expect(baby(born: "2026-11-14").ageInDays(at: at(2026, 11, 14, 23, 59), in: london) == 0)
        #expect(baby(born: "2026-11-14").ageInDays(at: at(2026, 11, 15, 0, 0), in: london) == 1)
    }

    @Test func itCountsWholeDaysAcrossAClockChange() {
        #expect(baby(born: "2026-11-02").ageInDays(at: at(2026, 11, 14, 9, 0), in: london) == 12)
        #expect(baby(born: "2026-10-20").ageInDays(at: at(2026, 11, 1, 12, 0), in: london) == 12)
        #expect(baby(born: "2026-03-20").ageInDays(at: at(2026, 4, 1, 12, 0), in: london) == 12)
    }

    @Test func itUsesTheHouseholdCalendar() {
        // 22:00 in London is 03:30 the next day in Kolkata.
        let instant = at(2026, 11, 14, 22, 0)
        #expect(baby(born: "2026-11-14").ageInDays(at: instant, in: london) == 0)
        #expect(baby(born: "2026-11-14").ageInDays(at: instant, in: TimeZone(identifier: "Asia/Kolkata")!) == 1)
    }

    @Test func noBirthDateOrOneInTheFutureShowsNothing() {
        #expect(baby(born: nil).ageInDays(at: at(2026, 11, 14, 9, 0), in: london) == nil)
        // A phone clock set back to before the birth.
        #expect(baby(born: "2026-11-15").ageInDays(at: at(2026, 11, 14, 9, 0), in: london) == nil)
    }
}

@Suite("Days of the week")
struct WeekdayTests {
    @Test func knownDays() {
        #expect(date("2026-11-16").weekday == 1) // Monday
        #expect(date("2026-11-15").weekday == 7) // Sunday
        #expect(date("2000-01-01").weekday == 6) // Saturday
        #expect(date("2028-02-29").weekday == 2) // Tuesday
    }

    @Test func itAgreesWithTheCalendarForThreeYears() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var day = date("2026-01-01")
        for _ in 0..<(3 * 366) {
            // Calendar: 1 is Sunday. ISO: 1 is Monday, 7 is Sunday.
            let sundayFirst = calendar.component(.weekday, from: at(day.year, day.month, day.day, 12, in: utc))
            #expect(day.weekday == (sundayFirst + 5) % 7 + 1, "\(day)")
            day = day.adding(days: 1)
        }
    }
}

@Suite("The 24-hour chart")
struct DayChartTests {
    let now = at(2026, 11, 14, 12, 0)
    var dayAgo: Date { now.addingTimeInterval(-.hours(24)) }

    func ended(_ snapshot: EventSnapshot, after minutes: Double) -> EventSnapshot {
        var snapshot = snapshot
        snapshot.event.endedAt = snapshot.event.startedAt.addingTimeInterval(.minutes(minutes))
        return snapshot
    }

    @Test func noFeedsMeansAnEmptyChart() {
        #expect(dayChart([], babyID: baby, now: now).isEmpty)
    }

    @Test func itShowsTheSameFeedsTheTotalsCount() {
        let events = [
            ended(snapshot(dayAgo, id: "exactly 24 hours", payload: breast(.left)), after: 20),
            ended(snapshot(dayAgo.addingTimeInterval(-1), id: "just over", payload: breast(.left)), after: 20),
            ended(snapshot(at(2026, 11, 14, 8, 0), id: "deleted", deletedAt: at(2026, 11, 14, 8, 30), payload: breast(.left)), after: 20),
            ended(snapshot(at(2026, 11, 14, 9, 0), id: "pump", kind: .pump,
                           payload: EventPayload(pump: PumpDetails(side: .left, leftML: 40))), after: 20),
            ended(snapshot(at(2026, 11, 14, 9, 30), id: "other baby", babyID: "baby-2", payload: breast(.left)), after: 20),
            snapshot(now.addingTimeInterval(60), id: "after now", payload: breast(.left)),
            ended(snapshot(at(2026, 11, 14, 10, 0), id: "kept", payload: bottles((.formula, 30))), after: 15),
        ]
        #expect(dayChart(events, babyID: baby, now: now).map(\.id) == ["exactly 24 hours", "kept"])
        #expect(summarise(events, babyID: baby, from: dayAgo, to: now).feeds == 2)
    }

    @Test func eachFeedHasItsKindsAndLength() {
        var mixed = breast(.left)
        mixed.feed?.bottles = [Bottle(milk: .formula, ml: 30)]
        let events = [
            snapshot(at(2026, 11, 14, 11, 40), id: "running", payload: breast(.right)),
            ended(snapshot(at(2026, 11, 14, 2, 0), id: "breast", payload: breast(.left, .right)), after: 25),
            ended(snapshot(at(2026, 11, 14, 5, 0), id: "bottle", payload: bottles((.expressed, 60))), after: 10),
            ended(snapshot(at(2026, 11, 14, 8, 0), id: "mixed", payload: mixed), after: 30),
            ended(snapshot(at(2026, 11, 14, 10, 0), id: "newer app", payload: nil), after: 20),
        ]
        let chart = dayChart(events, babyID: baby, now: now)
        #expect(chart.map(\.id) == ["breast", "bottle", "mixed", "newer app", "running"])
        #expect(chart.map(\.breast) == [true, false, true, false, true])
        #expect(chart.map(\.bottle) == [false, true, true, false, false])
        #expect(chart.map(\.duration) == [.minutes(25), .minutes(10), .minutes(30), .minutes(20), .minutes(20)])
        #expect(chart.map(\.running) == [false, false, false, false, true])
    }

    @Test func anEndBeforeTheStartCountsAsNoTime() {
        var odd = snapshot(at(2026, 11, 14, 10, 0), payload: breast(.left))
        odd.event.endedAt = at(2026, 11, 14, 9, 0)
        #expect(dayChart([odd], babyID: baby, now: now).map(\.duration) == [0])
    }
}

@Suite("The row of nights")
struct NightsRowTests {
    let tonight = date("2026-11-15")

    func state(rota: Rota?, claims: [NightClaim] = []) -> HouseholdState {
        HouseholdState(settings: HouseholdSettings(), rota: rota, claims: claims, pendingChanges: [])
    }

    @Test func fiveNightsBackThenTonightAndTomorrow() {
        let nights = state(rota: rotaFrom13Nov).nights(around: tonight, before: 5, after: 1)
        #expect(nights.map(\.night) == (-5...1).map { tonight.adding(days: $0) })
        // Parent A has the 13th and every second night from it.
        #expect(nights.map(\.onDuty) == [parentB, parentA, parentB, parentA, parentB, parentA, parentB])
    }

    @Test func aClaimBeatsTheRotaAndTheLaterClaimWins() {
        let claims = [
            NightClaim(night: date("2026-11-14"), member: parentA, claimedAt: at(2026, 11, 14, 18, 0)),
            NightClaim(night: tonight, member: parentA, claimedAt: at(2026, 11, 15, 18, 0)),
            NightClaim(night: tonight, member: parentB, claimedAt: at(2026, 11, 15, 19, 0)),
        ]
        let nights = state(rota: rotaFrom13Nov, claims: claims).nights(around: tonight, before: 1, after: 0)
        #expect(nights.map(\.onDuty) == [parentA, parentB])
    }

    @Test func withNoRotaOnlyATakenNightHasSomeone() {
        let claims = [NightClaim(night: tonight, member: parentB, claimedAt: at(2026, 11, 15, 18, 0))]
        let nights = state(rota: nil, claims: claims).nights(around: tonight, before: 2, after: 1)
        #expect(nights.map(\.onDuty) == [nil, nil, parentB, nil])
    }

    @Test func theRowNeverChangesWhoAlerts() {
        // With no rota, the row shows nobody, but the alerts still count this phone as on duty.
        let noRota = state(rota: nil)
        #expect(noRota.nights(around: tonight, before: 0, after: 0).map(\.onDuty) == [nil])
        #expect(noRota.roster(for: parentA).onDuty(night: tonight) == parentA)
    }
}
