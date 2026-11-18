import Foundation
import Testing
@testable import FeedingDev

/// The sync engine's list of records to send: an entry with nothing to send comes off it, as
/// Apple asks; one held for Undo stays (found on the owner's phone, 18 Nov 2026: such entries
/// piled up for good, 6 to 9 of them).
@Suite("The engine's list of records to send")
struct SendListTests {
    let now = Date(timeIntervalSince1970: 1_794_650_000)

    @Test func aChangeWaitingToGoIsSent() {
        #expect(HouseholdSync.sendDecision(needsUpload: true, uploadNotBefore: nil, now: now) == .send)
        #expect(HouseholdSync.sendDecision(needsUpload: true, uploadNotBefore: now, now: now) == .send)
    }

    @Test func aChangeHeldForUndoStaysOnTheList() {
        #expect(HouseholdSync.sendDecision(needsUpload: true, uploadNotBefore: now.addingTimeInterval(5), now: now) == .hold)
    }

    /// Already sent, or replaced by the other phone's copy after a clash.
    @Test func anEntryWithNothingToSendComesOff() {
        #expect(HouseholdSync.sendDecision(needsUpload: false, uploadNotBefore: nil, now: now) == .drop)
        #expect(HouseholdSync.sendDecision(needsUpload: false, uploadNotBefore: now.addingTimeInterval(5), now: now) == .drop)
    }
}
