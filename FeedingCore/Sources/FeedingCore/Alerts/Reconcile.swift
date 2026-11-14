import Foundation

/// One alert this phone should have scheduled.
public struct DesiredAlert: Hashable, Sendable {
    public enum Purpose: String, Hashable, Sendable, CaseIterable {
        /// The window opens: an optional gentle nudge.
        case windowOpens
        /// The window closes: the main alert, in this parent's chosen style.
        case windowCloses
        /// 10 minutes after the window closes, in the same style.
        case followUp
        /// After the window closes, if no feed has been logged: a loud alarm on both phones.
        case backup
    }

    public enum Mechanism: String, Hashable, Sendable {
        /// An AlarmKit alarm.
        case alarm
        /// A Time Sensitive notification.
        case notification
    }

    public var babyID: String
    public var purpose: Purpose
    public var mechanism: Mechanism
    public var fireDate: Date
    /// The feed start the alert is measured from, for the alert's text.
    public var lastFeedStart: Date

    /// The same for every run with the same baby, purpose and mechanism, so applying the output
    /// again replaces rather than adds.
    public var key: String { "\(babyID).\(purpose.rawValue).\(mechanism.rawValue)" }
}

/// How long after the window closes the follow-up alert goes off.
public let followUpDelay: TimeInterval = 10 * 60

/// Works out every alert this phone should have scheduled, from the newest data it holds.
///
/// A pure function: the same inputs always give the same output. It reads only the unencrypted
/// top-level fields of each event (`startedAt`, `kind`, `deletedAt`, `babyID`, and the server's
/// creation time), never the payload.
///
/// The household time zone comes from `settings`, so it needs no calendar from the phone.
///
/// - Parameters:
///   - events: every event this phone holds, deleted ones included.
///   - settings: the shared household settings.
///   - roster: the rota and the night claims.
///   - pendingChanges: changes waiting for the other phone to confirm them.
///   - me: the parent and phone this runs on.
///   - now: the current time. Alerts at or before it are left out.
/// - Returns: the alerts, sorted by fire date.
public func reconcile(
    events: [Event],
    settings: HouseholdSettings,
    roster: DutyRoster,
    pendingChanges: [PendingChange],
    me: Me,
    now: Date
) -> [DesiredAlert] {
    // The acknowledgement rule: while a change this phone made is unconfirmed, this phone alerts
    // as if on duty, using the stricter of the old and new settings.
    let myPending = pendingChanges.filter { $0.madeBy == me.id && $0.acknowledgedAt == nil }
    var effective = settings
    for change in myPending {
        if let previous = change.previousSettings { effective = effective.stricter(with: previous) }
    }
    let rules = AlertRules(settings: effective, roster: roster, me: me, forcedOnDuty: !myPending.isEmpty)

    guard effective.window.alertsEnabled else { return [] }

    let babies = Set(events.lazy.filter(\.isLiveFeed).map(\.babyID)).sorted()
    var alerts: [DesiredAlert] = []
    for baby in babies {
        guard let lastStart = events.latestFeedStart(babyID: baby, now: now) else { continue }
        let window = FeedWindow(lastFeedStart: lastStart, settings: effective.window)

        func add(_ purpose: DesiredAlert.Purpose, _ mechanism: DesiredAlert.Mechanism, at date: Date) {
            alerts.append(DesiredAlert(babyID: baby, purpose: purpose, mechanism: mechanism, fireDate: date, lastFeedStart: lastStart))
        }
        func addInStyle(_ style: AlertStyle, _ purpose: DesiredAlert.Purpose, at date: Date) {
            add(purpose, .notification, at: date)
            if style == .loudAlarm { add(purpose, .alarm, at: date) }
        }

        if me.preferences.windowOpensNudge, window.opensAt < window.closesAt,
           rules.style(at: window.opensAt) != nil {
            add(.windowOpens, .notification, at: window.opensAt)
        }
        if let style = rules.style(at: window.closesAt) {
            addInStyle(style, .windowCloses, at: window.closesAt)
        }
        let followUpAt = window.closesAt.addingTimeInterval(followUpDelay)
        if let style = rules.style(at: followUpAt) {
            addInStyle(style, .followUp, at: followUpAt)
        }
        // The backup rings on both phones, day or night, whatever each parent chose.
        addInStyle(.loudAlarm, .backup, at: window.closesAt.addingTimeInterval(effective.window.backupAfterClose))
    }

    let future = alerts.filter { $0.fireDate > now }
    return separatingAlarmMinutes(future).sorted { ($0.fireDate, $0.key) < ($1.fireDate, $1.key) }
}

/// Decides whether, and how, this phone alerts at a given moment, for the alerts that depend on
/// duty. Day or night is decided by when the alert fires, not by when it is scheduled.
struct AlertRules {
    let settings: HouseholdSettings
    let roster: DutyRoster
    let me: Me
    let forcedOnDuty: Bool

    /// This parent's style at `date`, or nil when this phone stays silent then.
    func style(at date: Date) -> AlertStyle? {
        let prefs = me.preferences
        switch settings.dayHours.period(at: date, in: settings.timeZone) {
        case .night(let night):
            return forcedOnDuty || roster.onDuty(night: night) == me.id ? prefs.nightStyle : nil
        case .day(let day):
            if !forcedOnDuty, isInLieIn(date, on: day),
               roster.onDuty(night: settings.dayHours.nightEnding(on: day)) != me.id {
                return nil
            }
            return prefs.dayStyle
        }
    }

    /// True when `date` is in the morning before this parent's lie-in time and they haven't
    /// opened the app since the day started.
    private func isInLieIn(_ date: Date, on day: PlainDate) -> Bool {
        guard let lieIn = me.preferences.lieInUntil else { return false }
        let dayStart = settings.dayHours.dayStart
        let time = WallClock.reading(date, in: settings.timeZone).time
        guard time >= dayStart, time < lieIn else { return false }
        if let opened = me.lastForegroundAt, opened <= date {
            let reading = WallClock.reading(opened, in: settings.timeZone)
            if reading.date == day, reading.time >= dayStart { return false }
        }
        return true
    }
}

/// Moves alarms so no two on this phone go off in the same minute. Two AlarmKit alarms in the
/// same minute have been reported to both stay silent. An alarm only ever moves later, to the
/// start of the next free minute.
func separatingAlarmMinutes(_ alerts: [DesiredAlert]) -> [DesiredAlert] {
    var result = alerts.filter { $0.mechanism != .alarm }
    let alarms = alerts.filter { $0.mechanism == .alarm }.sorted { ($0.fireDate, $0.key) < ($1.fireDate, $1.key) }
    var lastMinute: Int?
    for var alarm in alarms {
        var minute = Int((alarm.fireDate.timeIntervalSince1970 / 60).rounded(.down))
        if let last = lastMinute, minute <= last {
            minute = last + 1
            alarm.fireDate = Date(timeIntervalSince1970: TimeInterval(minute * 60))
        }
        lastMinute = minute
        result.append(alarm)
    }
    return result
}
