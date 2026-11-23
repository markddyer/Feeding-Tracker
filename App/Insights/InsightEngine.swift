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
}

/// Claude Sonnet 5.5 through Anthropic's package (D2): App Attest on a phone, with no key in the
/// app; the development key only in the simulator (step 2 S6, from the gitignored
/// `Config/Local.xcconfig`).
struct ClaudeAnswerer: CardAnswerer {
    let model: ClaudeLanguageModel

    static func fromInfo(_ info: [String: Any]?) -> ClaudeAnswerer? {
        #if targetEnvironment(simulator)
        guard let key = info?["ClaudeDevAPIKey"] as? String, key.hasPrefix("sk-ant-") else { return nil }
        let auth = AuthMode.apiKey(key)
        #else
        guard let id = info?["ClaudeClientID"] as? String, id.hasPrefix("clid_") else { return nil }
        let auth = AuthMode.appAttest(clientID: id)
        #endif
        // Medium effort to start; the model tests compare low and medium (Section 2 of the review).
        return ClaudeAnswerer(model: ClaudeLanguageModel(name: .sonnet5_5, auth: auth, fixedEffort: .medium, timeout: 60))
    }

    func answer(_ prompt: String, schema: GenerationSchema) async throws -> String {
        let session = LanguageModelSession(model: model)
        let response = try await session.respond(to: prompt, schema: schema)
        return response.content.jsonString
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

    @ObservationIgnored var answerer: (any CardAnswerer)? = ClaudeAnswerer.fromInfo(Bundle.main.infoDictionary)
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Looks at `kind` again (step 2 O7): when Home (the morning card) or Graphs ("This week")
    /// comes on screen, and when a sync finishes while one is on screen. Never from a widget, the
    /// watch, an intent or a notification (S13). The household's members are read from iCloud only
    /// when a card could be made, just before the call (O2).
    func look(_ kind: CardKind, model: AppModel = .shared) async {
        guard !making.contains(kind), let babyID = model.baby?.name else { return }
        let first = InsightCards.plan(kind, data: model.store.data, babyID: babyID, me: model.me, participants: nil,
                                      tries: tries(kind), now: Date())
        guard case .closed(.notChecked, _) = first else { return }
        making.insert(kind)
        defer { making.remove(kind) }
        let participants = await model.sync.householdParticipants()
        let plan = InsightCards.plan(kind, data: model.store.data, babyID: babyID, me: model.me,
                                     participants: participants, tries: tries(kind), now: Date())
        guard case .make(let job, _) = plan else { return }
        guard let answerer else {
            fail(.noKey)
            return
        }
        let result = await Self.make(job, data: { model.store.data }, babyID: babyID, answerer: answerer,
                                     onCall: { self.recordCall(kind, job.request.period) })
        switch result {
        case .made(let card):
            _ = model.store.change { $0.storeInsightCard(card, now: Date()) }
            lastFailure = nil
            lastFailureAt = nil
        case .failed(let failure):
            fail(failure)
        }
    }

    /// One try at a card: a call, and one more with the checker's reasons if the answer is turned
    /// down (AI3). `onCall` counts each call on this phone (D10).
    static func make(_ job: CardJob, data: () -> HouseholdData, babyID: String, answerer: any CardAnswerer,
                     now: () -> Date = Date.init, onCall: () -> Void) async -> CardMakeResult {
        let schema: GenerationSchema
        do {
            schema = try self.schema(job.form)
        } catch {
            return .failed(.unavailable)
        }
        let prompt = InsightCards.prompt(job.request, timeZone: data().householdSettings.timeZone)
        var note = ""
        for _ in 0..<2 {
            onCall()
            let text: String
            do {
                text = try await answerer.answer(prompt + note, schema: schema)
            } catch {
                return .failed(failure(error))
            }
            guard let choices = InsightCards.read(Data(text.utf8)) else {
                note = "\n\nYOUR LAST ANSWER COULDN'T BE READ: choose only from the form's lists."
                continue
            }
            let (verdict, card) = InsightCards.accept(choices, job: job, data: data(), babyID: babyID, now: now())
            if let card { return .made(card) }
            if case .rejected(let problems, _) = verdict {
                note = "\n\nYOUR LAST CHOICES WERE TURNED DOWN, so choose again: "
                    + problems.map { "\($0.part): \(String(describing: $0.reason))" }.joined(separator: "; ") + "."
            }
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
