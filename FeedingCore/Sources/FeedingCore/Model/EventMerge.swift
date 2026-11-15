import Foundation

/// An event as one phone holds it: the top-level record fields and the decoded details.
public struct EventSnapshot: Hashable, Sendable, Identifiable {
    public var event: Event
    /// Nil when the payload is missing, can't be read, or came from a newer app version.
    public var payload: EventPayload?

    public var id: String { event.id }

    public init(event: Event, payload: EventPayload?) {
        self.event = event
        self.payload = payload
    }

    /// Decodes the event's own payload.
    public init(event: Event) {
        self.init(event: event, payload: PayloadCoder.decode(EventPayload.self, from: event.payload))
    }

    /// Copies one field's value from `other`. With no payload to write into, payload fields stay.
    public mutating func copy(_ field: EventField, from other: EventSnapshot) {
        switch field {
        case .startedAt: event.startedAt = other.event.startedAt
        case .endedAt: event.endedAt = other.event.endedAt
        case .deletedAt: event.deletedAt = other.event.deletedAt
        case .breast:
            var feed = payload?.feed ?? FeedDetails()
            feed.breast = other.payload?.feed?.breast ?? []
            payload?.feed = feed
        case .bottles:
            var feed = payload?.feed ?? FeedDetails()
            feed.bottles = other.payload?.feed?.bottles ?? []
            payload?.feed = feed
        case .pump: payload?.pump = other.payload?.pump
        case .note: payload?.note = other.payload?.note
        }
    }

    /// The fields that differ between two copies of an event.
    public static func changedFields(from before: EventSnapshot, to after: EventSnapshot) -> Set<EventField> {
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

    /// The event with `payload` encoded into it, ready to save.
    public func encoded() throws -> Event {
        var result = event
        if let payload {
            result.payload = try PayloadCoder.encode(payload)
        }
        return result
    }
}

/// The outcome of merging this phone's edits onto iCloud's copy.
public struct MergeResult: Hashable, Sendable {
    public var snapshot: EventSnapshot
    /// Fields where this phone's edit won.
    public var applied: Set<EventField>
    /// Fields this phone changed, where the other phone's later edit won.
    public var overruled: Set<EventField>
    /// True when iCloud's copy couldn't be read (a newer app wrote it), so it was kept whole.
    public var keptServerCopyUnread: Bool
}

/// Merges this phone's edits onto iCloud's copy after a save clash (`serverRecordChanged`).
///
/// Only the fields this phone changed are considered. For each, this phone's edit wins when its
/// stamp is later than the stamp on iCloud's copy. Everything else keeps iCloud's value, so a
/// correction made on the other phone is never overwritten by an old copy.
public func merge(local: EventSnapshot, server: EventSnapshot, changedLocally: Set<EventField>) -> MergeResult {
    guard server.payload != nil else {
        return MergeResult(snapshot: server, applied: [], overruled: changedLocally, keptServerCopyUnread: true)
    }
    var result = server
    var applied: Set<EventField> = []
    var overruled: Set<EventField> = []

    for field in EventField.allCases where changedLocally.contains(field) {
        guard let mine = local.payload?.stamp(field) else {
            overruled.insert(field)
            continue
        }
        if let theirs = result.payload?.stamp(field), theirs >= mine {
            overruled.insert(field)
            continue
        }
        result.copy(field, from: local)
        result.payload?.setStamp(field, mine)
        applied.insert(field)
    }
    result.event.modifiedAt = max(local.event.modifiedAt, server.event.modifiedAt)
    return MergeResult(snapshot: result, applied: applied, overruled: overruled, keptServerCopyUnread: false)
}
