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
        // "Who does what" (engineering review E1, D2 A and D8 A): encrypted, and written only with
        // a value. A phone that lost a value (an older build dropped it from its file) then never
        // erases it in iCloud; CloudKit keeps a field a save doesn't set.
        for (key, value) in whoFields(event) { record.encryptedValues[key] = value }
        return record
    }

    /// The "who does what" fields with a value, by record field name.
    static func whoFields(_ event: Event) -> [(String, String)] {
        [("doneBy", event.doneBy?.rawValue), ("wakeID", event.wakeID),
         ("gotUpBy", event.gotUpBy?.rawValue), ("gotUpFor", event.gotUpFor)]
            .compactMap { key, value in value.map { (key, $0) } }
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
            serverCreatedAt: record.creationDate,
            doneBy: (record.encryptedValues["doneBy"] as? String).map(MemberID.init(rawValue:)),
            wakeID: record.encryptedValues["wakeID"] as? String,
            gotUpBy: (record.encryptedValues["gotUpBy"] as? String).map(MemberID.init(rawValue:)),
            gotUpFor: record.encryptedValues["gotUpFor"] as? String)
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

    // MARK: Photos and videos (the photos zone; journal plan, "Record shape")

    /// One photo or video of a first, as its `Media` record holds it. The file and its thumbnail
    /// go as CloudKit assets, which CloudKit encrypts by default; the details go in the encrypted
    /// payload. A `Media` record is never changed: removing or replacing an item deletes it.
    struct MediaFields: Equatable, Sendable {
        /// The record name: the item's ID, as the first's media list names it.
        var id: String
        /// The event the item belongs to (a first, today). A plain string, as a CloudKit
        /// reference can't point into another zone, and the event is in the household zone.
        var eventID: String
        /// The file and the thumbnail together, in bytes, for the household photo allowance.
        /// CloudKit doesn't report a record's size.
        var byteSize: Int64
        /// The item's details (photo or video, its length and size), written by FeedingCore.
        var payload: Data?
    }

    static let mediaType = "Media"

    /// What a tile needs: every field but the full file, so a fetch of the timeline never
    /// downloads a whole photo or video (journal plan, "thumbnails only").
    static let mediaThumbnailKeys: [CKRecord.FieldKey] = ["byteSize", "eventID", "payload", "thumbnail"]

    static func record(for media: MediaFields, file: URL, thumbnail: URL, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: mediaType, recordID: CKRecord.ID(recordName: media.id, zoneID: zoneID))
        record["eventID"] = media.eventID
        record["byteSize"] = media.byteSize
        record["file"] = CKAsset(fileURL: file)
        record["thumbnail"] = CKAsset(fileURL: thumbnail)
        record.encryptedValues["payload"] = media.payload
        return record
    }

    /// Nil when a required field is missing.
    static func media(from record: CKRecord) -> MediaFields? {
        guard record.recordType == mediaType,
              let eventID = record["eventID"] as? String,
              let byteSize = record["byteSize"] as? Int64
        else { return nil }
        return MediaFields(id: record.recordID.recordName, eventID: eventID, byteSize: byteSize,
                           payload: record.encryptedValues["payload"] as? Data)
    }

    /// Where CloudKit put a fetched item's file on this phone; nil if the fetch left it out.
    /// CloudKit may remove it once the fetch ends, so the caller moves it at once.
    static func fileURL(of record: CKRecord) -> URL? {
        (record["file"] as? CKAsset)?.fileURL
    }

    /// Where CloudKit put a fetched item's thumbnail on this phone, as `fileURL(of:)`.
    static func thumbnailURL(of record: CKRecord) -> URL? {
        (record["thumbnail"] as? CKAsset)?.fileURL
    }

    // MARK: The photo allowance's tally (CEO review D20, eng D2 and D11)

    /// One record in the photos zone. Its encrypted payload lists each item's ID and size; the
    /// bytes used are their sum. It is saved in the same all-or-nothing save as each `Media`
    /// record, and only if nobody changed it since it was read, so its version tag goes with it.
    static let mediaTallyType = "MediaTally"
    static let mediaTallyName = "mediaTally"

    static func tallyRecord(payload: Data, systemFields: Data?, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = record(fromSystemFields: systemFields)
            ?? CKRecord(recordType: mediaTallyType, recordID: CKRecord.ID(recordName: mediaTallyName, zoneID: zoneID))
        record.encryptedValues["payload"] = payload
        return record
    }

    /// Nil for any other record, or a tally with no payload.
    static func tallyPayload(from record: CKRecord) -> Data? {
        guard record.recordType == mediaTallyType else { return nil }
        return record.encryptedValues["payload"] as? Data
    }
}
