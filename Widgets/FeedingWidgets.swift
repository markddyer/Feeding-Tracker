import FeedingCore
import SwiftUI
import WidgetKit

/// The widget extension: the Lock Screen widget and the Control Center control (plan v1,
/// Phase 2; the user's choice of 16 Nov 2026). Both only read the household file in the App
/// Group; the actions run in the app (`FeedIntents.swift`).
@main
struct FeedingWidgets: WidgetBundle {
    var body: some Widget {
        LastFeedWidget()
        CareWidget()
        FeedControl()
        SleepControl()
        NappyControl()
        MedicineControl()
    }
}

/// Reads this phone's household file, which the app keeps in the App Group.
enum HouseholdReader {
    private static var group: String? {
        Bundle.main.object(forInfoDictionaryKey: "FeedingAppGroup") as? String
    }

    static func glance(now: Date) -> FeedGlance? {
        SharedHousehold.load()?.glance(now: now)
    }

    static func careGlance(now: Date) -> CareGlance? {
        SharedHousehold.load()?.careGlance(now: now)
    }

    /// This phone's "How you feed", as the app last told the widget.
    static var bottleOnly: Bool {
        group.flatMap { UserDefaults(suiteName: $0) }?.bool(forKey: WidgetSettings.bottleOnlyKey) ?? false
    }

    static func entry(now: Date) -> LastFeedEntry {
        LastFeedEntry(date: now, glance: glance(now: now), bottleOnly: bottleOnly)
    }
}

// MARK: - The Lock Screen widget

struct LastFeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LastFeed", provider: LastFeedProvider()) { entry in
            LastFeedFamilyView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Last feed")
        .description("The time since the last feed started, or the feed running now.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

private struct LastFeedFamilyView: View {
    let entry: LastFeedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LastFeedWidgetView(entry: entry, family: family)
    }
}

/// One entry a minute for two hours, then one every five minutes up to six hours; one entry for
/// the wide size (`LastFeedMoments`). The app asks for a new timeline whenever a feed starts,
/// finishes or changes.
struct LastFeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastFeedEntry {
        let now = Date()
        return LastFeedEntry(date: now, glance: FeedGlance(lastFeedStart: now.addingTimeInterval(-6000),
                                                           windowOpens: now.addingTimeInterval(1200),
                                                           windowCloses: now.addingTimeInterval(8400)))
    }

    func getSnapshot(in context: Context, completion: @escaping (LastFeedEntry) -> Void) {
        let now = Date()
        completion(context.isPreview ? placeholder(in: context) : HouseholdReader.entry(now: now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LastFeedEntry>) -> Void) {
        let now = Date()
        let read = HouseholdReader.entry(now: now)
        // Whole minutes, so "1h 40m" turns over on the minute.
        let start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        // The wide size gets one moment, as its time updates by itself (`LastFeedMoments`).
        let minutes = LastFeedMoments.minutes(for: context.family)
        let entries = minutes.map {
            LastFeedEntry(date: start.addingTimeInterval(Double($0) * 60), glance: read.glance, bottleOnly: read.bottleOnly)
        }
        let policy: TimelineReloadPolicy = minutes.count == 1
            ? .after(start.addingTimeInterval(LastFeedMoments.oneMomentLifetime))
            : .atEnd
        completion(Timeline(entries: entries, policy: policy))
    }
}

// MARK: - The control

/// A Control Center button, also for the Lock Screen's corners and the Action Button. When it is
/// added, the parent chooses the bottle it starts (Formula, Expressed milk, or Choose later), so a
/// bottle-only parent can add one per milk (the user's choice of 16 Nov 2026). On while a feed
/// runs; tapping it then finishes that feed.
struct FeedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "FeedControl", provider: FeedControlProvider()) { state in
            ControlWidgetToggle(isOn: state.running, action: FeedToggleIntent(bottle: state.bottle)) {
                Label(state.bottle.buttonTitle, systemImage: state.bottle.symbol)
            } valueLabel: { isOn in
                Label(isOn ? "Finish feed" : "Start", systemImage: isOn ? "stopwatch.fill" : state.bottle.symbol)
            }
            // DESIGN.md's `primary` (day), as on Start feed.
            .tint(Color(red: 0xFF / 255, green: 0x8E / 255, blue: 0x6E / 255))
        }
        .displayName("Start or finish a feed")
        .description("Starts a feed with the bottle you choose, or finishes the one running.")
        .promptsForUserConfiguration()
    }
}

struct FeedControlState {
    var running: Bool
    var bottle: ControlBottle
}

struct FeedControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: FeedControlConfiguration) -> FeedControlState {
        FeedControlState(running: false, bottle: configuration.bottle)
    }

    func currentValue(configuration: FeedControlConfiguration) async throws -> FeedControlState {
        FeedControlState(running: HouseholdReader.glance(now: Date())?.runningSince != nil, bottle: configuration.bottle)
    }
}

// MARK: - The Sleep and nappy widget (the users' choice F, 17 Nov 2026)

/// Beside Last feed on the Lock Screen: the time asleep or awake, the last nappy, and Woke up (or
/// Fell asleep), Wee, Poo and Both. The buttons run in the app (`CareIntents.swift`).
struct CareWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SleepAndNappy", provider: CareProvider()) { entry in
            CareWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Sleep and nappy")
        .description("How long the baby has slept or been awake, the last nappy, and buttons to log them.")
        .supportedFamilies([.accessoryRectangular])
    }
}

/// One moment: the times update by themselves, and the app asks for a new timeline whenever a
/// sleep or nappy is logged (`WidgetRefresher`). One moment also keeps the saved file small, which
/// matters for a widget with buttons (`LastFeedMoments`).
struct CareProvider: TimelineProvider {
    func placeholder(in context: Context) -> CareEntry {
        let now = Date()
        return CareEntry(date: now, glance: CareGlance(sleep: .asleep(id: "placeholder", since: now.addingTimeInterval(-4800)),
                                                       lastNappyAt: now.addingTimeInterval(-2400), lastNappyWee: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (CareEntry) -> Void) {
        let now = Date()
        completion(context.isPreview ? placeholder(in: context) : CareEntry(date: now, glance: HouseholdReader.careGlance(now: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CareEntry>) -> Void) {
        let now = Date()
        let entry = CareEntry(date: now, glance: HouseholdReader.careGlance(now: now))
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(LastFeedMoments.oneMomentLifetime))))
    }
}

// MARK: - The sleep, nappy and medicine controls (settled with round two, 17 Nov 2026)

/// DESIGN.md's `sleep` (day): periwinkle.
private let sleepTint = Color(red: 0x8B / 255, green: 0x8F / 255, blue: 0xE0 / 255)
/// DESIGN.md's `wee` (day): yellow.
private let nappyTint = Color(red: 0xF0 / 255, green: 0xC2 / 255, blue: 0x3B / 255)

/// The Sleep switch: on while the baby sleeps. Turning it on logs Fell asleep; off logs Woke up.
struct SleepControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SleepControl", provider: SleepControlProvider()) { asleep in
            ControlWidgetToggle(isOn: asleep, action: SleepToggleIntent()) {
                Label("Sleep", systemImage: "moon.fill")
            } valueLabel: { isOn in
                Label(isOn ? "Asleep" : "Awake", systemImage: isOn ? "moon.zzz.fill" : "moon")
            }
            .tint(sleepTint)
        }
        .displayName("Sleep")
        .description("On while the baby sleeps. Turn it on for Fell asleep, and off for Woke up.")
    }
}

struct SleepControlProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        HouseholdReader.careGlance(now: Date())?.isAsleep ?? false
    }
}

/// A nappy button, set up once as Wee, Poo or Both. It logs the nappy at once, with no details;
/// the colour and consistency can be added in the app.
struct NappyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "NappyControl", provider: NappyControlProvider()) { kind in
            ControlWidgetButton(action: NappyIntent(kind: kind)) {
                Label(kind.buttonTitle, systemImage: kind.symbol)
            }
            .tint(nappyTint)
        }
        .displayName("Log a nappy")
        .description("Logs a wee, a poo or both, as you choose when you add the button.")
        .promptsForUserConfiguration()
    }
}

struct NappyControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: NappyControlConfiguration) -> NappyChoice {
        configuration.kind
    }

    func currentValue(configuration: NappyControlConfiguration) async throws -> NappyChoice {
        configuration.kind
    }
}

/// A medicine button, set up once with one medicine from the household's list. It logs that
/// medicine at once. The app never shows a "next dose" time.
struct MedicineControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "MedicineControl", provider: MedicineControlProvider()) { medicine in
            ControlWidgetButton(action: MedicineIntent(medicine: medicine)) {
                Label(medicine, systemImage: "pills.fill")
            }
        }
        .displayName("Log a medicine")
        .description("Logs the medicine or vitamin you choose when you add the button.")
        .promptsForUserConfiguration()
    }
}

struct MedicineControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: MedicineControlConfiguration) -> String {
        configuration.medicine
    }

    func currentValue(configuration: MedicineControlConfiguration) async throws -> String {
        configuration.medicine
    }
}
