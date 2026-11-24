import Foundation
import Testing
@testable import FeedingDev

/// The Journal's and History's Undo bar goes at its own deadline, not at a later screen refresh
/// (journal plan, outside voice OV9; task T20).
@MainActor
@Suite("The Journal's Undo bar")
struct UndoCenterTests {
    @Test func theBarGoesAtItsOwnDeadline() async throws {
        let center = UndoCenter()
        center.show(UndoAction(message: "First smile saved", expiresAt: Date().addingTimeInterval(0.3)) {})
        #expect(center.action != nil)
        try await Task.sleep(for: .seconds(1))
        #expect(center.action == nil)
    }

    /// A newer bar is never closed by the older one's deadline, or by the older one's own close.
    @Test func aNewerBarOutlivesTheOlderOnesDeadline() async throws {
        let center = UndoCenter()
        let older = UndoAction(message: "First smile saved", expiresAt: Date().addingTimeInterval(0.3)) {}
        center.show(older)
        let newer = UndoAction(message: "First laugh saved", expiresAt: Date().addingTimeInterval(30)) {}
        center.show(newer)
        try await Task.sleep(for: .seconds(1))
        #expect(center.action?.id == newer.id)
        center.clear(ifStill: older.id)
        #expect(center.action?.id == newer.id)
    }
}
