import AppIntents
import FeedingCore
import Foundation

// Shared by the app and the widget extension: the extension needs the types to build the
// control and the widget's buttons, but every action runs in the app's own process
// (`allowedExecutionTargets`, and `LiveActivityIntent`, which Apple documents as running in the
// app's process when tapped in a widget). So a feed started from the Lock Screen saves, sets this
// phone's alarms and goes to the other phone exactly as a tap in the app does. The app is woken in
// the background for it.

/// The bottle Siri or a shortcut names: "Start a formula feed".
enum MilkChoice: String, AppEnum {
    case formula
    case expressed

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bottle"
    static let caseDisplayRepresentations: [MilkChoice: DisplayRepresentation] = [
        .formula: DisplayRepresentation(title: "Formula", synonyms: ["formula milk"]),
        .expressed: DisplayRepresentation(title: "Expressed milk", synonyms: ["expressed"]),
    ]

    var kind: MilkKind { self == .formula ? .formula : .expressed }
}

/// The bottle a button starts (the user's choice of 16 Nov 2026): chosen when the button is
/// added, so a bottle-only parent can have one button per milk.
enum ControlBottle: String, AppEnum {
    case later
    case formula
    case expressed

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bottle"
    static let caseDisplayRepresentations: [ControlBottle: DisplayRepresentation] = [
        .later: "Choose later",
        .formula: "Formula",
        .expressed: "Expressed milk",
    ]

    var kind: MilkKind? {
        switch self {
        case .later: nil
        case .formula: .formula
        case .expressed: .expressed
        }
    }

    /// The button's name in Control Center.
    var buttonTitle: String {
        switch self {
        case .later: "Feed"
        case .formula: "Formula"
        case .expressed: "Expressed milk"
        }
    }
}

/// "Start feed" from Siri, a shortcut, the Action Button or Spotlight. On a bottle-only phone,
/// with no bottle named, Siri asks "Formula or expressed milk?", as Start feed does in the app.
struct StartFeedIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start feed"
    static let description = IntentDescription("Starts a feed now. Add the sides and bottles in the app.")
    static let supportedModes: IntentModes = .background
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Parameter(title: "Bottle", requestValueDialog: "Formula or expressed milk?")
    var milk: MilkChoice?

    init() {}

    init(milk: MilkChoice?) {
        self.milk = milk
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if FEEDING_WIDGETS
        let said = try QuickFeedError.refuse()
        #else
        if milk == nil, QuickFeedRunner.isBottleOnly {
            throw $milk.needsValueError("Formula or expressed milk?")
        }
        let said = await QuickFeedRunner.start(bottle: milk?.kind)
        #endif
        return .result(dialog: "\(said)")
    }
}

/// "Finish feed": finishes the feed running now, whoever started it.
struct FinishFeedIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Finish feed"
    static let description = IntentDescription("Finishes the feed running now. The app then asks for the sides and bottles.")
    static let supportedModes: IntentModes = .background
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if FEEDING_WIDGETS
        let said = try QuickFeedError.refuse()
        #else
        let said = await QuickFeedRunner.finish()
        #endif
        return .result(dialog: "\(said)")
    }
}

/// The buttons' action, in Control Center and on the Lock Screen widget: on starts a feed with
/// the button's bottle, off finishes the feed running. Never asks anything: a button can't.
struct FeedToggleIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start or finish a feed"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .background
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Parameter(title: "Feed running")
    var value: Bool

    @Parameter(title: "Bottle", default: .later)
    var bottle: ControlBottle

    init() {}

    init(bottle: ControlBottle) {
        self.bottle = bottle
    }

    /// A widget button: starts (`true`) or finishes (`false`).
    init(value: Bool, bottle: ControlBottle) {
        self.value = value
        self.bottle = bottle
    }

    func perform() async throws -> some IntentResult {
        #if FEEDING_WIDGETS
        _ = try QuickFeedError.refuse()
        #else
        if value {
            _ = await QuickFeedRunner.start(bottle: bottle.kind)
        } else {
            _ = await QuickFeedRunner.finish()
        }
        #endif
        return .result()
    }
}

/// The settings of a Control Center button, asked when it is added: which bottle it starts.
struct FeedControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Feed button"
    static let description = IntentDescription("Choose the bottle this button starts, or choose it later in the app.")

    @Parameter(title: "Bottle", default: .later)
    var bottle: ControlBottle

    init() {}
}

/// Only if the system ever ran an action in the widget extension instead of the app: it says so,
/// rather than seeming to work while saving nothing.
enum QuickFeedError: Error, CustomLocalizedStringResourceConvertible {
    case openTheApp

    var localizedStringResource: LocalizedStringResource {
        "Open Feeding to start or finish the feed there."
    }

    static func refuse() throws -> String {
        throw QuickFeedError.openTheApp
    }
}
