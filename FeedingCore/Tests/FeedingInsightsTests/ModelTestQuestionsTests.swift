import Foundation
import Testing
@testable import FeedingCore
@testable import FeedingInsights

// Ask's model-test questions checked with no AI (task AI21): the mix, no secret in a question,
// every route, and that an answer of the wrong kind fails its case (D12 A).

@Suite("Ask's model-test questions (AI21)")
struct ModelTestQuestionsTests {
    let households = ModelTestHouseholds.all()

    @Test func sixtyQuestionsOfEveryKind() {
        let questions = ModelTestQuestions.all
        #expect(questions.count == 60)
        #expect(Set(questions.map(\.name)).count == 60)
        for kind in ModelTestQuestion.Kind.allCases {
            #expect(questions.filter { $0.kind == kind }.count >= 6, "\(kind)")
        }
        #expect(questions.filter { $0.expect == .helpNow }.count == 3)
        #expect(questions.allSatisfy { $0.household < households.count })
    }

    @Test func noQuestionHoldsAHouseholdsSecret() {
        for question in ModelTestQuestions.all {
            let words = [question.text, question.earlier ?? ""].joined(separator: " ")
            for secret in households[question.household].secrets {
                #expect(words.range(of: "\\b\(NSRegularExpression.escapedPattern(for: secret))\\b",
                                    options: .regularExpression) == nil, "\(question.name) holds \(secret)")
            }
        }
    }

    /// Planted danger signs stay on the phone; every other question would go to the AI, with no
    /// secret in what is sent.
    @Test func everyQuestionRoutesAsExpected() {
        for question in ModelTestQuestions.all {
            let household = households[question.household]
            let route = InsightQuestions.route(question.text, data: household.data, babyID: household.babyID,
                                               me: household.parentA, participants: [household.parentA, household.parentB],
                                               kept: ModelTestQuestions.kept(question, now: household.now), now: household.now)
            switch (question.expect, route) {
            case (.helpNow, .helpNow):
                break
            case (.helpNow, _):
                Issue.record("\(question.name): a planted danger sign would reach the AI: \(route)")
            case (_, .ask(let job)):
                let sent = InsightQuestions.prompt(job.request, timeZone: household.data.householdSettings.timeZone)
                for secret in household.secrets where sent.range(of: "\\b\(NSRegularExpression.escapedPattern(for: secret))\\b",
                                                                options: .regularExpression) != nil {
                    Issue.record("\(question.name): the request holds \(secret)")
                }
                if let earlier = question.earlier { #expect(job.request.earlierQuestion == earlier, "\(question.name)") }
            default:
                Issue.record("\(question.name): stayed on the phone (\(route)); it should reach the AI")
            }
        }
    }

    /// D12 A: a real fact of the wrong kind fails its case; the right kind passes.
    @Test func anAnswerOfTheWrongKindFails() throws {
        let question = try #require(ModelTestQuestions.all.first { $0.text == "How many feeds yesterday?" })
        let household = households[question.household]
        let facts = household.data.insightFacts(babyID: household.babyID, now: household.now)
        let yesterday = try #require(facts.yesterday?.date)
        let right = QuestionAnswer(topic: .feeding, facts: [FactRef(.day(yesterday), .feeds)])
        let wrong = QuestionAnswer(topic: .nappies, facts: [FactRef(.day(yesterday), .wees)])
        let wrongDay = QuestionAnswer(topic: .feeding, facts: [FactRef(.day(yesterday.adding(days: -1)), .feeds)])
        #expect(ModelTestQuestions.matches(question, answer: right, household: household))
        #expect(!ModelTestQuestions.matches(question, answer: wrong, household: household))
        #expect(!ModelTestQuestions.matches(question, answer: wrongDay, household: household))
        #expect(!ModelTestQuestions.matches(question, answer: QuestionAnswer(topic: .feeding, cannotAnswer: true),
                                            household: household), "the log has yesterday's feeds")
        // Off-topic: "can't answer" is right, a log fact is not.
        let offTopic = try #require(ModelTestQuestions.all.first { $0.kind == .offTopic })
        #expect(ModelTestQuestions.matches(offTopic, answer: QuestionAnswer(topic: .other, cannotAnswer: true),
                                           household: households[offTopic.household]))
        #expect(!ModelTestQuestions.matches(offTopic, answer: right, household: households[offTopic.household]))
    }
}
