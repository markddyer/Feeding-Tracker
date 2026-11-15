import FeedingCore
import Foundation
import Testing
@testable import FeedingDev

/// The details panel after Finish: each choice goes once it is made, so a second tap can't log
/// the same thing twice.
@Suite("Feed details choices")
struct DetailChoicesTests {
    @Test func aBottleOnlyFeedWithItsBottleAsksOnlyTheAmount() {
        let choices = DetailChoices(FeedDetails(bottles: [Bottle(milk: .formula)]), bottleOnly: true)
        #expect(choices.sides.isEmpty)
        #expect(choices.milks.isEmpty)
        #expect(choices.unmeasured.count == 1)
        #expect(!choices.isComplete)
    }

    @Test func aBottleOnlyFeedIsCompleteOnceTheAmountIsIn() {
        let choices = DetailChoices(FeedDetails(bottles: [Bottle(milk: .formula, ml: 90)]), bottleOnly: true)
        #expect(choices.isComplete)
    }

    @Test func aBottleOnlyFeedWithNoBottleAsksWhichBottleOnce() {
        #expect(DetailChoices(FeedDetails(), bottleOnly: true).milks == [.expressed, .formula])
        let picked = DetailChoices(FeedDetails(bottles: [Bottle(milk: .expressed)]), bottleOnly: true)
        #expect(picked.milks.isEmpty)
        #expect(picked.unmeasured.count == 1)
    }

    @Test func aSideOrBottleAlreadyLoggedIsNotOfferedAgain() {
        let details = FeedDetails(breast: [BreastSegment(side: .left)], bottles: [Bottle(milk: .formula, ml: 30)])
        let choices = DetailChoices(details, bottleOnly: false)
        #expect(choices.sides == [.right])
        #expect(choices.milks == [.expressed])
        #expect(choices.unmeasured.isEmpty)
        #expect(!choices.isComplete)
    }

    @Test func breastAndBottleOffersEverythingOnAnEmptyFeed() {
        let choices = DetailChoices(FeedDetails(), bottleOnly: false)
        #expect(choices.sides == [.left, .right])
        #expect(choices.milks == [.expressed, .formula])
        #expect(!choices.isComplete)
    }
}
