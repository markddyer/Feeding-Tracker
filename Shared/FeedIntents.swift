import AppIntents
import Foundation

// Shared by the app and the widget extension: the extension needs the types to build the
// control, but every action runs in the app's own process (`allowedExecutionTargets`, and
// `LiveActivityIntent`, which Apple documents as running in the app's process when tapped in a
// widget). So a feed started from the Lock Screen saves, sets this phone's alarms and goes to the
// other phone exactly as a tap in the app does. The app is woken in the background for it.

/// "Start feed" from Siri, a shortcut, the Action Button or Spotlight.
struct StartFeedIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start feed"
    static let description = IntentDescription("Starts a feed now. Add the sides and bottles in the app.")
    static let supportedModes: IntentModes = .background
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if FEEDING_WIDGETS
        let said = try QuickFeedError.refuse()
        #else
        let said = await QuickFeedRunner.start()
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

/// The control's switch: on starts a feed, off finishes the one running.
struct FeedToggleIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start or finish a feed"
    static let supportedModes: IntentModes = .background
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Parameter(title: "Feed running")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        #if FEEDING_WIDGETS
        _ = try QuickFeedError.refuse()
        #else
        if value {
            _ = await QuickFeedRunner.start()
        } else {
            _ = await QuickFeedRunner.finish()
        }
        #endif
        return .result()
    }
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
