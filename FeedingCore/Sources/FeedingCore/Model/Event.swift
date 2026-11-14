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
        serverCreatedAt: Date? = nil
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
