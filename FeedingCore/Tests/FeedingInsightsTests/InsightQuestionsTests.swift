import Foundation
import Testing
@testable import FeedingCore
@testable import FeedingInsights

// Ask's rules (AI insights step 3, task AI16): the route, what is sent, the AI's sentences, the
// repeat rule and the expiry. No AI runs here.

/// A household with two weeks of steady days, both yeses, two named parents, a named baby and a
/// medicine list, at 10:00 on 22 Nov 2026.
private func askHousehold(extra: [EventSnapshot] = []) -> HouseholdData {
    var data = consenting(household(loggedDays(from: date("2026-11-08"), feeds: Array(repeating: 8, count: 14)) + extra))
    let now = at(2026, 11, 22, 10)
    for (member, name) in [(parentA, "Rowan"), (parentB, "Jude")] {
        data.put(PlainRecord(type: .member, name: member.rawValue, modifiedAt: now,
                             payload: try? PayloadCoder.encode(MemberPayload(displayName: name, colour: "coral"))))
    }
    data.put(PlainRecord(type: .baby, name: baby, modifiedAt: now, payload: try? PayloadCoder.encode(BabyPayload(name: "Pip"))))
    data.setMedicines(["Vitamin D", "Gripe water"], now: now)
    return data
}

private let askNow = at(2026, 11, 22, 10)

private func route(_ text: String, _ data: HouseholdData = askHousehold(), kept: [KeptQuestion] = [],
                   now: Date = askNow) -> QuestionRoute {
    InsightQuestions.route(text, data: data, babyID: baby, me: parentA, participants: [parentA, parentB], kept: kept, now: now)
}

private func job(_ route: QuestionRoute) -> QuestionJob? {
    if case .ask(let job) = route { return job }
    return nil
}

@Suite("Ask: where a question goes (D1, A2, D6, X2, X4)")
struct QuestionRouteTests {
    @Test func aDangerSignNeverReachesTheAI() {
        guard case .helpNow(let signs) = route("She feels really hot and she's very sleepy") else {
            Issue.record("a danger sign went on")
            return
        }
        #expect(signs.contains(.temperature) && signs.contains(.hardToWake))
        // Typos and capitals too.
        if case .ask = route("SHE WONT WAKE UP PROPERLY") { Issue.record("capitals went to the AI") }
    }

    /// X2: "breathing" and "fast" make a danger sign only when the two questions are joined.
    @Test func aDangerSignSplitOverTwoQuestionsIsCaught() {
        let first = KeptQuestion(askedAt: askNow.addingTimeInterval(-60), text: "What should I look for with her breathing?",
                                 kind: .asked, answer: QuestionAnswer(topic: .other))
        if case .helpNow = route("What should I look for with her breathing?") { Issue.record("the first alone is no sign") }
        guard case .helpNow(let signs) = route("Fast, even when she's still?", kept: [first]) else {
            Issue.record("the joined words went to the AI")
            return
        }
        #expect(signs.contains(.breathing))
    }

    /// D6, X4: a look back gets the logged time; a look ahead or a dose gets the fixed reply.
    @Test func medicineQuestionsStayOnThePhone() {
        var data = askHousehold()
        _ = data.addMedicine(babyID: baby, MedicineDetails(name: "Vitamin D"), at: at(2026, 11, 22, 9, 5), by: parentA,
                             timeZoneID: "Europe/London", now: at(2026, 11, 22, 9, 5))
        #expect(route("When did she last have Vitamin D?", data) == .lastGiven(medicine: "Vitamin D", at: at(2026, 11, 22, 9, 5)))
        #expect(route("Has she had her vitamin d today?", data) == .lastGiven(medicine: "Vitamin D", at: at(2026, 11, 22, 9, 5)))
        for text in ["When can I give Vitamin D?", "Can she have gripe water again?", "How much vitamin D does she need?",
                     "Is Calpol safe for babies?", "When is her next Vitamin D due?"] {
            #expect(route(text, data) == .medicineReply, "\"\(text)\"")
        }
        // None logged yet: the look-up says so, with no AI.
        #expect(route("When did she last have gripe water?", data) == .lastGiven(medicine: "Gripe water", at: nil))
    }

    @Test func aClosedGateGetsTheFixedReply() {
        var data = askHousehold()
        data.setInsightYes(false, member: parentB, now: askNow)
        #expect(route("How many feeds yesterday?", data) == .closed(.turnedOff))
        // One yes only.
        var one = household(loggedDays(from: date("2026-11-08"), feeds: Array(repeating: 8, count: 14)))
        one.setInsightYes(true, member: parentA, now: askNow)
        #expect(route("How many feeds yesterday?", one) == .closed(.waitingForYes))
        // Before the members are read, too: no yes means no look at iCloud.
        #expect(InsightQuestions.route("How many feeds yesterday?", data: one, babyID: baby, me: parentA, participants: nil,
                                       kept: [], now: askNow) == .closed(.waitingForYes))
        // But a danger sign and a medicine question still answer on the phone.
        if case .helpNow = route("she's gone blue", one) {} else { Issue.record("the card needs no yes") }
        #expect(route("Can I give Calpol?", one) == .medicineReply)
    }
}

@Suite("Ask: what is sent (D3, D4, D9, A6)")
struct QuestionRequestTests {
    @Test func sevenDaysAndNightsTodaySoFarAndNoText() throws {
        var extra = [entry(.feed, at(2026, 11, 22, 7, 30), payload: bottle(120)),
                     entry(.nappy, at(2026, 11, 22, 8), payload: nappy(wee: true, poo: true))]
        extra.append(entry(.feed, at(2026, 11, 22, 9, 40), payload: EventPayload(note: "SECRET-NOTE")))
        var data = askHousehold(extra: extra)
        _ = data.addMedicine(babyID: baby, MedicineDetails(name: "Vitamin D"), at: at(2026, 11, 22, 9), by: parentA,
                             timeZoneID: "Europe/London", now: at(2026, 11, 22, 9))
        let job = try #require(job(route("How many feeds today?", data)))
        let request = job.request
        #expect(request.days.map(\.date) == (1...7).reversed().map { date("2026-11-22").adding(days: -$0) })
        #expect(request.nights.count == 7)
        #expect(request.nights.last?.evening == date("2026-11-21"))
        #expect(request.today.day.feeds == 2)
        #expect(request.today.lastFeed == at(2026, 11, 22, 9, 40))
        #expect(request.today.lastNappy == at(2026, 11, 22, 8))
        #expect(request.earlierQuestion == nil)
        let sent = InsightQuestions.prompt(request, timeZone: london)
        for secret in ["Rowan", "Jude", "Pip", "Vitamin D", "Gripe water", "SECRET-NOTE"] {
            #expect(!sent.contains(secret), "\(secret) left the phone")
        }
        #expect(sent.contains("How many feeds today?"))
    }

    /// D4 B: the question before goes along within 10 minutes, only if it was itself sent.
    @Test func theQuestionBeforeGoesAlongOnlyIfSentAndRecent() throws {
        let sent = KeptQuestion(askedAt: askNow.addingTimeInterval(-9 * 60), text: "How many feeds last night?",
                                kind: .asked, answer: QuestionAnswer(topic: .feeding))
        #expect(try #require(job(route("And the night before?", kept: [sent]))).request.earlierQuestion
                == "How many feeds last night?")
        let old = KeptQuestion(askedAt: askNow.addingTimeInterval(-11 * 60), text: "How many feeds last night?", kind: .asked)
        #expect(try #require(job(route("And the night before?", kept: [old]))).request.earlierQuestion == nil)
        for kind in [KeptQuestion.Kind.helpNow, .lastGiven, .medicineReply, .closed] {
            let local = KeptQuestion(askedAt: askNow.addingTimeInterval(-60), text: "When did she last have Vitamin D?", kind: kind)
            let request = try #require(job(route("And yesterday?", kept: [local]))).request
            #expect(request.earlierQuestion == nil, "\(kind) went along")
        }
        // Only the last one, never an older sent one behind a local answer.
        let local = KeptQuestion(askedAt: askNow.addingTimeInterval(-30), text: "Can I give Calpol?", kind: .medicineReply)
        #expect(try #require(job(route("And yesterday?", kept: [sent, local]))).request.earlierQuestion == nil)
    }

    @Test func todaySoFarWithNothingLoggedToday() {
        let data = askHousehold()
        let today = data.todaySoFar(babyID: baby, now: at(2026, 11, 22, 0, 5))
        #expect(today.day.feeds == 0)
        #expect(today.day.date == date("2026-11-22"))
        // The last feed is from the night before.
        #expect(today.lastFeed != nil)
        #expect(QuestionWording.today(.feeds, today, timeZone: london) == "0 feeds logged today so far.")
        #expect(QuestionWording.today(.lastFeed, today, timeZone: london)?.hasSuffix("yesterday.") == true)
    }
}

@Suite("Ask: checking the answer (D2 B, Q8, Q9, Q11, X6)")
struct QuestionAnswerTests {
    let data = askHousehold()

    func check(_ answer: QuestionAnswer, leaveOut: Bool = false) -> QuestionVerdict {
        InsightQuestions.accept(answer, offered: [], data: data, babyID: baby, now: askNow, leaveOut: leaveOut)
    }

    @Test func theAppWritesTheLogFacts() {
        let answer = QuestionAnswer(topic: .feeding, facts: [FactRef(.day(date("2026-11-21")), .feeds)], today: [.feeds])
        guard case .accepted(let checked) = check(answer) else { Issue.record("turned down"); return }
        #expect(checked.lines == ["8 feeds logged yesterday.", "0 feeds logged today so far."])
    }

    @Test func sentencesThatMustBeLeftOut() {
        let refused = [
            "She's fine.", "Nothing to worry about.", "Calpol can help.", "Give 2.5 ml.", "Most babies feed 8 times a day.",
            "Your baby is feeding well.", "Babies like Pip often feed more.", "Gripe water is sometimes used.",
            "This could be colic.", "Call your health visitor.", "It is normal for babies to cluster feed.",
            "There is no need to call for help, babies often do this.", "Vitamin drops are given daily.",
            "He will settle by tomorrow.", "Rowan should try a different position.",
        ]
        for text in refused {
            if case .accepted = check(QuestionAnswer(topic: .feeding, sentences: [text])) {
                // "There is no need …" is the known ceiling of D2 B (decision 0d90be60): it has "call".
                Issue.record("\"\(text)\" passed")
            }
            guard case .accepted(let kept) = check(QuestionAnswer(topic: .feeding, sentences: [text]), leaveOut: true) else {
                Issue.record("the last try lost the answer for \"\(text)\"")
                continue
            }
            #expect(kept.sentences.isEmpty, "\"\(text)\" was kept")
        }
    }

    @Test func sentencesThatMayStay() {
        for text in ["Many babies feed more often in the evening.", "Feeds can come close together for a while.",
                     "Babies' sleep often comes in short stretches at first."] {
            guard case .accepted(let checked) = check(QuestionAnswer(topic: .feeding, sentences: [text])) else {
                Issue.record("\"\(text)\" was turned down")
                continue
            }
            #expect(checked.sentences == [text])
        }
        // At most 2.
        if case .accepted = check(QuestionAnswer(topic: .sleep, sentences: ["Babies sleep a lot.", "Sleep comes in stretches.",
                                                                            "Days and nights take time."])) {
            Issue.record("3 sentences passed")
        }
    }

    /// Q9, O2: the flag is passed on even when the rest is turned down; X6: it is read first.
    @Test func theHelpFlagSurvives() {
        let answer = QuestionAnswer(needsHelpNow: true, topic: .other, sentences: ["She's fine."])
        #expect(check(answer) == .rejected([Rejection(part: "sentence 1", reason: .banned("fine"))], needsHelpNow: true))
        #expect(InsightQuestions.readsNeedsHelpNow(Data(#"{"needsHelpNow":true,"topic":"nonsense"}"#.utf8)))
        #expect(InsightQuestions.read(Data(#"{"needsHelpNow":true,"topic":"nonsense"}"#.utf8)) == nil)
        #expect(!InsightQuestions.readsNeedsHelpNow(Data("not json".utf8)))
    }

    @Test func nothingLeftMeansCantAnswer() {
        guard case .accepted(let checked) = check(QuestionAnswer(topic: .other)) else { Issue.record("turned down"); return }
        #expect(checked.cannotAnswer)
    }

    /// X8: a kept answer is checked again when shown; a deleted entry's fact goes.
    @Test func aDeletedEntryLeavesAKeptAnswer() {
        var data = askHousehold(extra: [entry(.feed, at(2026, 11, 22, 7), id: "today-feed", payload: bottle(90))])
        let answer = QuestionAnswer(topic: .feeding, today: [.feeds, .lastFeed])
        guard case .accepted(let before) = InsightQuestions.accept(answer, offered: [], data: data, babyID: baby, now: askNow)
        else { Issue.record("turned down"); return }
        #expect(before.lines.first == "1 feed logged today so far.")
        _ = data.delete("today-feed", by: parentA, now: askNow)
        guard case .accepted(let after) = InsightQuestions.accept(answer, offered: [], data: data, babyID: baby,
                                                                  now: askNow, leaveOut: true)
        else { Issue.record("turned down"); return }
        #expect(after.lines.first == "0 feeds logged today so far.")
    }

    @Test func theFormHasTheFlagFirstAndAPlaceForSentences() throws {
        let job = try #require(job(route("How many feeds yesterday?")))
        guard case .object(_, let fields) = job.form.root else { Issue.record("no form"); return }
        #expect(fields.first?.name == "needsHelpNow")
        #expect(fields.contains { $0.name == "sentences" && $0.node == .list(of: .text(maximumLength: 240), maximum: 2) })
    }
}

@Suite("Ask: the repeat rule and the expiry (D5 A, D6 A)")
struct QuestionKeptTests {
    func asked(_ minutesAgo: Double, _ topic: QuestionTopic) -> KeptQuestion {
        KeptQuestion(askedAt: askNow.addingTimeInterval(-minutesAgo * 60), text: "…", kind: .asked,
                     answer: QuestionAnswer(topic: topic))
    }

    @Test func theThirdOnATopicWithinTwoHoursBringsPeople() {
        #expect(InsightQuestions.needsPeopleLine(.crying, kept: [asked(100, .crying), asked(30, .crying)], now: askNow))
        #expect(!InsightQuestions.needsPeopleLine(.crying, kept: [asked(130, .crying), asked(30, .crying)], now: askNow))
        #expect(!InsightQuestions.needsPeopleLine(.crying, kept: [asked(20, .sleep), asked(10, .feeding)], now: askNow))
        #expect(!InsightQuestions.needsPeopleLine(.other, kept: [asked(20, .other), asked(10, .other)], now: askNow))
    }

    @Test func keptForTwentyFourHours() {
        let stays = KeptQuestion(askedAt: askNow.addingTimeInterval(-(24 * 3600 - 60)), text: "a", kind: .asked)
        let goes = KeptQuestion(askedAt: askNow.addingTimeInterval(-24 * 3600), text: "b", kind: .asked)
        let ahead = KeptQuestion(askedAt: askNow.addingTimeInterval(3600), text: "c", kind: .asked)
        #expect(InsightQuestions.kept([stays, goes, ahead], now: askNow).map(\.text) == ["a"])
        // Across the clocks going back (25 Oct 2026): 24 hours is 24 hours, not a calendar day.
        let before = at(2026, 10, 24, 12)
        let item = KeptQuestion(askedAt: before, text: "d", kind: .asked)
        #expect(InsightQuestions.kept([item], now: before.addingTimeInterval(24 * 3600 - 60)).count == 1)
        #expect(InsightQuestions.kept([item], now: before.addingTimeInterval(24 * 3600)).isEmpty)
    }
}

// AI insights step 4: Siri questions and what is read aloud (D3 A, D8 A, D10 B, design D10 A; Y1).
@Suite("Ask from Siri: the words read aloud and the first check")
struct SpokenReplyTests {
    let data = askHousehold()

    /// An answer as the screen shows it, with the facts the app writes and one AI sentence.
    var checked: CheckedAnswer? {
        let answer = QuestionAnswer(topic: .feeding, facts: [FactRef(.day(date("2026-11-21")), .feeds)],
                                    sentences: ["Many babies feed more often in the evening."])
        guard case .accepted(let checked) = InsightQuestions.accept(answer, offered: [], data: data, babyID: baby,
                                                                     now: askNow, leaveOut: true) else { return nil }
        return checked
    }

    @Test func anAnswerIsReadInTheParentsOrder() throws {
        let checked = try #require(checked)
        let words = InsightQuestions.spoken(.asked, checked: checked)
        // The facts, then the AI's sentence, then the notice (D10 B), and nothing the screen doesn't show.
        #expect(words.hasPrefix("8 feeds logged yesterday. Many babies feed more often in the evening. This is AI, not medical advice."))
        #expect(!words.contains("NHS"), "no passage was chosen")
    }

    @Test func anAnswerThatCantBeGivenSaysSo() {
        let words = InsightQuestions.spoken(.asked, checked: nil)
        #expect(words == "This is AI, not medical advice. " + InsightQuestions.cannotAnswerLine)
    }

    @Test func eachOtherReplySaysItsOwnWords() {
        #expect(InsightQuestions.spoken(.helpNow) == "Get help now. Call 999 and Call 111 are on the screen.")
        #expect(InsightQuestions.spoken(.parentHelp, helpTitle: "Urgent help") == "Urgent help. Call 999 and Call 111 are on the screen.")
        #expect(InsightQuestions.spoken(.medicineReply) == "Little Log doesn't answer questions about medicines or doses.")
        #expect(InsightQuestions.spoken(.lastGiven, lastGiven: "Vitamin D: last logged at 09:05 today.")
                == "Vitamin D: last logged at 09:05 today.")
        #expect(InsightQuestions.spoken(.closed) == "AI insights is off, so Little Log can't answer that.")
        #expect(InsightQuestions.spoken(.couldNotAsk) == "Couldn't reach the AI. Call 111 is on the screen.")
        #expect(InsightQuestions.spoken(.stopped) == InsightQuestions.stoppedReply)
        // Never a medicine's dose or an NHS passage's words in any of them.
        for kind in [KeptQuestion.Kind.helpNow, .medicineReply, .closed, .couldNotAsk, .stopped] {
            #expect(!InsightQuestions.spoken(kind).contains("ml"))
        }
    }

    /// Y1: the danger check that runs the moment a Siri question arrives is the route's own.
    @Test func theSiriCheckIsTheRoutesCheck() {
        let text = "She feels really hot and she's very sleepy"
        #expect(!InsightQuestions.dangerSigns(text, kept: [], now: askNow).isEmpty)
        guard case .helpNow(let signs) = InsightQuestions.route(text, data: data, babyID: baby, me: parentA,
                                                                participants: [parentA, parentB], kept: [], now: askNow) else {
            Issue.record("the route didn't stop it")
            return
        }
        #expect(signs == InsightQuestions.dangerSigns(text, kept: [], now: askNow))
        #expect(InsightQuestions.dangerSigns("How many feeds last night?", kept: [], now: askNow).isEmpty)
    }

    @Test func theSameQuestionAgain() {
        #expect(InsightQuestions.isSameQuestion("How long did she sleep?", "how long did she sleep"))
        #expect(InsightQuestions.isSameQuestion("How  long, did she sleep ?", "How long did she sleep"))
        #expect(!InsightQuestions.isSameQuestion("How long did she sleep?", "How many feeds?"))
        #expect(!InsightQuestions.isSameQuestion("?", "?"), "no words is never the same question")
    }

    /// An entry kept by an older build reads as typed: never read aloud.
    @Test func anOlderEntryIsTyped() throws {
        let json = #"{"id":"a","askedAt":0,"text":"x","kind":"asked","offered":[],"peopleLine":false}"#
        let item = try JSONDecoder().decode(KeptQuestion.self, from: Data(json.utf8))
        #expect(item.viaSiri == nil && !item.waitsToBeRead)
        let spoken = KeptQuestion(askedAt: askNow, text: "x", kind: .asked, viaSiri: true)
        #expect(spoken.waitsToBeRead)
        var read = spoken
        read.readAt = askNow
        #expect(!read.waitsToBeRead)
    }
}

@Suite("Ask: a parent's danger words go to their help, with no AI (Codex step 4 review, 1)")
struct ParentDangerRouteTests {
    @Test func aParentsDangerWordsNeverReachTheAI() {
        let data = HouseholdData()
        let route = InsightQuestions.route("I don't think I can keep myself safe tonight", data: data, babyID: "baby",
                                           me: "parent-a", participants: ["parent-a", "parent-b"], kept: [], now: Date())
        #expect(route == .parentHelp)
        let woken = InsightQuestions.route("She cannot be woken", data: data, babyID: "baby", me: "parent-a",
                                           participants: ["parent-a", "parent-b"], kept: [], now: Date())
        guard case .helpNow = woken else {
            Issue.record("a danger sign must open Get help now: \(woken)")
            return
        }
    }
}
