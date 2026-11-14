import Foundation

// Everything one phone holds about the household, kept in one JSON file. A change is saved on the
// phone at once; the sync layer then sends it to iCloud and brings the other phone's changes in.
// This file holds the rules for both directions, with no CloudKit types, so they are tested on
// Linux too. The sync layer keeps CloudKit's own version tag for each record as opaque bytes.

/// An event as this phone holds it.
public struct StoredEvent: Hashable, Sendable, Codable {
    /// The event, with its payload encoded inside.
    public var event: Event
    /// Fields this phone changed that iCloud hasn't confirmed yet. Used to merge a save clash.
    public var changedFields: Set<EventField>
    public var needsUpload: Bool
    /// The end of the undo window. Nothing is sent before it.
    public var uploadNotBefore: Date?
    /// CloudKit's version tag for the record (its archived system fields). Nil until it uploads.
    public var systemFields: Data?
    /// Goes up with every change on this phone, so an upload that was sent before a later change
    /// doesn't mark that change as sent.
    public var localRevision: Int

    public var snapshot: EventSnapshot { EventSnapshot(event: event) }
}

/// Baby, Member and Setting records. They change as a whole: the later change wins.
public enum PlainRecordType: String, Hashable, Sendable, Codable, CaseIterable {
    case baby = "Baby"
    case member = "Member"
    case setting = "Setting"
}

public struct PlainRecord: Hashable, Sendable, Codable {
    public var type: PlainRecordType
    /// The record name: the baby's ID, the member's ID, or the setting's key.
    public var name: String
    /// When it last changed. For Settings this is the record's own field; for Babies and Members
    /// it is iCloud's modification time once uploaded.
    public var modifiedAt: Date
    /// Babies only.
    public var archivedAt: Date?
    public var payload: Data?

    public init(type: PlainRecordType, name: String, modifiedAt: Date, archivedAt: Date? = nil, payload: Data? = nil) {
        self.type = type
        self.name = name
        self.modifiedAt = modifiedAt
        self.archivedAt = archivedAt
        self.payload = payload
    }

    public var key: String { "\(type.rawValue)/\(name)" }
}

public struct StoredPlainRecord: Hashable, Sendable, Codable {
    public var record: PlainRecord
    public var needsUpload: Bool
    public var systemFields: Data?
    public var localRevision: Int
}

/// What happened when a copy from iCloud met this phone's own changes.
public enum ReceiveOutcome: Hashable, Sendable {
    /// No local changes were waiting: iCloud's copy was taken.
    case replaced
    /// Local changes were merged onto iCloud's copy. `overruled` lists this phone's edits that a
    /// later edit on the other phone beat.
    case merged(applied: Set<EventField>, overruled: Set<EventField>)
    /// iCloud's copy came from a newer app version, so it was kept and this phone's edits were dropped.
    case keptNewerVersion(dropped: Set<EventField>)
}

public struct HouseholdData: Hashable, Sendable, Codable {
    public static let currentFormat = 1
    /// How long a new event waits before it is sent, so Undo can take it back quietly.
    public static let undoWindow: TimeInterval = 10

    public var format: Int
    public var events: [String: StoredEvent]
    public var plainRecords: [String: StoredPlainRecord]
    /// The sync engines' saved state, by database ("private", "shared"). Opaque here.
    public var syncState: [String: Data]

    public init() {
        format = Self.currentFormat
        events = [:]
        plainRecords = [:]
        syncState = [:]
    }

    // MARK: Reading

    public var snapshots: [EventSnapshot] { events.values.map(\.snapshot) }

    public var allEvents: [Event] { events.values.map(\.event) }

    /// The newest feed for `babyID` that has started and not finished, if any.
    public func feedInProgress(babyID: String) -> EventSnapshot? {
        events.values.lazy.map(\.event)
            .filter { $0.isLiveFeed && $0.babyID == babyID && $0.endedAt == nil }
            .max { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
            .map { EventSnapshot(event: $0) }
    }

    // MARK: Changes made on this phone

    /// Adds a new event. Every field is stamped, so if the same record ever meets an older copy
    /// in iCloud, this one wins. Returns the event's ID.
    @discardableResult
    public mutating func add(
        id: String = UUID().uuidString, kind: EventKind, babyID: String, startedAt: Date, endedAt: Date? = nil,
        payload: EventPayload, by member: MemberID, timeZoneID: String, now: Date
    ) -> String {
        var payload = payload
        for field in EventField.allCases { payload.setStamp(field, FieldStamp(at: now, by: member)) }
        let event = Event(id: id, babyID: babyID, kind: kind, startedAt: startedAt, endedAt: endedAt,
                          timeZoneID: timeZoneID, loggedBy: member, createdAt: now, modifiedAt: now,
                          payload: try? PayloadCoder.encode(payload))
        events[id] = StoredEvent(event: event, changedFields: Set(EventField.allCases), needsUpload: true,
                                 uploadNotBefore: now.addingTimeInterval(Self.undoWindow), systemFields: nil, localRevision: 1)
        return id
    }

    /// Starts a feed now, timed live, optionally on a side.
    @discardableResult
    public mutating func startFeed(id: String = UUID().uuidString, babyID: String, side: BreastSide?,
                                   by member: MemberID, timeZoneID: String, now: Date) -> String {
        let breast = side.map { [BreastSegment(side: $0, startedAt: now)] } ?? []
        return add(id: id, kind: .feed, babyID: babyID, startedAt: now, payload: EventPayload(feed: FeedDetails(breast: breast)),
                   by: member, timeZoneID: timeZoneID, now: now)
    }

    /// Changes an event. The changed fields are found by comparing before and after, then stamped.
    /// Returns false when the event is unknown or its details came from a newer app version.
    @discardableResult
    public mutating func edit(_ id: String, by member: MemberID, now: Date, _ change: (inout EventSnapshot) -> Void) -> Bool {
        guard var stored = events[id] else { return false }
        let before = stored.snapshot
        guard before.payload != nil else { return false }
        var after = before
        change(&after)
        let changed = Self.changedFields(from: before, to: after)
        guard !changed.isEmpty else { return true }
        for field in changed { after.payload?.setStamp(field, FieldStamp(at: now, by: member)) }
        after.event.modifiedAt = now
        guard let encoded = try? after.encoded() else { return false }
        stored.event = encoded
        stored.changedFields.formUnion(changed)
        stored.needsUpload = true
        stored.localRevision += 1
        events[id] = stored
        return true
    }

    /// Switches a live feed to `side`: the open segment gets its length, and a new one starts now.
    @discardableResult
    public mutating func switchSide(_ id: String, to side: BreastSide, by member: MemberID, now: Date) -> Bool {
        edit(id, by: member, now: now) { snapshot in
            var feed = snapshot.payload?.feed ?? FeedDetails()
            Self.closeOpenSegment(&feed, now: now)
            feed.breast.append(BreastSegment(side: side, startedAt: now))
            snapshot.payload?.feed = feed
        }
    }

    /// Ends a feed now. The open segment gets its length.
    @discardableResult
    public mutating func finishFeed(_ id: String, by member: MemberID, now: Date) -> Bool {
        edit(id, by: member, now: now) { snapshot in
            if var feed = snapshot.payload?.feed {
                Self.closeOpenSegment(&feed, now: now)
                snapshot.payload?.feed = feed
            }
            snapshot.event.endedAt = now
        }
    }

    /// Hides an event. It is never removed from iCloud.
    @discardableResult
    public mutating func delete(_ id: String, by member: MemberID, now: Date) -> Bool {
        edit(id, by: member, now: now) { $0.event.deletedAt = now }
    }

    @discardableResult
    public mutating func restore(_ id: String, by member: MemberID, now: Date) -> Bool {
        edit(id, by: member, now: now) { $0.event.deletedAt = nil }
    }

    /// Undo for an event added a moment ago: removes it completely, as long as it hasn't been sent.
    /// Returns false once it has been sent or its undo window has passed; then use `delete`.
    @discardableResult
    public mutating func undoAdd(_ id: String, now: Date) -> Bool {
        guard let stored = events[id], stored.systemFields == nil,
              let deadline = stored.uploadNotBefore, now < deadline else { return false }
        events[id] = nil
        return true
    }

    /// The app is going to the background: everything waiting may be sent at once.
    public mutating func endUndoWindows() {
        for id in events.keys { events[id]?.uploadNotBefore = nil }
    }

    // MARK: Plain records

    /// Saves a Baby, Member or Setting changed on this phone.
    public mutating func put(_ record: PlainRecord) {
        var stored = plainRecords[record.key] ?? StoredPlainRecord(record: record, needsUpload: true, systemFields: nil, localRevision: 0)
        stored.record = record
        stored.needsUpload = true
        stored.localRevision += 1
        plainRecords[record.key] = stored
    }

    public func plainRecord(_ type: PlainRecordType, _ name: String) -> PlainRecord? {
        plainRecords["\(type.rawValue)/\(name)"]?.record
    }

    public func plainRecords(of type: PlainRecordType) -> [PlainRecord] {
        plainRecords.values.map(\.record).filter { $0.type == type }.sorted { $0.name < $1.name }
    }

    // MARK: Sync: sending

    /// Events to send now: changed here, and past their undo window.
    public func eventsToUpload(now: Date) -> [StoredEvent] {
        events.values
            .filter { $0.needsUpload && ($0.uploadNotBefore.map { $0 <= now } ?? true) }
            .sorted { ($0.event.createdAt, $0.event.id) < ($1.event.createdAt, $1.event.id) }
    }

    public func plainRecordsToUpload() -> [StoredPlainRecord] {
        plainRecords.values.filter(\.needsUpload).sorted { $0.record.key < $1.record.key }
    }

    /// iCloud saved an event. `sentRevision` is the `localRevision` that was sent; changes made
    /// since then stay waiting.
    public mutating func didUploadEvent(_ id: String, sentRevision: Int, systemFields: Data, serverCreatedAt: Date?) {
        guard var stored = events[id] else { return }
        stored.systemFields = systemFields
        stored.event.serverCreatedAt = stored.event.serverCreatedAt ?? serverCreatedAt
        if stored.localRevision == sentRevision {
            stored.changedFields = []
            stored.needsUpload = false
        }
        events[id] = stored
    }

    public mutating func didUploadPlainRecord(_ key: String, sentRevision: Int, systemFields: Data) {
        guard var stored = plainRecords[key] else { return }
        stored.systemFields = systemFields
        if stored.localRevision == sentRevision { stored.needsUpload = false }
        plainRecords[key] = stored
    }

    // MARK: Sync: receiving

    /// A copy of an event came from iCloud: from a fetch, or with a save clash. With no local
    /// changes waiting, it replaces ours. Otherwise this phone's changes are merged onto it, field
    /// by field, and sent again on top of iCloud's version.
    @discardableResult
    public mutating func receiveEvent(_ server: Event, systemFields: Data) -> ReceiveOutcome {
        guard var stored = events[server.id], stored.needsUpload, !stored.changedFields.isEmpty else {
            let revision = events[server.id]?.localRevision ?? 0
            events[server.id] = StoredEvent(event: server, changedFields: [], needsUpload: false, uploadNotBefore: nil,
                                            systemFields: systemFields, localRevision: revision)
            return .replaced
        }
        let result = merge(local: stored.snapshot, server: EventSnapshot(event: server), changedLocally: stored.changedFields)
        stored.systemFields = systemFields
        stored.localRevision += 1
        if result.keptServerCopyUnread {
            stored.event = server
            stored.changedFields = []
            stored.needsUpload = false
            events[server.id] = stored
            return .keptNewerVersion(dropped: result.overruled)
        }
        var merged = (try? result.snapshot.encoded()) ?? server
        merged.serverCreatedAt = server.serverCreatedAt ?? stored.event.serverCreatedAt
        stored.event = merged
        stored.changedFields = result.applied
        stored.needsUpload = !result.applied.isEmpty
        events[server.id] = stored
        return .merged(applied: result.applied, overruled: result.overruled)
    }

    /// A copy of a plain record came from iCloud. A waiting local change that is newer stays and is
    /// sent again on top of iCloud's version; otherwise iCloud's copy is taken.
    public mutating func receivePlainRecord(_ server: PlainRecord, systemFields: Data) {
        if var stored = plainRecords[server.key], stored.needsUpload, stored.record.modifiedAt > server.modifiedAt {
            stored.systemFields = systemFields
            stored.localRevision += 1
            plainRecords[server.key] = stored
            return
        }
        let revision = plainRecords[server.key]?.localRevision ?? 0
        plainRecords[server.key] = StoredPlainRecord(record: server, needsUpload: false, systemFields: systemFields, localRevision: revision)
    }

    /// iCloud no longer has the record. Deletes are soft, so this happens only when the record is
    /// really gone; the local copy goes too.
    public mutating func removeEvent(_ id: String) { events[id] = nil }

    public mutating func removePlainRecord(_ key: String) { plainRecords[key] = nil }

    // MARK: Helpers

    static func changedFields(from before: EventSnapshot, to after: EventSnapshot) -> Set<EventField> {
        var changed: Set<EventField> = []
        if before.event.startedAt != after.event.startedAt { changed.insert(.startedAt) }
        if before.event.endedAt != after.event.endedAt { changed.insert(.endedAt) }
        if before.event.deletedAt != after.event.deletedAt { changed.insert(.deletedAt) }
        if before.payload?.feed?.breast ?? [] != after.payload?.feed?.breast ?? [] { changed.insert(.breast) }
        if before.payload?.feed?.bottles ?? [] != after.payload?.feed?.bottles ?? [] { changed.insert(.bottles) }
        if before.payload?.pump != after.payload?.pump { changed.insert(.pump) }
        if before.payload?.note != after.payload?.note { changed.insert(.note) }
        return changed
    }

    /// Gives the open segment (started, no length yet) its length up to `now`.
    static func closeOpenSegment(_ feed: inout FeedDetails, now: Date) {
        guard let last = feed.breast.indices.last, feed.breast[last].durationSeconds == nil,
              let started = feed.breast[last].startedAt else { return }
        feed.breast[last].durationSeconds = max(0, Int(now.timeIntervalSince(started).rounded()))
    }
}

/// Reads and writes the household file.
public enum HouseholdFile {
    public enum LoadError: Error, Equatable {
        /// A newer app version wrote the file. It must not be overwritten.
        case newerFormat(Int)
    }

    /// Nil when there is no file yet. Throws when the file can't be read or is from a newer app.
    public static func load(from url: URL) throws -> HouseholdData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        struct FormatProbe: Decodable { var format: Int }
        let probe = try decoder.decode(FormatProbe.self, from: data)
        guard probe.format <= HouseholdData.currentFormat else { throw LoadError.newerFormat(probe.format) }
        return try decoder.decode(HouseholdData.self, from: data)
    }

    /// Writes the whole file at once, so a crash leaves the old file or the new one, never half.
    /// The app adds its file protection option.
    public static func save(_ household: HouseholdData, to url: URL, options: Data.WritingOptions = []) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(household).write(to: url, options: options.union(.atomic))
    }
}
