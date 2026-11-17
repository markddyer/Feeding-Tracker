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
    func apply(_ desired: [DesiredAlert], latestFeedStarts: [String: Date], now: Date, timeZone: TimeZone) async {
        lastError = nil
        // The plan: reschedule everything after an iOS update, as alarms have gone missing then.
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var remembered = scheduledAlarms
        if defaults.string(forKey: "alarmsScheduledOnOS") != os {
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

        let changes = planAlertChanges(desired: wanted, scheduledAlarms: remembered, pendingNotifications: pending,
                                       now: now, latestFeedStarts: latestFeedStarts)
        var after = changes.alarmsAfter

        // New alarms first, then cancel the old ones: never a moment with neither.
        for new in changes.alarmsToSchedule {
            do {
                try await schedule(new.alert, id: new.alarmID, timeZone: timeZone)
            } catch {
                lastError = "Couldn't set an alarm: \(error.localizedDescription)"
                after.removeAll { $0.alarmID == new.alarmID }
            }
        }
        for id in changes.alarmsToCancel {
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
