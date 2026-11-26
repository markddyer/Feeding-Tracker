import FeedingCore
import FeedingInsights
import Foundation
import Testing
@testable import FeedingDev

/// The words of "Bottles through the day" (`docs/planning/14-bottles-through-the-day.md`): facts
/// only, never "more", "less", "too much", "usual" or "normal".
@Suite("Bottles through the day words")
struct BottlesTextTests {
    let london = TimeZone(identifier: "Europe/London")!

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func feed(_ start: Date, ml: Int?, breastSeconds: Int? = nil) -> EventSnapshot {
        let breast = breastSeconds.map { [BreastSegment(side: .left, durationSeconds: $0)] } ?? []
        let bottles = breastSeconds != nil && ml == nil ? [] : [Bottle(milk: .formula, ml: ml)]
        return EventSnapshot(event: Event(id: UUID().uuidString, babyID: "baby", kind: .feed, startedAt: start,
                                          timeZoneID: "Europe/London", loggedBy: "a", createdAt: start, modifiedAt: start),
                             payload: EventPayload(feed: FeedDetails(breast: breast, bottles: bottles)))
    }

    func facts(_ events: [EventSnapshot], date: PlainDate? = nil, now: Date) -> BottlesThroughDay {
        bottlesThroughDay(events, babyID: "baby", timeZone: london, date: date, now: now)!
    }

    /// Bottles at 06:00 on 23, 24 and 25 Nov (100, 110 and 120 ml), at 20:00 on 25 Nov (90 ml), and
    /// at 05:00 today (130 ml); it is 15:20 on 26 Nov.
    var week: [EventSnapshot] {
        [feed(at(23, 6), ml: 100), feed(at(24, 6), ml: 110), feed(at(25, 6), ml: 120), feed(at(25, 20), ml: 90),
         feed(at(26, 5), ml: 130)]
    }

    @Test func todaysNumbersAreReadAtTheSameClockTime() {
        let shown = facts(week, now: at(26, 15, 20))
        let numbers = BottlesText.numbers(shown, zone: london, now: at(26, 15, 20))
        // The clock as the phone writes it ("15:20", or "3:20 PM" in a 12-hour region).
        let clock = BottlesText.clock(at(26, 15, 20), in: london)
        #expect(numbers.map(\.label) == ["Today", "Yesterday by \(clock)", "3-day average by \(clock)"])
        #expect(numbers.map(\.ml) == [130, 120, 110])
        #expect(numbers.map(\.difference) == [nil, 10, 20], "today minus each")
        #expect(numbers.first?.main == true)
        #expect(BottlesText.homeLine(shown) == "130 ml today · 120 ml yesterday by now · 110 ml average by now")
        #expect(BottlesText.tileLine(shown, zone: london, now: at(26, 15, 20)) == "by \(clock) · yesterday 120 · average 110")
        #expect(BottlesText.dayHeading(shown, zone: london, now: at(26, 15, 20)) == "Today, by \(clock)")
    }

    @Test func aPastDayIsReadWhole() {
        let shown = facts(week, date: PlainDate("2026-11-25"), now: at(26, 15, 20))
        let numbers = BottlesText.numbers(shown, zone: london, now: at(26, 15, 20))
        #expect(numbers.map(\.label) == ["Whole day", "Day before", "2-day average"])
        #expect(numbers.map(\.ml) == [210, 110, 105])
        #expect(numbers.map(\.difference) == [nil, 100, 105])
        #expect(BottlesText.dayHeading(shown, zone: london, now: at(26, 15, 20)) == "Yesterday")
        #expect(BottlesText.dayKey(shown) == "That day")
        #expect(BottlesText.noBottles(shown) == "No bottles logged on this day.")
    }

    /// One day before is no average: it would only repeat the day before.
    @Test func anAverageNeedsTwoDays() {
        let shown = facts([feed(at(25, 6), ml: 100), feed(at(26, 7), ml: 90)], now: at(26, 9))
        #expect(!BottlesText.showsAverage(shown))
        #expect(BottlesText.numbers(shown, zone: london, now: at(26, 9)).count == 2)
        #expect(BottlesText.homeLine(shown) == "90 ml today · 100 ml yesterday by now")
        let first = facts([feed(at(26, 7), ml: 90)], now: at(26, 9))
        #expect(BottlesText.homeLine(first) == "90 ml today", "nothing before the first day")
    }

    /// A plain difference, like the weight's "+ 140 g since 12 Nov" (Parent A's choice B).
    @Test func theDifferenceIsAPlainSum() {
        #expect(BottlesText.difference(40) == "Difference + 40 ml")
        #expect(BottlesText.difference(-20) == "Difference − 20 ml")
        #expect(BottlesText.difference(0) == "Difference 0 ml")
    }

    @Test func theAverageIsToTheNearestFiveMl() {
        #expect(BottlesText.rounded(501.4) == 500)
        #expect(BottlesText.rounded(502.5) == 505)
        #expect(BottlesText.rounded(0) == 0)
    }

    @Test func whatIsNotInTheTotalIsSaid() {
        let shown = facts([feed(at(26, 2), ml: nil, breastSeconds: 1080), feed(at(26, 4), ml: nil, breastSeconds: 600),
                           feed(at(26, 6), ml: nil), feed(at(26, 8), ml: 60)], now: at(26, 9))
        #expect(BottlesText.alsoNote(shown)
                == "Also 2 breastfeeds today, 28m. A breastfeed has no amount. 1 bottle had no amount logged.")
        let one = facts([feed(at(26, 2), ml: nil, breastSeconds: 1080), feed(at(26, 8), ml: 60)], now: at(26, 9))
        #expect(BottlesText.alsoNote(one) == "Also 1 breastfeed today, 18m. A breastfeed has no amount.")
        #expect(BottlesText.alsoNote(facts([feed(at(26, 8), ml: 60)], now: at(26, 9))) == nil)
    }

    /// The bubble on the line: today's own value only up to now.
    @Test func aPickedTimeOnTheLine() {
        let shown = facts(week, now: at(26, 15, 20))
        #expect(BottlesText.scrubLines(shown, at: 9 * 3600)
                == ["By 09:00", "Today 130 ml", "Yesterday 120 ml (+ 10 ml)", "Average 110 ml (+ 20 ml)"])
        #expect(BottlesText.scrubLines(shown, at: 5 * 3600)
                == ["By 05:00", "Today 130 ml", "Yesterday 0 ml (+ 130 ml)", "Average 0 ml (+ 130 ml)"])
        #expect(BottlesText.scrubLines(shown, at: 21 * 3600)
                == ["By 21:00", "Yesterday 210 ml", "Average 140 ml"], "no today, and no difference, after now")
        #expect(BottlesText.clock(second: 0) == "00:00")
        #expect(BottlesText.clock(second: 86_399) == "23:59")
        #expect(BottlesText.runningTotal(520) == "520 ml from midnight")
    }

    /// No verdict words anywhere the page writes.
    @Test func noVerdictWords() {
        let shown = facts(week, now: at(26, 15, 20))
        let numbers = BottlesText.numbers(shown, zone: london, now: at(26, 15, 20))
        let words = numbers.map(\.label) + numbers.compactMap(\.difference).map(BottlesText.difference)
            + [BottlesText.homeLine(shown), BottlesText.tileLine(shown, zone: london, now: at(26, 15, 20)),
               BottlesText.spokenChart(shown, zone: london, now: at(26, 15, 20)), BottlesText.title, BottlesText.homeHeading]
            + BottlesText.scrubLines(shown, at: 9 * 3600)
        for word in ["more", "less", "too", "usual", "normal", "over", "under", "enough", "target", "limit"] {
            // Split on anything that isn't a letter, so "normal." is still found.
            let found = words.joined(separator: " ").lowercased().split { !$0.isLetter }
            #expect(!found.contains(Substring(word)), "\(word)")
        }
    }

    /// "About bottle feeding" keeps the bottle-feeding passages alone: not reflux, not breastfeeding.
    @MainActor @Test func theBottleLinkOpensOnlyBottleFeedingPassages() {
        let passages = ["bottle-guided", "bottle-settle-sick", "reflux-signs", "feeding-how-often"].compactMap(NHSPassages.passage)
        #expect(passages.count == 4)
        #expect(NHSLinks.bottleFeedingOnly(passages).map(\.id) == ["bottle-guided", "bottle-settle-sick"])
    }
}
