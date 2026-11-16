import FeedingCore
import SwiftUI
import WidgetKit

/// The watch face pieces (plan v1, Phase 2: "plus a complication"). They read what the watch app
/// last heard from the phone (`WatchFile`); the watch app reloads them when that changes. Tapping
/// one opens Feeding. The watch face draws them in its own colours.
@main
struct FeedingWatchWidgets: WidgetBundle {
    var body: some Widget {
        WatchLastFeedWidget()
        WatchStartWidget()
    }
}

struct WatchEntry: TimelineEntry {
    let date: Date
    let glance: FeedGlance?
    /// The side being fed now, during a feed.
    var side: BreastSide?
}

/// One entry a minute for two hours, then one every five minutes up to six hours, as on the
/// iPhone's Lock Screen.
struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        let now = Date()
        return WatchEntry(date: now, glance: FeedGlance(lastFeedStart: now.addingTimeInterval(-6000),
                                                        windowOpens: now.addingTimeInterval(1200),
                                                        windowCloses: now.addingTimeInterval(8400)))
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let now = Date()
        let read = read(now: now)
        let start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        let offsets = Array(stride(from: 0, to: 120, by: 1)) + Array(stride(from: 120, through: 360, by: 5))
        let entries = offsets.map {
            WatchEntry(date: start.addingTimeInterval(Double($0) * 60), glance: read.glance, side: read.side)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func read(now: Date) -> WatchEntry {
        let state = WatchFile.load().shown
        return WatchEntry(date: now, glance: state?.glance, side: state?.running?.side)
    }
}

// MARK: - Last feed

struct WatchLastFeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchLastFeed", provider: WatchProvider()) { entry in
            WatchLastFeedView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Last feed")
        .description("The time since the last feed started, or the feed running now.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

/// The same facts and words as the iPhone's Lock Screen widget (`DESIGN.md`, "Outside the app").
struct WatchLastFeedView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let glance = entry.glance {
            content(glance)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(glance))
        } else {
            notReady
        }
    }

    @ViewBuilder
    private func content(_ glance: FeedGlance) -> some View {
        let now = entry.date
        let running = glance.runningSince.map { now.timeIntervalSince($0) }
        let since = glance.lastFeedStart.map { now.timeIntervalSince($0) }
        switch family {
        case .accessoryCircular:
            Gauge(value: running == nil ? glance.windowProgress(at: now) : 1) {
                Image(systemName: running == nil ? "waterbottle" : "stopwatch")
            } currentValueLabel: {
                Text(GlanceText.compactElapsed(running ?? since ?? 0))
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryCorner:
            Text(GlanceText.compactElapsed(running ?? since ?? 0))
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .widgetCurvesContent()
                .widgetLabel {
                    if running != nil {
                        Text("Feed running")
                    } else {
                        Gauge(value: glance.windowProgress(at: now)) { Text("Last feed") }
                    }
                }
                .widgetAccentable()
        case .accessoryInline:
            if let running {
                Text("Feed running \(GlanceText.elapsed(running))")
            } else if let since {
                Text("Last feed \(GlanceText.elapsed(since)) ago")
            } else {
                Text("No feeds yet")
            }
        default:
            rectangular(glance, running: running, since: since)
        }
    }

    private func rectangular(_ glance: FeedGlance, running: TimeInterval?, since: TimeInterval?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let running, let start = glance.runningSince {
                Text("Feed running \(GlanceText.elapsed(running))")
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                    .widgetAccentable()
                let side = entry.side.map { $0 == .left ? " · Left" : " · Right" } ?? ""
                Text("Started \(GlanceText.clock(start, timeZoneID: glance.timeZoneID))\(side)")
                    .font(.system(.body, design: .rounded).monospacedDigit())
            } else if let since {
                Text("Last feed \(GlanceText.elapsed(since)) ago")
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                    .widgetAccentable()
                if let opens = glance.windowOpens {
                    Text("Feeding window \(GlanceText.clock(opens, timeZoneID: glance.timeZoneID))")
                        .font(.system(.body, design: .rounded).monospacedDigit())
                }
                Gauge(value: glance.windowProgress(at: entry.date)) {}
                    .gaugeStyle(.accessoryLinearCapacity)
                    .widgetAccentable()
            } else {
                Text("No feeds logged yet").font(.system(.headline, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// Before the watch has heard from the phone.
    private var notReady: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("Feeding")
            case .accessoryRectangular:
                Text("Open Feeding on your iPhone").font(.system(.body, design: .rounded))
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    BottleShape().frame(width: 22, height: 22)
                }
            }
        }
        .accessibilityLabel("Feeding")
    }

    private func spoken(_ glance: FeedGlance) -> String {
        let now = entry.date
        if let start = glance.runningSince {
            return "Feed running \(GlanceText.spokenElapsed(now.timeIntervalSince(start)))"
        }
        guard let last = glance.lastFeedStart else { return "No feeds logged yet" }
        let window = glance.windowOpens.map { ". Feeding window \(GlanceText.clock($0, timeZoneID: glance.timeZoneID))" } ?? ""
        return "Last feed \(GlanceText.spokenElapsed(now.timeIntervalSince(last))) ago\(window)"
    }
}

// MARK: - Start feed

/// Start feed on the watch face (the user's choice of 16 Nov 2026). A tap opens Feeding on its
/// question: "Formula or expressed?" on a bottle-only watch, and the feed starts from the tap. On
/// any other watch the feed starts at once, as Start feed in the app does. A watch face piece can
/// only open its app, so the question is in the app.
struct WatchStartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchStart", provider: OpenProvider()) { _ in
            WatchStartView()
                .widgetURL(WatchLinks.startFeed)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Start feed")
        .description("Starts a feed. A bottle-only watch asks: formula or expressed?")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct WatchStartView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCorner {
                BottleShape()
                    .frame(width: 24, height: 24)
                    .widgetAccentable()
                    .widgetLabel("Start feed")
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        BottleShape().frame(width: 20, height: 20).widgetAccentable()
                        Text("Start").font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start feed")
    }
}

/// The bottle never changes: one entry.
struct OpenProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
    }

    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date())], policy: .never))
    }
}
