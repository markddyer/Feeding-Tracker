import Foundation
import Testing
@testable import FeedingCore

@Suite("The household store: changes on this phone")
struct StoreEditTests {
    let t0 = at(2026, 11, 14, 10, 0)

    func newFeed(side: BreastSide? = .left) -> (HouseholdData, String) {
        var data = HouseholdData()
        let id = data.startFeed(id: "f1", babyID: baby, side: side, by: parentA, timeZoneID: "Europe/London", now: t0)
        return (data, id)
    }

    @Test func aLiveFeedTimesEachSide() throws {
        var (data, id) = newFeed()
        #expect(data.feedInProgress(babyID: baby)?.id == id)
        data.switchSide(id, to: .right, by: parentA, now: t0.addingTimeInterval(.minutes(12)))
        data.finishFeed(id, by: parentA, now: t0.addingTimeInterval(.minutes(20)))
        let feed = try #require(data.events[id]?.snapshot)
        #expect(feed.payload?.feed?.breast.map(\.side) == [.left, .right])
        #expect(feed.payload?.feed?.breast.map(\.durationSeconds) == [720, 480])
        #expect(feed.event.endedAt == t0.addingTimeInterval(.minutes(20)))
        #expect(data.feedInProgress(babyID: baby) == nil)
        #expect(feed.event.loggedBy == parentA)
    }

    /// A parent who feeds by bottle only starts a feed that already has its bottle; the amount
    /// comes after Finish.
    @Test func aBottleFeedStartsWithItsBottle() throws {
        var data = HouseholdData()
        let id = data.startFeed(babyID: baby, side: nil, bottle: .formula, by: parentB, timeZoneID: "Europe/London", now: t0)
        data.finishFeed(id, by: parentB, now: t0.addingTimeInterval(.minutes(15)))
        let feed = try #require(data.events[id]?.snapshot.payload?.feed)
        #expect(feed.breast.isEmpty)
        #expect(feed.bottles.map(\.milk) == [.formula])
        #expect(feed.bottles.map(\.ml) == [nil])
    }

    @Test func aNewEventWaitsOutItsUndoWindow() {
        var (data, id) = newFeed()
        #expect(data.eventsToUpload(now: t0.addingTimeInterval(9)).isEmpty)
        #expect(data.eventsToUpload(now: t0.addingTimeInterval(10)).map(\.event.id) == [id])
        data.endUndoWindows()
        #expect(data.eventsToUpload(now: t0).map(\.event.id) == [id])
    }

    @Test func undoTakesBackANewEventOnlyBeforeItIsSent() {
        var (data, id) = newFeed()
        let undone = data.undoAdd(id, now: t0.addingTimeInterval(5))
        #expect(undone)
        #expect(data.events.isEmpty)

        var (sent, sentID) = newFeed()
        sent.didUploadEvent(sentID, sentRevision: 1, systemFields: Data([1]), serverCreatedAt: t0)
        let undoneAfterSending = sent.undoAdd(sentID, now: t0.addingTimeInterval(5))
        #expect(!undoneAfterSending)

        var (late, lateID) = newFeed()
        let undoneTooLate = late.undoAdd(lateID, now: t0.addingTimeInterval(11))
        #expect(!undoneTooLate)
        #expect(late.events[lateID] != nil)
    }

    @Test func anEditStampsOnlyTheFieldsItChanged() throws {
        var (data, id) = newFeed()
        data.didUploadEvent(id, sentRevision: 1, systemFields: Data([1]), serverCreatedAt: t0)
        #expect(data.events[id]?.changedFields == [])
        let later = t0.addingTimeInterval(.minutes(30))
        data.edit(id, by: parentB, now: later) { $0.payload?.feed?.bottles = [Bottle(milk: .formula, ml: 30)] }
        let stored = try #require(data.events[id])
        #expect(stored.changedFields == [.bottles])
        #expect(stored.needsUpload)
        #expect(stored.snapshot.payload?.stamp(.bottles) == FieldStamp(at: later, by: parentB))
        #expect(stored.snapshot.payload?.stamp(.note) == FieldStamp(at: t0, by: parentA))
        #expect(stored.event.modifiedAt == later)
        #expect(stored.event.loggedBy == parentA)
    }

    @Test func anEditThatChangesNothingMarksNothing() {
        var (data, id) = newFeed()
        data.didUploadEvent(id, sentRevision: 1, systemFields: Data([1]), serverCreatedAt: t0)
        let accepted = data.edit(id, by: parentA, now: t0) { _ in }
        #expect(accepted)
        #expect(data.events[id]?.needsUpload == false)
    }

    @Test func deleteHidesAndRestoreBringsBack() {
        var (data, id) = newFeed()
        data.delete(id, by: parentA, now: t0.addingTimeInterval(60))
        #expect(data.events[id]?.event.deletedAt == t0.addingTimeInterval(60))
        #expect(data.feedInProgress(babyID: baby) == nil)
        data.restore(id, by: parentA, now: t0.addingTimeInterval(120))
        #expect(data.events[id]?.event.deletedAt == nil)
    }

    @Test func detailsFromANewerAppCannotBeEdited() {
        var data = HouseholdData()
        let newer = Event(id: "n1", babyID: baby, kind: .feed, startedAt: t0, timeZoneID: "Europe/London", loggedBy: parentB,
                          createdAt: t0, modifiedAt: t0, payload: Data(#"{"v":9,"stamps":{}}"#.utf8))
        data.receiveEvent(newer, systemFields: Data([1]))
        let deleted = data.delete("n1", by: parentA, now: t0)
        #expect(!deleted)
        #expect(data.events["n1"]?.event.deletedAt == nil)
        let editedUnknown = data.edit("unknown", by: parentA, now: t0) { _ in }
        #expect(!editedUnknown)
    }

    @Test func plainRecordsKeepTheLatestCopy() {
        var data = HouseholdData()
        data.put(PlainRecord(type: .setting, name: "feedWindow", modifiedAt: t0, payload: Data([1])))
        #expect(data.plainRecordsToUpload().count == 1)
        // An older copy from iCloud doesn't beat a newer waiting change.
        data.receivePlainRecord(PlainRecord(type: .setting, name: "feedWindow", modifiedAt: t0.addingTimeInterval(-60), payload: Data([2])),
                                systemFields: Data([9]))
        #expect(data.plainRecord(.setting, "feedWindow")?.payload == Data([1]))
        #expect(data.plainRecordsToUpload().first?.systemFields == Data([9]))
        // A newer one does.
        data.receivePlainRecord(PlainRecord(type: .setting, name: "feedWindow", modifiedAt: t0.addingTimeInterval(60), payload: Data([3])),
                                systemFields: Data([10]))
        #expect(data.plainRecord(.setting, "feedWindow")?.payload == Data([3]))
        #expect(data.plainRecordsToUpload().isEmpty)
    }
}

@Suite("The household store: syncing")
struct StoreSyncTests {
    let t0 = at(2026, 11, 14, 10, 0)

    /// A feed both phones know, already in iCloud with no changes waiting.
    func syncedFeed() -> HouseholdData {
        var data = HouseholdData()
        data.add(id: "f1", kind: .feed, babyID: baby, startedAt: t0, payload: breast(.left), by: parentA,
                 timeZoneID: "Europe/London", now: t0)
        data.didUploadEvent("f1", sentRevision: 1, systemFields: Data([1]), serverCreatedAt: t0)
        return data
    }

    @Test func anUploadClearsOnlyWhatWasSent() {
        var data = syncedFeed()
        data.edit("f1", by: parentA, now: t0.addingTimeInterval(60)) { $0.payload?.note = "first" }
        let sent = data.events["f1"]!.localRevision
        data.edit("f1", by: parentA, now: t0.addingTimeInterval(70)) { $0.payload?.note = "second" }
        data.didUploadEvent("f1", sentRevision: sent, systemFields: Data([2]), serverCreatedAt: t0)
        #expect(data.events["f1"]?.needsUpload == true)
        #expect(data.events["f1"]?.systemFields == Data([2]))
        data.didUploadEvent("f1", sentRevision: data.events["f1"]!.localRevision, systemFields: Data([3]), serverCreatedAt: t0)
        #expect(data.events["f1"]?.needsUpload == false)
    }

    @Test func aCopyFromICloudReplacesAnUnchangedEvent() {
        var data = syncedFeed()
        var server = data.events["f1"]!.snapshot
        server.payload?.note = "from B"
        server.payload?.setStamp(.note, FieldStamp(at: t0.addingTimeInterval(60), by: parentB))
        let outcome = data.receiveEvent(try! server.encoded(), systemFields: Data([2]))
        #expect(outcome == .replaced)
        #expect(data.events["f1"]?.snapshot.payload?.note == "from B")
        #expect(data.events["f1"]?.systemFields == Data([2]))
    }

    /// Round 2, S5, through the store: Parent A's start-time fix and Parent B's bottle both stay.
    @Test func aClashKeepsBothPhonesEdits() throws {
        var data = syncedFeed()
        data.edit("f1", by: parentA, now: t0.addingTimeInterval(.minutes(15))) { $0.event.startedAt = t0.addingTimeInterval(-.minutes(5)) }

        var server = data.events["f1"]!.snapshot
        server.event.startedAt = t0
        server.payload?.feed?.bottles = [Bottle(milk: .formula, ml: 30)]
        server.payload?.setStamp(.startedAt, FieldStamp(at: t0, by: parentA))
        server.payload?.setStamp(.bottles, FieldStamp(at: t0.addingTimeInterval(.minutes(20)), by: parentB))
        server.event.serverCreatedAt = t0

        let outcome = data.receiveEvent(try server.encoded(), systemFields: Data([2]))
        #expect(outcome == .merged(applied: [.startedAt], overruled: []))
        let stored = try #require(data.events["f1"])
        #expect(stored.event.startedAt == t0.addingTimeInterval(-.minutes(5)))
        #expect(stored.snapshot.payload?.feed?.bottles.first?.ml == 30)
        #expect(stored.needsUpload)
        #expect(stored.changedFields == [.startedAt])
        #expect(stored.systemFields == Data([2]))
    }

    @Test func aClashWithALaterEditOfTheSameFieldDropsOurs() {
        var data = syncedFeed()
        data.edit("f1", by: parentA, now: t0.addingTimeInterval(60)) { $0.payload?.note = "mine" }
        var server = data.events["f1"]!.snapshot
        server.payload?.note = "theirs"
        server.payload?.setStamp(.note, FieldStamp(at: t0.addingTimeInterval(120), by: parentB))
        let outcome = data.receiveEvent(try! server.encoded(), systemFields: Data([2]))
        #expect(outcome == .merged(applied: [], overruled: [.note]))
        #expect(data.events["f1"]?.snapshot.payload?.note == "theirs")
        #expect(data.events["f1"]?.needsUpload == false)
    }

    @Test func aCopyFromANewerAppWinsAndOurEditIsDropped() {
        var data = syncedFeed()
        data.edit("f1", by: parentA, now: t0.addingTimeInterval(60)) { $0.payload?.note = "mine" }
        var newer = data.events["f1"]!.event
        newer.payload = Data(#"{"v":9,"stamps":{}}"#.utf8)
        let outcome = data.receiveEvent(newer, systemFields: Data([2]))
        #expect(outcome == .keptNewerVersion(dropped: [.note]))
        #expect(data.events["f1"]?.event.payload == newer.payload)
        #expect(data.events["f1"]?.needsUpload == false)
    }

    @Test func anUploadInFlightDoesNotClearAChangeMergedMeanwhile() {
        var data = syncedFeed()
        data.edit("f1", by: parentA, now: t0.addingTimeInterval(60)) { $0.payload?.note = "mine" }
        let sent = data.events["f1"]!.localRevision
        var server = data.events["f1"]!.snapshot
        server.payload?.note = nil
        server.payload?.setStamp(.note, FieldStamp(at: t0, by: parentA))
        data.receiveEvent(try! server.encoded(), systemFields: Data([2]))
        data.didUploadEvent("f1", sentRevision: sent, systemFields: Data([3]), serverCreatedAt: t0)
        #expect(data.events["f1"]?.needsUpload == true)
        #expect(data.events["f1"]?.snapshot.payload?.note == "mine")
    }
}

@Suite("The household file")
struct HouseholdFileTests {
    let t0 = at(2026, 11, 14, 10, 0)

    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("household-\(UUID().uuidString).json")
    }

    @Test func itRoundTrips() throws {
        var data = HouseholdData()
        data.startFeed(id: "f1", babyID: baby, side: .right, by: parentA, timeZoneID: "Europe/London", now: t0)
        data.put(PlainRecord(type: .baby, name: baby, modifiedAt: t0, payload: try PayloadCoder.encode(BabyPayload(name: "Baby"))))
        data.syncState["private"] = Data([7, 8])
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try HouseholdFile.save(data, to: url)
        #expect(try HouseholdFile.load(from: url) == data)
    }

    @Test func noFileMeansNothingYet() throws {
        #expect(try HouseholdFile.load(from: temporaryURL()) == nil)
    }

    @Test func aFileFromANewerAppIsNotRead() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"format":2}"#.utf8).write(to: url)
        #expect(throws: HouseholdFile.LoadError.newerFormat(2)) { try HouseholdFile.load(from: url) }
    }

    @Test func aBrokenFileThrows() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(throws: (any Error).self) { try HouseholdFile.load(from: url) }
    }
}
