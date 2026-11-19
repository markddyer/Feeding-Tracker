import Foundation
import Testing
@testable import FeedingCore

/// Design review D40, eng2 D1 and D3: where the app opens on coming back.
@Suite("Coming back to the app")
struct ReturnRuleTests {
    func outcome(tapped: Bool = false, away: TimeInterval? = 6 * 60, at time: Date, formOpen: Bool = false,
                 zone: TimeZone = london) -> ReturnRule.Outcome {
        ReturnRule.outcome(tapped: tapped, awayFor: away, at: time, dayHours: .standard, timeZone: zone, formOpen: formOpen)
    }

    @Test func atNightAfterFiveMinutesAwayItOpensHome() {
        #expect(outcome(at: at(2026, 11, 20, 3, 0)) == .home)
        #expect(outcome(at: at(2026, 11, 19, 22, 30)) == .home)
    }

    @Test func aShorterTimeAwayOrTheDayLeavesItAsItWas() {
        #expect(outcome(away: 4 * 60, at: at(2026, 11, 20, 3, 0)) == .stay)
        #expect(outcome(away: 5 * 60, at: at(2026, 11, 20, 3, 0)) == .stay)
        #expect(outcome(at: at(2026, 11, 20, 14, 0)) == .stay)
        #expect(outcome(away: nil, at: at(2026, 11, 20, 3, 0)) == .stay)
    }

    /// Eng2 D1: a tap opens its own target, at night too.
    @Test func whatWasTappedWinsAtAnyHour() {
        #expect(outcome(tapped: true, at: at(2026, 11, 20, 3, 0)) == .tapped)
        #expect(outcome(tapped: true, at: at(2026, 11, 20, 14, 0)) == .tapped)
    }

    /// Eng2 D3: a form or panel open stays in front, nothing changes.
    @Test func anOpenFormStaysAsItWas() {
        #expect(outcome(at: at(2026, 11, 20, 3, 0), formOpen: true) == .stay)
    }

    /// The 21:00 and 07:00 boundaries, on the household's clock.
    @Test func theNightHoursDecide() {
        #expect(outcome(at: at(2026, 11, 19, 20, 59)) == .stay)
        #expect(outcome(at: at(2026, 11, 19, 21, 0)) == .home)
        #expect(outcome(at: at(2026, 11, 20, 6, 59)) == .home)
        #expect(outcome(at: at(2026, 11, 20, 7, 0)) == .stay)
    }

    /// Just over 5 minutes counts, exactly 5 doesn't.
    @Test func justOverFiveMinutesCounts() {
        #expect(outcome(away: 300.5, at: at(2026, 11, 20, 3, 0)) == .home)
        #expect(outcome(away: 300, at: at(2026, 11, 20, 3, 0)) == .stay)
    }

    /// The time away is read on the boot clock, kept across a launch, never across a restart.
    @Test func timeAwayIsTheBootClocksAndNeverAcrossARestart() {
        #expect(ReturnRule.timeAway(leftAt: 1_000, leftInBoot: 7, now: 1_400.25, boot: 7) == 400.25)
        #expect(ReturnRule.timeAway(leftAt: 1_000, leftInBoot: 6, now: 1_400, boot: 7) == nil)
        #expect(ReturnRule.timeAway(leftAt: nil, leftInBoot: nil, now: 1_400, boot: 7) == nil)
        #expect(ReturnRule.timeAway(leftAt: 2_000, leftInBoot: 7, now: 1_400, boot: 7) == nil)
    }

    /// Across a clock change (25 Oct 2026, 02:00 back to 01:00: 01:30 happens twice, both at night)
    /// and in a 30-minute zone.
    @Test func clockChangesAndHalfHourZones() {
        let firstOneThirty = Date(timeIntervalSince1970: 1_792_888_200) // 00:30 UTC, 01:30 BST
        let secondOneThirty = firstOneThirty.addingTimeInterval(3_600) // 01:30 UTC, 01:30 GMT
        #expect(outcome(at: firstOneThirty) == .home)
        #expect(outcome(at: secondOneThirty) == .home)
        let adelaide = TimeZone(identifier: "Australia/Adelaide")!
        let adelaideThreeAM = at(2026, 11, 20, 3, 0, in: adelaide)
        #expect(outcome(at: adelaideThreeAM, zone: adelaide) == .home)
        #expect(outcome(at: adelaideThreeAM, zone: london) == .stay)
    }
}
