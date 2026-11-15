import SwiftUI

@main
struct FeedingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                // SF Pro Rounded for all text not given a style, and fixed-width digits for
                // every number (DESIGN.md, "Typography").
                .fontDesign(.rounded)
                .monospacedDigit()
                .modifier(LookModifier())
        }
    }
}
