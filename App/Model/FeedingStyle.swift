import Foundation

/// How this parent feeds, chosen once on their own phone and changeable in Settings. It changes
/// only the buttons on this phone: a "bottle only" parent gets no Left and Right buttons, and
/// Start feed starts a bottle. The other phone and the shared log are not affected.
/// (The user's decision, 14 Nov 2026: side buttons make no sense for a parent who can't breastfeed.)
enum FeedingStyle: String, CaseIterable {
    case breastAndBottle
    case bottleOnly

    /// Kept as a plain string under this key; empty means not chosen yet.
    static let storageKey = "setup.feedingStyle"

    var title: String {
        switch self {
        case .breastAndBottle: "Breast and bottle"
        case .bottleOnly: "Bottle only"
        }
    }
}
