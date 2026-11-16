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

/// Asking the other parent to take a night (the user's choice of 15 Nov 2026).
@Suite("Asking for a night: words")
struct NightAskTextTests {
    let ask = NightAsk(night: PlainDate(year: 2026, month: 11, day: 15)!, askedBy: "a", askedAt: Date(timeIntervalSince1970: 1_794_769_000))

    @Test func theCardAndTheButton() {
        #expect(HomeText.askedOfMe(by: "Alex") == "Alex asks you to take tonight")
        #expect(HomeText.askButton("Sam") == "Ask Sam to take it")
        // No rota yet: no "on tonight" line before the button, so it says which night.
        #expect(HomeText.askButton("Sam", nobodyOn: true) == "Ask Sam to take tonight")
    }

    /// A request, not a hand-off: the asker's line says nothing has changed yet.
    @Test func theAskerKnowsNothingChangedYet() {
        #expect(HomeText.askWaiting("Sam") == "You asked Sam to take tonight. You stay on until Sam says yes.")
        #expect(HomeText.askWaiting("Sam", nobodyOn: true) == "You asked Sam to take tonight. Both phones alert until Sam says yes.")
        #expect(HomeText.askDeclined("Sam") == "Sam said not tonight.")
    }

    @Test func theNotifications() {
        #expect(HomeText.askNotification(.asked(ask), name: "Alex").body == "Alex asks you to take tonight.")
        #expect(HomeText.askNotification(.taken(ask, by: "b"), name: "Sam").body == "Sam is taking tonight.")
        #expect(HomeText.askNotification(.declined(ask, by: "b"), name: "Sam").body == "Sam said not tonight. You're still on tonight.")
        #expect(HomeText.askNotification(.declined(ask, by: "b"), name: "Sam", nobodyOn: true).body
                == "Sam said not tonight. Both phones alert tonight.")
    }

    /// A tap on any notification about an ask opens Home, where the card is; a tap on an alert
    /// about feeds leaves the app where it was.
    @Test func aTapOnAnAskNotificationOpensHome() {
        let news: [NightAskNews] = [.asked(ask), .taken(ask, by: "b"), .declined(ask, by: "b")]
        for item in news {
            #expect(NotificationTaps.opensHome(item.id))
        }
        #expect(!NotificationTaps.opensHome("windowCloses-baby-1"))
    }

    @Test func noWordSoundsLikeAVerdict() {
        let news: [NightAskNews] = [.asked(ask), .taken(ask, by: "b"), .declined(ask, by: "b")]
        let words = [HomeText.askedOfMe(by: "Alex"), HomeText.askButton("Sam"), HomeText.askButton("Sam", nobodyOn: true),
                     HomeText.askWaiting("Sam"), HomeText.askWaiting("Sam", nobodyOn: true),
                     HomeText.askDeclined("Sam"), "I'll take it", "Not tonight",
                     HomeText.bothPhonesTonight, HomeText.bothPhonesButton]
            + news.flatMap { item in
                [false, true].flatMap { nobodyOn in
                    let text = HomeText.askNotification(item, name: "Sam", nobodyOn: nobodyOn)
                    return [text.title, text.body]
                }
            }
        for word in words {
            let plain = word.lowercased().filter { $0.isLetter || $0 == " " || $0 == "'" }
            for forbidden in AlertText.forbiddenWords {
                #expect(!plain.split(separator: " ").contains(Substring(forbidden)), "\(word)")
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

/// When the home screen leaves out the tiles the Duo's second column shows. Widths are the ones
/// measured on a real Duo (`~/.claude/reference/iphone-duo.md`).
@Suite("The Duo's second column")
struct SecondColumnTests {
    @Test(arguments: [
        (382.0, 382.0, false),  // closed
        (385, 385, false),      // Split View, one of two
        (669, 669, false),      // laptop pose
        (433.5, 867, true),     // open flat or book pose: two columns
        (0, 867, false),        // not measured yet
        (433.5, 0, false),
    ] as [(CGFloat, CGFloat, Bool)])
    func itShowsOnlyWhenTheHomeColumnIsClearlyNarrower(_ home: CGFloat, _ whole: CGFloat, _ showing: Bool) {
        #expect(DayColumn.isShowing(homeWidth: home, arrangementWidth: whole) == showing)
    }
}

/// Where each feed's block sits on the 24-hour strip (option C, chosen 15 Nov 2026).
@Suite("The 24-hour strip")
struct DayChartPlaceTests {
    let now = Date(timeIntervalSince1970: 1_794_700_000)

    func place(minutesAgo: Double, lasting minutes: Double) -> (x: CGFloat, width: CGFloat) {
        DayChart.place(start: now.addingTimeInterval(-minutesAgo * 60), duration: minutes * 60, now: now, hours: 24, width: 300)
    }

    @Test func aFeedStartsAtItsTimeAndIsAsWideAsItLasted() {
        let block = place(minutesAgo: 720, lasting: 24)
        #expect(abs(block.x - 150) < 0.001)
        #expect(abs(block.width - 5) < 0.001)
    }

    @Test func aShortFeedIsStillThreePointsWide() {
        #expect(place(minutesAgo: 600, lasting: 5).width == 3)
        #expect(place(minutesAgo: 600, lasting: -5).width == 3)
    }

    @Test func feedsCloseTogetherSitSideBySide() {
        // 17:40 for 15 minutes, then 18:20: a 25-minute gap shows as a gap.
        let first = place(minutesAgo: 200, lasting: 15)
        let second = place(minutesAgo: 160, lasting: 10)
        #expect(first.x + first.width < second.x)
    }

    @Test func blocksStayInsideTheStrip() {
        // A feed running now, and one whose end is after now (a phone clock set back).
        let running = place(minutesAgo: 1, lasting: 1)
        #expect(running.x + running.width <= 300.0001)
        let pastNow = place(minutesAgo: 5, lasting: 30)
        #expect(pastNow.x + pastNow.width <= 300.0001)
        #expect(place(minutesAgo: 1440, lasting: 20).x == 0)
    }
}

/// The amount wheel (the user's choice of 16 Nov 2026, in place of the 30, 60, 90 and 120 ml
/// buttons): every 5 ml from 5 to 300 ml.
@Suite("The amount wheel")
struct AmountWheelTests {
    @Test func everyFiveMillilitresUpTo300() {
        let amounts = AmountWheel.amounts(including: 60, allowsNotSet: false)
        #expect(amounts.first == 5)
        #expect(amounts.last == 300)
        #expect(amounts.count == 60)
        #expect(amounts.contains(45))
    }

    @Test func theFormHasNotSetFirst() {
        #expect(AmountWheel.amounts(including: 0, allowsNotSet: true).prefix(2) == [0, 5])
    }

    /// An amount between the steps (logged another way) still shows on the wheel.
    @Test func anAmountBetweenStepsIsKept() {
        let amounts = AmountWheel.amounts(including: 47, allowsNotSet: false)
        #expect(amounts.contains(47))
        #expect(amounts == amounts.sorted())
    }

    @Test func itStartsAtTheLastAmount() {
        #expect(AmountWheel.start(75) == 75)
        #expect(AmountWheel.start(47) == 45)
        #expect(AmountWheel.start(2) == 5)
        #expect(AmountWheel.start(500) == 300)
        #expect(AmountWheel.start(nil) == 60)
    }
}
