import CloudKit
import FeedingCore
import Foundation
import Testing
@testable import FeedingDev

/// The mapping between the phone's records and CloudKit's. A mistake here breaks sync, or worse,
/// adds a field to the CloudKit schema by itself; the Production schema can never lose it.
@Suite("CloudKit record mapping")
struct RecordMappingTests {
    let zone = CKRecordZone.ID(zoneName: "Household", ownerName: CKCurrentUserDefaultName)
    let start = Date(timeIntervalSince1970: 1_794_650_000)

    func storedEvent(endedAt: Date? = nil, deletedAt: Date? = nil) -> StoredEvent {
        var data = HouseholdData()
        data.add(id: "event-1", kind: .feed, babyID: "baby-1", startedAt: start, endedAt: endedAt,
                 payload: EventPayload(feed: FeedDetails(bottles: [Bottle(milk: .formula, ml: 30)]), note: "x"),
                 by: "parent-a", timeZoneID: "Europe/London", now: start)
        if deletedAt != nil { data.delete("event-1", by: "parent-a", now: deletedAt!) }
        return data.events["event-1"]!
    }

    @Test func anEventRoundTrips() throws {
        let stored = storedEvent(endedAt: start.addingTimeInterval(600))
        let record = RecordMapping.record(for: stored, zoneID: zone)
        #expect(record.recordType == "Event")
        #expect(record.recordID == CKRecord.ID(recordName: "event-1", zoneID: zone))
        let back = try #require(RecordMapping.event(from: record))
        var expected = stored.event
        expected.serverCreatedAt = nil // a record made on the phone has no server time yet
        #expect(back == expected)
    }

    @Test func thePayloadIsEncryptedAndNothingElseIs() {
        let record = RecordMapping.record(for: storedEvent(deletedAt: start.addingTimeInterval(60)), zoneID: zone)
        #expect(record.encryptedValues["payload"] as? Data != nil)
        #expect(record["payload"] == nil)
        #expect(record.encryptedValues.allKeys() == ["payload"])
    }

    @Test func emptyOptionalFieldsAreLeftEmpty() {
        let record = RecordMapping.record(for: storedEvent(), zoneID: zone)
        #expect(record["endedAt"] == nil)
        #expect(record["deletedAt"] == nil)
    }

    @Test func aSavedRecordKeepsItsVersionTag() throws {
        var stored = storedEvent()
        let first = RecordMapping.record(for: stored, zoneID: zone)
        stored.systemFields = RecordMapping.systemFields(of: first)
        let again = RecordMapping.record(for: stored, zoneID: zone)
        #expect(again.recordID == first.recordID)
        #expect(again.recordType == "Event")
        #expect(again["kind"] as? String == "feed")
    }

    @Test func otherRecordsAreNotEvents() {
        let share = CKShare(recordZoneID: zone)
        #expect(RecordMapping.event(from: share) == nil)
        #expect(RecordMapping.plainRecord(from: share) == nil)
        let incomplete = CKRecord(recordType: "Event", recordID: CKRecord.ID(recordName: "e", zoneID: zone))
        #expect(RecordMapping.event(from: incomplete) == nil)
    }

    @Test func babiesMembersAndSettingsRoundTrip() throws {
        let records = [
            PlainRecord(type: .baby, name: "baby-1", modifiedAt: start, archivedAt: start.addingTimeInterval(5), payload: Data([1])),
            PlainRecord(type: .member, name: "parent-a", modifiedAt: start, payload: Data([2])),
            PlainRecord(type: .setting, name: "feedWindow", modifiedAt: start, payload: Data([3])),
        ]
        for plain in records {
            let stored = StoredPlainRecord(record: plain, needsUpload: true, systemFields: nil, localRevision: 1)
            let record = RecordMapping.record(for: stored, zoneID: zone)
            #expect(record.recordType == plain.type.rawValue)
            let back = try #require(RecordMapping.plainRecord(from: record))
            #expect(back.payload == plain.payload)
            #expect(back.archivedAt == plain.archivedAt)
            if plain.type == .setting {
                #expect(back.modifiedAt == plain.modifiedAt)
                #expect(record["key"] as? String == "feedWindow")
            }
        }
    }

    /// CloudKit keeps record names that start with "_" for itself, and iCloud user IDs look like
    /// "_293e…". A Member record named after one must go to iCloud under another name, and come
    /// back under the phone's name.
    @Test func memberRecordsNeverUseAReservedName() throws {
        let plain = PlainRecord(type: .member, name: "_0123abcd", modifiedAt: start, payload: Data([2]))
        let stored = StoredPlainRecord(record: plain, needsUpload: true, systemFields: nil, localRevision: 1)
        let record = RecordMapping.record(for: stored, zoneID: zone)
        #expect(!record.recordID.recordName.hasPrefix("_"))
        #expect(record.recordID.recordName == RecordMapping.cloudName(of: plain))
        let back = try #require(RecordMapping.plainRecord(from: record))
        #expect(back.name == "_0123abcd")
    }

    @Test func otherRecordNamesGoAsTheyAre() {
        for (type, name) in [(PlainRecordType.baby, "6F1C2E0A-0000-4000-8000-000000000001"), (.setting, "ack-_0123abcd")] {
            let plain = PlainRecord(type: type, name: name, modifiedAt: start, payload: nil)
            #expect(RecordMapping.cloudName(of: plain) == name)
            #expect(RecordMapping.localName(cloudName: name, type: type) == name)
        }
    }

    /// Every field the app writes must already be in schema.ckdb for that record type, with the
    /// payload declared encrypted. In the Development environment CloudKit would otherwise add the
    /// field by itself, and a deploy would make it permanent in Production.
    @Test func everyFieldWrittenIsInTheSchema() throws {
        let schema = try Schema.load()
        var written: [(String, CKRecord)] = [("Event", RecordMapping.record(for: storedEvent(endedAt: start, deletedAt: start), zoneID: zone))]
        for type in PlainRecordType.allCases {
            let plain = PlainRecord(type: type, name: "n", modifiedAt: start, archivedAt: start, payload: Data([1]))
            let stored = StoredPlainRecord(record: plain, needsUpload: true, systemFields: nil, localRevision: 1)
            written.append((type.rawValue, RecordMapping.record(for: stored, zoneID: zone)))
        }
        for (type, record) in written {
            let fields = try #require(schema.fields[type], "\(type) is not in schema.ckdb")
            for key in record.allKeys() {
                #expect(fields[key] != nil, "\(type).\(key) is not in schema.ckdb")
            }
            for key in record.encryptedValues.allKeys() {
                #expect(fields[key] == "ENCRYPTED BYTES", "\(type).\(key) must be ENCRYPTED BYTES in schema.ckdb")
            }
        }
    }
}

/// A small reader for schema.ckdb: record types and their fields.
struct Schema {
    var fields: [String: [String: String]] = [:]

    /// The simulator runs on the Mac, so the test can read the repository's file directly.
    static func load() throws -> Schema {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("schema.ckdb")
        var schema = Schema()
        var current: String?
        for rawLine in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("RECORD TYPE ") {
                current = line.dropFirst("RECORD TYPE ".count).split(separator: " ").first.map(String.init)
                schema.fields[current!] = [:]
            } else if line.hasPrefix(")") {
                current = nil
            } else if let type = current, !line.hasPrefix("GRANT"), !line.hasPrefix("//"), !line.isEmpty {
                let parts = line.trimmingCharacters(in: CharacterSet(charactersIn: ",")).split(separator: " ", maxSplits: 1)
                if parts.count == 2 {
                    schema.fields[type]?[parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))] =
                        parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return schema
    }
}
