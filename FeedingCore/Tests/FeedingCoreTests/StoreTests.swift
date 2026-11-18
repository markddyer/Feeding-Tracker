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

/// Step 0 of the milestones journal (CEO review D18): a phone put back on an older build reads the
/// file a newer build wrote, skips what it doesn't know, keeps it for the newer build, and keeps its
/// feeds, so its alarms are planned as before.
@Suite("A file from a newer build")
struct NewerBuildFileTests {
    let t0 = at(2026, 11, 18, 10, 0)

    /// A file as a newer build might write it: an unknown field name on a feed's waiting change, an
    /// event of an unknown kind, an entry in a shape this build can't read, a record type it
    /// doesn't know, and a new part of the file.
    func newerFile() throws -> Data {
        var data = HouseholdData()
        data.startFeed(id: "f1", babyID: baby, side: .left, by: parentA, timeZoneID: "Europe/London", now: t0)
        data.add(id: "m1", kind: "milestone", babyID: baby, startedAt: t0, payload: EventPayload(),
                 by: parentA, timeZoneID: "Europe/London", now: t0)
        data.put(PlainRecord(type: .baby, name: baby, modifiedAt: t0, payload: try PayloadCoder.encode(BabyPayload(name: "Baby"))))
        var file = try #require(try JSONSerialization.jsonObject(with: Self.encode(data)) as? [String: Any])
        var events = try #require(file["events"] as? [String: Any])
        var feed = try #require(events["f1"] as? [String: Any])
        feed["changedFields"] = ((feed["changedFields"] as? [String]) ?? []) + ["milestoneTitle"]
        events["f1"] = feed
        var milestone = try #require(events["m1"] as? [String: Any])
        milestone["changedFields"] = ["title", "startedAt"]
        events["m1"] = milestone
        events["x1"] = ["event": ["id": "x1", "startedAt": "soon"], "localRevision": 2, "at": 1_794_650_000_123.5]
        file["events"] = events
        var records = try #require(file["plainRecords"] as? [String: Any])
        records["Tally/photos"] = ["record": ["type": "Tally", "name": "photos", "modifiedAt": 1_794_650_000_000],
                                   "needsUpload": true, "localRevision": 1]
        file["plainRecords"] = records
        file["mediaQueue"] = ["items": ["a", "b"], "paused": false, "count": 2]
        return try JSONSerialization.data(withJSONObject: file)
    }

    static func encode(_ data: HouseholdData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(data)
    }

    func load(_ bytes: Data) throws -> HouseholdData {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("household-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try bytes.write(to: url)
        return try #require(try HouseholdFile.load(from: url))
    }

    @Test func itReadsWhatItKnowsAndKeepsTheRest() throws {
        let data = try load(try newerFile())
        let feed = try #require(data.events["f1"])
        #expect(feed.event.isLiveFeed)
        #expect(feed.changedFields == EventField.fields(for: .feed))
        #expect(feed.keptChangedFields == ["milestoneTitle"])
        let milestone = try #require(data.events["m1"])
        #expect(milestone.event.kind == "milestone")
        #expect(milestone.changedFields == [.startedAt])
        #expect(milestone.keptChangedFields == ["title"])
        #expect(Set(data.keptEvents.keys) == ["x1"])
        #expect(data.plainRecord(.baby, baby) != nil)
        #expect(Set(data.keptPlainRecords.keys) == ["Tally/photos"])
        #expect(Set(data.keptParts.keys) == ["mediaQueue"])
    }

    @Test func itsFeedsStillPlanTheAlarms() throws {
        let data = try load(try newerFile())
        #expect(!data.isWaitingForICloud(now: t0))
        #expect(data.allEvents.latestFeedStart(babyID: baby, now: t0.addingTimeInterval(60)) == t0)
    }

    @Test func savingWritesTheKeptPartsBackUnchanged() throws {
        let original = try newerFile()
        let data = try load(original)
        let again = try load(try Self.encode(data))
        #expect(again == data)
        let before = try #require(try JSONSerialization.jsonObject(with: original) as? NSDictionary)
        let after = try #require(try JSONSerialization.jsonObject(with: Self.encode(data)) as? NSDictionary)
        #expect(after["mediaQueue"] as? NSDictionary == before["mediaQueue"] as? NSDictionary)
        let keptBefore = (before["events"] as? NSDictionary)?["x1"] as? NSDictionary
        #expect(keptBefore != nil)
        #expect((after["events"] as? NSDictionary)?["x1"] as? NSDictionary == keptBefore)
        #expect((after["plainRecords"] as? NSDictionary)?["Tally/photos"] as? NSDictionary
            == (before["plainRecords"] as? NSDictionary)?["Tally/photos"] as? NSDictionary)
        let names = ((after["events"] as? NSDictionary)?["f1"] as? NSDictionary)?["changedFields"] as? [String]
        #expect(names?.contains("milestoneTitle") == true)
    }

    @Test func unknownChangedFieldsGoOnceTheChangeIsSent() throws {
        var data = try load(try newerFile())
        let revision = try #require(data.events["f1"]?.localRevision)
        data.didUploadEvent("f1", sentRevision: revision, systemFields: Data([1]), serverCreatedAt: t0)
        #expect(data.events["f1"]?.keptChangedFields == [])
        #expect(data.events["f1"]?.needsUpload == false)
    }

    @Test func aReadableCopyFromICloudReplacesAKeptEntry() throws {
        var data = try load(try newerFile())
        let server = Event(id: "x1", babyID: baby, kind: .feed, startedAt: t0, timeZoneID: "Europe/London",
                           loggedBy: parentB, createdAt: t0, modifiedAt: t0)
        data.receiveEvent(server, systemFields: Data([2]))
        #expect(data.keptEvents["x1"] == nil)
        #expect(data.events["x1"]?.event == server)
    }

    @Test func iCloudRemovingARecordRemovesItsKeptEntry() throws {
        var data = try load(try newerFile())
        data.removeEvent("x1")
        data.removePlainRecord("Tally/photos")
        #expect(data.keptEvents.isEmpty)
        #expect(data.keptPlainRecords.isEmpty)
    }

    /// A phone whose file couldn't be read waits for iCloud before it cancels any alert, for a day
    /// at most; the time is saved, so a restart before iCloud answers still waits. A file that isn't
    /// waiting doesn't mention it, so it reads exactly as before.
    @Test func waitingForICloudIsSavedOnlyWhenSet() throws {
        var data = HouseholdData()
        #expect(!data.isWaitingForICloud(now: t0))
        let plain = try #require(try JSONSerialization.jsonObject(with: Self.encode(data)) as? [String: Any])
        #expect(plain["waitingForICloudSince"] == nil)
        data.waitingForICloudSince = t0
        let again = try load(try Self.encode(data))
        #expect(again.waitingForICloudSince == t0)
        #expect(again.keptParts.isEmpty)
    }

    @Test func theWaitLastsADayAtMost() {
        var data = HouseholdData()
        data.waitingForICloudSince = t0
        #expect(data.isWaitingForICloud(now: t0.addingTimeInterval(.minutes(10))))
        #expect(data.isWaitingForICloud(now: t0.addingTimeInterval(23.9 * 3600)))
        #expect(!data.isWaitingForICloud(now: t0.addingTimeInterval(24 * 3600)))
        // A clock set back keeps the phone waiting.
        #expect(data.isWaitingForICloud(now: t0.addingTimeInterval(-3 * 3600)))
    }

    @Test func aPreciseFractionIsKeptExactly() throws {
        let text = #"{"format":1,"syncState":{},"events":{},"plainRecords":{},"rate":0.1,"precise":1.2345678901234567890123}"#
        let data = try load(Data(text.utf8))
        let written = String(decoding: try Self.encode(data), as: UTF8.self)
        #expect(written.contains(#""precise":1.2345678901234567890123"#))
        #expect(written.contains(#""rate":0.1"#))
    }

    @Test func aHugeWholeNumberIsKeptExactly() throws {
        var file = try #require(try JSONSerialization.jsonObject(with: try newerFile()) as? [String: Any])
        file["counter"] = UInt64.max
        let data = try load(try JSONSerialization.data(withJSONObject: file))
        #expect(data.keptParts["counter"] == .unsigned(.max))
    }

    @Test func aFileFromThisBuildHasNothingKept() throws {
        var data = HouseholdData()
        data.startFeed(id: "f1", babyID: baby, side: .right, by: parentA, timeZoneID: "Europe/London", now: t0)
        let again = try load(try Self.encode(data))
        #expect(again == data)
        #expect(again.keptEvents.isEmpty && again.keptPlainRecords.isEmpty && again.keptParts.isEmpty)
        #expect(again.events["f1"]?.keptChangedFields == [])
    }
}

/// eng D6, part 2 (18 Nov 2026): today's deletes are sent at once. The journal holds only a
/// milestone delete for its Undo window; this keeps every other kind as it is.
@Suite("Deletes are sent at once")
struct DeleteUploadTests {
    let t0 = at(2026, 11, 18, 10, 0)

    @Test(arguments: [EventKind.feed, .sleep, .nappy, .growth, .medicine])
    func aDeleteIsReadyToSendAtOnce(kind: EventKind) throws {
        var data = HouseholdData()
        data.add(id: "e1", kind: kind, babyID: baby, startedAt: t0, payload: EventPayload(),
                 by: parentA, timeZoneID: "Europe/London", now: t0)
        let revision = try #require(data.events["e1"]?.localRevision)
        data.didUploadEvent("e1", sentRevision: revision, systemFields: Data([1]), serverCreatedAt: t0)
        let later = t0.addingTimeInterval(.minutes(5))
        #expect(data.eventsToUpload(now: later).isEmpty)
        data.delete("e1", by: parentA, now: later)
        #expect(data.eventsToUpload(now: later).map(\.event.id) == ["e1"])
    }
}

@Suite("A parent's colour")
struct MemberColourTests {
    let now = at(2026, 11, 15, 12, 0)

    func household(colour: String = "sunflower") -> HouseholdData {
        var data = HouseholdData()
        data.put(PlainRecord(type: .member, name: parentA.rawValue, modifiedAt: now,
                             payload: try? PayloadCoder.encode(MemberPayload(displayName: "Alex", colour: colour))))
        return data
    }

    @Test func itChangesTheColourAndKeepsTheName() throws {
        var data = household()
        let before = try #require(data.plainRecords["\(PlainRecordType.member.rawValue)/\(parentA.rawValue)"]).localRevision
        let changed = data.setColour("lavender", of: parentA, now: now.addingTimeInterval(60))
        #expect(changed)
        let record = try #require(data.plainRecord(.member, parentA.rawValue))
        let payload = try #require(PayloadCoder.decode(MemberPayload.self, from: record.payload))
        #expect(payload.colour == "lavender")
        #expect(payload.displayName == "Alex")
        #expect(record.modifiedAt == now.addingTimeInterval(60))
        #expect(data.plainRecords["\(PlainRecordType.member.rawValue)/\(parentA.rawValue)"]?.needsUpload == true)
        #expect(data.plainRecords["\(PlainRecordType.member.rawValue)/\(parentA.rawValue)"]?.localRevision == before + 1)
    }

    @Test func theSameColourChangesNothing() {
        var data = household(colour: "teal")
        let before = data
        let changed = data.setColour("teal", of: parentA, now: now.addingTimeInterval(60))
        #expect(changed)
        #expect(data == before)
    }

    @Test func noRecordYetChangesNothing() {
        var data = HouseholdData()
        let changed = data.setColour("plum", of: parentA, now: now)
        #expect(!changed)
        #expect(data.plainRecords(of: .member).isEmpty)
    }

    @Test func aRecordFromANewerAppIsLeftAlone() {
        var data = HouseholdData()
        let newer = Data(#"{"v":99,"displayName":"Alex","colour":"teal","pronouns":"they"}"#.utf8)
        data.put(PlainRecord(type: .member, name: parentA.rawValue, modifiedAt: now, payload: newer))
        let before = data
        let changed = data.setColour("plum", of: parentA, now: now.addingTimeInterval(60))
        #expect(!changed)
        #expect(data == before)
    }
}
