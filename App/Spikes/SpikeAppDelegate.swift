#if FEEDING_DEV
import CloudKit
import UIKit
import UserNotifications

/// Feeding Dev only: push notifications and invite links for the Phase 0 spikes.
final class SpikeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = SpikeNotificationDelegate.shared
        // A process start with no "screen opened" note at the same moment means iOS launched the
        // app for a push or an alarm: it wasn't running. (The state here reads "background" even
        // when the user opens the app, because the screen connects a moment later.)
        SyncSpikeStore.shared.note("The app process started.")
        // Start syncing at launch, also when a push wakes the app in the background.
        SyncSpikeStore.shared.start()
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SpikeSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await SyncSpikeStore.shared.handlePush(userInfo)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        SyncSpikeStore.shared.note("Could not register for pushes: \(error.localizedDescription)")
    }
}

/// Accepts an invite link, both when the app is running and when the link launches it.
final class SpikeSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        SyncSpikeStore.shared.note("The app's screen opened.")
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { await SyncSpikeStore.shared.accept(metadata, how: "the link opened the app") }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { await SyncSpikeStore.shared.accept(cloudKitShareMetadata, how: "the link, app already running") }
    }
}
#endif
