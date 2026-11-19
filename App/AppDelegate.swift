import CloudKit
import UIKit
import UserNotifications

/// Push notifications and the start of syncing.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set before launch ends, so a tap that launched the app is handled.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        #if FEEDING_DEV && targetEnvironment(simulator)
        SampleData.loadIfAsked(into: AppModel.shared.store)
        // `-tapFirstNotice <first ID>`: as if that first's notice was tapped to start the app.
        if let id = UserDefaults.standard.string(forKey: "tapFirstNotice") {
            MainActor.assumeIsolated { NotificationTaps.shared.showFirst(id) }
        }
        #endif
        // Work and half-made exports left by an app that was stopped (journal, outside voice OE8).
        MediaStore.removeLeftovers()
        // Start at launch, also when a push wakes the app in the background.
        AppModel.shared.sync.start()
        AppModel.shared.reconciler.runSoon()
        // Photos move only while the app is open (journal plan: they may wait for it).
        if application.applicationState != .background { AppModel.shared.media.kick() }
        // The watch can wake the app in the background with a tap.
        AppModel.shared.watch.activate()
        if AppConfig.syncEnabled {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let result = await AppModel.shared.sync.handlePush()
        // The alerts are set from what arrived (the run waits for a pass that holds it), then a new
        // first from the other phone is told, for 5 seconds at most, before the app sleeps again.
        await AppModel.shared.reconciler.run()
        await AppModel.shared.waitForNewFirsts(upTo: .seconds(5))
        // An ask from the other phone: tell this parent before the app goes back to sleep.
        await AppModel.shared.tellNightAskNews()
        return result
    }
}

/// Accepts invite links, and syncs as the app comes and goes.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { await AppModel.shared.sync.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { await AppModel.shared.sync.accept(cloudKitShareMetadata) }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        AppModel.shared.reconciler.appCameToForeground()
        Task {
            await AppModel.shared.sync.fetchNow()
            AppModel.shared.media.kick()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AppModel.shared.sync.appDidEnterBackground()
        AppModel.shared.media.stop()
        // A first's Undo ends when the app leaves the screen, as its hold does.
        UndoCenter.shared.clear()
    }
}
