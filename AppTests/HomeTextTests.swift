import FeedingCore
import Foundation
import Testing
@testable import FeedingDev

/// The words and numbers on the redesigned home screen (`05-visual-redesign.md`, "Checks").
@Suite("Home screen words")
struct HomeTextTests {
    @Test(arguments: [
        (0, "0m"), (59, "0m"), (60, "1m"), (45 * 60, "45m"), (59 * 60 + 59, "59m"),
        (3600, "1h 00m"), (2 * 3600 + 5 * 60, "2h 05m"), (2 * 3600 + 50 * 60, "2h 50m"), (26 * 3600 + 10 * 60, "26h 10m"),
        (-120, "0m"),
    ] as [(TimeInterval, String)])
    func theMainTime(_ seconds: TimeInterval, _ expected: String) {
        #expect(HomeText.elapsed(seconds) == expected)
    }

    @Test func theMainTimeSpoken() {
        #expect(HomeText.spokenElapsed(2 * 3600 + 5 * 60) == "2 hours, 5 minutes")
        #expect(HomeText.spokenElapsed(3600) == "1 hour")
        #expect(HomeText.spokenElapsed(60) == "1 minute")
        #expect(HomeText.spokenElapsed(3600 + 60) == "1 hour, 1 minute")
        #expect(HomeText.spokenElapsed(30) == "0 minutes")
    }

    @Test func theAgeChip() {
        #expect(HomeText.age(days: 0) == "Born today")
        #expect(HomeText.age(days: 1) == "1 day")
        #expect(HomeText.age(days: 12) == "12 days")
    }

    @Test func theGreetingByTime() {
        #expect(PartOfDay.allCases.map(HomeText.greeting) == ["Good morning", "Good afternoon", "Good evening", "Night"])
        #expect(HomeText.greetingSymbol(.night) == "moon")
    }

    @Test func whoIsOnTonight() {
        #expect(HomeText.onTonight("Sam", isMe: false) == "Sam's on tonight")
        #expect(HomeText.onTonight("Alex", isMe: true) == "You're on tonight")
    }

    @Test func chipsShowShapesAndNumbersOnly() {
        let snapshot = EventSnapshot(
            event: Event(id: "f", babyID: "b", kind: .feed, startedAt: Date(), timeZoneID: "Europe/London",
                         loggedBy: "a", createdAt: Date(), modifiedAt: Date()),
            payload: EventPayload(feed: FeedDetails(
                breast: [BreastSegment(side: .left, durationSeconds: 720), BreastSegment(side: .right, durationSeconds: 30),
                         BreastSegment(side: .left)],
                bottles: [Bottle(milk: .formula, ml: 30), Bottle(milk: .expressed)])))
        let chips = HomeText.chips(snapshot)
        #expect(chips.map(\.mark) == [.side(.left), .side(.right), .side(.left), .bottle, .bottle])
        #expect(chips.map(\.text) == ["12m", "<1m", "", "30 ml", ""])
        #expect(chips.map(\.spoken) == ["Left side, 12 minutes", "Right side, less than a minute", "Left side",
                                        "Formula bottle, 30 ml", "Expressed milk bottle"])
    }

    @Test func aFeedFromANewerAppStillShowsAChip() {
        let snapshot = EventSnapshot(
            event: Event(id: "f", babyID: "b", kind: .feed, startedAt: Date(), timeZoneID: "Europe/London",
                         loggedBy: "a", createdAt: Date(), modifiedAt: Date()),
            payload: nil)
        #expect(HomeText.chips(snapshot).map(\.text) == ["Feed"])
    }

    @Test func noWordSoundsLikeAVerdict() {
        let words = PartOfDay.allCases.map(HomeText.greeting)
            + [HomeText.age(days: 3), HomeText.onTonight("Sam", isMe: false), HomeText.onTonight("Sam", isMe: true)]
        for word in words {
            for forbidden in AlertText.forbiddenWords {
                #expect(!word.lowercased().split(separator: " ").contains(Substring(forbidden)), "\(word)")
            }
        }
    }
}
