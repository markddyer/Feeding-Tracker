import SwiftUI

@main
struct FeedingApp: App {
    #if FEEDING_DEV
    // Push notifications and invite links for the Phase 0 test screens.
    @UIApplicationDelegateAdaptor(SpikeAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
