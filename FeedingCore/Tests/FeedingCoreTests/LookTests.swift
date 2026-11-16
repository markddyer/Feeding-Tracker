import Foundation
import Testing
@testable import FeedingCore

@Suite("Day and night looks")
struct LookTests {
    let hours = DayHours.standard

    func automatic(at now: Date, hours: DayHours = .standard, in zone: TimeZone = london) -> LookResolution {
        LookSetting.automatic.resolve(dayHours: hours, timeZone: zone, phoneIsDark: false, now: now)
    }

    @Test func theNightLookStartsAt21() {
        #expect(automatic(at: at(2026, 11, 15, 20, 59)) == LookResolution(look: .day, nextChange: at(2026, 11, 15, 21, 0)))
        #expect(automatic(at: at(2026, 11, 15, 20, 59, 59)).look == .day)
        #expect(automatic(at: at(2026, 11, 15, 21, 0)) == LookResolution(look: .night, nextChange: at(2026, 11, 16, 7, 0)))
    }

    @Test func theNightLookRunsPastMidnightAndEndsAt7() {
        #expect(automatic(at: at(2026, 11, 15, 23, 59, 59)) == LookResolution(look: .night, nextChange: at(2026, 11, 16, 7, 0)))
        #expect(automatic(at: at(2026, 11, 16, 0, 0)) == LookResolution(look: .night, nextChange: at(2026, 11, 16, 7, 0)))
        #expect(automatic(at: at(2026, 11, 16, 6, 59)) == LookResolution(look: .night, nextChange: at(2026, 11, 16, 7, 0)))
        #expect(automatic(at: at(2026, 11, 16, 7, 0)) == LookResolution(look: .day, nextChange: at(2026, 11, 16, 21, 0)))
    }

    @Test func partSecondsStillGiveTheBoundary() {
        let now = at(2026, 11, 15, 20, 59, 59).addingTimeInterval(0.75)
        #expect(automatic(at: now).nextChange == at(2026, 11, 15, 21, 0))
    }

    @Test func followsTheHouseholdsHours() {
        let hours = DayHours(dayStart: time("06:00"), nightStart: time("22:00"))
        #expect(automatic(at: at(2026, 11, 15, 21, 30), hours: hours) == LookResolution(look: .day, nextChange: at(2026, 11, 15, 22, 0)))
        #expect(automatic(at: at(2026, 11, 16, 6, 30), hours: hours) == LookResolution(look: .day, nextChange: at(2026, 11, 16, 22, 0)))
    }

    @Test func aNightThatDoesNotCrossMidnight() {
        let hours = DayHours(dayStart: time("06:00"), nightStart: time("00:30"))
        #expect(automatic(at: at(2026, 11, 15, 23, 0), hours: hours) == LookResolution(look: .day, nextChange: at(2026, 11, 16, 0, 30)))
        #expect(automatic(at: at(2026, 11, 16, 0, 30), hours: hours) == LookResolution(look: .night, nextChange: at(2026, 11, 16, 6, 0)))
    }

    @Test func noNightMeansAlwaysTheDayLook() {
        let hours = DayHours(dayStart: time("07:00"), nightStart: time("07:00"))
        #expect(automatic(at: at(2026, 11, 16, 3, 0), hours: hours) == LookResolution(look: .day, nextChange: nil))
    }

    @Test func theOtherSettingsNeverChangeByThemselves() {
        // At midday, and at 3am inside the night hours, with the phone's Dark Mode off and on.
        for now in [at(2026, 11, 15, 12, 0), at(2026, 11, 16, 3, 0)] {
            for dark in [false, true] {
                #expect(LookSetting.alwaysDay.resolve(dayHours: hours, timeZone: london, phoneIsDark: dark, now: now)
                        == LookResolution(look: .day, nextChange: nil))
                #expect(LookSetting.alwaysNight.resolve(dayHours: hours, timeZone: london, phoneIsDark: dark, now: now)
                        == LookResolution(look: .night, nextChange: nil))
                #expect(LookSetting.matchPhone.resolve(dayHours: hours, timeZone: london, phoneIsDark: dark, now: now)
                        == LookResolution(look: dark ? .night : .day, nextChange: nil))
            }
        }
        // Automatic ignores the phone's Dark Mode.
        let midday = at(2026, 11, 15, 12, 0)
        #expect(LookSetting.automatic.resolve(dayHours: hours, timeZone: london, phoneIsDark: true, now: midday).look == .day)
    }

    /// The setting is kept by name, so an older app version that doesn't know a name reads it as
    /// Automatic, and the names never change.
    @Test func theSettingsAreKeptByName() {
        #expect(LookSetting.allCases.map(\.rawValue) == ["automatic", "alwaysDay", "alwaysNight", "matchPhone"])
    }

    @Test func aClockSetBackGivesTheLookForTheNewTime() {
        #expect(automatic(at: at(2026, 11, 15, 21, 30)).look == .night)
        #expect(automatic(at: at(2026, 11, 15, 20, 30)) == LookResolution(look: .day, nextChange: at(2026, 11, 15, 21, 0)))
    }

    @Test func clocksGoingForwardDuringTheNight() {
        // 29 March 2026: 01:00 GMT becomes 02:00 BST. The day still starts at 07:00 on the wall clock.
        #expect(automatic(at: at(2026, 3, 28, 23, 0, in: utc)).nextChange == at(2026, 3, 29, 6, 0, in: utc))
    }

    @Test func clocksGoingBackDuringTheNight() {
        // 25 October 2026: 02:00 BST becomes 01:00 GMT. The day still starts at 07:00 on the wall clock.
        #expect(automatic(at: at(2026, 10, 24, 21, 0, in: utc)).nextChange == at(2026, 10, 25, 7, 0, in: utc))
    }

    @Test func aDayStartInsideTheSkippedHour() {
        // Day from 01:30. On 29 March 2026 there is no 01:30: the clock goes from 00:59:59 GMT
        // straight to 02:00 BST, so the day look starts then.
        let hours = DayHours(dayStart: time("01:30"), nightStart: time("21:00"))
        #expect(automatic(at: at(2026, 3, 28, 23, 0, in: utc), hours: hours).nextChange == at(2026, 3, 29, 1, 0, in: utc))
    }

    @Test func aDayStartInsideTheRepeatedHour() {
        // Day from 01:30. On 25 October 2026 01:30 happens twice, so the night look comes back
        // for the half hour between the clock change and the second 01:30.
        let hours = DayHours(dayStart: time("01:30"), nightStart: time("21:00"))
        let firstDay = at(2026, 10, 25, 0, 30, in: utc)   // 01:30 BST
        let clockChange = at(2026, 10, 25, 1, 0, in: utc)  // 02:00 BST becomes 01:00 GMT
        let secondDay = at(2026, 10, 25, 1, 30, in: utc)  // 01:30 GMT
        #expect(automatic(at: at(2026, 10, 24, 23, 0, in: utc), hours: hours).nextChange == firstDay)
        #expect(automatic(at: firstDay, hours: hours) == LookResolution(look: .day, nextChange: clockChange))
        #expect(automatic(at: clockChange, hours: hours) == LookResolution(look: .night, nextChange: secondDay))
        #expect(automatic(at: secondDay, hours: hours).look == .day)
    }

    @Test(arguments: [("Asia/Kolkata", 15, 30), ("Australia/Adelaide", 10, 30)])
    func halfHourTimeZones(_ identifier: String, _ utcHour: Int, _ utcMinute: Int) {
        // 21:00 in Kolkata (UTC+5:30) is 15:30 UTC; in Adelaide in November (UTC+10:30) it is 10:30 UTC.
        let zone = TimeZone(identifier: identifier)!
        let nightStart = at(2026, 11, 13, utcHour, utcMinute, in: utc)
        #expect(automatic(at: nightStart.addingTimeInterval(-3600), in: zone) == LookResolution(look: .day, nextChange: nightStart))
    }

    /// Across a whole year, in several time zones and with awkward hours, the next change is
    /// always a real change, and the look holds steady until it.
    @Test(arguments: [
        ("Europe/London", "07:00", "21:00"),
        ("Europe/London", "01:30", "21:00"),
        ("Europe/London", "06:00", "01:30"),
        ("America/New_York", "07:00", "21:00"),
        ("Australia/Lord_Howe", "02:00", "21:00"),
        ("Asia/Kolkata", "07:00", "21:00"),
    ])
    func theNextChangeIsAlwaysTheFirstChange(_ identifier: String, _ dayStart: String, _ nightStart: String) throws {
        let zone = TimeZone(identifier: identifier)!
        let hours = DayHours(dayStart: time(dayStart), nightStart: time(nightStart))
        var now = at(2026, 1, 1, 0, 0, in: utc)
        let end = at(2027, 1, 1, 0, 0, in: utc)
        while now < end {
            let resolution = automatic(at: now, hours: hours, in: zone)
            let next = try #require(resolution.nextChange)
            #expect(next > now)
            #expect(next.timeIntervalSince(now) <= 25 * 3600)
            #expect(hours.look(at: next, in: zone) != resolution.look, "\(now) → \(next)")
            #expect(hours.look(at: next.addingTimeInterval(-1), in: zone) == resolution.look, "\(now) → \(next)")
            var check = now
            while check < next {
                #expect(hours.look(at: check, in: zone) == resolution.look, "\(now) → \(next), but changed by \(check)")
                check.addTimeInterval(10 * 60)
            }
            now.addTimeInterval(7 * 3600 + 13 * 60 + 17)
        }
    }
}
