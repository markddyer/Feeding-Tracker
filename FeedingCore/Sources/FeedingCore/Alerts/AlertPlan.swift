import Foundation

/// An AlarmKit alarm this phone scheduled, as the app remembers it.
public struct ScheduledAlarm: Hashable, Sendable, Codable {
    /// The `DesiredAlert.key` it was scheduled for.
    public var key: String
    public var alarmID: UUID
    public var fireDate: Date
    /// The baby and the feed start it was set for, so an alarm whose time has come is kept until a
    /// newer feed is logged. Nil for an alarm an older build remembered.
    public var babyID: String?
    public var lastFeedStart: Date?

    public init(key: String, alarmID: UUID, fireDate: Date, babyID: String? = nil, lastFeedStart: Date? = nil) {
        self.key = key
        self.alarmID = alarmID
        self.fireDate = fireDate
        self.babyID = babyID
        self.lastFeedStart = lastFeedStart
    }
}

/// How long an alarm whose time has come is kept: it may be ringing, or waiting for the parent.
/// Cancelling it after that does nothing that can be heard.
public let soundingAlarmKept: TimeInterval = 6 * 3600

/// What to do to the phone's alarms and notifications so they match `reconcile`'s output.
public struct AlertChanges: Hashable, Sendable {
    public struct NewAlarm: Hashable, Sendable {
        public var alert: DesiredAlert
        public var alarmID: UUID
    }

    /// Schedule these first. Each has a new ID, because AlarmKit can't change an alarm.
    public var alarmsToSchedule: [NewAlarm]
    /// Then cancel these: replaced or no longer wanted.
    public var alarmsToCancel: [UUID]
    /// Add these. Each uses a fixed identifier, so adding replaces the old one.
    public var notificationsToAdd: [DesiredAlert]
    /// Remove these pending notifications: no longer wanted.
    public var notificationsToRemove: [String]
    /// The alarms to remember once the changes are made.
    public var alarmsAfter: [ScheduledAlarm]

    public var isEmpty: Bool {
        alarmsToSchedule.isEmpty && alarmsToCancel.isEmpty && notificationsToAdd.isEmpty && notificationsToRemove.isEmpty
    }
}

/// The identifier of an alert's notification. Fixed for the alert's key, so adding it again replaces it.
public func notificationIdentifier(for alert: DesiredAlert) -> String { "alert.\(alert.key)" }

/// Works out the changes. Alarms and notifications already set for the same moment are kept, so an
/// unchanged plan changes nothing. A moved alarm gets a new one first; the old one is cancelled after.
/// `pendingNotifications` maps this app's pending notification identifiers to their fire dates;
/// only identifiers starting "alert." are ever removed.
///
/// `reconcile` leaves out alerts whose time has passed. An alarm whose time has come is still kept
/// (it may be ringing, or iOS may deliver it late) for as long as no newer feed has been logged:
/// `latestFeedStarts` holds each baby's latest feed start. So a nappy, a sleep or any other change
/// never stops it; a feed does (Codex review, 17 Nov 2026).
public func planAlertChanges(
    desired: [DesiredAlert],
    scheduledAlarms: [ScheduledAlarm],
    pendingNotifications: [String: Date],
    now: Date = .distantPast,
    latestFeedStarts: [String: Date] = [:],
    newID: () -> UUID = UUID.init
) -> AlertChanges {
    var schedule: [AlertChanges.NewAlarm] = []
    var cancel: [UUID] = []
    var after: [ScheduledAlarm] = []
    let scheduledByKey = Dictionary(scheduledAlarms.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    let desiredAlarms = desired.filter { $0.mechanism == .alarm }
    for alert in desiredAlarms {
        if var existing = scheduledByKey[alert.key], existing.fireDate == alert.fireDate {
            existing.babyID = alert.babyID
            existing.lastFeedStart = alert.lastFeedStart
            after.append(existing)
            continue
        }
        let id = newID()
        schedule.append(.init(alert: alert, alarmID: id))
        after.append(ScheduledAlarm(key: alert.key, alarmID: id, fireDate: alert.fireDate, babyID: alert.babyID,
                                    lastFeedStart: alert.lastFeedStart))
    }
    let keptIDs = Set(after.map(\.alarmID))
    let replacedKeys = Set(desiredAlarms.map(\.key))
    for alarm in scheduledAlarms where !keptIDs.contains(alarm.alarmID) {
        if !replacedKeys.contains(alarm.key), stillSounding(alarm, now: now, latestFeedStarts: latestFeedStarts) {
            after.append(alarm)
        } else {
            cancel.append(alarm.alarmID)
        }
    }

    let notifications = desired.filter { $0.mechanism == .notification }
    let wanted = Set(notifications.map(notificationIdentifier(for:)))
    let add = notifications.filter { alert in
        guard let pending = pendingNotifications[notificationIdentifier(for: alert)] else { return true }
        return abs(pending.timeIntervalSince(alert.fireDate)) >= 1
    }
    let remove = pendingNotifications.keys.filter { $0.hasPrefix("alert.") && !wanted.contains($0) }.sorted()

    return AlertChanges(alarmsToSchedule: schedule, alarmsToCancel: cancel, notificationsToAdd: add,
                        notificationsToRemove: remove, alarmsAfter: after)
}

/// An alarm whose time has come, set for the feed that is still the latest, within the last
/// `soundingAlarmKept`: it may be ringing now, so it stays.
func stillSounding(_ alarm: ScheduledAlarm, now: Date, latestFeedStarts: [String: Date]) -> Bool {
    guard alarm.fireDate <= now, now.timeIntervalSince(alarm.fireDate) < soundingAlarmKept,
          let baby = alarm.babyID, let start = alarm.lastFeedStart, let latest = latestFeedStarts[baby] else { return false }
    return abs(latest.timeIntervalSince(start)) < 1
}
