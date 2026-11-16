import SwiftUI

/// The Apple Watch app (plan v1, Phase 2). It talks only to its own iPhone (`PhoneLink`), which
/// saves each tap, sets the alarms and tells the other phone. The alarms themselves already ring
/// on the watch: AlarmKit and Time Sensitive notifications are mirrored to it by the system.
@main
struct FeedingWatchApp: App {
    init() {
        PhoneLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
        // The phone's news (a feed started on either phone) wakes the app in the background, so
        // the watch face is up to date when the wrist is raised.
        .backgroundTask(.watchConnectivity) {
            await PhoneLink.shared.finishBackgroundDelivery()
        }
    }
}
