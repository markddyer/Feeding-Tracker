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
    /// Changed fields a newer build named that this build doesn't know (step 0, CEO review D18).
    /// They are kept for the newer build and cleared when the change is sent or replaced.
    public var keptChangedFields: Set<String> = []
    /// What Undo puts back for a first's delete or a photo taken out, held on this phone until
    /// `uploadNotBefore` (outside review O6). Gone once the change is sent.
    public var heldUndo: HeldUndo?

    public var snapshot: EventSnapshot { EventSnapshot(event: event) }
}

/// A first's delete, or photos taken out of a first, waiting on this phone for the Undo window.
/// Its photos are deleted for good once the change is sent, so it is never sent before Undo has
/// ended (outside review O6, outside voice OE4).
public struct HeldUndo: Hashable, Sendable, Codable {
    /// True for a first's delete: Undo shows the first again.
    public var undeletes: Bool
    /// The photo list before, for Undo to put back.
    public var media: [String]
    /// Photos the held saves added (a replaced photo's new one): Undo takes them out again, onto
    /// the removed list, so they are never sent.
    public var addedLocally: [String]
    /// The IDs the held change put on the removed list, for Undo to take off again. An ID iCloud
    /// already has as removed (the other phone removed it too) is taken off this list, as Undo
    /// can't bring that one back.
    public var addedRemovals: [String]
    /// The crops of the photos the held change took out, so Undo puts each back in its place in the
    /// square (Codex review of step 2). Nil from a build before 19 Nov 2026.
    public var crops: [String: MediaCrop]?

    public init(undeletes: Bool, media: [String], addedLocally: [String] = [], addedRemovals: [String],
                crops: [String: MediaCrop]? = nil) {
        self.undeletes = undeletes
        self.media = media
        self.addedLocally = addedLocally
        self.addedRemovals = addedRemovals
        self.crops = crops
    }

    /// What Undo can still do once iCloud's copy says `removed` are removed, and whether the
    /// first is deleted there (Codex review of T5 and T6).
    func trimmed(byICloud removed: Set<String>, deleted: Bool) -> HeldUndo {
        var held = self
        held.addedRemovals.removeAll { removed.contains($0) }
        held.media.removeAll { removed.contains($0) }
        if deleted { held.undeletes = false }
        return held
    }
}

extension StoredEvent {
    private enum CodingKeys: String, CodingKey {
        case event, changedFields, needsUpload, uploadNotBefore, systemFields, localRevision, heldUndo
    }

    /// Reads the changed fields by name, so one this build doesn't know is kept, not fatal.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(Event.self, forKey: .event)
        let names = try container.decode([String].self, forKey: .changedFields)
        changedFields = Set(names.compactMap(EventField.init(rawValue:)))
        keptChangedFields = Set(names.filter { EventField(rawValue: $0) == nil })
        needsUpload = try container.decode(Bool.self, forKey: .needsUpload)
        uploadNotBefore = try container.decodeIfPresent(Date.self, forKey: .uploadNotBefore)
        systemFields = try container.decodeIfPresent(Data.self, forKey: .systemFields)
        localRevision = try container.decode(Int.self, forKey: .localRevision)
        heldUndo = try? container.decodeIfPresent(HeldUndo.self, forKey: .heldUndo)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event, forKey: .event)
        try container.encode((changedFields.map(\.rawValue) + keptChangedFields).sorted(), forKey: .changedFields)
        try container.encode(needsUpload, forKey: .needsUpload)
        try container.encodeIfPresent(uploadNotBefore, forKey: .uploadNotBefore)
        try container.encodeIfPresent(systemFields, forKey: .systemFields)
        try container.encode(localRevision, forKey: .localRevision)
        try container.encodeIfPresent(heldUndo, forKey: .heldUndo)
    }
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

    public init(record: PlainRecord, needsUpload: Bool, systemFields: Data?, localRevision: Int) {
        self.record = record
        self.needsUpload = needsUpload
        self.systemFields = systemFields
        self.localRevision = localRevision
    }
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

/// Everything one phone holds about the household.
///
/// **Rule for later versions (step 0, CEO review D18):** an older build skips and keeps what it
/// doesn't know: a new part of the file, a new kind of record, an entry it can't read, and a new
/// `EventField` name. So add new things that way. Raise `currentFormat` only for a change an older
/// build must not read at all; such a file is never written over, and the older build waits for
/// iCloud before it cancels any alert (`isWaitingForICloud`). Never change the type of a field an
/// older build already reads: its whole entry would be skipped.
public struct HouseholdData: Hashable, Sendable, Codable {
    public static let currentFormat = 1
    /// How long a new event waits before it is sent, so Undo can take it back quietly.
    public static let undoWindow: TimeInterval = 10

    public var format: Int
    public var events: [String: StoredEvent]
    public var plainRecords: [String: StoredPlainRecord]
    /// The sync engines' saved state, by database ("private", "shared"). Opaque here.
    public var syncState: [String: Data]
    /// Events, plain records and parts of the file that a newer build wrote and this build can't
    /// read, by their key in the file. Kept as they were and written back (step 0, CEO review D18).
    public private(set) var keptEvents: [String: KeptJSON]
    public private(set) var keptPlainRecords: [String: KeptJSON]
    public private(set) var keptParts: [String: KeptJSON]
    /// When this phone's file couldn't be read (moved aside, or written by a newer build). Until
    /// iCloud has sent the household back, or for a day at most, what the phone knows may be
    /// missing feeds, so no alert already set is cancelled (CEO review D18, `planAlertChanges`).
    public var waitingForICloudSince: Date?
    /// Entries fetched again by name because their "done by" or "got up" had a stamp with no
    /// value, that iCloud had no value for either: never fetched again (engineering review of
    /// "who does what", E3, D9 A). A part of the file an older build keeps as it is.
    public internal(set) var whoValuesChecked: Set<String> = []

    public init() {
        format = Self.currentFormat
        events = [:]
        plainRecords = [:]
        syncState = [:]
        keptEvents = [:]
        keptPlainRecords = [:]
        keptParts = [:]
        waitingForICloudSince = nil
    }

    /// The longest a phone waits for iCloud before planning alerts from what it holds: every alert
    /// set from the lost data belongs to a feed window, which is long past by then. It also ends the
    /// wait on a phone with no iCloud, or with sync off.
    public static let longestWaitForICloud: TimeInterval = 24 * 3600

    // MARK: Reading

    /// See `waitingForICloudSince`. A clock set back keeps the phone waiting, never the reverse.
    public func isWaitingForICloud(now: Date) -> Bool {
        guard let since = waitingForICloudSince else { return false }
        return now.timeIntervalSince(since) < Self.longestWaitForICloud
    }

    /// True when each baby's latest feed that the alerts were planned from before the file was
    /// lost (`latest`, kept outside the file) is back, within a second, as iCloud keeps
    /// milliseconds. Entries of other kinds coming back are not enough: until the feeds are, or
    /// for a day at most, the phone keeps waiting and cancels no alert (CEO review D18). A feed
    /// that never reached iCloud never comes back, so its alert is kept for that day. With nothing
    /// noted (`nil`: a build from before this rule), any feed coming back is enough.
    public func hasFeedsBack(plannedFrom latest: [String: Date]?, now: Date) -> Bool {
        let events = allEvents
        guard let latest else { return events.contains(where: \.isLiveFeed) }
        return latest.allSatisfy { baby, start in
            (events.latestFeedStart(babyID: baby, now: now) ?? .distantPast) >= start.addingTimeInterval(-1)
        }
    }

    public var snapshots: [EventSnapshot] { events.values.map(\.snapshot) }

    public var allEvents: [Event] { events.values.map(\.event) }

    /// The newest feed for `babyID` that has started and not finished, if any. A copy of a feed
    /// logged on both phones (`hiddenDuplicates`) is left out, so when both parents tap Start feed
    /// at once, both phones show the feed logged first.
    public func feedInProgress(babyID: String) -> EventSnapshot? {
        let hidden = hiddenDuplicates(babyID: babyID)
        return events.values.lazy.map(\.event)
            .filter { $0.isLiveFeed && $0.babyID == babyID && $0.endedAt == nil && !hidden.contains($0.id) }
            .max { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
            .map { EventSnapshot(event: $0) }
    }

    // MARK: Changes made on this phone

    /// Adds a new event. Every field of its kind is stamped (`EventField.fields(for:)`), so if the
    /// same record ever meets an older copy in iCloud, this one wins. A "done by" given now (a
    /// breastfeed logged for the other parent, design 4B) is stored and stamped too; with none,
    /// there is no "done by" stamp (`EventField.onlyWhenSet`). Returns the event's ID.
    @discardableResult
    public mutating func add(
        id: String = UUID().uuidString, kind: EventKind, babyID: String, startedAt: Date, endedAt: Date? = nil,
        payload: EventPayload, by member: MemberID, doneBy: MemberID? = nil, timeZoneID: String, now: Date
    ) -> String {
        var payload = payload
        var fields = EventField.fields(for: kind)
        if doneBy != nil, kind.countsAsWork { fields.insert(.doneBy) }
        for field in fields { payload.setStamp(field, FieldStamp(at: now, by: member)) }
        let event = Event(id: id, babyID: babyID, kind: kind, startedAt: startedAt, endedAt: endedAt,
                          timeZoneID: timeZoneID, loggedBy: member, createdAt: now, modifiedAt: now,
                          payload: try? PayloadCoder.encode(payload),
                          doneBy: kind.countsAsWork ? doneBy : nil)
        events[id] = StoredEvent(event: event, changedFields: fields, needsUpload: true,
                                 uploadNotBefore: now.addingTimeInterval(Self.undoWindow), systemFields: nil, localRevision: 1)
        return id
    }

    /// Starts a feed now, timed live, optionally on a side or with a bottle (for a parent who
    /// feeds by bottle only). A sleep running now ends (the users' choice O, 17 Nov 2026: the baby
    /// woke to feed).
    @discardableResult
    public mutating func startFeed(id: String = UUID().uuidString, babyID: String, side: BreastSide?,
                                   bottle: MilkKind? = nil,
                                   by member: MemberID, timeZoneID: String, now: Date) -> String {
        let breast = side.map { [BreastSegment(side: $0, startedAt: now)] } ?? []
        let bottles = bottle.map { [Bottle(milk: $0)] } ?? []
        let id = add(id: id, kind: .feed, babyID: babyID, startedAt: now,
                     payload: EventPayload(feed: FeedDetails(breast: breast, bottles: bottles)),
                     by: member, timeZoneID: timeZoneID, now: now)
        endSleepForFeed(babyID: babyID, start: now, feedID: id, by: member, now: now)
        return id
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
        Self.keepSleepEnding(before: before, after: &after, by: member)
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

    /// "Done by" chosen by a parent (R2): on the Undo bar's swap or in an editor. Only for kinds
    /// that count as work; a stored choice always wins and is never cleared. Returns false for
    /// another kind, an unknown event, or details from a newer app version.
    @discardableResult
    public mutating func setDoneBy(_ id: String, to doer: MemberID, by member: MemberID, now: Date) -> Bool {
        guard let kind = events[id]?.event.kind, kind.countsAsWork else { return false }
        return edit(id, by: member, now: now) { $0.event.doneBy = doer }
    }

    /// "Got up" chosen by a parent for an ended sleep (R3): on the Woke up bar's swap or in the
    /// sleep's editor. It is given for the sleep's current ending (`Event.endingID`), so a later
    /// ending ignores it, and to every sleep of the baby that one wake-up ended (the same wake-up
    /// ID, D8 A), as they are one wake-up. Returns false for a running sleep, another kind or an
    /// unknown event.
    @discardableResult
    public mutating func setGotUp(_ id: String, to riser: MemberID, by member: MemberID, now: Date) -> Bool {
        guard let event = events[id]?.event, event.kind == .sleep, event.endingID != nil else { return false }
        let wakeUp = event.wakeID.map { wake in
            allEvents.filter { $0.kind == .sleep && $0.babyID == event.babyID && $0.endedAt != nil && $0.wakeID == wake }
        } ?? [event]
        var done = false
        for sleep in wakeUp {
            guard let ending = sleep.endingID else { continue }
            let changed = edit(sleep.id, by: member, now: now) { snapshot in
                snapshot.event.gotUpBy = riser
                snapshot.event.gotUpFor = ending
            }
            if sleep.id == id { done = changed }
        }
        return done
    }

    /// Entries whose own copy holds a "done by" or "got up" stamp with no value, not yet checked: an
    /// older build of the app dropped the value from this phone's file, and iCloud still has it
    /// (engineering review E3, D9 A). The app fetches just these by name at launch.
    public var entriesMissingWhoValues: [String] {
        events.values.filter { !whoValuesChecked.contains($0.event.id) && Self.missesWhoValue($0) }.map(\.event.id).sorted()
    }

    /// After fetching `ids` by name and receiving what came back: an entry still missing a value is
    /// noted as checked, so it is never fetched again; one that has its values now leaves the note.
    public mutating func noteWhoValuesFetched(_ ids: [String]) {
        for id in ids {
            guard let stored = events[id] else { continue }
            if Self.missesWhoValue(stored) { whoValuesChecked.insert(id) } else { whoValuesChecked.remove(id) }
        }
    }

    /// A stamp always means a value (`EventField.onlyWhenSet`), so a stamp alone means a lost one.
    static func missesWhoValue(_ stored: StoredEvent) -> Bool {
        guard let payload = stored.snapshot.payload else { return false }
        let event = stored.event
        return (payload.stamp(.doneBy) != nil && event.doneBy == nil)
            || (payload.stamp(.gotUp) != nil && (event.gotUpBy == nil || event.gotUpFor == nil))
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

    /// Hides an event. It is never removed from iCloud. A first's delete is held for its Undo
    /// window (`deleteMilestone`).
    @discardableResult
    public mutating func delete(_ id: String, by member: MemberID, now: Date) -> Bool {
        if events[id]?.event.kind == .milestone { return deleteMilestone(id, by: member, now: now) }
        return edit(id, by: member, now: now) { $0.event.deletedAt = now }
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

    /// The app is going to the background: everything waiting may be sent at once, and Undo ends
    /// with it.
    public mutating func endUndoWindows() {
        for id in events.keys {
            events[id]?.uploadNotBefore = nil
            events[id]?.heldUndo = nil
        }
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
            .filter { Self.mayUpload($0, now: now) }
            .sorted { ($0.event.createdAt, $0.event.id) < ($1.event.createdAt, $1.event.id) }
    }

    /// The one answer to "may this go now?", for `eventsToUpload` and for the sync engine asking
    /// for a record to send: changed here and past its undo window. So a change queued earlier
    /// can't carry a held delete out early (outside voice OE4).
    public static func mayUpload(_ stored: StoredEvent, now: Date) -> Bool {
        stored.needsUpload && (stored.uploadNotBefore.map { $0 <= now } ?? true)
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
            stored.keptChangedFields = []
            stored.needsUpload = false
            stored.heldUndo = nil
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
        // This build can read iCloud's copy, so a kept, unreadable entry for it is no longer needed.
        // A newer build's change in it that was never sent is lost: this build can't send or merge
        // it, and iCloud's copy (with any feed in it, for the alerts) is the one it can use.
        keptEvents[server.id] = nil
        guard var stored = events[server.id], stored.needsUpload, !stored.changedFields.isEmpty else {
            let previous = events[server.id]
            let revision = previous?.localRevision ?? 0
            var incoming = StoredEvent(event: server, changedFields: [], needsUpload: false, uploadNotBefore: nil,
                                       systemFields: systemFields, localRevision: revision)
            // A first's photos and removals this phone holds and iCloud's copy lacks (an older copy
            // arriving late) are kept and sent again, so a removed photo never comes back and a
            // kept one never goes (eng D10, the parents' choice A).
            if let previous, previous.event.kind == .milestone {
                let healed = merge(local: previous.snapshot, server: EventSnapshot(event: server), changedLocally: [])
                if !healed.applied.isEmpty, var event = try? healed.snapshot.encoded() {
                    event.serverCreatedAt = server.serverCreatedAt ?? previous.event.serverCreatedAt
                    incoming.event = event
                    incoming.changedFields = healed.applied
                    incoming.needsUpload = true
                    incoming.localRevision = revision + 1
                    events[server.id] = incoming
                    return .merged(applied: healed.applied, overruled: [])
                }
            }
            events[server.id] = incoming
            return .replaced
        }
        let serverSnapshot = EventSnapshot(event: server)
        let result = merge(local: stored.snapshot, server: serverSnapshot, changedLocally: stored.changedFields)
        stored.systemFields = systemFields
        stored.localRevision += 1
        // A held change's Undo can't take back what iCloud already has from the other phone. A
        // photo the other phone added to a first this phone holds deleted is moved onto the
        // removed list by the merge; Undo must bring that one back too.
        if let held = stored.heldUndo {
            if result.keptServerCopyUnread {
                stored.heldUndo = nil
            } else {
                let serverRemoved = Set(serverSnapshot.payload?.milestone?.removedMedia ?? [])
                let localRemoved = Set(stored.snapshot.payload?.milestone?.removedMedia ?? [])
                let mergedRemoved = Set(result.snapshot.payload?.milestone?.removedMedia ?? [])
                let movedByMerge = (serverSnapshot.payload?.milestone?.media ?? []).filter {
                    mergedRemoved.contains($0) && !serverRemoved.contains($0) && !localRemoved.contains($0)
                }
                var adjusted = held.trimmed(byICloud: serverRemoved, deleted: server.deletedAt != nil)
                adjusted.media += movedByMerge.filter { !adjusted.media.contains($0) }
                adjusted.addedRemovals += movedByMerge.filter { !adjusted.addedRemovals.contains($0) }
                stored.heldUndo = adjusted
            }
        }
        // Fields this build can't name can't be merged: iCloud's copy decides them.
        stored.keptChangedFields = []
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
        keptPlainRecords[server.key] = nil
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
    public mutating func removeEvent(_ id: String) {
        events[id] = nil
        keptEvents[id] = nil
    }

    public mutating func removePlainRecord(_ key: String) {
        plainRecords[key] = nil
        keptPlainRecords[key] = nil
    }

    // MARK: Helpers

    static func changedFields(from before: EventSnapshot, to after: EventSnapshot) -> Set<EventField> {
        EventSnapshot.changedFields(from: before, to: after)
    }

    /// Every ending of a sleep carries its wake-up ID (engineering review of "who does what", D8 A),
    /// whichever screen ends it: a sleep made to run again (Undo of Woke up, the editor's "Still
    /// asleep") loses its ID, and one ended without an ID of its own (the editor) gets a new one,
    /// with the parent who ended it as "got up". Woke up and the feed rules set their own ID, which
    /// is kept. A sleep ended before wake-up IDs existed keeps none when only its time changes.
    static func keepSleepEnding(before: EventSnapshot, after: inout EventSnapshot, by member: MemberID) {
        guard after.event.kind == .sleep else { return }
        if after.event.endedAt == nil {
            after.event.wakeID = nil
        } else if before.event.endedAt == nil, after.event.wakeID == nil || after.event.wakeID == before.event.wakeID {
            let wake = UUID().uuidString
            after.event.wakeID = wake
            after.event.gotUpBy = member
            after.event.gotUpFor = wake
        }
    }

    /// Gives the open segment (started, no length yet) its length up to `now`.
    static func closeOpenSegment(_ feed: inout FeedDetails, now: Date) {
        guard let last = feed.breast.indices.last, feed.breast[last].durationSeconds == nil,
              let started = feed.breast[last].startedAt else { return }
        feed.breast[last].durationSeconds = max(0, Int(now.timeIntervalSince(started).rounded()))
    }
}

// MARK: Reading a file a newer build wrote

extension HouseholdData {
    private static let knownParts: Set<String> = ["format", "events", "plainRecords", "syncState", "waitingForICloudSince",
                                                  "whoValuesChecked"]

    /// Reads every entry it can. An entry it can't read, and a part of the file it doesn't know, is
    /// kept as it was (step 0, CEO review D18). A file that isn't JSON at all still throws.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        format = try container.decode(Int.self, forKey: AnyCodingKey("format"))
        syncState = try container.decode([String: Data].self, forKey: AnyCodingKey("syncState"))
        waitingForICloudSince = try container.decodeIfPresent(Date.self, forKey: AnyCodingKey("waitingForICloudSince"))
        whoValuesChecked = Set((try? container.decodeIfPresent([String].self, forKey: AnyCodingKey("whoValuesChecked"))) ?? [])
        (events, keptEvents) = Self.split(try container.decode([String: Lenient<StoredEvent>].self,
                                                               forKey: AnyCodingKey("events")))
        (plainRecords, keptPlainRecords) = Self.split(try container.decode([String: Lenient<StoredPlainRecord>].self,
                                                                           forKey: AnyCodingKey("plainRecords")))
        var parts: [String: KeptJSON] = [:]
        for key in container.allKeys where !Self.knownParts.contains(key.stringValue) {
            parts[key.stringValue] = try container.decode(KeptJSON.self, forKey: key)
        }
        keptParts = parts
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (name, part) in keptParts where !Self.knownParts.contains(name) {
            try container.encode(part, forKey: AnyCodingKey(name))
        }
        try container.encode(format, forKey: AnyCodingKey("format"))
        try container.encode(syncState, forKey: AnyCodingKey("syncState"))
        try container.encodeIfPresent(waitingForICloudSince, forKey: AnyCodingKey("waitingForICloudSince"))
        if !whoValuesChecked.isEmpty {
            try container.encode(whoValuesChecked.sorted(), forKey: AnyCodingKey("whoValuesChecked"))
        }
        try container.encode(Self.joined(events, keptEvents), forKey: AnyCodingKey("events"))
        try container.encode(Self.joined(plainRecords, keptPlainRecords), forKey: AnyCodingKey("plainRecords"))
    }

    private static func split<Value>(_ entries: [String: Lenient<Value>]) -> ([String: Value], [String: KeptJSON]) {
        var read: [String: Value] = [:]
        var kept: [String: KeptJSON] = [:]
        for (key, entry) in entries {
            switch entry {
            case .read(let value): read[key] = value
            case .kept(let json): kept[key] = json
            }
        }
        return (read, kept)
    }

    /// The entries to write: every one this build reads, and every kept one it doesn't also hold.
    private static func joined<Value>(_ read: [String: Value], _ kept: [String: KeptJSON]) -> [String: Lenient<Value>] {
        var all = kept.filter { read[$0.key] == nil }.mapValues { Lenient<Value>.kept($0) }
        for (key, value) in read { all[key] = .read(value) }
        return all
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

extension HouseholdData {
    /// Changes a parent's colour ("Your colour" in Settings), keeping the rest of their Member
    /// record. Returns false and changes nothing when there is no record yet, or when a newer app
    /// version wrote it, so nothing that version saved is lost.
    @discardableResult
    public mutating func setColour(_ colour: String, of member: MemberID, now: Date) -> Bool {
        guard let record = plainRecord(.member, member.rawValue),
              var payload = PayloadCoder.decode(MemberPayload.self, from: record.payload) else { return false }
        guard payload.colour != colour else { return true }
        payload.colour = colour
        guard let data = try? PayloadCoder.encode(payload) else { return false }
        var updated = record
        updated.payload = data
        updated.modifiedAt = now
        put(updated)
        return true
    }
}

// MARK: - One feed logged on both phones

/// Two feeds the parents said are two real feeds, not one feed logged on both phones ("They were
/// two feeds"). A Setting record, so both phones see it.
public struct DistinctFeeds: Hashable, Sendable, Codable {
    /// The two event IDs, sorted.
    public var ids: [String]
    public var by: MemberID
    public var at: Date

    public init(_ first: String, _ second: String, by: MemberID, at: Date) {
        ids = [first, second].sorted()
        self.by = by
        self.at = at
    }
}

extension SettingKey {
    /// "distinct-<id>-<id>", the two IDs sorted, so both phones name the record the same.
    public static func distinct(_ first: String, _ second: String) -> String {
        let ids = [first, second].sorted()
        return "distinct-\(ids[0])-\(ids[1])"
    }
}

extension HouseholdData {
    /// Every pair the parents marked as two feeds.
    public var distinctFeedPairs: Set<Set<String>> {
        Set(plainRecords(of: .setting).filter { $0.name.hasPrefix("distinct-") }.compactMap {
            PayloadCoder.decode(SettingPayload<DistinctFeeds>.self, from: $0.payload).map { Set($0.value.ids) }
        })
    }

    /// Feeds of `babyID` that look like one feed logged on both phones: starting within 5 minutes
    /// of each other, logged by different parents, and not marked as two feeds.
    public func duplicatePairs(babyID: String) -> [DuplicatePair] {
        duplicateFeeds(allEvents.filter { $0.babyID == babyID }, confirmedDistinct: distinctFeedPairs)
    }

    /// The copies the screens leave out: in each pair, the feed logged second. Only the screens
    /// use this: `reconcile` reads every feed, so alerts never depend on a merge.
    public func hiddenDuplicates(babyID: String) -> Set<String> {
        Set(duplicatePairs(babyID: babyID).map(\.duplicate))
    }

    /// What the screens show for `babyID`: every event except the hidden copies.
    public func visibleSnapshots(babyID: String) -> [EventSnapshot] {
        let hidden = hiddenDuplicates(babyID: babyID)
        return snapshots.filter { !hidden.contains($0.id) }
    }

    /// "They were two feeds": both show again, on both phones.
    public mutating func markDistinct(_ first: String, _ second: String, by member: MemberID, now: Date) {
        putSetting(DistinctFeeds(first, second, by: member, at: now), key: SettingKey.distinct(first, second), now: now)
    }

    /// This parent's own hidden copies still running after the feed they copy has finished, with
    /// the time to end each: the kept feed's end, or the copy's start if that is later.
    public func strandedDuplicates(by member: MemberID) -> [(id: String, end: Date)] {
        let babies = Set(allEvents.map(\.babyID))
        return babies.flatMap { baby in
            duplicatePairs(babyID: baby).compactMap { pair -> (id: String, end: Date)? in
                guard let copy = events[pair.duplicate]?.event, copy.loggedBy == member, copy.endedAt == nil,
                      copy.isLiveFeed, let keptEnd = events[pair.kept]?.event.endedAt else { return nil }
                return (copy.id, max(keptEnd, copy.startedAt))
            }
        }
    }

    /// Ends this parent's stranded copies (see `strandedDuplicates`), so a copy put aside when both
    /// parents tapped Start feed finishes with the feed it copies. Changes only this parent's own
    /// records, so the two phones never fight over one. Returns false when there was nothing to do.
    @discardableResult
    public mutating func finishStrandedDuplicates(by member: MemberID, now: Date) -> Bool {
        let stranded = strandedDuplicates(by: member)
        for (id, end) in stranded {
            edit(id, by: member, now: now) { snapshot in
                if var feed = snapshot.payload?.feed {
                    Self.closeOpenSegment(&feed, now: end)
                    snapshot.payload?.feed = feed
                }
                snapshot.event.endedAt = end
            }
        }
        return !stranded.isEmpty
    }
}
