import FeedingCore
import Foundation
import SwiftUI
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
        #expect(chips.map(\.text) == ["12m", "<1m", "", "30 ml", "Expressed"])
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

/// The hero's colour and middle shape while a feed runs (`05-visual-redesign.md`, "Home, a feed running").
@Suite("A running feed")
struct RunningFeedTests {
    func feed(_ details: FeedDetails?) -> EventSnapshot {
        EventSnapshot(
            event: Event(id: "f", babyID: "b", kind: .feed, startedAt: Date(), timeZoneID: "Europe/London",
                         loggedBy: "a", createdAt: Date(), modifiedAt: Date()),
            payload: details.map { EventPayload(feed: $0) })
    }

    @Test func theSideBeingFedIsInTheMiddle() {
        let running = RunningFeed(feed(FeedDetails(breast: [BreastSegment(side: .left, startedAt: Date(), durationSeconds: 480),
                                                             BreastSegment(side: .right, startedAt: Date())])), bottleOnly: false)
        #expect(!running.isBottle)
        #expect(running.centre == .side(.right))
        #expect(running.bottleKinds == nil)
    }

    @Test func aBottleAddedToABreastFeedKeepsItABreastFeed() {
        let running = RunningFeed(feed(FeedDetails(breast: [BreastSegment(side: .left, startedAt: Date())],
                                                   bottles: [Bottle(milk: .formula)])), bottleOnly: false)
        #expect(!running.isBottle)
        #expect(running.centre == .side(.left))
    }

    @Test func aBottleFeedShowsTheBottleAndItsKind() {
        let running = RunningFeed(feed(FeedDetails(bottles: [Bottle(milk: .formula)])), bottleOnly: false)
        #expect(running.isBottle)
        #expect(running.centre == .bottle)
        #expect(running.bottleKinds == "Formula")
    }

    @Test func aFeedWithNothingYetFollowsThePhonesStyle() {
        #expect(!RunningFeed(feed(FeedDetails()), bottleOnly: false).isBottle)
        #expect(RunningFeed(feed(FeedDetails()), bottleOnly: false).centre == nil)
        #expect(RunningFeed(feed(FeedDetails()), bottleOnly: true).isBottle)
        #expect(RunningFeed(feed(nil), bottleOnly: true).bottleKinds == nil)
    }
}

/// The words on History (`05-visual-redesign.md`, "History").
@Suite("History words")
struct HistoryTextTests {
    let london = TimeZone(identifier: "Europe/London")!
    let today = PlainDate(year: 2026, month: 11, day: 15)!

    @Test func dayHeadings() {
        #expect(HomeText.dayTitle(today, today: today, in: london) == "Today")
        #expect(HomeText.dayTitle(today.adding(days: -1), today: today, in: london) == "Yesterday")
        #expect(HomeText.dayTitle(today.adding(days: -3), today: today, in: london, locale: Locale(identifier: "en_GB"))
                == "Thursday 12 November")
    }

    @Test func aDayHeadingIsTheHouseholdsDate() {
        // Far from London, noon on the day is still that day.
        let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
        #expect(HomeText.dayTitle(today.adding(days: -3), today: today, in: kiritimati, locale: Locale(identifier: "en_GB"))
                == "Thursday 12 November")
    }

    @Test func historyChipsNameTheMilkAndThePumping() {
        let feed = EventSnapshot(
            event: Event(id: "f", babyID: "b", kind: .feed, startedAt: Date(), timeZoneID: "Europe/London",
                         loggedBy: "a", createdAt: Date(), modifiedAt: Date()),
            payload: EventPayload(feed: FeedDetails(bottles: [Bottle(milk: .formula, ml: 30), Bottle(milk: .expressed)])))
        #expect(HomeText.chips(feed, detailed: true).map(\.text) == ["Formula 30 ml", "Expressed"])
        #expect(HomeText.chips(feed).map(\.text) == ["30 ml", "Expressed"])
        let pump = EventSnapshot(
            event: Event(id: "p", babyID: "b", kind: .pump, startedAt: Date(), timeZoneID: "Europe/London",
                         loggedBy: "a", createdAt: Date(), modifiedAt: Date()),
            payload: EventPayload(pump: PumpDetails(side: .both, leftML: 50, rightML: 40)))
        #expect(HomeText.chips(pump, detailed: true).map(\.text) == ["Pumped 90 ml"])
        #expect(HomeText.chips(pump).map(\.text) == ["90 ml"])
    }

    @Test func rowsAreTintedByKind() {
        func row(_ kind: EventKind, _ payload: EventPayload?) -> Color {
            HistoryRow.tint(EventSnapshot(
                event: Event(id: "x", babyID: "b", kind: kind, startedAt: Date(), timeZoneID: "Europe/London",
                             loggedBy: "a", createdAt: Date(), modifiedAt: Date()),
                payload: payload))
        }
        #expect(row(.pump, EventPayload(pump: PumpDetails(side: .left))) == Theme.pumpTint)
        #expect(row(.feed, EventPayload(feed: FeedDetails(breast: [BreastSegment(side: .left)], bottles: [Bottle(milk: .formula)])))
                == Theme.breastTint)
        #expect(row(.feed, EventPayload(feed: FeedDetails(bottles: [Bottle(milk: .formula)]))) == Theme.bottleTint)
        #expect(row(.feed, nil) == Theme.surface)
    }
}

/// The six parent colours ("Your colour", DESIGN.md).
@Suite("Parent colours")
struct ParentColourTests {
    @Test func sixColoursInTheOrderSettingsShows() {
        #expect(ParentColour.allCases.map(\.rawValue) == ["sunflower", "teal", "lavender", "plum", "caramel", "stone"])
        #expect(ParentColour.allCases.map(\.title) == ["Sunflower", "Teal", "Lavender", "Plum", "Caramel", "Stone"])
    }

    @Test func savedNamesReadBack() {
        for colour in ParentColour.allCases {
            #expect(ParentColour(named: colour.rawValue) == colour)
        }
        // What the first builds saved for sunflower.
        #expect(ParentColour(named: "amber") == .sunflower)
        // A colour from a newer version: the caller picks a default.
        #expect(ParentColour(named: "aubergine") == nil)
    }
}
