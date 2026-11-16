import AppIntents

/// "Start a feed in Feeding" and "Finish the feed in Feeding" for Siri, Spotlight and the
/// Shortcuts app, ready to use with no setting up. Each also goes on the Action Button from the
/// iPhone's Settings (Action Button, then Shortcut).
struct FeedingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // On a bottle-only phone, "Start a feed" asks "Formula or expressed milk?"; naming the
        // milk skips the question.
        AppShortcut(intent: StartFeedIntent(),
                    phrases: ["Start a feed in \(.applicationName)", "Start feed in \(.applicationName)",
                              "Start a \(\.$milk) feed in \(.applicationName)",
                              "Start an \(\.$milk) feed in \(.applicationName)",
                              "Start \(\.$milk) in \(.applicationName)"],
                    shortTitle: "Start feed", systemImageName: "waterbottle")
        AppShortcut(intent: FinishFeedIntent(),
                    phrases: ["Finish the feed in \(.applicationName)", "Finish feed in \(.applicationName)"],
                    shortTitle: "Finish feed", systemImageName: "stopwatch")
    }
}
