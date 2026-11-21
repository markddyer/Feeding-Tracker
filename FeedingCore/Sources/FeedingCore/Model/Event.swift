import Foundation

/// One logged event, as stored in the CloudKit `Event` record.
///
/// The top-level fields are stored unencrypted so `reconcile` can read them. The details (sides,
/// bottles, ml, the note) are in `payload`, which CloudKit encrypts. `reconcile` never decodes
/// `payload`, so a feed still counts when its payload can't be read or comes from a newer app.
public struct Event: Hashable, Sendable, Identifiable, Codable {
    public var id: String
    public var babyID: String
    public var kind: EventKind
    public var startedAt: Date
    public var endedAt: Date?
    /// The time zone of the phone that logged it, for showing local times in the history.
    public var timeZoneID: String
    public var loggedBy: MemberID
    public var createdAt: Date
    public var modifiedAt: Date
    /// Set when the event is deleted. Deletes hide the event; they never remove the record.
    public var deletedAt: Date?
    public var schemaVersion: Int
    /// The encoded details. Encrypted by CloudKit.
    public var payload: Data?
    /// When the server created the record (`CKRecord.creationDate`). Nil until it has uploaded.
    public var serverCreatedAt: Date?
    /// Who did it, when a parent chose (`docs/planning/09-who-does-what.md`, R2). Nil means the
    /// starting rule decides (`WhoDidIt`). An encrypted record field (engineering review E1);
    /// `reconcile` never reads it. Never cleared once set; its stamp is in the payload.
    public var doneBy: MemberID?
    /// The ending a sleep's `endedAt` belongs to (engineering review, D8 A): one ID per Woke up
    /// tap, shared by every sleep it ends, and "feed:<feed ID>" when a feed ended it. Merged with
    /// `endedAt` as one field. Nil while the sleep runs, and on sleeps ended before this build.
    public var wakeID: String?
    /// Who got up when a sleep ended (R3), and the ending it was given for (`gotUpFor`, an
    /// `endingID`). Merged as one field. A "got up" for another ending is ignored (`validGotUp`).
    public var gotUpBy: MemberID?
    public var gotUpFor: String?

    public init(
        id: String,
        babyID: String,
        kind: EventKind,
        startedAt: Date,
        endedAt: Date? = nil,
        timeZoneID: String,
        loggedBy: MemberID,
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date? = nil,
        schemaVersion: Int = 1,
        payload: Data? = nil,
        serverCreatedAt: Date? = nil,
        doneBy: MemberID? = nil,
        wakeID: String? = nil,
        gotUpBy: MemberID? = nil,
        gotUpFor: String? = nil
    ) {
        self.id = id
        self.babyID = babyID
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timeZoneID = timeZoneID
        self.loggedBy = loggedBy
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.serverCreatedAt = serverCreatedAt
        self.doneBy = doneBy
        self.wakeID = wakeID
        self.gotUpBy = gotUpBy
        self.gotUpFor = gotUpFor
    }

    /// The ending a sleep's "got up" binds to, and the key that groups the sleeps of one wake-up:
    /// its wake-up ID (or, for a sleep ended before wake-up IDs existed, one made from its own ID)
    /// with its end time. So an end changed by an older build, which keeps the wake-up ID but
    /// knows nothing of it, leaves the old "got up" and the old wake-up behind; this build moves
    /// them with an end it changes (`keepSleepEnding`). Nil while it runs (Codex review of the
    /// build, 21 Nov 2026).
    public var endingID: String? {
        guard let endedAt else { return nil }
        return "\(wakeID ?? "end:\(id)"):\(Int64((endedAt.timeIntervalSince1970 * 1000).rounded()))"
    }

    /// The stored "got up", when it belongs to this ending; nil otherwise (engineering review, D8 A).
    public var validGotUp: MemberID? {
        guard let endingID, gotUpFor == endingID else { return nil }
        return gotUpBy
    }

    /// How long after the server created the record a start time may be. Guards against the
    /// logging phone's clock running fast.
    public static let serverClockAllowance: TimeInterval = 60

    /// The start time the alerts are measured from.
    ///
    /// It is never later than the server's creation time plus one minute, and never later than
    /// `now`. Both caps can only move an alert earlier, never later.
    public func effectiveStart(now: Date) -> Date {
        var start = startedAt
        if let serverCreatedAt {
            start = min(start, serverCreatedAt.addingTimeInterval(Event.serverClockAllowance))
        }
        return min(start, now)
    }

    /// True for a feed that hasn't been deleted.
    public var isLiveFeed: Bool { kind == .feed && deletedAt == nil }
}

extension Collection where Element == Event {
    /// The latest effective start of a live feed for `babyID`, or nil when there is none.
    public func latestFeedStart(babyID: String, now: Date) -> Date? {
        lazy.filter { $0.isLiveFeed && $0.babyID == babyID }.map { $0.effectiveStart(now: now) }.max()
    }
}
