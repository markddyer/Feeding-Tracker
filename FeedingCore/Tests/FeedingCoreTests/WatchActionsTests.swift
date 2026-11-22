import Foundation
import Testing
@testable import FeedingCore

/// Step 1 of the watch parity work (`11-watch-parity.md`): the watch's new taps applied on the
/// phone, the phone's answers, and the watch's queue of them.
@Suite("Watch: the new taps")
struct WatchActionsTests {
    let now = at(2026, 11, 21, 22, 40)
    let zone = "Europe/London"

    func household() -> HouseholdData {
        var data = HouseholdData()
        data.put(PlainRecord(type: .baby, name: baby, modifiedAt: now,
                             payload: try? PayloadCoder.encode(BabyPayload(name: "Baby", birthDate: date("2026-11-04")))))
        return data
    }

    func apply(_ data: inout HouseholdData, _ action: WatchAction, at time: Date? = nil, by me: MemberID = parentA,
               applyAt: Date? = nil) -> WatchOutcome {
        data.applyWatchAction(WatchActionRequest(action: action, at: time ?? now), babyID: baby, by: me, timeZoneID: zone,
                              now: applyAt ?? time ?? now)
    }

    @Test func aBathIsLoggedOnceWhateverTimesTheTapArrives() {
        var data = household()
        #expect(apply(&data, .bath(id: "b1")) == .applied)
        #expect(apply(&data, .bath(id: "b1")) == .unchanged)
        #expect(data.events["b1"]?.event.kind == .bath)
        #expect(data.events["b1"]?.event.startedAt == now)
        // Sent at once: the watch has no Undo bar of the phone's kind.
        #expect(data.events["b1"]?.uploadNotBefore == nil)
        #expect(data.lastBath(babyID: baby, now: now) == now)
    }

    @Test func aMedicineIsGivenByName() {
        var data = household()
        #expect(apply(&data, .medicine(id: "m1", name: "Vitamin D")) == .applied)
        #expect(data.events["m1"]?.snapshot.payload?.medicine?.name == "Vitamin D")
    }

    /// Pumping uses the phone's defaults (30 to 10 minutes before), and an amount may be left out.
    @Test func pumpingUsesThePhonesTimesAndMayHaveNoAmount() {
        var data = household()
        #expect(apply(&data, .pump(id: "p1", side: .both, leftML: 60, rightML: nil)) == .applied)
        let event = data.events["p1"]?.event
        #expect(event?.startedAt == now.addingTimeInterval(-30 * 60))
        #expect(event?.endedAt == now.addingTimeInterval(-10 * 60))
        let pump = data.events["p1"]?.snapshot.payload?.pump
        #expect(pump?.side == .both)
        #expect(pump?.leftML == 60)
        #expect(pump?.rightML == nil)
    }

    @Test func pooDetailsSetOnlyWhatIsGiven() {
        var data = household()
        data.addNappy(id: "n1", babyID: baby, wee: true, poo: true, at: now, by: parentA, timeZoneID: zone, now: now)
        #expect(apply(&data, .pooDetails(nappyID: "n1", colour: .yellow, consistency: nil)) == .applied)
        #expect(apply(&data, .pooDetails(nappyID: "n1", colour: nil, consistency: .loose)) == .applied)
        let nappy = data.events["n1"]?.snapshot.payload?.nappy
        #expect(nappy?.colour == .yellow)
        #expect(nappy?.consistency == .loose)
        #expect(apply(&data, .pooDetails(nappyID: "n1", colour: .yellow, consistency: nil)) == .unchanged)
        // A wee only has no poo to describe.
        data.addNappy(id: "n2", babyID: baby, wee: true, poo: false, at: now, by: parentA, timeZoneID: zone, now: now)
        #expect(apply(&data, .pooDetails(nappyID: "n2", colour: .green, consistency: nil)) == .refused)
    }

    @Test func earlierMovesTheEntryOnlyWhileItIsWhatTheTapWrote() {
        var data = household()
        data.addNappy(id: "n1", babyID: baby, wee: true, poo: false, at: now, by: parentA, timeZoneID: zone, now: now)
        #expect(apply(&data, .earlier(id: "n1", minutes: 10, expected: now)) == .applied)
        #expect(data.events["n1"]?.event.startedAt == now.addingTimeInterval(-600))
        // Sent twice, or after a newer change: the start is no longer what the tap wrote.
        #expect(apply(&data, .earlier(id: "n1", minutes: 10, expected: now)) == .refused)
        #expect(data.events["n1"]?.event.startedAt == now.addingTimeInterval(-600))
    }

    @Test func earlierMovesPumpingAsAWhole() {
        var data = household()
        _ = apply(&data, .pump(id: "p1", side: .left, leftML: 40, rightML: nil))
        let start = now.addingTimeInterval(-30 * 60)
        #expect(apply(&data, .earlier(id: "p1", minutes: 20, expected: start)) == .applied)
        #expect(data.events["p1"]?.event.startedAt == start.addingTimeInterval(-1200))
        #expect(data.events["p1"]?.event.endedAt == now.addingTimeInterval(-30 * 60))
    }

    /// Never a feed: moving a feed moves the alarms (step 3), nor another parent's entry.
    @Test func earlierNeverMovesAFeedOrAnotherParentsEntry() {
        var data = household()
        data.add(id: "f1", kind: .feed, babyID: baby, startedAt: now, payload: EventPayload(feed: FeedDetails()), by: parentA,
                 timeZoneID: zone, now: now)
        #expect(apply(&data, .earlier(id: "f1", minutes: 10, expected: now)) == .refused)
        data.addNappy(id: "n1", babyID: baby, wee: true, poo: false, at: now, by: parentB, timeZoneID: zone, now: now)
        #expect(apply(&data, .earlier(id: "n1", minutes: 10, expected: now)) == .refused)
    }

    @Test func doneByIsSetOnce() {
        var data = household()
        data.addNappy(id: "n1", babyID: baby, wee: true, poo: false, at: now, by: parentA, timeZoneID: zone, now: now)
        #expect(apply(&data, .doneBy(id: "n1", member: parentB)) == .applied)
        #expect(data.events["n1"]?.event.doneBy == parentB)
        #expect(apply(&data, .doneBy(id: "n1", member: parentB)) == .unchanged)
    }

    @Test func undoRemovesAnEntryJustLoggedHere() {
        var data = household()
        _ = apply(&data, .bath(id: "b1"))
        #expect(apply(&data, .undo(id: "b1"), at: now.addingTimeInterval(5)) == .applied)
        #expect(data.events["b1"].map { $0.event.deletedAt != nil } ?? true)
        #expect(data.lastBath(babyID: baby, now: now) == nil)
        // Twice: nothing more to do.
        #expect(apply(&data, .undo(id: "b1"), at: now.addingTimeInterval(6)) == .unchanged)
    }

    @Test func undoIsRefusedLateForAnotherParentsEntryAndForAWakeUp() {
        var data = household()
        _ = apply(&data, .medicine(id: "m1", name: "Vitamin D"))
        // A tap kept while the phone was away for half an hour: the entry may have been corrected.
        #expect(apply(&data, .undo(id: "m1"), at: now.addingTimeInterval(1800)) == .refused)
        _ = apply(&data, .bath(id: "b1"), by: parentB)
        #expect(apply(&data, .undo(id: "b1")) == .refused)
        data.startSleep(id: "s1", babyID: baby, startedAt: now, by: parentA, timeZoneID: zone, now: now)
        data.endSleep(babyID: baby, at: now.addingTimeInterval(60), by: parentA, now: now.addingTimeInterval(60))
        #expect(apply(&data, .undo(id: "s1"), at: now.addingTimeInterval(90)) == .refused)
    }

    @Test func aTapTooOldIsRefused() {
        var data = household()
        #expect(apply(&data, .bath(id: "b1"), at: now, applyAt: now.addingTimeInterval(26 * 3600)) == .refused)
        #expect(data.events["b1"] == nil)
    }

    // MARK: What the phone sends

    @Test func theStateSaysWhatThePhoneUnderstandsAndShowsTheNewFacts() {
        var data = household()
        data.setMedicines(["Vitamin D"], now: now)
        _ = apply(&data, .medicine(id: "m1", name: "Vitamin D"))
        _ = apply(&data, .bath(id: "b1"))
        data.addNappy(id: "n1", babyID: baby, wee: false, poo: true, at: now, by: parentA, timeZoneID: zone, now: now)
        _ = apply(&data, .pooDetails(nappyID: "n1", colour: .brown, consistency: .firm))
        let state = data.watchState(me: parentA, names: [parentA: "Alex", parentB: "Sam"],
                                    colours: [parentA: "lavender", parentB: "teal"], bottleOnly: false,
                                    lookSetting: .automatic, results: [WatchResult(id: "r1", outcome: .applied)],
                                    now: now.addingTimeInterval(60))
        #expect(state.understands(WatchCapability.bath))
        #expect(state.medicines == [WatchMedicine(name: "Vitamin D", lastGiven: now)])
        #expect(state.lastBath == now)
        #expect(state.lastNappy?.colour == .brown)
        #expect(state.lastNappy?.consistency == .firm)
        #expect(state.members?.map(\.name) == ["Alex", "Sam"])
        #expect(state.me == parentA)
        #expect(state.result(of: "r1") == .applied)
    }

    /// A state from an older phone (version 2) reads, and understands none of the new taps.
    @Test func anOlderPhonesStateReadsAndUnderstandsNothingNew() throws {
        var old = WatchState(version: 2, madeAt: now, setUp: true, lastFeedStart: now)
        old.capabilities = nil
        let data = try WatchCoding.encode(old)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["capabilities", "results", "medicines", "lastBath", "members", "me"] { json.removeValue(forKey: key) }
        let decoded = try #require(WatchCoding.decode(WatchState.self, from: try JSONSerialization.data(withJSONObject: json)))
        #expect(!decoded.understands(WatchCapability.bath))
        #expect(decoded.lastFeedStart == now)
    }

    // MARK: On the watch

    /// One tap this build can't read (from a newer one) never loses the rest of the queue.
    @Test func theQueueReadsItemByItem() throws {
        let saved = WatchSaved(phone: nil, pending: [], actions: [WatchActionRequest(id: "a1", action: .bath(id: "b1"), at: now)])
        var json = try #require(try JSONSerialization.jsonObject(with: try WatchCoding.encode(saved)) as? [String: Any])
        var actions = try #require(json["actions"] as? [Any])
        actions.insert(["id": "x", "at": now.timeIntervalSince1970, "action": ["fromTheFuture": ["id": "?"]]], at: 0)
        json["actions"] = actions
        let decoded = try #require(WatchCoding.decode(WatchSaved.self, from: try JSONSerialization.data(withJSONObject: json)))
        #expect(decoded.actions.map(\.id) == ["a1"])
    }

    /// A tap stays until the phone has answered it; "waiting" keeps it to send again.
    @Test func aTapStaysUntilAnswered() {
        var phone = WatchState(madeAt: now, setUp: true)
        var saved = WatchSaved(phone: phone, actions: [
            WatchActionRequest(id: "a1", action: .bath(id: "b1"), at: now),
            WatchActionRequest(id: "a2", action: .doneBy(id: "b1", member: parentB), at: now, after: "a1"),
        ])
        #expect(saved.shown?.lastBath == now)
        phone.madeAt = now.addingTimeInterval(1)
        phone.lastBath = now
        phone.results = [WatchResult(id: "a1", outcome: .applied), WatchResult(id: "a2", outcome: .waiting)]
        _ = saved.receive(phone, now: now.addingTimeInterval(2))
        #expect(saved.actions.map(\.id) == ["a2"])
    }

    /// A tap undone before the phone answered it isn't shown.
    @Test func aTapUndoneBeforeTheAnswerIsNotShown() {
        let saved = WatchSaved(phone: WatchState(madeAt: now, setUp: true), actions: [
            WatchActionRequest(id: "a1", action: .bath(id: "b1"), at: now),
            WatchActionRequest(id: "a2", action: .undo(id: "b1"), at: now, after: "a1"),
        ])
        #expect(saved.shown?.lastBath == nil)
    }

    // MARK: The outside review of step 1

    /// The answers are saved in the household file, with the change, and read back (P1).
    @Test func theAnswersSurviveTheFile() throws {
        var data = household()
        data.watchReceipts.record("t1", .applied)
        data.watchReceipts.record("t2", .refused)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let read = try decoder.decode(HouseholdData.self, from: encoder.encode(data))
        #expect(read.watchReceipts == data.watchReceipts)
        #expect(read.keptParts.isEmpty)
        // A phone with none writes nothing for them.
        let empty = try JSONSerialization.jsonObject(with: encoder.encode(household())) as? [String: Any]
        #expect(empty?["watchReceipts"] == nil)
    }

    /// An answer a newer build wrote that this one can't read is left out, not the rest.
    @Test func anUnknownAnswerIsLeftOutNotTheRest() throws {
        let json = #"[{"id":"t1","outcome":"applied"},{"id":"t2","outcome":"someday"},{"id":"t3","outcome":"refused"}]"#
        let read = try JSONDecoder().decode(WatchReceipts.self, from: Data(json.utf8))
        #expect(read.results.map(\.id) == ["t1", "t3"])
    }

    /// The list an earlier build kept outside the file comes across once, so no old tap is applied again.
    @Test func theEarlierListComesAcross() {
        let receipts = WatchReceipts.earlier(handled: ["t1", "t2", "t3"],
                                             results: [WatchResult(id: "t2", outcome: .refused),
                                                       WatchResult(id: "t3", outcome: .waiting)])
        #expect(receipts.outcome(of: "t1") == .applied)
        #expect(receipts.outcome(of: "t2") == .refused)
        #expect(receipts.outcome(of: "t3") == .applied)
    }

    /// A tap that arrives again after its answer left the latest 30 is answered again, once, last;
    /// one still waiting isn't counted as handled (P2).
    @Test func anAnswerGivenAgainIsToldLast() {
        var receipts = WatchReceipts()
        for number in 0..<40 { receipts.record("tap-\(number)", .applied) }
        let told = receipts.told([WatchResult(id: "tap-2", outcome: .applied), WatchResult(id: "x", outcome: .waiting)])
        #expect(told.results.last?.id == "x")
        #expect(told.results.filter { $0.id == "tap-2" }.count == 1)
        #expect(told.handled.contains("tap-2"))
        #expect(!told.handled.contains("x"))
        // Asked again for one in the latest 30: still told once.
        let again = receipts.told([WatchResult(id: "tap-39", outcome: .applied)])
        #expect(again.results.filter { $0.id == "tap-39" }.count == 1)
    }

    /// A Fell asleep turned down because another sleep runs is "Not saved", not "logged"; the same
    /// tap arriving twice is "unchanged" (P2).
    @Test func aFellAsleepTurnedDownIsRefused() {
        var data = household()
        data.startSleep(id: "s0", babyID: baby, startedAt: now.addingTimeInterval(-600), by: parentB, timeZoneID: zone,
                        now: now.addingTimeInterval(-600))
        let late = WatchRequest(command: .fellAsleep(sleepID: "s1"), at: now)
        #expect(data.applyWatchRequest(late, babyID: baby, by: parentA, timeZoneID: zone) == .refused)
        #expect(data.events["s1"] == nil)
        let first = WatchRequest(command: .nappy(nappyID: "n1", wee: true, poo: false), at: now)
        #expect(data.applyWatchRequest(first, babyID: baby, by: parentA, timeZoneID: zone) == .applied)
        #expect(data.applyWatchRequest(first, babyID: baby, by: parentA, timeZoneID: zone) == .unchanged)
    }

    /// A Finish for a feed already finished is "unchanged"; for one removed, "refused".
    @Test func aFinishSaysWhetherTheFeedWasFinished() {
        var data = household()
        let start = WatchRequest(command: .start(feedID: "f1", bottle: nil, bottleID: "b"), at: now)
        #expect(data.applyWatchRequest(start, babyID: baby, by: parentA, timeZoneID: zone) == .applied)
        let finish = WatchRequest(command: .finish(feedID: "f1"), at: now.addingTimeInterval(600))
        #expect(data.applyWatchRequest(finish, babyID: baby, by: parentA, timeZoneID: zone) == .applied)
        #expect(data.applyWatchRequest(finish, babyID: baby, by: parentA, timeZoneID: zone) == .unchanged)
        let gone = WatchRequest(command: .finish(feedID: "nothing"), at: now)
        #expect(data.applyWatchRequest(gone, babyID: baby, by: parentA, timeZoneID: zone) == .refused)
    }

    /// A nappy or Fell asleep undone before the phone heard isn't shown (P2).
    @Test func anUndoneNappyOrSleepIsNotShownWhileWaiting() {
        var phone = WatchState(madeAt: now, setUp: true)
        phone.lastNappy = WatchNappy(id: "old", at: now.addingTimeInterval(-3600), wee: true, poo: false)
        let nappy = WatchRequest(command: .nappy(nappyID: "n1", wee: false, poo: true), at: now)
        let sleep = WatchRequest(command: .fellAsleep(sleepID: "s1"), at: now)
        let saved = WatchSaved(phone: phone, pending: [nappy, sleep], actions: [
            WatchActionRequest(action: .undo(id: "n1"), at: now, after: nappy.id),
            WatchActionRequest(action: .undo(id: "s1"), at: now, after: sleep.id),
        ])
        #expect(saved.shown?.lastNappy?.id == "old")
        #expect(saved.shown?.sleep == nil)
    }

    /// Earlier moves a bath's or a medicine's time on the watch at once, only while it is still the
    /// tap's (P3).
    @Test func earlierMovesABathOrMedicineShownAtTheTap() {
        var state = WatchState(madeAt: now, setUp: true)
        state.lastBath = now
        state.medicines = [WatchMedicine(name: "Vitamin D", lastGiven: now),
                           WatchMedicine(name: "Other", lastGiven: now.addingTimeInterval(120))]
        let moved = state.applying(WatchActionRequest(action: .earlier(id: "b1", minutes: 20, expected: now), at: now))
        #expect(moved.lastBath == now.addingTimeInterval(-1200))
        #expect(moved.medicines?[0].lastGiven == now.addingTimeInterval(-1200))
        #expect(moved.medicines?[1].lastGiven == now.addingTimeInterval(120))
    }

    /// Details added to the last nappy don't change what the watch face shows (P3).
    @Test func nappyDetailsAreNotOnTheFace() {
        let plain = WatchNappy(id: "n1", at: now, wee: false, poo: true)
        let detailed = WatchNappy(id: "n1", at: now, wee: false, poo: true, colour: .yellow, consistency: .loose, doneBy: parentB)
        #expect(plain.onFace == detailed.onFace)
    }
}
