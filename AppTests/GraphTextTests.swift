import FeedingCore
import Foundation
import Testing
@testable import FeedingDev

/// The words on the Graphs tab (the user's choices of 16 Nov 2026).
@Suite("Graphs tab words")
struct GraphTextTests {
    let london = TimeZone(identifier: "Europe/London")!

    func day(_ string: String, today: Bool = false, gaps: [TimeInterval] = []) -> GraphDay {
        var day = GraphDay(date: PlainDate(string)!, isToday: today)
        day.gaps = gaps
        return day
    }

    @Test func theDaysUnderTheBars() {
        // 10 Nov 2026 is a Tuesday.
        #expect(GraphText.axisLabel(day("2026-11-10"), in: london, week: true).hasPrefix("Tue"))
        #expect(GraphText.axisLabel(day("2026-11-10"), in: london, week: false).contains("10"))
        #expect(GraphText.axisLabel(day("2026-11-16", today: true), in: london, week: true) == "Today")
        #expect(GraphText.spokenDay(day("2026-11-10"), in: london).contains("Tuesday"))
        #expect(GraphText.spokenDay(day("2026-11-16", today: true), in: london) == "Today")
    }

    @Test func aWeekLabelsEveryDayAndLongerRangesAboutFive() {
        let week = (0..<7).map { day(PlainDate("2026-11-10")!.adding(days: $0).description, today: $0 == 6) }
        #expect(GraphText.labelled(week).count == 7)
        let month = (0..<28).map { day(PlainDate("2026-10-20")!.adding(days: $0).description, today: $0 == 27) }
        let labelled = GraphText.labelled(month)
        #expect(labelled.last?.isToday == true)
        #expect(labelled.count == 4)
        let long = (0..<120).map { day(PlainDate("2026-07-20")!.adding(days: $0).description, today: $0 == 119) }
        #expect((4...6).contains(GraphText.labelled(long).count))
    }

    @Test func whatVoiceOverReads() {
        #expect(GraphText.feeds(1) == "1 feed")
        #expect(GraphText.feeds(9) == "9 feeds")
        var bottles = day("2026-11-10")
        bottles.formulaML = 240
        bottles.expressedML = 180
        #expect(GraphText.bottles(bottles) == "420 ml: 240 ml formula, 180 ml expressed milk")
        #expect(GraphText.gaps(day("2026-11-10", gaps: [5400, 9000, 7200]))
                == "Shortest 1 hour, 30 minutes; longest 2 hours, 30 minutes; middle 2 hours")
        #expect(GraphText.gaps(day("2026-11-10", gaps: [7200])) == "One gap of 2 hours")
        #expect(GraphText.gaps(day("2026-11-10")) == "No time between feeds")
        var sides = day("2026-11-10")
        sides.leftSeconds = 3720
        sides.rightSeconds = 60
        #expect(GraphText.sides(sides) == "Left 62 minutes, right 1 minute")
        var pump = day("2026-11-10")
        pump.pumpedML = 90
        pump.pumpSessions = 1
        #expect(GraphText.pumped(pump) == "90 ml pumped, 1 session")
    }

    @Test func noWordSoundsLikeAVerdict() {
        var full = day("2026-11-10", gaps: [5400, 9000])
        full.formulaML = 60
        full.leftSeconds = 600
        full.pumpedML = 50
        full.pumpSessions = 2
        let words = [GraphText.feeds(3), GraphText.bottles(full), GraphText.gaps(full), GraphText.sides(full),
                     GraphText.pumped(full), "Graphs", "7 days", "4 weeks", "All", "Feeds each day",
                     "Bottles each day · ml", "Time between feeds", "Breast each day · minutes",
                     "Pumped each day · ml", "Formula", "Expressed", "Shortest to longest", "Middle", "Left",
                     "Right", "No feeds logged yet."]
        for word in words {
            let plain = word.lowercased().filter { $0.isLetter || $0 == " " || $0 == "'" }
            for forbidden in AlertText.forbiddenWords {
                #expect(!plain.split(separator: " ").contains(Substring(forbidden)), "\(word)")
            }
        }
    }
}
