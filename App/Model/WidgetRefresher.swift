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
    /// The medicine names Siri last heard of (`docs/planning/15-hands-free-siri.md`).
    private var medicines: [String]?

    func update(_ data: HouseholdData, now: Date = Date()) {
        // "Log Vitamin D in Little Log": Siri's phrases follow the list, changed here or on the
        // other phone (Codex review of doc 15, 9).
        if medicines != data.medicines {
            medicines = data.medicines
            FeedingShortcuts.updateAppShortcutParameters()
        }
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
