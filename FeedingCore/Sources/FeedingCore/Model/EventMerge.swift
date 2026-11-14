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
    guard var payload = server.payload else {
        return MergeResult(snapshot: server, applied: [], overruled: changedLocally, keptServerCopyUnread: true)
    }
    var event = server.event
    var applied: Set<EventField> = []
    var overruled: Set<EventField> = []

    for field in EventField.allCases where changedLocally.contains(field) {
        guard let mine = local.payload?.stamp(field) else {
            overruled.insert(field)
            continue
        }
        if let theirs = payload.stamp(field), theirs >= mine {
            overruled.insert(field)
            continue
        }
        switch field {
        case .startedAt: event.startedAt = local.event.startedAt
        case .endedAt: event.endedAt = local.event.endedAt
        case .deletedAt: event.deletedAt = local.event.deletedAt
        case .breast:
            var feed = payload.feed ?? FeedDetails()
            feed.breast = local.payload?.feed?.breast ?? []
            payload.feed = feed
        case .bottles:
            var feed = payload.feed ?? FeedDetails()
            feed.bottles = local.payload?.feed?.bottles ?? []
            payload.feed = feed
        case .pump: payload.pump = local.payload?.pump
        case .note: payload.note = local.payload?.note
        }
        payload.setStamp(field, mine)
        applied.insert(field)
    }
    event.modifiedAt = max(local.event.modifiedAt, server.event.modifiedAt)
    return MergeResult(snapshot: EventSnapshot(event: event, payload: payload), applied: applied,
                       overruled: overruled, keptServerCopyUnread: false)
}
