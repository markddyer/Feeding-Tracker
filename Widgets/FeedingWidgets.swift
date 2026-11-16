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
        FeedControl()
    }
}

/// Reads this phone's household file, which the app keeps in the App Group.
enum HouseholdReader {
    private static var group: String? {
        Bundle.main.object(forInfoDictionaryKey: "FeedingAppGroup") as? String
    }

    static func glance(now: Date) -> FeedGlance? {
        guard let group,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? HouseholdFile.load(from: folder.appendingPathComponent("household.json"))
        else { return nil }
        return data.glance(now: now)
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

/// One entry a minute for two hours, then one every five minutes up to six hours. The app asks
/// for a new timeline whenever a feed starts, finishes or changes.
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
        let offsets = Array(stride(from: 0, to: 120, by: 1)) + Array(stride(from: 120, through: 360, by: 5))
        let entries = offsets.map {
            LastFeedEntry(date: start.addingTimeInterval(Double($0) * 60), glance: read.glance, bottleOnly: read.bottleOnly)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
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
