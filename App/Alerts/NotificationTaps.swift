import Observation
import UserNotifications

/// Shows the app's notifications while it is open, and opens Home at the top when a notification
/// about an ask is tapped, so its card is in view. (The first phone test of the night ask found
/// that a tap seemed to do nothing: the app opened wherever it was left.)
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        #if FEEDING_DEV
        _ = await SpikeNotificationDelegate.shared.userNotificationCenter(center, willPresent: notification)
        #endif
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        #if FEEDING_DEV
        await SpikeNotificationDelegate.shared.userNotificationCenter(center, didReceive: response)
        #endif
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              NotificationTaps.opensHome(response.notification.request.identifier) else { return }
        await MainActor.run { NotificationTaps.shared.showHome() }
    }
}

/// Asks the screens to go back to Home and scroll to its top.
@MainActor @Observable
final class NotificationTaps {
    static let shared = NotificationTaps()

    /// Goes up by one for each request; the screens watch it.
    private(set) var homeRequests = 0

    func showHome() {
        homeRequests += 1
    }

    /// The notifications whose tap opens Home: those about an ask (`NightAskNews.id`).
    nonisolated static func opensHome(_ identifier: String) -> Bool {
        identifier.hasPrefix("nightAsk-")
    }
}
