import FeedingCore
import Foundation
import WidgetKit

/// Tells the Lock Screen widget and the control to read the household again, only when what they
/// show has changed (a feed started, finished, added or deleted), so iOS's limit on reloads isn't
/// spent on other changes.
@MainActor
final class WidgetRefresher {
    private var shown: FeedGlance??

    func update(_ data: HouseholdData, now: Date = Date()) {
        let glance = data.glance(now: now)
        guard shown != .some(glance) else { return }
        shown = .some(glance)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }

    /// Tells the widget this phone's "How you feed", so a bottle-only phone's widget shows a
    /// button per milk. The widget can't read the app's own settings, only the App Group's.
    func feedingStyleChanged(_ style: String) {
        let defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
        let bottleOnly = style == FeedingStyle.bottleOnly.rawValue
        guard defaults.object(forKey: WidgetSettings.bottleOnlyKey) as? Bool != bottleOnly else { return }
        defaults.set(bottleOnly, forKey: WidgetSettings.bottleOnlyKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
