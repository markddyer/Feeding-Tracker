import ClaudeForFoundationModels
import FeedingCore
import FeedingInsights
import Foundation
import FoundationModels
import Testing
@testable import FeedingDev

// The engine (AI insights step 2, task AI8): the card's form becomes Apple's run-time form, an
// answer becomes a stored card, a turned-down answer is tried once more, and each failure lands on
// the short list. A fixed answer stands in for Claude: no network, no key.

/// A fixed answer, or a fixed error, counting its calls.
final class FixedAnswerer: CardAnswerer, @unchecked Sendable {
    let reply: Result<String, Error>
    private(set) var calls = 0

    init(_ reply: Result<String, Error>) { self.reply = reply }

    func answer(_ prompt: String, schema: GenerationSchema) async throws -> String {
        calls += 1
        return try reply.get()
    }
}

@MainActor
@Suite("Insight engine")
struct InsightEngineTests {
    let zone = TimeZone(identifier: "Europe/London")!
    let baby = "baby-1"

    func at(_ day: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    /// Two weeks of feeds and nights of sleep, and both parents' yes.
    func household() -> HouseholdData {
        var data = HouseholdData()
        for day in 9...21 {
            for hour in stride(from: 1, to: 24, by: 3) {
                data.add(kind: .feed, babyID: baby, startedAt: at(day, hour), endedAt: at(day, hour).addingTimeInterval(1200),
                         payload: EventPayload(feed: FeedDetails(bottles: [Bottle(milk: .formula, ml: 90)])),
                         by: "parent-a", timeZoneID: "Europe/London", now: at(day, hour))
            }
            data.add(kind: .sleep, babyID: baby, startedAt: at(day, 22), endedAt: at(day, 22).addingTimeInterval(7 * 3600),
                     payload: EventPayload(), by: "parent-a", timeZoneID: "Europe/London", now: at(day, 22))
        }
        data.setInsightYes(true, member: "parent-a", now: at(1, 12))
        data.setInsightYes(true, member: "parent-b", now: at(1, 12))
        return data
    }

    func job(_ data: HouseholdData) -> CardJob? {
        guard case .make(let job, _) = InsightCards.plan(.morning, data: data, babyID: baby, me: "parent-a",
                                                         participants: ["parent-a", "parent-b"], tries: LocalCardTries(),
                                                         now: at(22, 10)) else { return nil }
        return job
    }

    @Test func theFormBecomesApplesForm() throws {
        let data = household()
        let job = try #require(job(data))
        _ = try InsightEngine.schema(job.form)
    }

    @Test func aGoodAnswerMakesACard() async throws {
        let data = household()
        let job = try #require(job(data))
        let answerer = FixedAnswerer(.success(#"{"facts":[{"scope":"day:2026-11-21","measure":"feeds"}],"patterns":[],"passages":[]}"#))
        var calls = 0
        let result = await InsightEngine.make(job, data: { data }, babyID: baby, answerer: answerer, now: { self.at(22, 10) },
                                              onCall: { calls += 1 })
        guard case .made(let card) = result else { Issue.record("\(result)"); return }
        #expect(calls == 1)
        #expect(InsightCards.show(card, data: data, babyID: baby, now: at(22, 10))?.lines == ["8 feeds logged yesterday."])
    }

    @Test func twoUnreadableAnswersFallBackToFacts() async throws {
        let data = household()
        let job = try #require(job(data))
        let answerer = FixedAnswerer(.success("{}"))
        var calls = 0
        let result = await InsightEngine.make(job, data: { data }, babyID: baby, answerer: answerer, onCall: { calls += 1 })
        #expect(result == .failed(.turnedDown))
        #expect(calls == 2)
    }

    @Test func aTurnedDownAnswerIsTriedOnceMore() async throws {
        let data = household()
        let job = try #require(job(data))
        // A day the card doesn't cover is turned down by the checker, so the AI is asked again.
        let answerer = FixedAnswerer(.success(#"{"facts":[{"scope":"day:2026-11-10","measure":"feeds"}],"patterns":[],"passages":[]}"#))
        let result = await InsightEngine.make(job, data: { data }, babyID: baby, answerer: answerer, onCall: {})
        #expect(answerer.calls == 2)
        if case .made = result { Issue.record("a day outside the card was accepted") }
    }

    /// AI13 D3 A: a pick that fails twice is left out on the last try; the rest of the card stays.
    @Test func aBadPickIsLeftOutOnTheLastTry() async throws {
        let data = household()
        let job = try #require(job(data))
        // Steady feeds read as a fall: turned down at the first try, left out at the second.
        let answerer = FixedAnswerer(.success(#"""
            {"facts":[{"scope":"day:2026-11-21","measure":"feeds"}],
             "patterns":[{"shape":"lower","measure":"feeds","nights":false,"recentFirst":"2026-11-19","recentLast":"2026-11-21",
                          "earlierFirst":"2026-11-12","earlierLast":"2026-11-18"}],"passages":[]}
            """#))
        let result = await InsightEngine.make(job, data: { data }, babyID: baby, answerer: answerer, now: { self.at(22, 10) },
                                              onCall: {})
        guard case .made(let card) = result else { Issue.record("\(result)"); return }
        #expect(answerer.calls == 2)
        #expect(card.choices.patterns.isEmpty)
        #expect(card.choices.facts.count == 1)
    }

    @Test func failuresLandOnTheShortList() async throws {
        let data = household()
        let job = try #require(job(data))
        let offline = await InsightEngine.make(job, data: { data }, babyID: baby,
                                               answerer: FixedAnswerer(.failure(URLError(.notConnectedToInternet))), onCall: {})
        #expect(offline == .failed(.noSignal))
        let attest = await InsightEngine.make(job, data: { data }, babyID: baby,
                                              answerer: FixedAnswerer(.failure(ClaudeError.attestationFailed)), onCall: {})
        #expect(attest == .failed(.couldNotConnect))
        let other = await InsightEngine.make(job, data: { data }, babyID: baby,
                                             answerer: FixedAnswerer(.failure(CocoaError(.featureUnsupported))), onCall: {})
        #expect(other == .failed(.unavailable))
    }
}
