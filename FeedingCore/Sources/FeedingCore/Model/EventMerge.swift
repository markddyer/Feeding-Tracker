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
        case .endedAt:
            event.endedAt = other.event.endedAt
            event.wakeID = other.event.wakeID
        case .deletedAt: event.deletedAt = other.event.deletedAt
        case .doneBy: event.doneBy = other.event.doneBy
        case .gotUp:
            event.gotUpBy = other.event.gotUpBy
            event.gotUpFor = other.event.gotUpFor
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
        case .nappy, .pooColour, .pooConsistency:
            // Each part on its own, so a colour added on one phone and a consistency on the other
            // are both kept. Only where either copy is a nappy, so nothing else gains nappy details.
            guard payload?.nappy != nil || other.payload?.nappy != nil else { return }
            let theirs = other.payload?.nappy
            var nappy = payload?.nappy ?? NappyDetails(wee: false, poo: false)
            switch field {
            case .nappy:
                nappy.wee = theirs?.wee ?? false
                nappy.poo = theirs?.poo ?? false
            case .pooColour: nappy.colour = theirs?.colour
            default: nappy.consistency = theirs?.consistency
            }
            payload?.nappy = nappy
        case .medicine: payload?.medicine = other.payload?.medicine
        case .weight, .length, .head:
            // Only where either copy has growth details, so a feed never gains an empty set of
            // them (which would raise its version and hide it from an older build).
            guard payload?.growth != nil || other.payload?.growth != nil else { return }
            var growth = payload?.growth ?? GrowthDetails()
            let theirs = other.payload?.growth
            switch field {
            case .weight: growth.weightGrams = theirs?.weightGrams
            case .length: growth.lengthMM = theirs?.lengthMM
            default: growth.headMM = theirs?.headMM
            }
            payload?.growth = growth
        case .title, .media, .removedMedia, .crops:
            // Only where either copy is a first, so nothing else gains a first's details (which
            // would raise its version and hide it from an older build).
            guard payload?.milestone != nil || other.payload?.milestone != nil else { return }
            let theirs = other.payload?.milestone
            var milestone = payload?.milestone ?? MilestoneDetails(title: "")
            switch field {
            case .title: milestone.title = theirs?.title ?? ""
            case .media: milestone.media = theirs?.media ?? []
            case .crops: milestone.crops = theirs?.crops ?? [:]
            // Removed items only add up: copying joins the two lists (eng D10).
            default: milestone.removedMedia = milestone.removedMedia + (theirs?.removedMedia ?? [])
            }
            milestone.normalize()
            payload?.milestone = milestone
        }
    }

    /// The fields that differ between two copies of an event.
    public static func changedFields(from before: EventSnapshot, to after: EventSnapshot) -> Set<EventField> {
        var changed: Set<EventField> = []
        if before.event.startedAt != after.event.startedAt { changed.insert(.startedAt) }
        if before.event.endedAt != after.event.endedAt || before.event.wakeID != after.event.wakeID {
            changed.insert(.endedAt)
        }
        if before.event.deletedAt != after.event.deletedAt { changed.insert(.deletedAt) }
        if before.event.doneBy != after.event.doneBy { changed.insert(.doneBy) }
        if before.event.gotUpBy != after.event.gotUpBy || before.event.gotUpFor != after.event.gotUpFor {
            changed.insert(.gotUp)
        }
        if before.payload?.feed?.breast ?? [] != after.payload?.feed?.breast ?? [] { changed.insert(.breast) }
        if before.payload?.feed?.bottles ?? [] != after.payload?.feed?.bottles ?? [] { changed.insert(.bottles) }
        if before.payload?.pump != after.payload?.pump { changed.insert(.pump) }
        if before.payload?.note != after.payload?.note { changed.insert(.note) }
        let (was, now) = (before.payload?.nappy, after.payload?.nappy)
        if was?.wee != now?.wee || was?.poo != now?.poo { changed.insert(.nappy) }
        if was?.colour != now?.colour { changed.insert(.pooColour) }
        if was?.consistency != now?.consistency { changed.insert(.pooConsistency) }
        if before.payload?.medicine != after.payload?.medicine { changed.insert(.medicine) }
        let (old, new) = (before.payload?.growth, after.payload?.growth)
        if old?.weightGrams != new?.weightGrams { changed.insert(.weight) }
        if old?.lengthMM != new?.lengthMM { changed.insert(.length) }
        if old?.headMM != new?.headMM { changed.insert(.head) }
        let (first, last) = (before.payload?.milestone, after.payload?.milestone)
        if first?.title != last?.title { changed.insert(.title) }
        if first?.media != last?.media { changed.insert(.media) }
        if first?.removedMedia != last?.removedMedia { changed.insert(.removedMedia) }
        if first?.crops ?? [:] != last?.crops ?? [:] { changed.insert(.crops) }
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
///
/// A first's photo lists are the exception, whether or not they changed here (an older copy can
/// also arrive late):
/// - the removed lists join (eng D10);
/// - the media lists join (the parents' choice A, 18 Nov 2026): the order of the later change,
///   then any item only the other list has, up to the limit. So a photo added on each phone at
///   the same time is kept on both, and a photo leaves a first only when a parent takes it out:
///   no removed item is ever named again.
public func merge(local: EventSnapshot, server: EventSnapshot, changedLocally: Set<EventField>) -> MergeResult {
    guard server.payload != nil else {
        return MergeResult(snapshot: server, applied: [], overruled: changedLocally, keptServerCopyUnread: true)
    }
    var result = server
    var applied: Set<EventField> = []
    var overruled: Set<EventField> = []

    for field in EventField.allCases where changedLocally.contains(field) && field != .media && field != .removedMedia {
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
    // A "got up" belongs to one ending (engineering review, D8 A). When the merged ending isn't
    // the one the merged "got up" was given for, the copy whose "got up" matches it wins, if
    // either does; otherwise the mismatch stays and is ignored (`Event.validGotUp`). So a late
    // correction meant for an earlier ending never replaces the current ending's "got up".
    if let ending = result.event.endingID, result.event.gotUpFor != ending {
        if local.event.gotUpFor == ending {
            result.copy(.gotUp, from: local)
            if let stamp = local.payload?.stamp(.gotUp) { result.payload?.setStamp(.gotUp, stamp) }
            overruled.remove(.gotUp)
            applied.insert(.gotUp)
        } else if server.event.gotUpFor == ending {
            result.copy(.gotUp, from: server)
            if let stamp = server.payload?.stamp(.gotUp) { result.payload?.setStamp(.gotUp, stamp) }
            if applied.remove(.gotUp) != nil { overruled.insert(.gotUp) }
        }
    }
    if var joined = result.payload?.milestone, let mineDetails = local.payload?.milestone {
        let theirs = joined
        let theirsStamp = result.payload?.stamp(.media)
        joined.removedMedia += mineDetails.removedMedia
        let mine = local.payload?.stamp(.media)
        let mineIsLater: Bool = {
            guard changedLocally.contains(.media), let mine else { return false }
            guard let serverStamp = theirsStamp else { return true }
            return mine > serverStamp
        }()
        joined.media = mineIsLater ? mineDetails.media + theirs.media : theirs.media + mineDetails.media
        if result.event.deletedAt != nil {
            // A deleted first holds no photos: one the other phone added meanwhile is removed too,
            // so it is cleaned up and never kept for a later restore (Codex review of T5 and T6).
            joined.removedMedia += joined.media
            joined.media = []
        }
        joined.normalize()
        result.payload?.milestone = joined
        if joined.removedMedia != theirs.removedMedia {
            // iCloud's copy lacked one of this phone's removals. The stamp moves only then, so both
            // phones keep the same one.
            applied.insert(.removedMedia)
            if let stamp = local.payload?.stamp(.removedMedia), stamp > result.payload?.stamp(.removedMedia) ?? stamp {
                result.payload?.setStamp(.removedMedia, stamp)
            }
        }
        if mineIsLater, let mine {
            result.payload?.setStamp(.media, mine)
            applied.insert(.media)
        } else if joined.media != theirs.media {
            applied.insert(.media)
        } else if changedLocally.contains(.media) {
            overruled.insert(.media)
        }
    }
    result.event.modifiedAt = max(local.event.modifiedAt, server.event.modifiedAt)
    return MergeResult(snapshot: result, applied: applied, overruled: overruled, keptServerCopyUnread: false)
}
