import Observation
import UserNotifications

/// Shows the app's notifications while it is open, and opens Home at the top when a notification
/// about an ask is tapped, so its card is in view. (The first phone test of the night ask found
/// that a tap seemed to do nothing: the app opened wherever it was left.) A notice of a new first
/// opens that first's page (design review D18), at any hour (eng2 D1).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        #if FEEDING_DEV
        _ = await SpikeNotificationDelegate.shared.userNotificationCenter(center, willPresent: notification)
        #endif
        let identifier = notification.request.identifier
        // Feed alerts and asks answer at once, as before; only a new first's notice looks at the hour.
        guard NotificationTaps.firstID(identifier) != nil else { return [.banner, .list, .sound] }
        let isNight = await MainActor.run {
            let settings = AppModel.shared.store.data.householdSettings
            if case .night = settings.dayHours.period(at: Date(), in: settings.timeZone) { return true }
            return false
        }
        return Self.presentation(for: identifier, isNight: isNight)
    }

    /// With the app open: a new first's notice in the list only at night, a banner with no sound
    /// by day (design review D19, outside voice OV6); every other notification as before.
    nonisolated static func presentation(for identifier: String, isNight: Bool) -> UNNotificationPresentationOptions {
        guard NotificationTaps.firstID(identifier) != nil else { return [.banner, .list, .sound] }
        return isNight ? [.list] : [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        #if FEEDING_DEV
        await SpikeNotificationDelegate.shared.userNotificationCenter(center, didReceive: response)
        #endif
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let identifier = response.notification.request.identifier
        if let first = NotificationTaps.firstID(identifier) {
            await MainActor.run { NotificationTaps.shared.showFirst(first) }
        } else if identifier == JournalExporter.noticeID {
            await MainActor.run { NotificationTaps.shared.showExport() }
        } else if NotificationTaps.opensHome(identifier) {
            await MainActor.run { NotificationTaps.shared.showHome() }
        }
    }
}

/// Asks the screens to go back to Home and scroll to its top.
@MainActor @Observable
final class NotificationTaps {
    static let shared = NotificationTaps()

    /// Goes up by one for each request; the screens watch it.
    private(set) var homeRequests = 0
    /// Goes up by one for each first to open; the screens watch it, and take `pendingFirst`.
    private(set) var firstRequests = 0
    /// The first a tap asked for, kept until the screens open it (a tap can come before they are
    /// there, when it starts the app).
    @ObservationIgnored private var pendingFirst: String?

    func showHome() {
        homeRequests += 1
    }

    /// Goes up by one for each tap on the export's notice; `pendingExport` holds it until the
    /// Journal opens the Export screen.
    private(set) var exportRequests = 0
    private(set) var pendingExport = false

    func showExport() {
        pendingExport = true
        exportRequests += 1
    }

    /// True once, when the export's notice was tapped.
    func takePendingExport() -> Bool {
        defer { pendingExport = false }
        return pendingExport
    }

    func showFirst(_ id: String) {
        pendingFirst = id
        firstRequests += 1
    }

    /// The first waiting to be opened, once.
    func takePendingFirst() -> String? {
        defer { pendingFirst = nil }
        return pendingFirst
    }

    /// The first a notice is about, from its identifier (`NewFirstNotifier.prefix`).
    nonisolated static func firstID(_ identifier: String) -> String? {
        guard identifier.hasPrefix(NewFirstNotifier.prefix) else { return nil }
        let id = String(identifier.dropFirst(NewFirstNotifier.prefix.count))
        return id.isEmpty ? nil : id
    }

    /// The notifications whose tap opens Home: those about an ask (`NightAskNews.id`).
    nonisolated static func opensHome(_ identifier: String) -> Bool {
        identifier.hasPrefix("nightAsk-")
    }
}
