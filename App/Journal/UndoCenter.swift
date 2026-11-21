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
        // The card itself reads it out when it comes (`UndoCard`).
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

    /// Closes the bar only if it is still `id`'s: an Undo that couldn't be saved shows a new bar.
    func clear(ifStill id: UUID) {
        guard action?.id == id else { return }
        clear()
    }
}

extension View {
    /// The Journal's Undo, as the Undo card at the top of the screen in front (DD7).
    func undoCenterCard() -> some View {
        undoCard(UndoCenter.shared.action) { UndoCenter.shared.clear(ifStill: $0.id) }
    }
}
