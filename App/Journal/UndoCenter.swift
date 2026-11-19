import FeedingCore
import SwiftUI
import UIKit

/// The Journal's Undo bar (design review D15), in one place, so it shows on whatever screen is in
/// front (the Journal, History, a first's page or the Firsts list), is read out by VoiceOver, and
/// goes when its Undo does: at its deadline, or when the app leaves the screen, as the store's own
/// hold ends then (Codex review of T7 and T8).
@MainActor
@Observable
final class UndoCenter {
    static let shared = UndoCenter()

    private(set) var action: UndoAction?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    func show(_ action: UndoAction?) {
        self.action = action
        expiry?.cancel()
        guard let action else { return }
        AccessibilityNotification.Announcement("\(action.message). Undo is available.").post()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, action.expiresAt.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.action = nil
        }
    }

    func clear() {
        expiry?.cancel()
        action = nil
    }
}

/// The bar, when there is one.
struct UndoCenterBar: View {
    var body: some View {
        if let action = UndoCenter.shared.action {
            UndoBanner(action: action) { UndoCenter.shared.clear() }
        }
    }
}
