import AppIntents

/// "Start a feed in Feeding" and "Finish the feed in Feeding" for Siri, Spotlight and the
/// Shortcuts app, ready to use with no setting up. Each also goes on the Action Button from the
/// iPhone's Settings (Action Button, then Shortcut).
struct FeedingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFeedIntent(),
                    phrases: ["Start a feed in \(.applicationName)", "Start feed in \(.applicationName)"],
                    shortTitle: "Start feed", systemImageName: "waterbottle")
        AppShortcut(intent: FinishFeedIntent(),
                    phrases: ["Finish the feed in \(.applicationName)", "Finish feed in \(.applicationName)"],
                    shortTitle: "Finish feed", systemImageName: "stopwatch")
    }
}
