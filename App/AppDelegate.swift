import CloudKit
import UIKit
#if FEEDING_DEV
import UserNotifications
#endif

/// Push notifications and the start of syncing.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if FEEDING_DEV
        UNUserNotificationCenter.current().delegate = SpikeNotificationDelegate.shared
        #endif
        #if FEEDING_DEV && targetEnvironment(simulator)
        SampleData.loadIfAsked(into: AppModel.shared.store)
        #endif
        // Start at launch, also when a push wakes the app in the background.
        AppModel.shared.sync.start()
        AppModel.shared.reconciler.runSoon()
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
        Task { await AppModel.shared.sync.fetchNow() }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AppModel.shared.sync.appDidEnterBackground()
    }
}
