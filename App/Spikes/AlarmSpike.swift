#if FEEDING_DEV
import AlarmKit
import AppIntents
import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications

// Phase 0, spike 1: do AlarmKit alarms and Time Sensitive notifications go off on time on a
// phone left locked overnight? Each test is an alarm, optionally with a notification at the same
// moment, plus an optional follow-up alarm. Pressing Stop on the alarm records the time and
// cancels the follow-up. That proves the alarm's button runs our code on a locked phone. The real
// app differs: Stop only silences, and only a logged feed cancels the later layers (plan v1).
//
// First run on the Duo (14 Nov 2026): eight quick tests got set by repeated taps, so eight alarms
// and eight notifications went off within 42 seconds and the alarm went quiet. Now only one quick
// test can wait at a time, and "alarm only" and "alarm with notification" are separate tests, to
// find out whether the notification is what silences the alarm.

struct SpikeAlarmMetadata: AlarmMetadata {}

/// One fixed-time test alarm with a Stop button that runs our code. Used by every spike.
enum SpikeAlarm {
    static func schedule(id: UUID, at date: Date, title: LocalizedStringResource) async throws {
        let attributes = AlarmAttributes<SpikeAlarmMetadata>(
            presentation: AlarmPresentation(alert: AlarmPresentation.Alert(title: title)),
            metadata: SpikeAlarmMetadata(),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration<SpikeAlarmMetadata>.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: SpikeStopAlarmIntent(alarmID: id.uuidString)
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }
}

struct AlarmTest: Codable, Identifiable, Hashable {
    var id: UUID
    var dueAt: Date
    var scheduledAt: Date
    var mainAlarmID: UUID
    var followUpAlarmID: UUID?
    var followUpDueAt: Date?
    /// Nil when the test is an alarm only, with no notification.
    var notificationID: String?
    /// Seconds after the alarm that the notification is set for. Nil or 0: the same moment.
    var notificationDelay: Double?
    var iosVersion: String
    var watchWorn: Bool
    var isQuickTest: Bool

    var notificationDeliveredAt: Date?
    var mainSeenAlertingAt: Date?
    var mainStoppedAt: Date?
    var followUpSeenAlertingAt: Date?
    var followUpStoppedAt: Date?
    var followUpCancelledAt: Date?
    var phoneRangAloud: Bool?
    /// Set when "Cancel test alarms" removed this test before Stop was pressed.
    var cancelledAt: Date?
    var errors: [String] = []
}

struct AlarmSpikeLog: Codable {
    var tests: [AlarmTest] = []
    /// Each time the app came to the foreground. Shows when the app could have seen anything.
    var appActiveTimes: [Date] = []
}

@MainActor
@Observable
final class AlarmSpikeStore {
    static let shared = AlarmSpikeStore()
    static let fileName = "alarm-spike.json"

    private(set) var log: AlarmSpikeLog
    private(set) var alarmAuthorization: AlarmManager.AuthorizationState
    private(set) var notificationStatus = "unknown"
    private(set) var timeSensitiveStatus = "unknown"
    private(set) var permissionError: String?
    /// True while tests are being set, so a second tap does nothing.
    private(set) var isScheduling = false

    private init() {
        log = SpikeFile.load(AlarmSpikeLog.self, from: Self.fileName) ?? AlarmSpikeLog()
        alarmAuthorization = AlarmManager.shared.authorizationState
    }

    private func save() { SpikeFile.save(log, to: Self.fileName) }

    // MARK: Permissions

    func requestPermissions() async {
        do {
            alarmAuthorization = try await AlarmManager.shared.requestAuthorization()
            permissionError = nil
        } catch {
            permissionError = "Alarm permission: \(error)"
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshPermissions()
    }

    func refreshPermissions() async {
        alarmAuthorization = AlarmManager.shared.authorizationState
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = switch settings.authorizationStatus {
        case .authorized: "allowed"
        case .denied: "denied"
        case .notDetermined: "not asked yet"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
        timeSensitiveStatus = switch settings.timeSensitiveSetting {
        case .enabled: "on"
        case .disabled: "off"
        case .notSupported: "not supported"
        @unknown default: "unknown"
        }
    }

    // MARK: Scheduling

    /// The quick test that is still waiting or ringing, if any. Only one at a time.
    func activeQuickTest(now: Date = Date()) -> AlarmTest? {
        log.tests.last {
            $0.isQuickTest && $0.cancelledAt == nil && $0.mainStoppedAt == nil && now < $0.dueAt.addingTimeInterval(300)
        }
    }

    /// Overnight tests that have not rung yet.
    func waitingOvernightTests(now: Date = Date()) -> [AlarmTest] {
        log.tests.filter { !$0.isQuickTest && $0.cancelledAt == nil && $0.mainStoppedAt == nil && $0.dueAt > now }
    }

    /// Sets one quick test whose alarm rings 2 minutes from now. `notificationDelay` nil means no
    /// notification. Does nothing while another quick test waits. Returns the ring time, or nil
    /// if nothing was set.
    func scheduleQuickTest(notificationDelay: TimeInterval?, followUpAfter: TimeInterval?, watchWorn: Bool) async -> Date? {
        guard !isScheduling, activeQuickTest() == nil else { return nil }
        isScheduling = true
        defer { isScheduling = false }
        let due = Date().addingTimeInterval(120)
        await schedule(at: due, followUpAfter: followUpAfter, notificationDelay: notificationDelay, watchWorn: watchWorn, quick: true)
        return due
    }

    /// Sets the overnight tests. Does nothing while earlier overnight tests still wait.
    func scheduleOvernight(at dates: [Date], followUpAfter: TimeInterval?, withNotification: Bool, watchWorn: Bool) async -> [Date] {
        guard !isScheduling, waitingOvernightTests().isEmpty else { return [] }
        isScheduling = true
        defer { isScheduling = false }
        for due in dates {
            await schedule(at: due, followUpAfter: followUpAfter, notificationDelay: withNotification ? 0 : nil, watchWorn: watchWorn, quick: false)
        }
        return dates
    }

    /// Schedules one test: an alarm at `due`, a Time Sensitive notification `notificationDelay`
    /// after it when given, and a follow-up alarm `followUpAfter` later when given.
    private func schedule(at due: Date, followUpAfter: TimeInterval?, notificationDelay: TimeInterval?, watchWorn: Bool, quick: Bool) async {
        let id = UUID()
        var test = AlarmTest(
            id: id,
            dueAt: due,
            scheduledAt: Date(),
            mainAlarmID: UUID(),
            followUpAlarmID: followUpAfter == nil ? nil : UUID(),
            followUpDueAt: followUpAfter.map { due.addingTimeInterval($0) },
            notificationID: notificationDelay == nil ? nil : "spike.\(id.uuidString)",
            notificationDelay: notificationDelay,
            iosVersion: UIDevice.current.systemVersion,
            watchWorn: watchWorn,
            isQuickTest: quick
        )
        do {
            try await scheduleAlarm(id: test.mainAlarmID, at: due, title: "Feeding Dev test alarm")
        } catch {
            test.errors.append("main alarm: \(error)")
        }
        if let followUpID = test.followUpAlarmID, let followUpDue = test.followUpDueAt {
            do {
                try await scheduleAlarm(id: followUpID, at: followUpDue, title: "Feeding Dev test follow-up")
            } catch {
                test.errors.append("follow-up alarm: \(error)")
            }
        }
        if let notificationID = test.notificationID {
            do {
                try await scheduleNotification(id: notificationID, at: due.addingTimeInterval(notificationDelay ?? 0))
            } catch {
                test.errors.append("notification: \(error)")
            }
        }
        log.tests.append(test)
        save()
    }

    private func scheduleAlarm(id: UUID, at date: Date, title: LocalizedStringResource) async throws {
        try await SpikeAlarm.schedule(id: id, at: date, title: title)
    }

    private func scheduleNotification(id: String, at date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Feeding Dev test alert"
        content.body = "Practice alert, set for \(date.formatted(date: .omitted, time: .shortened))."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Cancels every test alarm and notification that hasn't gone off yet. Results stay.
    func cancelAllPending() {
        let now = Date()
        for i in log.tests.indices {
            let test = log.tests[i]
            try? AlarmManager.shared.cancel(id: test.mainAlarmID)
            if let followUp = test.followUpAlarmID { try? AlarmManager.shared.cancel(id: followUp) }
            if test.mainStoppedAt == nil, test.cancelledAt == nil, test.dueAt > now.addingTimeInterval(-300) {
                log.tests[i].cancelledAt = now
            }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: log.tests.compactMap(\.notificationID))
        save()
    }

    /// Cancels anything still waiting, then empties the results list.
    func clearResults() {
        cancelAllPending()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: log.tests.compactMap(\.notificationID))
        log = AlarmSpikeLog()
        save()
    }

    // MARK: Recording what happened

    /// Called by the alarm's Stop button, even while the phone is locked.
    func recordStop(alarmID: String, at date: Date) {
        guard let uuid = UUID(uuidString: alarmID) else { return }
        try? AlarmManager.shared.stop(id: uuid)
        if let i = log.tests.firstIndex(where: { $0.mainAlarmID == uuid }) {
            if log.tests[i].mainStoppedAt == nil { log.tests[i].mainStoppedAt = date }
            if let followUp = log.tests[i].followUpAlarmID,
               log.tests[i].followUpStoppedAt == nil, log.tests[i].followUpCancelledAt == nil {
                do {
                    try AlarmManager.shared.cancel(id: followUp)
                    log.tests[i].followUpCancelledAt = date
                } catch {
                    log.tests[i].errors.append("cancel follow-up: \(error)")
                }
            }
        } else if let i = log.tests.firstIndex(where: { $0.followUpAlarmID == uuid }) {
            if log.tests[i].followUpStoppedAt == nil { log.tests[i].followUpStoppedAt = date }
        }
        save()
    }

    /// Records the first time the app saw each test alarm ringing. Runs while the app runs.
    func observeAlarms() async {
        for await alarms in AlarmManager.shared.alarmUpdates {
            let now = Date()
            var changed = false
            for alarm in alarms where alarm.state == .alerting {
                if let i = log.tests.firstIndex(where: { $0.mainAlarmID == alarm.id }), log.tests[i].mainSeenAlertingAt == nil {
                    log.tests[i].mainSeenAlertingAt = now
                    changed = true
                } else if let i = log.tests.firstIndex(where: { $0.followUpAlarmID == alarm.id }), log.tests[i].followUpSeenAlertingAt == nil {
                    log.tests[i].followUpSeenAlertingAt = now
                    changed = true
                }
            }
            if changed { save() }
        }
    }

    func recordNotification(id: String, deliveredAt: Date) {
        guard let i = log.tests.firstIndex(where: { $0.notificationID == id }), log.tests[i].notificationDeliveredAt == nil else { return }
        log.tests[i].notificationDeliveredAt = deliveredAt
        save()
    }

    /// Reads the delivery time of every test notification still in Notification Center.
    func collectDeliveredNotifications() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        for notification in delivered where notification.request.identifier.hasPrefix("spike.") {
            recordNotification(id: notification.request.identifier, deliveredAt: notification.date)
        }
    }

    func recordAppActive() {
        log.appActiveTimes.append(Date())
        save()
    }

    func setRangAloud(testID: UUID, _ value: Bool) {
        guard let i = log.tests.firstIndex(where: { $0.id == testID }) else { return }
        log.tests[i].phoneRangAloud = value
        save()
    }
}

/// The alarm's Stop button. Runs in the app's process, also when the phone is locked.
struct SpikeStopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop test alarm" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let now = Date()
        AlarmSpikeStore.shared.recordStop(alarmID: alarmID, at: now)
        return .result()
    }
}

/// Records when test notifications arrive while the app is open or when one is tapped.
final class SpikeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SpikeNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        let date = notification.date
        await AlarmSpikeStore.shared.recordNotification(id: id, deliveredAt: date)
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        let date = response.notification.date
        await AlarmSpikeStore.shared.recordNotification(id: id, deliveredAt: date)
    }
}
#endif
