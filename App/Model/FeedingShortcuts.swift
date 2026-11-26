import AppIntents

/// "Start a feed in Little Log" and "Finish the feed in Little Log" (the app's name, 19 Nov 2026) for Siri, Spotlight and the
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
        // AI insights step 4 (D3 A): Siri then asks "What's your question?", and Little Log opens
        // after an unlock. Three phrases, as "Ask Little Log" alone may meet Siri's own "Ask …" (F18);
        // the one that works on the Duo is noted in CLAUDE.md.
        AppShortcut(intent: AskLittleLogIntent(),
                    phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) a question",
                              "Question for \(.applicationName)"],
                    shortTitle: "Ask", systemImageName: "bubble.left.and.text.bubble.right")
    }
}
