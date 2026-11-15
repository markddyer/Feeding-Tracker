import CloudKit
import FeedingCore
import Foundation

/// Turns stored events and plain records into CloudKit records and back. Field names match
/// `schema.ckdb`; writing any other field would add it to the Development schema by itself.
enum RecordMapping {
    // MARK: CloudKit's version tag

    /// The record's system fields (ID, zone, version tag), archived, to keep beside our copy.
    static func systemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    /// A record holding only the archived system fields, ready to fill and save on top of the
    /// version iCloud last confirmed.
    static func record(fromSystemFields data: Data?) -> CKRecord? {
        guard let data, let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }

    // MARK: Events

    static func record(for stored: StoredEvent, zoneID: CKRecordZone.ID) -> CKRecord {
        let event = stored.event
        let record = record(fromSystemFields: stored.systemFields)
            ?? CKRecord(recordType: "Event", recordID: CKRecord.ID(recordName: event.id, zoneID: zoneID))
        record["babyID"] = event.babyID
        record["kind"] = event.kind.rawValue
        record["startedAt"] = event.startedAt
        record["endedAt"] = event.endedAt
        record["timeZoneID"] = event.timeZoneID
        record["loggedBy"] = event.loggedBy.rawValue
        record["createdAt"] = event.createdAt
        record["modifiedAt"] = event.modifiedAt
        record["deletedAt"] = event.deletedAt
        record["schemaVersion"] = Int64(event.schemaVersion)
        record.encryptedValues["payload"] = event.payload
        return record
    }

    /// Nil when a required top-level field is missing.
    static func event(from record: CKRecord) -> Event? {
        guard record.recordType == "Event",
              let babyID = record["babyID"] as? String,
              let kind = record["kind"] as? String,
              let startedAt = record["startedAt"] as? Date,
              let loggedBy = record["loggedBy"] as? String
        else { return nil }
        let createdAt = record["createdAt"] as? Date ?? record.creationDate ?? startedAt
        return Event(
            id: record.recordID.recordName,
            babyID: babyID,
            kind: EventKind(rawValue: kind),
            startedAt: startedAt,
            endedAt: record["endedAt"] as? Date,
            timeZoneID: record["timeZoneID"] as? String ?? "Europe/London",
            loggedBy: MemberID(rawValue: loggedBy),
            createdAt: createdAt,
            modifiedAt: record["modifiedAt"] as? Date ?? record.modificationDate ?? createdAt,
            deletedAt: record["deletedAt"] as? Date,
            schemaVersion: (record["schemaVersion"] as? Int64).map(Int.init) ?? 1,
            payload: record.encryptedValues["payload"] as? Data,
            serverCreatedAt: record.creationDate)
    }

    // MARK: Record names

    /// CloudKit keeps record names that start with "_" for its own records, and iCloud user IDs
    /// look like "_293e…". A Member record is named after its parent's ID on the phone, so in
    /// iCloud it goes as "member-<ID>". Every other name (UUIDs, setting keys) goes as it is.
    /// (Found on two real phones on 14 Nov 2026: neither parent's Member record would send.)
    static let memberPrefix = "member-"

    /// The record name in iCloud for a record the phone knows by `plain.name`.
    static func cloudName(of plain: PlainRecord) -> String {
        plain.type == .member ? memberPrefix + plain.name : plain.name
    }

    /// The phone's name for a record that iCloud knows by `cloudName`.
    static func localName(cloudName: String, type: PlainRecordType) -> String {
        guard type == .member, cloudName.hasPrefix(memberPrefix) else { return cloudName }
        return String(cloudName.dropFirst(memberPrefix.count))
    }

    // MARK: Babies, members and settings

    static func record(for stored: StoredPlainRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let plain = stored.record
        let record = record(fromSystemFields: stored.systemFields)
            ?? CKRecord(recordType: plain.type.rawValue, recordID: CKRecord.ID(recordName: cloudName(of: plain), zoneID: zoneID))
        switch plain.type {
        case .baby:
            record["archivedAt"] = plain.archivedAt
        case .member:
            break
        case .setting:
            record["key"] = plain.name
            record["modifiedAt"] = plain.modifiedAt
        }
        record.encryptedValues["payload"] = plain.payload
        return record
    }

    static func plainRecord(from record: CKRecord) -> PlainRecord? {
        guard let type = PlainRecordType(rawValue: record.recordType) else { return nil }
        let modifiedAt = (type == .setting ? record["modifiedAt"] as? Date : nil) ?? record.modificationDate ?? .distantPast
        return PlainRecord(
            type: type,
            name: localName(cloudName: record.recordID.recordName, type: type),
            modifiedAt: modifiedAt,
            archivedAt: type == .baby ? record["archivedAt"] as? Date : nil,
            payload: record.encryptedValues["payload"] as? Data)
    }
}
