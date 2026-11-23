import Foundation
import Testing
import FeedingCore
@testable import FeedingInsights

// AI13's 30 made-up households, checked with no AI (Linux and macOS, every CI run): each makes a
// card of its kind at its time, what is sent holds none of its names, notes or medicines, and with
// one parent's yes nothing would be sent. The real model runs on them in the simulator
// (`ModelTests/ModelTests.swift`, the FeedingDevModelTests scheme).
@Suite("Model test households (AI13)")
struct ModelTestHouseholdsTests {
    @Test func thereAreThirtyTwentyMorningsAndTenWeeks() {
        let recipes = ModelTestHouseholds.recipes
        #expect(recipes.count == 30)
        #expect(recipes.filter { $0.kind == .morning }.count == 20)
        #expect(Set(recipes.map(\.name)).count == 30)
    }

    @Test func eachMakesACardWithNothingPrivateInIt() throws {
        var passages = 0
        for household in ModelTestHouseholds.all() {
            let plan = InsightCards.plan(household.kind, data: household.data, babyID: household.babyID,
                                         me: household.parentA, participants: [household.parentA, household.parentB],
                                         tries: LocalCardTries(), now: household.now)
            guard case .make(let job, _) = plan else {
                Issue.record("\(household.name): no card to make (\(plan))")
                continue
            }
            #expect(job.request.period.kind == household.kind, "\(household.name)")
            let prompt = InsightCards.prompt(job.request, timeZone: household.data.householdSettings.timeZone)
            for secret in household.secrets {
                #expect(prompt.range(of: "\\b\(NSRegularExpression.escapedPattern(for: secret))\\b",
                                     options: .regularExpression) == nil, "\(household.name): \(secret) is sent")
            }
            // A card has something to choose from, and NHS passages when Parent A ticked them.
            #expect(!job.request.days.isEmpty, "\(household.name)")
            let recipe = ModelTestHouseholds.recipes.first { $0.name == household.name }
            if recipe?.ticked == false { #expect(job.request.passages.isEmpty, "\(household.name)") }
            passages += job.request.passages.count
        }
        // Most households are offered NHS passages, so the model's summary choice is tested too.
        #expect(passages >= 30, "passages offered across the 30: \(passages)")
    }

    @Test func withOneYesNothingIsSent() {
        for household in ModelTestHouseholds.all(bothYes: false) {
            let plan = InsightCards.plan(household.kind, data: household.data, babyID: household.babyID, me: household.parentA,
                                         participants: [household.parentA, household.parentB], tries: LocalCardTries(),
                                         now: household.now)
            guard case .closed(.waitingForYes, _) = plan else {
                Issue.record("\(household.name): \(plan)")
                continue
            }
        }
    }

    @Test func theSameSeedMakesTheSameHousehold() {
        let one = ModelTestHouseholds.all().map { InsightCards.preview($0.kind, data: $0.data, babyID: $0.babyID, now: $0.now) }
        let two = ModelTestHouseholds.all().map { InsightCards.preview($0.kind, data: $0.data, babyID: $0.babyID, now: $0.now) }
        #expect(one == two)
    }

    /// The households cover what the plan asks: both cards, breast, bottle and pumping, the
    /// clock changes both ways, a half-hour time zone, gaps, copies on both phones, no birth date
    /// and no ticks.
    @Test func theyCoverTheHardCases() {
        let recipes = ModelTestHouseholds.recipes
        #expect(recipes.contains { $0.zone == "Asia/Kolkata" })
        #expect(recipes.contains { $0.now.hasPrefix("2027-10-31") })
        #expect(recipes.contains { $0.now.hasPrefix("2027-03-28") })
        #expect(recipes.contains { $0.duplicates })
        #expect(recipes.contains { !$0.gapDays.isEmpty })
        #expect(recipes.contains { $0.ageWeeks == nil })
        #expect(recipes.contains { !$0.ticked })
        #expect(recipes.contains { $0.pump })
        #expect(recipes.contains { $0.running })
    }
}
