import Foundation
import FeedingCore

// Ask (AI insights step 3, `docs/planning/12-ai-insights-gauntlet.md`, "Engineering review: step 3,
// Ask"): every rule for a typed question, in one place (step 3 D1 A). The screen and the call are in
// the app; the checker that makes the one thing the screen shows (`CheckedAnswer`) is in
// `InsightSafety.swift`, beside the cards' checker.
//
//  typed words ──▶ route ──┬─▶ danger signs (the words, and with the question before them, X2) ──▶ Get help now, no AI
//                          ├─▶ a medicine ──▶ "last given" from the log (a look back only, X4), or D6's fixed reply
//                          ├─▶ the gate closed (no yes, off, paused) ──▶ the fixed reply
//                          └─▶ .ask(job): the last 7 days and nights, today so far, the latest weights,
//                              the question before it (D4 B) and the question ──▶ the AI ──▶ accept ──▶ CheckedAnswer
//
// Questions are "questions" in code: "ask" already means the night rota's ask (Q4).

// MARK: - The AI's form and answer

/// What a question is about, from a closed list (step 3 D6 A): the third on the same topic within
/// 2 hours brings the line to people. "Something else" never counts.
public enum QuestionTopic: String, Hashable, Sendable, Codable, CaseIterable {
    case feeding, sleep, nappies, crying, weight, skin, feelings
    case other
}

/// A fact about today so far (step 3 D3 A), written by the app (`QuestionWording`).
public enum TodayMeasure: String, Hashable, Sendable, Codable, CaseIterable {
    case feeds, wees, poos, baths, sleep
    case lastFeed, lastNappy, lastSleep, lastBath
}

/// The AI's answer to a question, as chosen on its form. Kept on the phone with the question, and
/// checked again each time it is shown (X8), so a deleted entry's fact goes.
public struct QuestionAnswer: Hashable, Sendable, Codable {
    public var needsHelpNow: Bool
    public var topic: QuestionTopic
    public var cannotAnswer: Bool
    public var facts: [FactRef]
    public var today: [TodayMeasure]
    public var passages: [PassageChoice]
    /// Up to 2 sentences of general information (step 3 D2 B).
    public var sentences: [String]

    public init(needsHelpNow: Bool = false, topic: QuestionTopic = .other, cannotAnswer: Bool = false,
                facts: [FactRef] = [], today: [TodayMeasure] = [], passages: [PassageChoice] = [],
                sentences: [String] = []) {
        self.needsHelpNow = needsHelpNow
        self.topic = topic
        self.cannotAnswer = cannotAnswer
        self.facts = facts
        self.today = today
        self.passages = passages
        self.sentences = sentences
    }
}

// MARK: - What is sent (step 3 D3 A, D4 B, D9 A)

/// Exactly what leaves the phone for a question, and what "What the AI sees" shows: the typed
/// question (and the one before it, D4 B), the last 7 whole days and nights of the facts sheet,
/// today so far, the weights of that week and the one before them, the baby's age in whole weeks
/// and the NHS passages offered. Nothing else from the log is free text (A6).
public struct QuestionRequest: Hashable, Sendable, Codable {
    public var question: String
    public var earlierQuestion: String?
    public var ageInWeeks: Int?
    public var days: [DayFacts]
    public var nights: [NightFacts]
    public var today: TodaySoFar
    public var weights: [WeightFact]
    public var passages: [OfferedPassage]
}

public struct QuestionJob: Hashable, Sendable {
    public var request: QuestionRequest
    public var form: CardForm
    /// The passages chosen by code for this question (O6): only they may appear.
    public var offered: [String]
}

/// Where a typed question goes.
public enum QuestionRoute: Hashable, Sendable {
    /// A danger sign: the Get help now card, in place of an answer, with no AI (A2).
    case helpNow([DangerSign])
    /// "When did she last have Vitamin D?": answered from the log, with no AI (D6, X4). Nil: none logged.
    case lastGiven(medicine: String, at: Date?)
    /// Any other medicine question: D6's fixed reply, with no AI.
    case medicineReply
    /// The AI may not be asked now (one yes, off, paused, not checked yet): the fixed reply.
    case closed(CardClosed)
    case ask(QuestionJob)
}

// MARK: - Kept on the phone (step 3 D5 A)

/// One question and what it got, kept on the phone that asked for 24 hours, never synced.
public struct KeptQuestion: Hashable, Sendable, Codable, Identifiable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case helpNow, lastGiven, medicineReply, closed, asked, couldNotAsk
    }

    public var id: String
    public var askedAt: Date
    public var text: String
    public var kind: Kind
    /// The AI's choices (for `asked`), checked again whenever shown.
    public var answer: QuestionAnswer?
    /// The offered passages for that answer (O6).
    public var offered: [String]
    /// It started with the line to people (step 3 D6 A).
    public var peopleLine: Bool

    public init(id: String = UUID().uuidString, askedAt: Date, text: String, kind: Kind, answer: QuestionAnswer? = nil,
                offered: [String] = [], peopleLine: Bool = false) {
        self.id = id
        self.askedAt = askedAt
        self.text = text
        self.kind = kind
        self.answer = answer
        self.offered = offered
        self.peopleLine = peopleLine
    }

    /// Sent to the AI: only these may go along with the next question (D4 B).
    public var wasSent: Bool { kind == .asked }
}

// MARK: - The rules

public enum InsightQuestions {
    /// Ask sends the last 7 whole days and nights (step 3 D9 A).
    public static let daysSent = 7
    /// A question and its answer are kept for 24 hours (step 3 D5 A).
    public static let keptFor: TimeInterval = 24 * 3600
    /// The question before goes along if asked within 10 minutes (step 3 D4 B).
    public static let earlierWithin: TimeInterval = 10 * 60
    /// The third question on a topic within 2 hours brings the line to people (step 3 D6 A).
    public static let repeatWithin: TimeInterval = 2 * 3600
    public static let repeatCount = 3
    public static let maxTypedLength = 500

    /// The fixed lines, written by the app.
    public static let peopleLine = "You've asked about this a few times. Your health visitor, GP or NHS 111 can talk it through with you."
    public static let cannotAnswerLine = "Little Log can't answer that from your log or the NHS pages here. Your health visitor, GP or NHS 111 can help."
    public static let medicineReply = "Little Log doesn't answer questions about medicines or doses. Check the leaflet, or ask a pharmacist, your GP or NHS 111."
    public static let closedReply = "AI insights are off, so only the log and the NHS pages answer here. Settings › AI insights says why."
    public static let footer = "AI · not medical advice. If you're worried, ask your health visitor or call NHS 111."
    /// The NHS pages the people line brings (A10, D6 A), with its urgent pair.
    public static let peoplePassages = ["postnatal-depression-help", "mental-health-urgent"]

    // MARK: Route

    /// Where `text` goes. `kept` are this phone's kept questions (for D4 B's question before it);
    /// `participants` the household share's members as read from iCloud (nil: not read yet).
    public static func route(_ text: String, data: HouseholdData, babyID: String, me: MemberID?,
                             participants: Set<MemberID>?, kept: [KeptQuestion], now: Date) -> QuestionRoute {
        let earlier = earlierQuestion(kept, now: now)
        // The checks read the words alone and with the question before them, which is what is sent (X2).
        let sent = [earlier?.text, text].compactMap { $0 }.joined(separator: " ")
        let signs = Array(Set(DangerSigns.check(text) + DangerSigns.check(sent))).sorted { $0.rawValue < $1.rawValue }
        if !signs.isEmpty { return .helpNow(signs) }
        let medicines = data.medicines
        if let medicine = MedicineQuestions.check(text, medicines: medicines) ?? MedicineQuestions.check(sent, medicines: medicines) {
            if medicine.asksWhenLastGiven, let name = medicine.medicine {
                return .lastGiven(medicine: name, at: data.lastGiven(name, babyID: babyID, now: now))
            }
            return .medicineReply
        }
        // No yes yet, off or paused: closed at once, without reading the household's members.
        let gate = InsightCards.gate(data, me: me, participants: participants, now: now)
        if let closed = gate.show ?? gate.make { return .closed(closed) }
        let (request, offered) = self.request(text, earlier: earlier?.text, data: data, babyID: babyID, now: now)
        return .ask(QuestionJob(request: request, form: form(for: request), offered: offered))
    }

    /// The question before it in the open chat (D4 B): only the last one, only if it was itself
    /// sent to the AI, and only within 10 minutes.
    public static func earlierQuestion(_ kept: [KeptQuestion], now: Date) -> KeptQuestion? {
        guard let last = kept.max(by: { $0.askedAt < $1.askedAt }), last.wasSent else { return nil }
        let age = now.timeIntervalSince(last.askedAt)
        return age >= 0 && age <= earlierWithin ? last : nil
    }

    // MARK: The request

    /// What a question would send now, whatever the gate says: "What the AI sees" shows it, and
    /// `route` sends the same.
    public static func request(_ text: String, earlier: String?, data: HouseholdData, babyID: String,
                               now: Date) -> (QuestionRequest, [String]) {
        let settings = data.householdSettings
        let timeZone = settings.timeZone
        let facts = data.insightFacts(babyID: babyID, now: now)
        let today = PlainDate(now, in: timeZone)
        let firstDay = today.adding(days: -daysSent)
        let days = facts.days.filter { $0.date >= firstDay }
        let nights = facts.nights.filter { $0.evening >= firstDay.adding(days: -1) }.suffix(daysSent)
        // The week's weights, and the one before them for the change (R2).
        let start = firstDay.firstMoment(in: timeZone)
        let before = facts.weights.lastIndex { $0.at < start }
        let weights = facts.weights.enumerated().filter { $0.element.at >= start || $0.offset == before }.map(\.element)
        // Every ticked passage for the baby's age and feeding (a question can be about anything);
        // by kind and age, never by a value (O8).
        let passages = NHSPassages.choose(kinds: Set(InsightKind.allCases), ageInDays: facts.ageInDays,
                                          breastfeeds: facts.days.contains { $0.breastFeeds > 0 },
                                          bottleFeeds: facts.days.contains { $0.bottleFeeds > 0 },
                                          checks: data.passageChecks, today: today, limit: Int.max)
        let offered = passages.map { passage in
            OfferedPassage(id: passage.id, page: passage.page,
                           summaries: NHSPassages.checkedSummaries(of: passage, checks: data.passageChecks, today: today)
                               .map { OfferedSummary(id: $0.id, words: $0.words) })
        }
        let request = QuestionRequest(question: String(text.prefix(maxTypedLength)),
                                      earlierQuestion: earlier.map { String($0.prefix(maxTypedLength)) },
                                      ageInWeeks: facts.ageInDays.map { $0 / 7 }, days: days, nights: Array(nights),
                                      today: data.todaySoFar(babyID: babyID, now: now), weights: weights,
                                      passages: offered)
        return (request, passages.map(\.id))
    }

    /// The text sent: the instructions, then the log and the question as JSON with no spaces.
    public static func prompt(_ request: QuestionRequest, timeZone: TimeZone) -> String {
        instructions + "\n\nTHE LOG AND THE QUESTION (JSON):\n" + InsightCards.encode(request, timeZone: timeZone)
    }

    /// The same, spaced out for reading ("What the AI sees").
    public static func readablePrompt(_ request: QuestionRequest, timeZone: TimeZone) -> String {
        instructions + "\n\nTHE LOG AND THE QUESTION (JSON):\n" + InsightCards.encode(request, timeZone: timeZone, readable: true)
    }

    static let instructions = """
    You help a parent with a question about their own log of their baby's care, or about what the NHS \
    pages offered say. The log holds numbers and times only: the last 7 days and nights (a night is \
    named by its evening), today so far, weights, and the baby's age in weeks. "question" is what the \
    parent typed; "earlierQuestion", if any, is the one they asked just before.

    Fill in the form:
    - needsHelpNow: yes if the question could describe a baby who needs urgent help. When in doubt, yes.
    - topic: what the question is about.
    - facts and today: the facts from the log that answer the question, if any, up to 6 in all. The app \
    writes every number; you never do.
    - passages: up to 2 offered NHS passages that answer it, each with the summary that fits best, or none.
    - sentences: at most 2 short sentences of general information about babies, only if they help. No \
    numbers, times, names, medicines or doses. Nothing about this baby, and never say whether anything \
    is normal, fine or worrying, or whether to call someone: the app shows the NHS's words and who to ask.
    - cannotAnswer: yes if the log and the passages can't answer it.

    Never judge the baby's health, compare the baby with others, or reassure. When in doubt, choose fewer.
    """

    // MARK: The form

    /// The form for a question: facts only for the days and nights sent (and the latest weight),
    /// today's facts, and only the passages and summaries offered.
    public static func form(for request: QuestionRequest) -> CardForm {
        var scopes = request.days.map { "day:\($0.date)" } + request.nights.map { "night:\($0.evening)" }
        if !request.weights.isEmpty { scopes.append("latest") }
        let fact = FormNode.object(name: "LogFact", fields: [
            FormField(name: "scope", about: "A day (day:DATE) or night (night:EVENING) sent, or latest for the weight",
                      node: .oneOf(scopes.isEmpty ? ["latest"] : scopes)),
            FormField(name: "measure", about: "What the fact counts", node: .oneOf(Measure.allCases.map(\.rawValue))),
        ])
        var fields = [
            FormField(name: "needsHelpNow", about: "Could the question describe a baby who needs urgent help?", node: .yesNo),
            FormField(name: "topic", about: "What the question is about", node: .oneOf(QuestionTopic.allCases.map(\.rawValue))),
            FormField(name: "facts", about: "Facts from the days and nights sent", node: .list(of: fact, maximum: AnswerCheck.maxFacts)),
            FormField(name: "today", about: "Facts about today so far",
                      node: .list(of: .oneOf(TodayMeasure.allCases.map(\.rawValue)), maximum: AnswerCheck.maxFacts)),
        ]
        let passageIDs = request.passages.map(\.id)
        if !passageIDs.isEmpty {
            let pick = FormNode.object(name: "AnswerPassage", fields: [
                FormField(name: "passage", about: "An offered NHS passage", node: .oneOf(passageIDs)),
                FormField(name: "summary", about: "One of its summaries, or none",
                          node: .oneOf(request.passages.flatMap { $0.summaries.map(\.id) } + ["none"])),
            ])
            fields.append(FormField(name: "passages", about: "Up to 2 passages", node: .list(of: pick, maximum: AnswerCheck.maxPassages)))
        }
        fields.append(FormField(name: "sentences", about: "At most 2 short sentences of general information, or none",
                                node: .list(of: .text(maximumLength: AnswerCheck.maxLength), maximum: AnswerCheck.maxSentences)))
        fields.append(FormField(name: "cannotAnswer", about: "The log and the passages can't answer it", node: .yesNo))
        return CardForm(root: .object(name: "Answer", fields: fields))
    }

    // MARK: Reading the answer

    private struct WireAnswer: Decodable {
        var needsHelpNow: Bool
        var topic: String
        var facts: [WireFact]
        var today: [String]
        var passages: [WirePassage]?
        var sentences: [String]?
        var cannotAnswer: Bool
    }

    private struct WireFact: Decodable {
        var scope: String
        var measure: String
    }

    private struct WirePassage: Decodable {
        var passage: String
        var summary: String
    }

    /// The AI's choices; nil when anything in it isn't on the form's lists, so it is asked again.
    public static func read(_ json: Data) -> QuestionAnswer? {
        guard let wire = try? JSONDecoder().decode(WireAnswer.self, from: json),
              let topic = QuestionTopic(rawValue: wire.topic) else { return nil }
        var facts: [FactRef] = []
        for item in wire.facts {
            guard let measure = Measure(rawValue: item.measure), let scope = InsightCards.scope(item.scope) else { return nil }
            facts.append(FactRef(scope, measure))
        }
        var today: [TodayMeasure] = []
        for item in wire.today {
            guard let measure = TodayMeasure(rawValue: item) else { return nil }
            today.append(measure)
        }
        let passages = (wire.passages ?? []).map { PassageChoice($0.passage, summary: $0.summary == "none" ? nil : $0.summary) }
        return QuestionAnswer(needsHelpNow: wire.needsHelpNow, topic: topic, cannotAnswer: wire.cannotAnswer, facts: facts,
                              today: today, passages: passages, sentences: wire.sentences ?? [])
    }

    /// The "needs help now" flag on its own, read before anything else (X6): an answer that can't
    /// be read in full still brings the Get help now card if it says yes.
    public static func readsNeedsHelpNow(_ json: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return false }
        return object["needsHelpNow"] as? Bool ?? false
    }

    // MARK: Checking and showing

    /// The answer checked against this phone's log now, with the household's names and medicines
    /// kept out of the AI's sentences. Used when the answer arrives and each time it is shown (X8).
    public static func accept(_ answer: QuestionAnswer, offered: [String], data: HouseholdData, babyID: String,
                              now: Date, leaveOut: Bool = false) -> QuestionVerdict {
        let (names, medicines) = privateWords(data)
        return AnswerCheck.accept(answer, offered: offered, facts: data.insightFacts(babyID: babyID, now: now),
                                  today: data.todaySoFar(babyID: babyID, now: now), checks: data.passageChecks,
                                  names: names, medicines: medicines, timeZone: data.householdSettings.timeZone,
                                  leaveOut: leaveOut)
    }

    /// The parents' and babies' names, and the household's medicines.
    static func privateWords(_ data: HouseholdData) -> (names: [String], medicines: [String]) {
        let babies = data.plainRecords(of: .baby).compactMap { PayloadCoder.decode(BabyPayload.self, from: $0.payload)?.name }
        let parents = data.plainRecords(of: .member).compactMap {
            PayloadCoder.decode(MemberPayload.self, from: $0.payload)?.displayName
        }
        let names = (parents + babies).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return (names, data.medicines)
    }

    // MARK: The repeat rule (step 3 D6 A) and the expiry (step 3 D5 A)

    /// Whether an answer on `topic` should start with the line to people: with it, `repeatCount`
    /// questions on that topic within `repeatWithin`. "Something else" never counts.
    public static func needsPeopleLine(_ topic: QuestionTopic, kept: [KeptQuestion], now: Date) -> Bool {
        guard topic != .other else { return false }
        let earlier = kept.filter { item in
            let age = now.timeIntervalSince(item.askedAt)
            return item.kind == .asked && item.answer?.topic == topic && age >= 0 && age <= repeatWithin
        }
        return earlier.count + 1 >= repeatCount
    }

    /// The questions still kept: those asked less than 24 hours ago. One dated ahead of now (a
    /// clock set back) goes too, rather than staying for ever.
    public static func kept(_ questions: [KeptQuestion], now: Date) -> [KeptQuestion] {
        questions.filter { item in
            let age = now.timeIntervalSince(item.askedAt)
            return age >= 0 && age < keptFor
        }
    }
}

// MARK: - The app's own wording for today (step 3 D3 A)

/// Every sentence about today so far, written by the app, each with "logged" (R6).
public enum QuestionWording {
    public static func today(_ measure: TodayMeasure, _ today: TodaySoFar, timeZone: TimeZone) -> String? {
        let day = today.day
        func count(_ value: Int, _ one: String, _ many: String) -> String {
            "\(value) \(value == 1 ? one : many) logged today so far."
        }
        switch measure {
        case .feeds: return count(day.feeds, "feed", "feeds")
        case .wees: return count(day.wees, "wet nappy", "wet nappies")
        case .poos: return count(day.poos, "poo", "poos")
        case .baths: return count(day.baths.count, "bath", "baths")
        case .sleep:
            return "\(AnswerCheck.write(day.sleepSeconds, unit: .seconds, timeZone: timeZone)) of sleep logged today so far."
        case .lastFeed:
            return today.lastFeed.map { "The last feed logged started at \(when($0, today.asOf, timeZone))." }
        case .lastNappy:
            return today.lastNappy.map { "The last nappy logged was at \(when($0, today.asOf, timeZone))." }
        case .lastBath:
            return today.lastBath.map { "The last bath logged was at \(when($0, today.asOf, timeZone))." }
        case .lastSleep:
            guard let start = today.lastSleepStart else { return nil }
            if let end = today.lastSleepEnd {
                return "The last sleep logged ended at \(when(end, today.asOf, timeZone))."
            }
            return "The last sleep logged began at \(when(start, today.asOf, timeZone)) and hasn't been ended."
        }
    }

    /// "14:05 today", "23:40 yesterday" or "18:30 on Friday 20 November".
    public static func when(_ date: Date, _ now: Date, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        let day = PlainDate(date, in: timeZone)
        let today = PlainDate(now, in: timeZone)
        if day == today { return "\(time) today" }
        if day == today.adding(days: -1) { return "\(time) yesterday" }
        formatter.dateFormat = "EEEE d MMMM"
        return "\(time) on \(formatter.string(from: date))"
    }
}
