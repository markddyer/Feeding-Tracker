import Foundation

/// The feed window, measured from the start of the last feed. Shared by both phones.
public struct FeedWindowSettings: Hashable, Sendable, Codable {
    /// When the window opens: "may be ready to feed".
    public var opensAfter: TimeInterval
    /// When the window closes and the main alert goes off.
    public var closesAfter: TimeInterval
    /// How long after the window closes the backup alarm rings on both phones.
    public var backupAfterClose: TimeInterval
    /// Turning this off turns off every alert, the backup alarm included.
    public var alertsEnabled: Bool

    public init(
        opensAfter: TimeInterval = 2 * 3600,
        closesAfter: TimeInterval = 4 * 3600,
        backupAfterClose: TimeInterval = 30 * 60,
        alertsEnabled: Bool = true
    ) {
        self.opensAfter = opensAfter
        self.closesAfter = closesAfter
        self.backupAfterClose = backupAfterClose
        self.alertsEnabled = alertsEnabled
    }
}

/// Settings shared by the household.
public struct HouseholdSettings: Hashable, Sendable, Codable {
    public var window: FeedWindowSettings
    public var dayHours: DayHours
    /// The household time zone. Day and night are read on this clock on both phones, wherever
    /// the phones are.
    public var timeZoneID: String

    public init(window: FeedWindowSettings = .init(), dayHours: DayHours = .standard, timeZoneID: String = "Europe/London") {
        self.window = window
        self.dayHours = dayHours
        self.timeZoneID = timeZoneID
    }

    /// The household time zone. An unknown identifier falls back to UTC, the same on both phones.
    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
    }

    /// The stricter of two settings: alerts on if either has them on, and the earlier of each time.
    /// Used while a change is waiting for the other phone to confirm it.
    public func stricter(with other: HouseholdSettings) -> HouseholdSettings {
        var result = self
        result.window.alertsEnabled = window.alertsEnabled || other.window.alertsEnabled
        result.window.opensAfter = min(window.opensAfter, other.window.opensAfter)
        result.window.closesAfter = min(window.closesAfter, other.window.closesAfter)
        result.window.backupAfterClose = min(window.backupAfterClose, other.window.backupAfterClose)
        return result
    }
}

/// How a parent wants to be alerted.
public enum AlertStyle: String, Hashable, Sendable, Codable {
    /// An AlarmKit alarm plus a Time Sensitive notification at the same moment.
    case loudAlarm
    /// A Time Sensitive notification only.
    case gentleNudge
}

/// One parent's own alert choices. Stored on their own phone only.
public struct MemberPreferences: Hashable, Sendable, Codable {
    public var dayStyle: AlertStyle
    /// Used only on nights this parent is on duty.
    public var nightStyle: AlertStyle
    /// A gentle nudge when the window opens.
    public var windowOpensNudge: Bool
    /// After a night off duty, this phone keeps the night's rules until this time, or until the
    /// parent opens the app, whichever comes first. Nil means no lie-in.
    public var lieInUntil: TimeOfDay?

    public init(
        dayStyle: AlertStyle = .loudAlarm,
        nightStyle: AlertStyle = .loudAlarm,
        windowOpensNudge: Bool = false,
        lieInUntil: TimeOfDay? = nil
    ) {
        self.dayStyle = dayStyle
        self.nightStyle = nightStyle
        self.windowOpensNudge = windowOpensNudge
        self.lieInUntil = lieInUntil
    }
}

/// The phone `reconcile` is running on.
public struct Me: Hashable, Sendable {
    public var id: MemberID
    public var preferences: MemberPreferences
    /// The last time the app came to the foreground on this phone.
    public var lastForegroundAt: Date?

    public init(id: MemberID, preferences: MemberPreferences = .init(), lastForegroundAt: Date? = nil) {
        self.id = id
        self.preferences = preferences
        self.lastForegroundAt = lastForegroundAt
    }
}

/// A change this phone made that could make a phone alert later or not at all. It stays pending
/// until the other phone confirms it has seen it.
public struct PendingChange: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var madeBy: MemberID
    public var madeAt: Date
    /// The household settings before the change, when the change altered them.
    public var previousSettings: HouseholdSettings?
    /// When the other phone confirmed it. Nil while pending.
    public var acknowledgedAt: Date?

    public init(id: String, madeBy: MemberID, madeAt: Date, previousSettings: HouseholdSettings? = nil, acknowledgedAt: Date? = nil) {
        self.id = id
        self.madeBy = madeBy
        self.madeAt = madeAt
        self.previousSettings = previousSettings
        self.acknowledgedAt = acknowledgedAt
    }
}
