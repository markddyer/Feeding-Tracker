import FeedingCore
import Foundation
import WidgetKit

/// Tells the Lock Screen widgets and the controls to read the household again, only when what
/// they show has changed (a feed, sleep or nappy started, finished, added or deleted), so iOS's
/// limit on reloads isn't spent on other changes.
@MainActor
final class WidgetRefresher {
    private struct Shown: Hashable {
        var feed: FeedGlance?
        var care: CareGlance?
    }

    private var shown: Shown?

    func update(_ data: HouseholdData, now: Date = Date()) {
        let glance = Shown(feed: data.glance(now: now), care: data.careGlance(now: now))
        guard shown != glance else { return }
        shown = glance
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
