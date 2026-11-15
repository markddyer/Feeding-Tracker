import Foundation
import Testing
@testable import FeedingCore

/// "Both phones tonight" (the user's choice of 15 Nov 2026): gives a taken night back, so both
/// phones alert. It only adds alerting, so it is safe at once.
@Suite("Both phones tonight")
struct BothPhonesTests {
    let night = date("2026-11-15")
    let evening = at(2026, 11, 15, 20, 0)

    /// No rota. Parent A asks at 20:00 and Parent B takes the night at 20:05.
    func takenByB(rota: Rota? = nil) -> HouseholdData {
        var data = HouseholdData()
        if let rota { data.setRota(rota, by: parentA, now: at(2026, 11, 13, 9, 0)) }
        let asked = data.askNight(night, by: parentA, now: evening)
        #expect(asked)
        data.claimNight(night, by: parentB, now: evening.addingTimeInterval(.minutes(5)))
        return data
    }

    /// Who this phone's alerts treat as on duty on `night`.
    func alertsOnDuty(_ data: HouseholdData, phone: MemberID) -> MemberID {
        data.householdState.roster(for: phone).onDuty(night: night)
    }

    @Test func withNoRotaItGivesTheNightBackToBothPhones() {
        var data = takenByB()
        #expect(alertsOnDuty(data, phone: parentA) == parentB)
        data.setBothPhones(night, by: parentA, now: evening.addingTimeInterval(.minutes(10)))
        #expect(data.householdState.onDuty(night: night) == nil)
        #expect(data.householdState.claim(for: night) == nil)
        #expect(alertsOnDuty(data, phone: parentA) == parentA)
        #expect(alertsOnDuty(data, phone: parentB) == parentB)
        #expect(data.pendingChanges.isEmpty)
    }

    @Test func theParentWhoTookTheNightCanTapItToo() {
        var data = takenByB()
        data.setBothPhones(night, by: parentB, now: evening.addingTimeInterval(.minutes(10)))
        #expect(alertsOnDuty(data, phone: parentA) == parentA)
        #expect(alertsOnDuty(data, phone: parentB) == parentB)
    }

    /// The other phone hears late: until then it stays as it was, so the phone that had the
    /// night is on at every moment, and nothing goes quiet.
    @Test func itNeverLeavesTheNightWithoutAPhone() {
        let before = takenByB()
        var after = before
        after.setBothPhones(night, by: parentA, now: evening.addingTimeInterval(.minutes(10)))
        for phoneB in [before, after] {
            #expect(alertsOnDuty(phoneB, phone: parentB) == parentB)
        }
        #expect(alertsOnDuty(after, phone: parentA) == parentA)
    }

    @Test func withARotaBothPhonesAlertToo() {
        // Parent A is on duty on 15 Nov by the rota; Parent B took it.
        var data = takenByB(rota: rotaFrom13Nov)
        #expect(alertsOnDuty(data, phone: parentA) == parentB)
        data.setBothPhones(night, by: parentB, now: evening.addingTimeInterval(.minutes(10)))
        #expect(data.householdState.onDuty(night: night) == nil)
        #expect(alertsOnDuty(data, phone: parentA) == parentA)
        #expect(alertsOnDuty(data, phone: parentB) == parentB)
    }

    @Test func aLaterClaimDecidesTheNightAgain() {
        var data = takenByB()
        data.setBothPhones(night, by: parentA, now: evening.addingTimeInterval(.minutes(10)))
        data.claimNight(night, by: parentA, now: evening.addingTimeInterval(.minutes(20)))
        #expect(data.householdState.onDuty(night: night) == parentA)
        #expect(alertsOnDuty(data, phone: parentB) == parentA)
    }

    @Test func onATieBothPhonesAlert() {
        var data = HouseholdData()
        data.claimNight(night, by: parentB, now: evening)
        data.setBothPhones(night, by: parentA, now: evening)
        #expect(data.householdState.onDuty(night: night) == nil)
        #expect(alertsOnDuty(data, phone: parentA) == parentA)
    }

    @Test func otherNightsAreNotTouched() {
        var data = takenByB(rota: rotaFrom13Nov)
        data.setBothPhones(night, by: parentA, now: evening.addingTimeInterval(.minutes(10)))
        let tomorrow = date("2026-11-16")
        #expect(data.householdState.onDuty(night: tomorrow) == parentB)
        #expect(data.householdState.roster(for: parentA).onDuty(night: tomorrow) == parentB)
    }

    /// End to end: the phone that gave the night away gets the night alerts back.
    @Test func reconcileGivesThisPhoneTheNightAlertsAgain() {
        var data = takenByB()
        let lastFeed = feed(at(2026, 11, 15, 21, 30))
        let now = at(2026, 11, 15, 21, 45)
        func alertsForA() -> [String] {
            let state = data.householdState
            return summary(reconcile(events: [lastFeed], settings: state.settings, roster: state.roster(for: parentA),
                                     pendingChanges: state.pendingChanges, me: Me(id: parentA), now: now))
        }
        #expect(!alertsForA().contains { $0.hasPrefix("windowCloses") })
        data.setBothPhones(night, by: parentA, now: at(2026, 11, 15, 21, 40))
        #expect(alertsForA().contains { $0.hasPrefix("windowCloses") })
    }

    // MARK: The ask

    @Test func itClosesTheAskAndTheParentCanAskAgain() throws {
        var data = takenByB()
        data.setBothPhones(night, by: parentA, now: evening.addingTimeInterval(.minutes(10)))
        #expect(data.nightAskStatus(night: night, me: parentA) == nil)
        #expect(data.nightAskStatus(night: night, me: parentB) == nil)
        #expect(data.nightAskNews(me: parentB, now: evening.addingTimeInterval(.minutes(11))).isEmpty)

        let askedAgain = data.askNight(night, by: parentA, now: evening.addingTimeInterval(.minutes(15)))
        #expect(askedAgain)
        let ask = try #require(data.nightAsk(for: night))
        #expect(data.nightAskStatus(night: night, me: parentB) == .askedOfMe(ask))
    }

    // MARK: Undo for "I'll take it"

    @Test func undoBeforeSendingRemovesTheClaim() {
        var data = HouseholdData()
        data.claimNight(night, by: parentA, now: evening)
        data.undoTake(night, by: parentA, now: evening.addingTimeInterval(5))
        #expect(data.nightClaims.isEmpty)
        #expect(data.bothPhonesNights.isEmpty)
    }

    @Test func undoAfterSendingTurnsOnBothPhones() {
        var data = HouseholdData()
        data.claimNight(night, by: parentA, now: evening)
        data.didUploadPlainRecord("Setting/night-2026-11-15", sentRevision: 1, systemFields: Data([1]))
        data.undoTake(night, by: parentA, now: evening.addingTimeInterval(5))
        #expect(data.householdState.onDuty(night: night) == nil)
        #expect(alertsOnDuty(data, phone: parentB) == parentB)
        #expect(alertsOnDuty(data, phone: parentA) == parentA)
    }

    @Test func undoDoesNothingOnceTheOtherParentTookTheNight() {
        var data = HouseholdData()
        data.claimNight(night, by: parentA, now: evening)
        data.didUploadPlainRecord("Setting/night-2026-11-15", sentRevision: 1, systemFields: Data([1]))
        data.claimNight(night, by: parentB, now: evening.addingTimeInterval(3))
        data.undoTake(night, by: parentA, now: evening.addingTimeInterval(5))
        #expect(data.householdState.onDuty(night: night) == parentB)
        #expect(data.bothPhonesNights.isEmpty)
    }

    @Test func itSurvivesASaveAndALoad() throws {
        var data = takenByB()
        data.setBothPhones(night, by: parentA, now: evening.addingTimeInterval(.minutes(10)))
        let copy = try JSONDecoder().decode(HouseholdData.self, from: JSONEncoder().encode(data))
        #expect(copy.householdState.onDuty(night: night) == nil)
        #expect(copy.householdState.roster(for: parentA).onDuty(night: night) == parentA)
    }
}
