import Foundation
import Testing
@testable import FeedingCore

@Suite("Payloads: encoding and versions")
struct PayloadTests {
    let start = at(2026, 11, 14, 10, 0)

    var fullFeed: EventPayload {
        var payload = EventPayload(
            feed: FeedDetails(
                breast: [BreastSegment(id: "s1", side: .left, startedAt: start, durationSeconds: 600),
                         BreastSegment(id: "s2", side: .right, durationSeconds: 480)],
                bottles: [Bottle(id: "b1", milk: .expressed, ml: 60), Bottle(id: "b2", milk: .formula)]),
            note: "Sleepy")
        payload.setStamp(.bottles, FieldStamp(at: start.addingTimeInterval(900), by: parentB))
        return payload
    }

    @Test func aFeedRoundTrips() throws {
        let data = try PayloadCoder.encode(fullFeed)
        #expect(PayloadCoder.decode(EventPayload.self, from: data) == fullFeed)
    }

    @Test func aPumpRoundTrips() throws {
        let payload = EventPayload(pump: PumpDetails(side: .both, leftML: 50, rightML: 40))
        let decoded = PayloadCoder.decode(EventPayload.self, from: try PayloadCoder.encode(payload))
        #expect(decoded == payload)
        #expect(decoded?.pump?.totalML == 90)
    }

    @Test func theSameValueGivesTheSameBytes() throws {
        #expect(try PayloadCoder.encode(fullFeed) == PayloadCoder.encode(fullFeed))
        let text = String(decoding: try PayloadCoder.encode(EventPayload(note: "x")), as: UTF8.self)
        #expect(text == #"{"note":"x","stamps":{},"v":1}"#)
    }

    @Test func millisecondsAreKept() throws {
        let precise = Date(timeIntervalSince1970: 1_794_650_000.25)
        var payload = EventPayload()
        payload.setStamp(.note, FieldStamp(at: precise, by: parentA))
        let decoded = PayloadCoder.decode(EventPayload.self, from: try PayloadCoder.encode(payload))
        let seconds = try #require(decoded?.stamp(.note)?.at.timeIntervalSince1970)
        #expect(abs(seconds - precise.timeIntervalSince1970) < 0.001)
    }

    @Test func aNewerVersionIsNotRead() {
        #expect(PayloadCoder.decode(EventPayload.self, from: Data(#"{"v":3,"stamps":{}}"#.utf8)) == nil)
    }

    @Test func unknownFieldsInTheSameVersionAreSkipped() {
        let json = #"{"v":1,"note":"hi","mood":"calm","stamps":{"mood":{"at":1794650000000,"by":"parent-b"}}}"#
        let decoded = PayloadCoder.decode(EventPayload.self, from: Data(json.utf8))
        #expect(decoded?.note == "hi")
        #expect(decoded?.stamps["mood"]?.by == parentB)
    }

    @Test func missingOrBrokenPayloadsAreNotRead() {
        #expect(PayloadCoder.decode(EventPayload.self, from: nil) == nil)
        #expect(PayloadCoder.decode(EventPayload.self, from: Data("not json".utf8)) == nil)
        #expect(PayloadCoder.decode(EventPayload.self, from: Data(#"{"note":"no version"}"#.utf8)) == nil)
    }

    @Test func aSnapshotReadsAndWritesItsEvent() throws {
        let saved = try snapshot(start, id: "e1", payload: fullFeed).encoded()
        #expect(saved.payload != nil)
        let reread = EventSnapshot(event: saved)
        #expect(reread.payload == fullFeed)
        #expect(reread.id == "e1")
    }

    @Test func babyAndMemberRoundTrip() throws {
        let babyPayload = BabyPayload(name: "Baby", birthDate: date("2026-11-01"))
        let data = try PayloadCoder.encode(babyPayload)
        #expect(String(decoding: data, as: UTF8.self).contains(#""birthDate":"2026-11-01""#))
        #expect(PayloadCoder.decode(BabyPayload.self, from: data) == babyPayload)
        let member = MemberPayload(displayName: "Parent A", colour: "amber")
        #expect(PayloadCoder.decode(MemberPayload.self, from: try PayloadCoder.encode(member)) == member)
    }

    @Test func bottleTotalsSkipMissingAmounts() {
        let feed = FeedDetails(bottles: [Bottle(milk: .formula, ml: 30), Bottle(milk: .formula), Bottle(milk: .expressed, ml: 20)])
        #expect(feed.ml(of: .formula) == 30)
        #expect(feed.ml(of: .expressed) == 20)
    }
}

@Suite("Merging two phones' edits")
struct MergeTests {
    let start = at(2026, 11, 14, 10, 0)
    let base = snapshot(at(2026, 11, 14, 10, 0), id: "e1", payload: breast(.left))

    func stamped(_ snapshot: EventSnapshot, _ field: EventField, at time: Date, by member: MemberID,
                 edit: (inout EventSnapshot) -> Void) -> EventSnapshot {
        var copy = snapshot
        edit(&copy)
        copy.payload?.setStamp(field, FieldStamp(at: time, by: member))
        copy.event.modifiedAt = time
        return copy
    }

    /// Round 2, S5: Parent A corrects the start time while Parent B adds a bottle to an old copy.
    @Test func editsToDifferentFieldsAreBothKept() {
        let server = stamped(base, .bottles, at: at(2026, 11, 14, 10, 20), by: parentB) {
            $0.payload?.feed?.bottles = [Bottle(milk: .formula, ml: 30)]
        }
        let local = stamped(base, .startedAt, at: at(2026, 11, 14, 10, 15), by: parentA) {
            $0.event.startedAt = at(2026, 11, 14, 9, 55)
        }
        let result = merge(local: local, server: server, changedLocally: [.startedAt])
        #expect(result.snapshot.event.startedAt == at(2026, 11, 14, 9, 55))
        #expect(result.snapshot.payload?.feed?.bottles.first?.ml == 30)
        #expect(result.snapshot.payload?.feed?.breast.first?.side == .left)
        #expect(result.applied == [.startedAt])
        #expect(result.snapshot.event.modifiedAt == at(2026, 11, 14, 10, 20))
    }

    @Test func theLaterEditOfTheSameFieldWins() {
        let server = stamped(base, .bottles, at: at(2026, 11, 14, 10, 20), by: parentB) {
            $0.payload?.feed?.bottles = [Bottle(milk: .formula, ml: 30)]
        }
        let laterLocal = stamped(base, .bottles, at: at(2026, 11, 14, 10, 25), by: parentA) {
            $0.payload?.feed?.bottles = [Bottle(milk: .expressed, ml: 40)]
        }
        let won = merge(local: laterLocal, server: server, changedLocally: [.bottles])
        #expect(won.snapshot.payload?.feed?.bottles.first?.ml == 40)
        #expect(won.snapshot.payload?.stamp(.bottles)?.by == parentA)

        let earlierLocal = stamped(base, .bottles, at: at(2026, 11, 14, 10, 18), by: parentA) {
            $0.payload?.feed?.bottles = [Bottle(milk: .expressed, ml: 40)]
        }
        let lost = merge(local: earlierLocal, server: server, changedLocally: [.bottles])
        #expect(lost.snapshot.payload?.feed?.bottles.first?.ml == 30)
        #expect(lost.overruled == [.bottles])
        #expect(lost.applied.isEmpty)
    }

    @Test func aTieGoesTheSameWayOnBothPhones() {
        let time = at(2026, 11, 14, 10, 20)
        let byA = stamped(base, .note, at: time, by: parentA) { $0.payload?.note = "from A" }
        let byB = stamped(base, .note, at: time, by: parentB) { $0.payload?.note = "from B" }
        let onPhoneA = merge(local: byA, server: byB, changedLocally: [.note])
        let onPhoneB = merge(local: byB, server: byA, changedLocally: [.note])
        #expect(onPhoneA.snapshot.payload?.note == "from B")
        #expect(onPhoneB.snapshot.payload?.note == "from B")
    }

    @Test func aDeleteSurvivesAnEditOnTheOtherPhone() {
        let deletedAt = at(2026, 11, 14, 10, 30)
        let server = stamped(base, .deletedAt, at: deletedAt, by: parentB) { $0.event.deletedAt = deletedAt }
        let local = stamped(base, .note, at: at(2026, 11, 14, 10, 31), by: parentA) { $0.payload?.note = "Sleepy" }
        let result = merge(local: local, server: server, changedLocally: [.note])
        #expect(result.snapshot.event.deletedAt == deletedAt)
        #expect(result.snapshot.payload?.note == "Sleepy")
    }

    @Test func aLaterUndoBringsADeletedFeedBack() {
        let deletedAt = at(2026, 11, 14, 10, 30)
        let server = stamped(base, .deletedAt, at: deletedAt, by: parentB) { $0.event.deletedAt = deletedAt }
        let undone = stamped(base, .deletedAt, at: at(2026, 11, 14, 10, 32), by: parentA) { $0.event.deletedAt = nil }
        #expect(merge(local: undone, server: server, changedLocally: [.deletedAt]).snapshot.event.deletedAt == nil)
    }

    @Test func fieldsThisPhoneDidNotChangeKeepTheServerValue() {
        let server = stamped(base, .note, at: at(2026, 11, 14, 10, 20), by: parentB) { $0.payload?.note = "from B" }
        var local = base
        local.payload?.note = "stale copy"
        let result = merge(local: local, server: server, changedLocally: [])
        #expect(result.snapshot == EventSnapshot(event: server.event, payload: server.payload))
    }

    @Test func anUnreadableServerCopyIsKeptWhole() {
        var server = base
        server.payload = nil
        let local = stamped(base, .note, at: at(2026, 11, 14, 10, 20), by: parentA) { $0.payload?.note = "mine" }
        let result = merge(local: local, server: server, changedLocally: [.note])
        #expect(result.keptServerCopyUnread)
        #expect(result.snapshot == server)
        #expect(result.overruled == [.note])
    }

    @Test func aChangeWithoutAStampDoesNotWin() {
        var local = base
        local.event.endedAt = at(2026, 11, 14, 10, 40)
        let result = merge(local: local, server: base, changedLocally: [.endedAt])
        #expect(result.snapshot.event.endedAt == nil)
        #expect(result.overruled == [.endedAt])
    }
}
