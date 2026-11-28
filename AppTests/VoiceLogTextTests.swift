import AppIntents
import FeedingCore
import Foundation
import Testing
@testable import FeedingDev

/// Hands-free logging with Siri (`docs/planning/15-hands-free-siri.md`): what Siri says, and that
/// every logging action runs on a locked phone with no Touch ID (V4). Siri itself can't be driven
/// by a test: the phrases and the voice are checked on the Duo.
@Suite("Logging by voice: words")
@MainActor
struct VoiceLogTextTests {
    let start = Date(timeIntervalSince1970: 1_794_798_000) // 16 Nov 2026, 03:00 in London
    let me: MemberID = "a"
    let names: [MemberID: String] = ["a": "Alex", "b": "Sam"]

    func feed(by member: MemberID, minutes: Double, _ details: FeedDetails) -> EventSnapshot {
        EventSnapshot(event: Event(id: "f", babyID: "baby", kind: .feed, startedAt: start,
                                   endedAt: start.addingTimeInterval(minutes * 60), timeZoneID: "Europe/London",
                                   loggedBy: member, createdAt: start, modifiedAt: start),
                      payload: EventPayload(feed: details))
    }

    @Test func finishSaysTheTimeTheLengthAndTheDetails() {
        let end = GlanceText.clock(start.addingTimeInterval(25 * 60), timeZoneID: "Europe/London")
        let bottle = FeedDetails(breast: [], bottles: [Bottle(id: "b", milk: .formula, ml: 90)])
        #expect(SiriText.finished(feed(by: "a", minutes: 25, bottle), me: me, names: names, timeZoneID: "Europe/London", now: start)
                == "Feed finished at \(end), after 25 minutes. 90 ml of formula.")
        let sides = FeedDetails(breast: [BreastSegment(side: .left), BreastSegment(side: .right)], bottles: [])
        #expect(SiriText.finished(feed(by: "b", minutes: 25, sides), me: me, names: names, timeZoneID: "Europe/London", now: start)
                == "Sam's feed finished at \(end), after 25 minutes. Left, then right.")
        #expect(SiriText.finished(feed(by: "a", minutes: 25, FeedDetails()), me: me, names: names, timeZoneID: "Europe/London",
                                  now: start) == "Feed finished at \(end), after 25 minutes.")
    }

    @Test func detailsInWords() {
        #expect(SiriText.detailsSaid(FeedDetails(breast: [BreastSegment(side: .right)], bottles: [])) == "Right side.")
        #expect(SiriText.detailsSaid(FeedDetails(breast: [], bottles: [Bottle(id: "b", milk: .expressed, ml: nil)]))
                == "Expressed milk, no amount.")
        #expect(SiriText.detailsSaid(FeedDetails()) == nil)
    }

    @Test func questionsNameTheMilkAndTheBaby() {
        #expect(SiriText.howMuch(.formula, baby: "Sam") == "How much formula did Sam drink, in ml?")
        #expect(SiriText.isThatRight(90, .expressed) == "90 ml of expressed milk. Is that right?")
    }

    @Test func aNappyWithItsDetails() {
        let three = GlanceText.clock(start, timeZoneID: "Europe/London")
        #expect(SiriText.nappy(at: start, wee: false, poo: true, colour: .yellow, consistency: .loose, timeZoneID: "Europe/London")
                == "Poo logged at \(three), yellow, loose.")
        #expect(SiriText.nappy(at: start, wee: true, poo: false, colour: nil, consistency: nil, timeZoneID: "Europe/London")
                == "Wee logged at \(three).")
    }

    /// The poo lists Siri hears are the app's own (`PooColour.known`, `PooConsistency.known`).
    @Test func theSpokenListsAreTheAppsLists() {
        let colours = PooColourChoice.allCases.compactMap(\.colour)
        #expect(Set(colours) == Set(PooColour.known))
        let textures = PooTextureChoice.allCases.compactMap(\.consistency)
        #expect(Set(textures) == Set(PooConsistency.known))
        #expect(SidesChoice.allCases.compactMap(\.sides) == VoiceSides.allCases)
    }

    @Test func noWordSoundsLikeAVerdict() {
        let tz = "Europe/London"
        let words = [SiriText.howMuch(.formula, baby: "Sam"), SiriText.isThatRight(90, .formula), SiriText.whichMilk,
                     SiriText.whichSides, SiriText.weeOrPoo, SiriText.whatColour, SiriText.whatTexture, SiriText.whichMedicine,
                     SiriText.amountNotSaved, SiriText.bottleAdded(ml: 60, milk: .formula, feedStart: start, timeZoneID: tz),
                     SiriText.bottleAdded(ml: nil, milk: .expressed, feedStart: start, timeZoneID: tz),
                     SiriText.runningHasBottle, SiriText.runningNotMine,
                     SiriText.alreadyHas(.formula, feedStart: start, timeZoneID: tz), SiriText.noFeed,
                     SiriText.medicine("Vitamin D", at: start, timeZoneID: tz), SiriText.onItsWay, SiriText.phoneRefused, SiriText.watchNotSetUp,
                     SiriText.running(by: "Sam", since: start, timeZoneID: tz),
                     SiriText.finished(feed(by: "a", minutes: 25, FeedDetails()), me: me, names: names, timeZoneID: tz, now: start)]
        for word in words {
            let plain = word.lowercased().filter { $0.isLetter || $0 == " " || $0 == "'" }
            for forbidden in AlertText.forbiddenWords + ["enough", "too"] {
                #expect(!plain.split(separator: " ").contains(Substring(forbidden)), "\(word)")
            }
        }
    }

    /// V4: logging by voice works on a locked phone, in the background, in the app's own process.
    @Test func everyLoggingActionRunsOnALockedPhone() {
        func check<T: AppIntent>(_ type: T.Type) {
            #expect(T.authenticationPolicy == .alwaysAllowed, "\(T.self)")
            #expect(T.supportedModes == .background, "\(T.self)")
            #expect(T.allowedExecutionTargets == [.main], "\(T.self)")
        }
        check(StartFeedIntent.self)
        check(FinishFeedIntent.self)
        check(AddBottleIntent.self)
        check(FellAsleepIntent.self)
        check(WokeUpIntent.self)
        check(LogNappyIntent.self)
        check(LogMedicineIntent.self)
    }

    /// Apple allows 10 App Shortcuts at most.
    @Test func atMostTenPhrases() {
        #expect(FeedingShortcuts.appShortcuts.count <= 10)
    }
}
