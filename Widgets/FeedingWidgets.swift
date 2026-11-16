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
    static func glance(now: Date) -> FeedGlance? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FeedingAppGroup") as? String,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? HouseholdFile.load(from: folder.appendingPathComponent("household.json"))
        else { return nil }
        return data.glance(now: now)
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
        completion(context.isPreview ? placeholder(in: context) : LastFeedEntry(date: now, glance: HouseholdReader.glance(now: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LastFeedEntry>) -> Void) {
        let now = Date()
        let glance = HouseholdReader.glance(now: now)
        // Whole minutes, so "1h 40m" turns over on the minute.
        let start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        let offsets = Array(stride(from: 0, to: 120, by: 1)) + Array(stride(from: 120, through: 360, by: 5))
        let entries = offsets.map { LastFeedEntry(date: start.addingTimeInterval(Double($0) * 60), glance: glance) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - The control

/// "Start feed" in Control Center, on the Lock Screen and on the Action Button. On while a feed
/// runs; tapping it then finishes that feed.
struct FeedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "FeedControl", provider: FeedControlProvider()) { running in
            ControlWidgetToggle("Feed", isOn: running, action: FeedToggleIntent()) { isOn in
                Label(isOn ? "Finish feed" : "Start feed", systemImage: isOn ? "stopwatch.fill" : "waterbottle")
            }
            // DESIGN.md's `primary` (day), as on Start feed.
            .tint(Color(red: 0xFF / 255, green: 0x8E / 255, blue: 0x6E / 255))
        }
        .displayName("Start or finish a feed")
        .description("Starts a feed, or finishes the one running. Add the sides and bottles in the app.")
    }
}

struct FeedControlProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        HouseholdReader.glance(now: Date())?.runningSince != nil
    }
}
