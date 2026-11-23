import FeedingCore
import FeedingInsights
import Foundation
import Testing
@testable import FeedingDev

// Ask's call and its file on the phone (AI insights step 3, task AI18). A fixed answer stands in
// for Claude: no network, no key.

@MainActor
@Suite("Ask: the call and the file")
struct QuestionEngineTests {
    let engine = InsightEngineTests()

    func job(_ text: String = "How many feeds yesterday?") -> QuestionJob? {
        let route = InsightQuestions.route(text, data: engine.household(), babyID: engine.baby, me: "parent-a",
                                           participants: ["parent-a", "parent-b"], kept: [], now: engine.at(22, 10))
        if case .ask(let job) = route { return job }
        return nil
    }

    func ask(_ job: QuestionJob, _ answerer: FixedAnswerer, gate: @escaping () -> CardClosed? = { nil }) async
        -> InsightEngine.QuestionResult {
        let data = engine.household()
        return await InsightEngine.askAI(job, data: { data }, babyID: engine.baby, answerer: answerer,
                                         now: { engine.at(22, 10) }, gate: gate)
    }

    static let good = #"""
        {"needsHelpNow":false,"topic":"feeding","facts":[{"scope":"day:2026-11-21","measure":"feeds"}],"today":["feeds"],
         "passages":[],"sentences":["Many babies feed more often in the evening."],"cannotAnswer":false}
        """#

    @Test func theFormBecomesApplesForm() throws {
        let job = try #require(job())
        _ = try InsightEngine.schema(job.form)
    }

    @Test func aGoodAnswerIsKeptAsChosen() async throws {
        let job = try #require(job())
        let answerer = FixedAnswerer(.success(Self.good))
        let result = await ask(job, answerer)
        guard case .answered(let answer) = result else { Issue.record("\(result)"); return }
        #expect(answerer.calls == 1)
        #expect(answer.sentences == ["Many babies feed more often in the evening."])
        guard case .accepted(let checked) = InsightQuestions.accept(answer, offered: job.offered, data: engine.household(),
                                                                    babyID: engine.baby, now: engine.at(22, 10))
        else { Issue.record("turned down when shown"); return }
        #expect(checked.lines.first == "8 feeds logged yesterday.")
    }

    /// X6: the flag is read first; an answer that can't be read in full still brings the card.
    @Test func theHelpFlagWinsEvenInAnUnreadableAnswer() async throws {
        let job = try #require(job())
        let answerer = FixedAnswerer(.success(#"{"needsHelpNow":true,"topic":"nonsense"}"#))
        #expect(await ask(job, answerer) == .helpNow)
        #expect(answerer.calls == 1)
    }

    @Test func twoUnreadableAnswersGiveTheFixedReply() async throws {
        let job = try #require(job())
        let answerer = FixedAnswerer(.success("not an answer"))
        #expect(await ask(job, answerer) == .failed(.turnedDown))
        #expect(answerer.calls == 2)
    }

    /// The first try is turned down for a verdict; the last try leaves that sentence out.
    @Test func aBadSentenceIsTriedAgainThenLeftOut() async throws {
        let job = try #require(job())
        let answerer = FixedAnswerer(.success(#"""
            {"needsHelpNow":false,"topic":"feeding","facts":[{"scope":"day:2026-11-21","measure":"feeds"}],"today":[],
             "passages":[],"sentences":["That is completely normal."],"cannotAnswer":false}
            """#))
        let result = await ask(job, answerer)
        guard case .answered(let answer) = result else { Issue.record("\(result)"); return }
        #expect(answerer.calls == 2)
        guard case .accepted(let shown) = InsightQuestions.accept(answer, offered: job.offered, data: engine.household(),
                                                                  babyID: engine.baby, now: engine.at(22, 10), leaveOut: true)
        else { Issue.record("nothing shown"); return }
        #expect(shown.sentences.isEmpty)
        #expect(shown.lines == ["8 feeds logged yesterday."])
    }

    /// X5: a yes withdrawn during the call stops the next and drops the answer.
    @Test func aYesWithdrawnDropsTheAnswer() async throws {
        let job = try #require(job())
        var checks = 0
        let result = await ask(job, FixedAnswerer(.success(Self.good)), gate: {
            checks += 1
            return checks > 1 ? .turnedOff : nil
        })
        #expect(result == .closed(.turnedOff))
    }

    @Test func failuresLandOnTheShortList() async throws {
        let job = try #require(job())
        #expect(await ask(job, FixedAnswerer(.failure(URLError(.notConnectedToInternet)))) == .failed(.noSignal))
    }

    // MARK: The file (D5 A, Q12)

    func temporaryLog(now: Date) -> (QuestionLog, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("questions-\(UUID().uuidString).json")
        return (QuestionLog(url: url, now: now), url)
    }

    @Test func theFileIsProtectedLeftOutOfBackupsAndKeptADay() throws {
        let now = engine.at(22, 10)
        let (log, url) = temporaryLog(now: now)
        log.add(KeptQuestion(askedAt: now, text: "How many feeds?", kind: .asked), now: now)
        log.add(KeptQuestion(askedAt: now.addingTimeInterval(-25 * 3600), text: "Old", kind: .asked), now: now)
        #expect(log.questions.map(\.text) == ["How many feeds?"])
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        // Read again from the file, as on the next launch.
        #expect(QuestionLog(url: url, now: now).questions.count == 1)
        #expect(QuestionLog(url: url, now: now.addingTimeInterval(24 * 3600)).questions.isEmpty)
        #expect(log.shown(now: now.addingTimeInterval(24 * 3600)).isEmpty, "gone while Ask is open")
        log.empty()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(log.questions.isEmpty)
    }
}
