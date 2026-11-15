import Foundation
import Testing
@testable import FeedingCore

/// "Ask the other parent to take a night" (plan v1, "Who gets alerted"; the user's choice of
/// 15 Nov 2026: a card on the other parent's Home, plus an ordinary notification). A request, not
/// a hand-off: the asker stays on duty until the other parent says yes.
@Suite("Asking the other parent to take a night")
struct NightAskTests {
    /// Parent A is on duty on the night of 15 November (rotaFrom13Nov).
    let night = date("2026-11-15")
    let evening = at(2026, 11, 15, 20, 0)

    func household() -> HouseholdData {
        var data = HouseholdData()
        data.setRota(rotaFrom13Nov, by: parentA, now: at(2026, 11, 13, 9, 0))
        return data
    }

    /// Parent A asks Parent B at 20:00.
    func asked() -> HouseholdData {
        var data = household()
        let asked = data.askNight(night, by: parentA, now: evening)
        #expect(asked)
        return data
    }

    @Test func theOtherParentSeesTheAsk() throws {
        let data = asked()
        let ask = try #require(data.nightAsk(for: night))
        #expect(data.nightAskStatus(night: night, me: parentB) == .askedOfMe(ask))
        #expect(data.nightAskStatus(night: night, me: parentA) == .waiting(ask))
    }

    @Test func theAskerStaysOnDuty() {
        let data = asked()
        #expect(data.householdState.onDuty(night: night) == parentA)
        #expect(data.householdState.roster(for: parentB).onDuty(night: night) == parentA)
        #expect(data.pendingChanges.isEmpty)
    }

    @Test func onlyTheParentOnDutyCanAsk() {
        var data = household()
        let asked = data.askNight(night, by: parentB, now: evening)
        #expect(!asked)
        #expect(data.nightAsk(for: night) == nil)
    }

    @Test func noAskWithoutARota() {
        var data = HouseholdData()
        let asked = data.askNight(night, by: parentA, now: evening)
        #expect(!asked)
    }

    @Test func illTakeItMovesTheNight() throws {
        var data = asked()
        let ask = try #require(data.nightAsk(for: night))
        data.claimNight(night, by: parentB, now: evening.addingTimeInterval(60))
        #expect(data.householdState.onDuty(night: night) == parentB)
        #expect(data.nightAskStatus(night: night, me: parentB) == nil)
        #expect(data.nightAskStatus(night: night, me: parentA) == .taken(ask, by: parentB))
    }

    @Test func notTonightKeepsTheAskerOn() throws {
        var data = asked()
        let ask = try #require(data.nightAsk(for: night))
        data.declineAsk(night, by: parentB, now: evening.addingTimeInterval(60))
        #expect(data.householdState.onDuty(night: night) == parentA)
        #expect(data.nightAskStatus(night: night, me: parentB) == nil)
        #expect(data.nightAskStatus(night: night, me: parentA) == .declined(ask, by: parentB))
        // No asking again after "Not tonight".
        let asked = data.askNight(night, by: parentA, now: evening.addingTimeInterval(120))
        #expect(!asked)
        // The reply is not read as an ask.
        #expect(data.nightAsks.count == 1)
    }

    @Test func theAskerCanUndoTheAsk() {
        var data = asked()
        data.withdrawAsk(night, by: parentA, now: evening.addingTimeInterval(5))
        #expect(data.nightAskStatus(night: night, me: parentB) == nil)
        #expect(data.nightAskStatus(night: night, me: parentA) == nil)
        // Only the asker can take it back.
        var other = asked()
        other.withdrawAsk(night, by: parentB, now: evening.addingTimeInterval(5))
        #expect(other.nightAsk(for: night)?.withdrawn == false)
    }

    @Test func aNewAskShowsAgainAfterAnOldNotTonight() throws {
        var data = asked()
        data.declineAsk(night, by: parentB, now: evening.addingTimeInterval(60))
        data.withdrawAsk(night, by: parentA, now: evening.addingTimeInterval(90))
        let asked = data.askNight(night, by: parentA, now: evening.addingTimeInterval(120))
        #expect(asked)
        let ask = try #require(data.nightAsk(for: night))
        #expect(data.nightAskStatus(night: night, me: parentB) == .askedOfMe(ask))
    }

    @Test func takingTheNightBackClosesTheAsk() {
        var data = asked()
        data.claimNight(night, by: parentB, now: evening.addingTimeInterval(60))
        data.claimNight(night, by: parentA, now: evening.addingTimeInterval(120))
        #expect(data.nightAskStatus(night: night, me: parentA) == nil)
        // The card must not come back on Parent B's phone.
        #expect(data.nightAskStatus(night: night, me: parentB) == nil)
    }

    @Test func theNewParentOnDutyCanAskBack() throws {
        var data = asked()
        data.claimNight(night, by: parentB, now: evening.addingTimeInterval(60))
        let asked = data.askNight(night, by: parentB, now: evening.addingTimeInterval(120))
        #expect(asked)
        let ask = try #require(data.nightAsk(for: night))
        #expect(data.nightAskStatus(night: night, me: parentA) == .askedOfMe(ask))
    }

    /// The other phone's clock is a minute slow: its claim looks older than the ask.
    @Test func aClaimFromASlowClockStillAnswersTheAsk() throws {
        var data = asked()
        let ask = try #require(data.nightAsk(for: night))
        data.claimNight(night, by: parentB, now: evening.addingTimeInterval(-50))
        #expect(data.nightAskStatus(night: night, me: parentA) == .taken(ask, by: parentB))
        #expect(data.nightAskStatus(night: night, me: parentB) == nil)
    }

    @Test func eachPhoneIsToldWhatConcernsIt() throws {
        var data = asked()
        let ask = try #require(data.nightAsk(for: night))
        let now = evening.addingTimeInterval(30)
        #expect(data.nightAskNews(me: parentB, now: now) == [.asked(ask)])
        #expect(data.nightAskNews(me: parentA, now: now).isEmpty)

        data.declineAsk(night, by: parentB, now: now)
        #expect(data.nightAskNews(me: parentB, now: now).isEmpty)
        #expect(data.nightAskNews(me: parentA, now: now) == [.declined(ask, by: parentB)])

        // Then Parent B takes the night after all.
        data.claimNight(night, by: parentB, now: now.addingTimeInterval(60))
        #expect(data.nightAskNews(me: parentA, now: now) == [.taken(ask, by: parentB)])
    }

    @Test func newsIDsDifferByOutcome() throws {
        let ask = try #require(asked().nightAsk(for: night))
        let ids = Set([NightAskNews.asked(ask), .taken(ask, by: parentB), .declined(ask, by: parentB)].map(\.id))
        #expect(ids.count == 3)
        #expect(NightAskNews.asked(ask).id.hasPrefix("nightAsk-2026-11-15-"))
    }

    @Test func nothingToTellOnceTheNightIsOver() {
        let data = asked()
        // 07:00 on the 16th: the night of the 15th has ended.
        #expect(data.nightAskNews(me: parentB, now: at(2026, 11, 16, 7, 1)).isEmpty)
        #expect(data.nightAskNews(me: parentB, now: at(2026, 11, 16, 6, 59)).count == 1)
    }

    @Test func tonightIsTheNightOnNowOrComingTonight() {
        let settings = HouseholdSettings()
        #expect(settings.tonight(at: at(2026, 11, 15, 14, 0)) == night)
        #expect(settings.tonight(at: at(2026, 11, 15, 23, 0)) == night)
        #expect(settings.tonight(at: at(2026, 11, 16, 3, 0)) == night)
        #expect(settings.tonight(at: at(2026, 11, 16, 7, 0)) == date("2026-11-16"))
    }

    @Test func anAskFromANewerAppVersionIsIgnored() throws {
        var data = household()
        var payload = SettingPayload(NightAsk(night: night, askedBy: parentA, askedAt: evening))
        payload.v = 99
        data.put(PlainRecord(type: .setting, name: SettingKey.ask(night), modifiedAt: evening,
                             payload: try PayloadCoder.encode(payload)))
        #expect(data.nightAsk(for: night) == nil)
        #expect(data.nightAskStatus(night: night, me: parentB) == nil)
        #expect(data.nightAskNews(me: parentB, now: evening).isEmpty)
    }

    @Test func anAskSurvivesASaveAndALoad() throws {
        var data = asked()
        data.declineAsk(night, by: parentB, now: evening.addingTimeInterval(60))
        let copy = try JSONDecoder().decode(HouseholdData.self, from: JSONEncoder().encode(data))
        let ask = try #require(copy.nightAsk(for: night))
        #expect(copy.nightAskStatus(night: night, me: parentA) == .declined(ask, by: parentB))
    }
}
