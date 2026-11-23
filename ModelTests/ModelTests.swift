import ClaudeForFoundationModels
import FeedingCore
import FeedingInsights
import Foundation
import FoundationModels
import Testing
@testable import FeedingDev

// AI13 (`docs/planning/12-ai-insights-gauntlet.md`, step 2 D7 C): the model tests. The 30 made-up
// households (`ModelTestHouseholds`) are each made into a card by the real model, Claude Sonnet
// 5.5, with the simulator's development key, through the app's own `InsightEngine.make` (one call,
// and one more with the checker's reasons). The run passes only if at least 27 of 30 cards pass
// the checker, no request holds a name, note or medicine, nothing is sent before both yeses, and
// no call fails. Run it before each TestFlight upload and after any change of model or package:
//
//   xcodebuild test -project Feeding.xcodeproj -scheme FeedingDevModelTests \
//     -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
//
// It costs money (the report gives the cost). Settings, as `TEST_RUNNER_` variables:
// MODEL_TEST_EFFORTS ("low,medium" compares the two; the app's effort by default),
// MODEL_TEST_MAX_DOLLARS (stops making calls past it; 4 by default), MODEL_TEST_REPORT (a path for
// the report; it is printed as MODELTEST lines too), MODEL_TEST_ONLY (some households by name: a
// check of the run, never a pass).
//
// gstack-shortcut(dec-5b7b346c): 30 households can't tell a real change from chance; upgrade to 100
// households, gate at 90, when a run fails, when the model or package changes, or when a parent
// reports a wrong card.

/// The real answerer, counting calls, tokens and the checker's reasons for a second try.
final class MeasuredAnswerer: CardAnswerer, @unchecked Sendable {
    let inner: ClaudeAnswerer
    private(set) var calls = 0
    private(set) var input = 0
    private(set) var cached = 0
    private(set) var output = 0
    private(set) var reasoning = 0
    private(set) var retryReasons: [String] = []

    init(_ inner: ClaudeAnswerer) { self.inner = inner }

    func answer(_ prompt: String, schema: GenerationSchema) async throws -> String {
        calls += 1
        if let note = prompt.range(of: "\n\nYOUR LAST ") {
            retryReasons.append(String(prompt[note.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let (text, usage) = try await inner.answerWithUsage(prompt, schema: schema)
        input += usage.input.totalTokenCount
        cached += usage.input.cachedTokenCount
        output += usage.output.totalTokenCount
        reasoning += usage.output.reasoningTokenCount
        return text
    }
}

/// One household's card at one effort.
struct ModelTestOutcome: Sendable {
    let name: String
    let kind: CardKind
    let effort: String
    /// "passed", "turned down" or "error: …".
    let result: String
    let calls: Int
    let input: Int
    let cached: Int
    let output: Int
    let reasoning: Int
    let seconds: Double
    let card: String
    let retryReasons: [String]

    var passed: Bool { result == "passed" }

    /// Claude Sonnet 5.5's price per million tokens: $2 in, $0.10 for cached input, $10 out
    /// (Anthropic's price list, cached 3 Nov 2026). Cache writes are counted as input.
    var dollars: Double {
        Double(input - cached) * 2 / 1_000_000 + Double(cached) * 0.1 / 1_000_000 + Double(output) * 10 / 1_000_000
    }
}

@MainActor
@Suite("Model tests (AI13)", .serialized)
struct ModelTests {
    let env = ProcessInfo.processInfo.environment

    @Test(.timeLimit(.minutes(60)))
    func thirtyHouseholdsMakeCards() async throws {
        let info = Bundle.main.infoDictionary
        let efforts = (env["MODEL_TEST_EFFORTS"] ?? ClaudeAnswerer.effort.rawValue)
            .split(separator: ",").compactMap { ClaudeModel.Effort(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
        try #require(!efforts.isEmpty, "MODEL_TEST_EFFORTS names no effort")
        try #require(ClaudeAnswerer.fromInfo(info) != nil,
                     "No development key: put CLAUDE_DEV_API_KEY in Config/Local.xcconfig and build again.")
        let budget = Double(env["MODEL_TEST_MAX_DOLLARS"] ?? "") ?? 4
        let households = ModelTestHouseholds.all()
        let oneYes = ModelTestHouseholds.all(bothYes: false)
        try #require(households.count == 30 && oneYes.count == 30)

        // Before any call: each request is free of names, notes and medicines, and with one
        // parent's yes nothing would be sent.
        var jobs: [(ModelTestHousehold, CardJob)] = []
        for (household, waiting) in zip(households, oneYes) {
            guard case .make(let job, _) = InsightCards.plan(household.kind, data: household.data, babyID: household.babyID,
                                                              me: household.parentA,
                                                              participants: [household.parentA, household.parentB],
                                                              tries: LocalCardTries(), now: household.now) else {
                Issue.record("\(household.name): no card to make")
                continue
            }
            let prompt = InsightCards.prompt(job.request, timeZone: household.data.householdSettings.timeZone)
            let leaks = household.secrets.filter {
                prompt.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0))\\b", options: .regularExpression) != nil
            }
            if !leaks.isEmpty {
                Issue.record("\(household.name): the request holds \(leaks); nothing sent")
                continue
            }
            guard case .closed(.waitingForYes, _) = InsightCards.plan(household.kind, data: waiting.data, babyID: household.babyID,
                                                                      me: household.parentA,
                                                                      participants: [household.parentA, household.parentB],
                                                                      tries: LocalCardTries(), now: household.now) else {
                Issue.record("\(household.name): a card could be made with one yes; nothing sent")
                continue
            }
            jobs.append((household, job))
        }
        try #require(jobs.count == 30, "every household checked before any call")

        // MODEL_TEST_ONLY=m01-mixed-steady,w01-mixed-steady runs just those, as a check of the run
        // itself; it is then not a gate.
        let only = env["MODEL_TEST_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let checked = jobs.filter { only?.contains($0.0.name) ?? true }
        var outcomes: [ModelTestOutcome] = []
        for effort in efforts {
            guard let answerer = ClaudeAnswerer.fromInfo(info, effort: effort) else { continue }
            // Five at a time, stopping once the run has cost `budget` dollars.
            for batch in stride(from: 0, to: checked.count, by: 5) {
                let spent = outcomes.reduce(0) { $0 + $1.dollars }
                if spent > budget {
                    Issue.record("Stopped at $\(String(format: "%.2f", spent)), past MODEL_TEST_MAX_DOLLARS ($\(budget))")
                    break
                }
                let results = await withTaskGroup(of: ModelTestOutcome.self) { group in
                    for index in batch..<min(batch + 5, checked.count) {
                        let (household, job) = checked[index]
                        let name = effort.rawValue
                        group.addTask {
                            await Self.run(household, job, answerer: answerer, effort: name)
                        }
                    }
                    var done: [ModelTestOutcome] = []
                    for await outcome in group { done.append(outcome) }
                    return done
                }
                outcomes += results.sorted { $0.name < $1.name }
            }
        }

        let report = Self.report(outcomes, efforts: efforts.map(\.rawValue))
        for line in report.split(separator: "\n", omittingEmptySubsequences: false) { print("MODELTEST \(line)") }
        let path = env["MODEL_TEST_REPORT"] ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("model-test-report.md")
        try? report.write(toFile: path, atomically: true, encoding: .utf8)

        // The gate (step 2 D7 C), for each effort run.
        if only != nil {
            Issue.record("MODEL_TEST_ONLY was set: a check of the run, not the gate")
            return
        }
        for effort in efforts.map(\.rawValue) {
            let run = outcomes.filter { $0.effort == effort }
            let errors = run.filter { $0.result.hasPrefix("error") }
            #expect(run.count == 30, "\(effort): \(run.count) of 30 households run")
            #expect(errors.isEmpty, "\(effort): \(errors.map { "\($0.name) \($0.result)" })")
            #expect(run.filter(\.passed).count >= 27, "\(effort): \(run.filter(\.passed).count) of 30 passed; 27 needed")
        }
    }

    /// One household's card, through the app's own engine.
    nonisolated static func run(_ household: ModelTestHousehold, _ job: CardJob, answerer: ClaudeAnswerer,
                    effort: String) async -> ModelTestOutcome {
        let measured = MeasuredAnswerer(answerer)
        let started = Date()
        let result = await InsightEngine.make(job, data: { household.data }, babyID: household.babyID, answerer: measured,
                                              now: { household.now },
                                              gate: { InsightCards.gate(household.data, me: household.parentA,
                                                                        participants: [household.parentA, household.parentB],
                                                                        now: household.now).make },
                                              onCall: {})
        let text: String
        var card = ""
        switch result {
        case .made(let stored):
            text = "passed"
            let summaries = stored.choices.passages.filter { $0.summaryID != nil }.count
            card = "\(stored.choices.facts.count) facts, \(stored.choices.patterns.count) patterns "
                + "(\(stored.choices.patterns.map { "\($0.shape) \($0.measure)" }.joined(separator: ", "))), "
                + "\(stored.choices.passages.count) passages (\(summaries) with a summary)"
        case .failed(.turnedDown):
            text = "turned down"
        case .closed(let closed):
            text = "error: the gate closed (\(closed))"
        case .failed(let failure):
            text = "error: \(failure)"
        }
        return ModelTestOutcome(name: household.name, kind: household.kind, effort: effort, result: text,
                                calls: measured.calls, input: measured.input, cached: measured.cached,
                                output: measured.output, reasoning: measured.reasoning,
                                seconds: Date().timeIntervalSince(started), card: card,
                                retryReasons: measured.retryReasons)
    }

    static func report(_ outcomes: [ModelTestOutcome], efforts: [String]) -> String {
        func money(_ value: Double) -> String { String(format: "$%.2f", value) }
        var lines = ["# Model test run (AI13)", "",
                     "Claude Sonnet 5.5, \(outcomes.count) cards. Price: $2 in, $0.10 cached in, $10 out per million tokens.", ""]
        for effort in efforts {
            let run = outcomes.filter { $0.effort == effort }
            guard !run.isEmpty else { continue }
            let passed = run.filter(\.passed).count
            let firstTry = run.filter { $0.passed && $0.calls == 1 }.count
            let input = run.reduce(0) { $0 + $1.input }, output = run.reduce(0) { $0 + $1.output }
            let calls = run.reduce(0) { $0 + $1.calls }
            lines += ["## Effort \(effort): \(passed) of \(run.count) passed (\(firstTry) at the first try), "
                      + "gate 27: \(passed >= 27 ? "PASS" : "FAIL")", "",
                      "Cost \(money(run.reduce(0) { $0 + $1.dollars })), \(calls) calls; tokens in \(input) "
                      + "(cached \(run.reduce(0) { $0 + $1.cached })), out \(output) (reasoning \(run.reduce(0) { $0 + $1.reasoning })); "
                      + "per call: \(input / max(1, calls)) in, \(output / max(1, calls)) out; "
                      + "slowest \(Int(run.map(\.seconds).max() ?? 0)) s", "",
                      "| Household | Result | Calls | In | Out | Cost | Seconds | Card |",
                      "|---|---|---|---|---|---|---|---|"]
            for outcome in run {
                lines.append("| \(outcome.name) | \(outcome.result) | \(outcome.calls) | \(outcome.input) | \(outcome.output) | "
                             + "\(money(outcome.dollars)) | \(Int(outcome.seconds)) | \(outcome.card) |")
            }
            let reasons = run.filter { !$0.retryReasons.isEmpty }
            if !reasons.isEmpty {
                lines += ["", "Why a first answer was turned down:"]
                for outcome in reasons {
                    for reason in outcome.retryReasons { lines.append("- \(outcome.name): \(reason)") }
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
