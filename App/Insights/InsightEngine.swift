import ClaudeForFoundationModels
import FeedingCore
import FeedingInsights
import Foundation
import FoundationModels
import Observation

// AI insights, step 2 (`docs/planning/12-ai-insights-gauntlet.md`, task AI8): the one place the
// app calls Claude. Every rule (when a card is due, the two-yes gate, what is sent, the form,
// reading and checking the answer, storing it) is `InsightCards`' in `FeedingInsights`; this file
// only turns the form into Apple's run-time form, makes the call, and maps failures to a short
// list. Nothing here writes a prompt or an answer to any log (A9).

/// Answers a card's form. The app asks Claude (`ClaudeAnswerer`); a test gives a fixed answer.
protocol CardAnswerer: Sendable {
    func answer(_ prompt: String, schema: GenerationSchema) async throws -> String
    /// Gets this phone ready before the first card (App Attest's first run); nothing by default.
    func prepare() async throws
}

extension CardAnswerer {
    func prepare() async throws {}
}

/// Claude Sonnet 5.5 through Anthropic's package (D2): App Attest on a phone, with no key in the
/// app; the development key only in the simulator (step 2 S6, from the gitignored
/// `Config/Local.xcconfig`).
struct ClaudeAnswerer: CardAnswerer {
    /// The effort sent with every card (Section 2 of the review): the model tests (AI13) compare
    /// low and medium and keep the cheaper one unless it is turned down more often.
    static let effort: ClaudeModel.Effort = .medium

    let model: ClaudeLanguageModel

    static func fromInfo(_ info: [String: Any]?, effort: ClaudeModel.Effort = Self.effort) -> ClaudeAnswerer? {
        #if targetEnvironment(simulator)
        guard let key = info?["ClaudeDevAPIKey"] as? String, key.hasPrefix("sk-ant-") else { return nil }
        let auth = AuthMode.apiKey(key)
        #else
        guard let id = info?["ClaudeClientID"] as? String, id.hasPrefix("clid_") else { return nil }
        let auth = AuthMode.appAttest(clientID: id)
        #endif
        return ClaudeAnswerer(model: ClaudeLanguageModel(name: .sonnet5_5, auth: auth, fixedEffort: effort, timeout: 60))
    }

    func answer(_ prompt: String, schema: GenerationSchema) async throws -> String {
        try await answerWithUsage(prompt, schema: schema).text
    }

    /// The answer and the tokens it used; the model tests (AI13) measure the cost with it.
    func answerWithUsage(_ prompt: String, schema: GenerationSchema) async throws
        -> (text: String, usage: LanguageModelSession.Usage) {
        let session = LanguageModelSession(model: model)
        let response = try await session.respond(to: prompt, schema: schema)
        return (response.content.jsonString, session.usage)
    }

    /// The package's first-run App Attest (4 to 8 seconds), safe to run again (`ClaudeLanguageModel`
    /// 0.2.3); nothing with the simulator's development key.
    func prepare() async throws {
        try await model.authenticateIfNeeded()
    }
}

/// Why no AI card was made, in the short list Settings shows (S12, S17).
enum InsightFailure: String, Hashable, Sendable, Codable {
    /// No signal, or iCloud and Anthropic couldn't be reached.
    case noSignal
    /// This phone couldn't prove it runs the real app (App Attest).
    case couldNotConnect
    /// The AI turned the request down, the spend limit was reached, or another error.
    case unavailable
    /// Two answers in a row didn't pass the checker (AI3).
    case turnedDown
    /// No client ID (a phone) or development key (the simulator) in this build.
    case noKey
}

/// What one try at a card gave.
enum CardMakeResult: Hashable, Sendable {
    case made(StoredCard)
    case failed(InsightFailure)
    /// The gate closed between calls or while the AI answered (X5); nothing is kept.
    case closed(CardClosed)
}

/// Why the last look at a kind of card made none, for its period: the screens then show the
/// facts-only card (S12) rather than "Making…".
struct CardOutcome: Hashable, Sendable {
    enum Reason: Hashable, Sendable {
        case failed(InsightFailure)
        case closed(CardClosed)
    }

    let period: CardPeriod
    let reason: Reason
}

@MainActor
@Observable
final class InsightEngine {
    static let shared = InsightEngine()

    /// The cards being made now, in memory only (the stored card is the household's).
    private(set) var making: Set<CardKind> = []
    /// The last failure and when, for Settings; cleared when a card is made.
    private(set) var lastFailure: InsightFailure?
    private(set) var lastFailureAt: Date?
    /// True while this phone gets ready after a yes (S8).
    private(set) var preparing = false
    /// Why the last look at each kind made no card, with its period; cleared when one is made.
    private(set) var outcomes: [CardKind: CardOutcome] = [:]

    @ObservationIgnored var answerer: (any CardAnswerer)? = ClaudeAnswerer.fromInfo(Bundle.main.infoDictionary)
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        #if FEEDING_DEV && targetEnvironment(simulator)
        // `-sampleInsightFailure noSignal` (or another `InsightFailure`): Settings' "why", for screenshots.
        if let name = UserDefaults.standard.string(forKey: "sampleInsightFailure"), let failure = InsightFailure(rawValue: name) {
            lastFailure = failure
            lastFailureAt = Calendar.current.date(bySettingHour: 7, minute: 10, second: 0, of: Date())
        }
        // `-sampleInsightMaking YES`: both cards stay "Making…", for screenshots.
        if UserDefaults.standard.bool(forKey: "sampleInsightMaking") {
            making = Set(CardKind.allCases)
        }
        #endif
    }

    /// Runs App Attest's first run just after this parent's yes (step 2 S8), so its few seconds and
    /// any failure come then, not with the first card at 3am. Settings shows a failure.
    func prepare() async {
        guard !preparing else { return }
        guard let answerer else {
            fail(.noKey)
            return
        }
        preparing = true
        defer { preparing = false }
        do {
            try await answerer.prepare()
            if lastFailure == .couldNotConnect || lastFailure == .noKey {
                lastFailure = nil
                lastFailureAt = nil
            }
        } catch {
            fail(Self.failure(error))
        }
    }

    /// Looks at `kind` again (step 2 O7): when Home (the morning card) or Graphs ("This week")
    /// comes on screen, and when a sync finishes while one is on screen. Never from a widget, the
    /// watch, an intent or a notification (S13). The household's members are read from iCloud only
    /// when a card could be made, just before the call (O2).
    func look(_ kind: CardKind, model: AppModel = .shared) async {
        guard !making.contains(kind), let babyID = model.baby?.name else { return }
        guard let period = InsightCards.currentPeriod(kind, data: model.store.data, babyID: babyID, now: Date()) else {
            outcomes[kind] = nil
            return
        }
        let first = InsightCards.plan(kind, data: model.store.data, babyID: babyID, me: model.me, participants: nil,
                                      tries: tries(kind), now: Date())
        switch first {
        case .closed(.notChecked, _):
            break
        case .closed(let closed, _):
            outcomes[kind] = CardOutcome(period: period, reason: .closed(closed))
            return
        default:
            return
        }
        making.insert(kind)
        defer { making.remove(kind) }
        // Signed out, no household yet or no signal: nothing can be sent, so the card shows the
        // facts only and Settings says why (S12).
        guard let participants = await model.sync.householdParticipants() else {
            fail(.noSignal, kind, period)
            return
        }
        let plan = InsightCards.plan(kind, data: model.store.data, babyID: babyID, me: model.me,
                                     participants: participants, tries: tries(kind), now: Date())
        let job: CardJob
        switch plan {
        case .make(let planned, _):
            job = planned
        case .closed(let closed, _):
            outcomes[kind] = CardOutcome(period: period, reason: .closed(closed))
            return
        case .show:
            // The stored card stands. If none of it holds on this phone any more, the screen shows
            // the facts only rather than waiting.
            outcomes[kind] = CardOutcome(period: period, reason: .closed(.later))
            return
        case .none:
            outcomes[kind] = nil
            return
        }
        guard let answerer else {
            fail(.noKey, kind, period)
            return
        }
        let result = await Self.make(job, data: { model.store.data }, babyID: babyID, answerer: answerer,
                                     gate: { InsightCards.gate(model.store.data, me: model.me, participants: participants,
                                                               now: Date()).make },
                                     onCall: { self.recordCall(kind, job.request.period) })
        switch result {
        case .closed(let closed):
            outcomes[kind] = CardOutcome(period: period, reason: .closed(closed))
        case .made(let card):
            _ = model.store.change { $0.storeInsightCard(card, now: Date()) }
            lastFailure = nil
            lastFailureAt = nil
            outcomes[kind] = nil
        case .failed(let failure):
            fail(failure, kind, period)
        }
    }

    private func fail(_ failure: InsightFailure, _ kind: CardKind, _ period: CardPeriod) {
        fail(failure)
        outcomes[kind] = CardOutcome(period: period, reason: .failed(failure))
    }

    /// One try at a card: a call, and one more with the checker's reasons in plain words if the
    /// answer is turned down (AI3). On that last call a pick that fails the check is left out on
    /// its own rather than losing the card (AI13 D3 A). `onCall` counts each call on this phone (D10).
    /// `gate` is asked before each call and again before a card is kept (step 1 O3, step 3 X5): a
    /// yes withdrawn, an off or a pause that arrives while the AI is answering stops the second
    /// call and throws the answer away.
    static func make(_ job: CardJob, data: () -> HouseholdData, babyID: String, answerer: any CardAnswerer,
                     now: () -> Date = Date.init, gate: () -> CardClosed?, onCall: () -> Void) async -> CardMakeResult {
        let schema: GenerationSchema
        do {
            schema = try self.schema(job.form)
        } catch {
            return .failed(.unavailable)
        }
        let prompt = InsightCards.prompt(job.request, timeZone: data().householdSettings.timeZone)
        var note = ""
        for attempt in 0..<2 {
            if let closed = gate() { return .closed(closed) }
            onCall()
            let text: String
            do {
                text = try await answerer.answer(prompt + note, schema: schema)
            } catch {
                return .failed(failure(error))
            }
            guard let choices = InsightCards.read(Data(text.utf8)) else {
                note = InsightCards.unreadableNote
                continue
            }
            let (verdict, card) = InsightCards.accept(choices, job: job, data: data(), babyID: babyID, now: now(),
                                                      leaveOut: attempt == 1)
            if let card {
                if let closed = gate() { return .closed(closed) }
                return .made(card)
            }
            if case .rejected(let problems, _) = verdict { note = InsightCards.retryNote(problems) }
        }
        return .failed(.turnedDown)
    }

    /// The card's form in Apple's run-time form (step 2 D3): every name unique, as nested forms
    /// with shared names can loop (Apple forum 798773).
    static func schema(_ form: CardForm) throws -> GenerationSchema {
        func dynamic(_ node: FormNode, name: String, about: String?) -> DynamicGenerationSchema {
            switch node {
            case .object(let objectName, let fields):
                return DynamicGenerationSchema(name: objectName, description: about, properties: fields.map { field in
                    DynamicGenerationSchema.Property(name: field.name, description: field.about,
                                                     schema: dynamic(field.node, name: "\(objectName)_\(field.name)", about: field.about))
                })
            case .list(let item, let maximum):
                return DynamicGenerationSchema(arrayOf: dynamic(item, name: name, about: about), minimumElements: 0,
                                               maximumElements: maximum)
            case .oneOf(let values):
                return DynamicGenerationSchema(name: name, description: about, anyOf: values)
            case .yesNo:
                return DynamicGenerationSchema(type: Bool.self)
            }
        }
        return try GenerationSchema(root: dynamic(form.root, name: "Card", about: nil), dependencies: [])
    }

    static func failure(_ error: Error) -> InsightFailure {
        if let claude = error as? ClaudeError {
            switch claude {
            case .missingCredential: return .noKey
            case .attestationUnsupported, .attestationFailed: return .couldNotConnect
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                 .dataNotAllowed, .internationalRoamingOff:
                return .noSignal
            default:
                return .unavailable
            }
        }
        return .unavailable
    }

    private func fail(_ failure: InsightFailure) {
        lastFailure = failure
        lastFailureAt = Date()
    }

    // MARK: This phone's calls (D10)

    private func triesKey(_ kind: CardKind) -> String { "insights.tries.\(kind.rawValue)" }

    func tries(_ kind: CardKind) -> LocalCardTries {
        guard let data = defaults.data(forKey: triesKey(kind)),
              let tries = try? JSONDecoder().decode(LocalCardTries.self, from: data) else { return LocalCardTries() }
        return tries
    }

    private func recordCall(_ kind: CardKind, _ period: CardPeriod) {
        var tries = tries(kind)
        tries.record(period, at: Date())
        if let data = try? JSONEncoder().encode(tries) { defaults.set(data, forKey: triesKey(kind)) }
    }
}
