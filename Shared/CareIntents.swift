import AppIntents
import FeedingCore
import Foundation

// Sleep, nappy and medicine buttons outside the app (the users' choice F for the Lock Screen and
// the settled Control Center buttons, 17 Nov 2026; `docs/planning/06-more-than-feeds.md`). Shared
// by the app and the widget extension, like `FeedIntents.swift`: every action runs in the app's
// own process, so a tap saves, syncs and refreshes the widgets as a tap in the app does. They work
// on a locked phone, with no Touch ID, as Start feed does. Not offered to Siri or Shortcuts for
// now (Q3: "Not Siri or the Action Button for these").

/// What a nappy button logs, chosen when the button is added.
enum NappyChoice: String, AppEnum {
    case wee
    case poo
    case both

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Nappy"
    static let caseDisplayRepresentations: [NappyChoice: DisplayRepresentation] = [
        .wee: "Wee",
        .poo: "Poo",
        .both: "Wee and poo",
    ]

    var wee: Bool { self != .poo }
    var poo: Bool { self != .wee }

    /// The button's name in Control Center.
    var buttonTitle: String {
        switch self {
        case .wee: "Wee"
        case .poo: "Poo"
        case .both: "Both"
        }
    }

    /// The button's icon. Control Center can only show Apple's symbols, and there is none for a
    /// poo, so poo and both get letters, as the two milks do (a circled P and a circled B).
    var symbol: String {
        switch self {
        case .wee: "drop.fill"
        case .poo: "p.circle.fill"
        case .both: "b.circle.fill"
        }
    }

    /// What VoiceOver says for the button.
    var spoken: String {
        switch self {
        case .wee: "Log a wee"
        case .poo: "Log a poo"
        case .both: "Log a wee and a poo"
        }
    }
}

/// "Fell asleep": starts a sleep now. Changes nothing while a sleep runs.
struct FellAsleepIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Fell asleep"
    static let description = IntentDescription("Logs that the baby fell asleep now.")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    init() {}

    func perform() async throws -> some IntentResult {
        #if FEEDING_WIDGETS
        _ = try QuickCareError.refuse()
        #else
        _ = await QuickFeedRunner.fellAsleep()
        #endif
        return .result()
    }
}

/// "Woke up": ends the sleep running now, whoever started it.
struct WokeUpIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Woke up"
    static let description = IntentDescription("Ends the sleep running now.")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    init() {}

    func perform() async throws -> some IntentResult {
        #if FEEDING_WIDGETS
        _ = try QuickCareError.refuse()
        #else
        _ = await QuickFeedRunner.wokeUp()
        #endif
        return .result()
    }
}

/// The Control Center Sleep switch: on logs Fell asleep, off logs Woke up.
struct SleepToggleIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Fell asleep or woke up"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Parameter(title: "Asleep")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        #if FEEDING_WIDGETS
        _ = try QuickCareError.refuse()
        #else
        if value {
            _ = await QuickFeedRunner.fellAsleep()
        } else {
            _ = await QuickFeedRunner.wokeUp()
        }
        #endif
        return .result()
    }
}

/// A nappy change now: wee, poo or both, with no colour or consistency (the app's Nappy tile then
/// offers "Add details").
struct NappyIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Log a nappy"
    static let description = IntentDescription("Logs a nappy change now: wee, poo or both.")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Parameter(title: "Nappy", default: .both)
    var kind: NappyChoice

    init() {}

    init(kind: NappyChoice) {
        self.kind = kind
    }

    func perform() async throws -> some IntentResult {
        #if FEEDING_WIDGETS
        _ = try QuickCareError.refuse()
        #else
        _ = await QuickFeedRunner.nappy(wee: kind.wee, poo: kind.poo)
        #endif
        return .result()
    }
}

/// A medicine or vitamin given now, named on the button.
struct MedicineIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Log a medicine"
    static let description = IntentDescription("Logs a medicine or vitamin given now.")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Parameter(title: "Medicine", default: "Vitamin D")
    var medicine: String

    init() {}

    init(medicine: String) {
        self.medicine = medicine
    }

    func perform() async throws -> some IntentResult {
        #if FEEDING_WIDGETS
        _ = try QuickCareError.refuse()
        #else
        _ = await QuickFeedRunner.medicine(medicine)
        #endif
        return .result()
    }
}

/// The settings of a nappy button, asked when it is added: Wee, Poo or Both.
struct NappyControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Nappy button"
    static let description = IntentDescription("Choose what this button logs: a wee, a poo, or both.")

    @Parameter(title: "Nappy", default: .both)
    var kind: NappyChoice

    init() {}
}

/// The settings of a medicine button, asked when it is added: one medicine from the household's
/// list (Settings in the app).
struct MedicineControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Medicine button"
    static let description = IntentDescription("Choose the medicine or vitamin this button logs.")

    @Parameter(title: "Medicine", default: "Vitamin D", optionsProvider: MedicineOptions())
    var medicine: String

    init() {}
}

/// The household's medicine list, read from the household file in the App Group.
struct MedicineOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let list = SharedHousehold.load()?.medicines ?? []
        return list.isEmpty ? HouseholdData.defaultMedicines : list
    }

    func defaultResult() async -> String? {
        (try? await results())?.first
    }
}

/// The household file in the App Group, which the app keeps. Read by the widget extension, and by
/// the medicine list in either process.
enum SharedHousehold {
    static func load() -> HouseholdData? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FeedingAppGroup") as? String,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return try? HouseholdFile.load(from: folder.appendingPathComponent("household.json"))
    }
}

/// Only if the system ever ran an action in the widget extension instead of the app: it says so,
/// rather than seeming to work while saving nothing.
enum QuickCareError: Error, CustomLocalizedStringResourceConvertible {
    case openTheApp

    var localizedStringResource: LocalizedStringResource {
        "Open Little Log to log it there."
    }

    static func refuse() throws -> String {
        throw QuickCareError.openTheApp
    }
}
