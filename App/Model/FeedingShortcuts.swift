import AppIntents

/// Little Log's Siri phrases, for Siri, Spotlight and the Shortcuts app, ready to use with no
/// setting up. Each also goes on the Action Button from the iPhone's Settings (Action Button, then
/// Shortcut). Apple allows 10 App Shortcuts at most; this is 8. Every logging phrase works on a
/// locked phone, with no Touch ID (`docs/planning/15-hands-free-siri.md`, V4). A phrase must name
/// the app, and can hold a word from a fixed list (a milk, a nappy, a medicine), never a number:
/// Siri asks the amount after it.
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
        // Then Siri asks the sides, or the amount (read back for a "yes").
        AppShortcut(intent: FinishFeedIntent(),
                    phrases: ["Finish the feed in \(.applicationName)", "Finish feed in \(.applicationName)",
                              "Finish a feed in \(.applicationName)", "End the feed in \(.applicationName)",
                              "Feed finished in \(.applicationName)"],
                    shortTitle: "Finish feed", systemImageName: "stopwatch")
        AppShortcut(intent: AddBottleIntent(),
                    phrases: ["Add a bottle in \(.applicationName)", "Add a bottle to the feed in \(.applicationName)",
                              "Add \(\.$milk) in \(.applicationName)", "Add a \(\.$milk) bottle in \(.applicationName)",
                              "Add an \(\.$milk) bottle in \(.applicationName)"],
                    shortTitle: "Add a bottle", systemImageName: "waterbottle.fill")
        AppShortcut(intent: FellAsleepIntent(),
                    phrases: ["Baby's asleep in \(.applicationName)", "Asleep in \(.applicationName)",
                              "Fell asleep in \(.applicationName)", "Log a sleep in \(.applicationName)"],
                    shortTitle: "Fell asleep", systemImageName: "moon.zzz")
        AppShortcut(intent: WokeUpIntent(),
                    phrases: ["Baby's awake in \(.applicationName)", "Awake in \(.applicationName)",
                              "Woke up in \(.applicationName)"],
                    shortTitle: "Woke up", systemImageName: "sun.max")
        AppShortcut(intent: LogNappyIntent(),
                    phrases: ["Log a nappy in \(.applicationName)", "Nappy change in \(.applicationName)",
                              "Log a \(\.$kind) in \(.applicationName)", "Log a \(\.$kind) nappy in \(.applicationName)"],
                    shortTitle: "Log a nappy", systemImageName: "drop")
        AppShortcut(intent: LogMedicineIntent(),
                    phrases: ["Log a medicine in \(.applicationName)", "Log \(\.$medicine) in \(.applicationName)",
                              "Gave \(\.$medicine) in \(.applicationName)"],
                    shortTitle: "Log a medicine", systemImageName: "pills")
        // AI insights step 4 (D3 A): Siri then asks "What's your question?", and Little Log opens
        // after an unlock. Three phrases, as "Ask Little Log" alone may meet Siri's own "Ask …" (F18);
        // the one that works on the Duo is noted in CLAUDE.md.
        AppShortcut(intent: AskLittleLogIntent(),
                    phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) a question",
                              "Question for \(.applicationName)"],
                    shortTitle: "Ask", systemImageName: "bubble.left.and.text.bubble.right")
    }
}
