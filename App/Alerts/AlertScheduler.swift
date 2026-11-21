import AlarmKit
import FeedingCore
import Foundation
import UserNotifications

/// What a Feeding alarm carries. Only its purpose, for the record.
struct FeedingAlarmMetadata: AlarmMetadata {
    var purpose: String
}

/// Puts `reconcile`'s alerts onto this phone: AlarmKit alarms and Time Sensitive notifications.
/// Applying the same alerts again changes nothing (plan v1, "Applying the output").
@MainActor
final class AlertScheduler {
    private let defaults: UserDefaults
    private(set) var lastError: String?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The alarms this app has scheduled, as remembered between launches.
    private(set) var scheduledAlarms: [ScheduledAlarm] {
        get {
            defaults.data(forKey: "scheduledAlarms")
                .flatMap { try? JSONDecoder().decode([ScheduledAlarm].self, from: $0) } ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "scheduledAlarms")
        }
    }

    var alarmsAllowed: Bool { AlarmManager.shared.authorizationState == .authorized }

    /// `latestFeedStarts` (each baby's latest feed start) keeps an alarm whose time has come until
    /// a newer feed is logged (`planAlertChanges`).
    /// `passed` (`passedAlerts`): an alert there that this phone still has set for later goes off
    /// at once instead of being cancelled (`catchUpAlerts`).
    func apply(_ desired: [DesiredAlert], latestFeedStarts: [String: Date], now: Date, timeZone: TimeZone,
               keepExisting: Bool = false, passed: [DesiredAlert] = []) async {
        lastError = nil
        // The plan: reschedule everything after an iOS update, as alarms have gone missing then.
        // Not while waiting for iCloud (`keepExisting`): what is known may be missing a feed. The
        // marker stays unset, so the first plan after the wait does it.
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var remembered = scheduledAlarms
        if !keepExisting, defaults.string(forKey: "alarmsScheduledOnOS") != os {
            for alarm in remembered { try? AlarmManager.shared.cancel(id: alarm.alarmID) }
            remembered = []
            defaults.set(os, forKey: "alarmsScheduledOnOS")
        }

        // Without alarm permission, only the notifications go on. A loud alert always has its
        // notification at the same moment, so nothing goes quiet.
        let wanted = alarmsAllowed ? desired : desired.filter { $0.mechanism == .notification }
        let center = UNUserNotificationCenter.current()
        var pending: [String: Date] = [:]
        for request in await center.pendingNotificationRequests() where request.identifier.hasPrefix("alert.") {
            if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger, let date = trigger.nextTriggerDate() {
                pending[request.identifier] = date
            } else {
                pending[request.identifier] = .distantPast
            }
        }

        let passedWanted = alarmsAllowed ? passed : passed.filter { $0.mechanism == .notification }
        let changes = planAlertChanges(desired: wanted, scheduledAlarms: remembered, pendingNotifications: pending,
                                       now: now, latestFeedStarts: latestFeedStarts, keepExisting: keepExisting,
                                       passed: passedWanted)
        var after = changes.alarmsAfter

        // New alarms first, then cancel the old ones: never a moment with neither. An old alarm
        // whose replacement couldn't be set stays (Codex review of T3 and T4).
        var failedKeys = Set<String>()
        for new in changes.alarmsToSchedule {
            do {
                try await schedule(new.alert, id: new.alarmID, timeZone: timeZone)
            } catch {
                lastError = "Couldn't set an alarm: \(error.localizedDescription)"
                after.removeAll { $0.alarmID == new.alarmID }
                failedKeys.insert(new.alert.key)
            }
        }
        for id in changes.alarmsToCancel {
            if let old = remembered.first(where: { $0.alarmID == id }), failedKeys.contains(old.key) {
                after.append(old)
                continue
            }
            try? AlarmManager.shared.cancel(id: id)
        }
        scheduledAlarms = after

        for alert in changes.notificationsToAdd {
            let content = UNMutableNotificationContent()
            content.title = AlertText.title(for: alert)
            content.body = AlertText.body(for: alert, timeZone: timeZone)
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = "feeding-alerts"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, alert.fireDate.timeIntervalSinceNow), repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: notificationIdentifier(for: alert), content: content, trigger: trigger))
            } catch {
                lastError = "Couldn't set a notification: \(error.localizedDescription)"
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: changes.notificationsToRemove)
    }

    /// Feeding Dev with its alarms and notices off (G4): cancels every alarm this app has, set by
    /// any build, the test screen's too, and takes away every alert and test notification,
    /// waiting or shown. Every run does it again, so an alarm that wouldn't cancel is tried again.
    func silenceAll() async {
        lastError = nil
        var ids = Set(scheduledAlarms.map(\.alarmID))
        ids.formUnion(((try? AlarmManager.shared.alarms) ?? []).map(\.id))
        var stuck = 0
        for id in ids {
            do { try AlarmManager.shared.cancel(id: id) } catch { stuck += 1 }
        }
        if stuck > 0 { lastError = "Couldn't cancel \(stuck) alarm\(stuck == 1 ? "" : "s"). Trying again next time." }
        scheduledAlarms = []
        let ours = { (id: String) in id.hasPrefix("alert.") || id.hasPrefix("spike.") }
        let center = UNUserNotificationCenter.current()
        let waiting = await center.pendingNotificationRequests().map(\.identifier).filter(ours)
        center.removePendingNotificationRequests(withIdentifiers: waiting)
        let shown = await center.deliveredNotifications().map(\.request.identifier).filter(ours)
        center.removeDeliveredNotifications(withIdentifiers: shown)
    }

    private func schedule(_ alert: DesiredAlert, id: UUID, timeZone: TimeZone) async throws {
        let title = AlertText.title(for: alert)
        let attributes = AlarmAttributes<FeedingAlarmMetadata>(
            presentation: AlarmPresentation(alert: AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title))),
            metadata: FeedingAlarmMetadata(purpose: alert.purpose.rawValue),
            tintColor: .orange)
        let configuration = AlarmManager.AlarmConfiguration<FeedingAlarmMetadata>.alarm(
            schedule: .fixed(alert.fireDate), attributes: attributes)
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    /// Asks for alarm and notification permission. Called during setup.
    func requestPermissions() async {
        _ = try? await AlarmManager.shared.requestAuthorization()
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}
