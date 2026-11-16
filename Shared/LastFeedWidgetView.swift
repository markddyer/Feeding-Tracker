import AppIntents
import FeedingCore
import SwiftUI
import WidgetKit

// Shared by the widget extension and the app, so the app's tests can draw it.

/// One moment of the Lock Screen widget.
struct LastFeedEntry: TimelineEntry {
    let date: Date
    /// Nil before the household is set up on this phone.
    let glance: FeedGlance?
    /// This phone's "How you feed" is Bottle only: the buttons then name the bottle.
    var bottleOnly = false
}

/// The moments the widget prepares, in minutes from now. The wide size has buttons, and iOS asks
/// for every moment in about 8 looks; with 90 moments its saved file went missing on the Duo
/// ("unable to find or unarchive file" in the phone's log, 16 Nov 2026), so the Lock Screen
/// showed the grey stand-in, while the round size, with no buttons, drew. The wide size's time
/// now updates by itself, so it needs one moment. The others keep a moment a minute for two
/// hours, then one every five minutes up to six hours.
enum LastFeedMoments {
    static func minutes(for family: WidgetFamily) -> [Int] {
        family == .accessoryRectangular
            ? [0]
            : Array(0..<120) + Array(stride(from: 120, through: 360, by: 5))
    }

    /// A one-moment timeline asks again after this long, in case the app's own reload is missed.
    static let oneMomentLifetime: TimeInterval = 6 * 3600
}

/// Where the app tells the widget this phone's "How you feed" (the widget can't read the app's
/// own settings).
enum WidgetSettings {
    static let bottleOnlyKey = "widgets.bottleOnly"
}

/// "Last feed 1h 40m ago" on the Lock Screen (plan v1, Phase 2; the user's choice of
/// 16 Nov 2026). Facts only, as on the home screen. The Lock Screen draws it in one tint, so it
/// has no colours of its own; amounts and times are in SF Pro Rounded (DESIGN.md).
struct LastFeedWidgetView: View {
    let entry: LastFeedEntry
    let family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .fontDesign(.rounded)
        .monospacedDigit()
    }

    private var glance: FeedGlance? { entry.glance }

    // MARK: Rectangular: the time, a detail, and the buttons (the user's choice of 16 Nov 2026)

    /// The time on its own line and the words under it (the user's choices of 16 Nov 2026):
    /// "Last feed 1h 40m ago" on one line was cut off on the Duo, and iOS sets the widget's width.
    /// iOS keeps the time up to date by itself ("1 hour, 40 minutes"), so this size needs one
    /// moment only (`LastFeedMoments`).
    @ViewBuilder
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Group {
                if let glance, let since = glance.runningSince {
                    Label { liveElapsed(since: since) } icon: { Image(systemName: "stopwatch") }
                        .font(.headline)
                    Text("Feed running, from \(GlanceText.clock(since, timeZoneID: glance.timeZoneID))")
                        .font(.caption)
                } else if let glance, let start = glance.lastFeedStart {
                    Label { liveElapsed(since: start) } icon: { Image(systemName: "waterbottle") }
                        .font(.headline)
                    Text(glance.windowOpens.map { "Last feed · window \(GlanceText.clock($0, timeZoneID: glance.timeZoneID))" }
                         ?? "Last feed")
                        .font(.caption)
                } else {
                    Label("Feeding", systemImage: "waterbottle")
                        .font(.headline)
                    Text(glance == nil ? "Open the app to set up" : "No feeds logged yet")
                        .font(.caption)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLive)
            if glance != nil {
                buttons
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Finish while a feed runs; otherwise Start, or one button per milk on a bottle-only phone.
    /// They run in the app, as Siri's Start feed and Finish feed do: plain actions, not the
    /// Control Center switch's (`FeedToggleIntent`), which is meant for a switch.
    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 6) {
            if glance?.runningSince != nil {
                button("Finish feed", FinishFeedIntent())
            } else if entry.bottleOnly {
                button("Formula", StartFeedIntent(milk: .formula), spoken: "Start a formula bottle")
                button("Expressed", StartFeedIntent(milk: .expressed), spoken: "Start an expressed milk bottle")
            } else {
                button("Start feed", StartFeedIntent(milk: nil))
            }
        }
    }

    private func button(_ title: String, _ intent: some AppIntent, spoken: String? = nil) -> some View {
        Button(intent: intent) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(.fill.secondary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken ?? title)
    }

    // MARK: Circular: the ring, as on Home, with the time inside

    @ViewBuilder
    private var circular: some View {
        if let glance, let start = glance.runningSince ?? glance.lastFeedStart {
            Gauge(value: glance.runningSince == nil ? glance.windowProgress(at: entry.date) : 0) {
                Image(systemName: glance.runningSince == nil ? "waterbottle" : "stopwatch")
            } currentValueLabel: {
                Text(GlanceText.compactElapsed(entry.date.timeIntervalSince(start)))
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        } else {
            Image(systemName: "waterbottle")
                .font(.title2)
                .accessibilityLabel(spoken)
        }
    }

    // MARK: Inline: one line above the clock

    private var inline: some View {
        Text(inlineText)
            .accessibilityLabel(spoken)
    }

    private var inlineText: String {
        guard let glance else { return "Feeding" }
        if let since = glance.runningSince { return "Feed running \(GlanceText.elapsed(entry.date.timeIntervalSince(since)))" }
        if let start = glance.lastFeedStart { return "Last feed \(GlanceText.elapsed(entry.date.timeIntervalSince(start))) ago" }
        return "No feeds logged yet"
    }

    /// The time since `start` in iOS's own words ("1 hour, 40 minutes"), which iOS keeps up to
    /// date on the Lock Screen with no new moment from the widget.
    private func liveElapsed(since start: Date) -> Text {
        Text(.currentDate, format: .offset(to: start, allowedFields: [.hour, .minute], maxFieldCount: 2))
    }

    /// What VoiceOver reads on the wide size: as `spoken`, with the time kept up to date by iOS.
    private var spokenLive: Text {
        guard let glance else { return Text(spoken) }
        if let since = glance.runningSince { return Text("Feed running for \(liveElapsed(since: since)).") }
        if let start = glance.lastFeedStart {
            let window = glance.windowOpens.map { " Feeding window \(GlanceText.clock($0, timeZoneID: glance.timeZoneID))." } ?? ""
            return Text("Last feed \(liveElapsed(since: start)) ago.\(window)")
        }
        return Text(spoken)
    }

    /// The sentence VoiceOver reads.
    private var spoken: String {
        guard let glance else { return "Feeding. Open the app to set up." }
        if let since = glance.runningSince {
            return "Feed running for \(GlanceText.spokenElapsed(entry.date.timeIntervalSince(since)))."
        }
        if let start = glance.lastFeedStart {
            let window = glance.windowOpens.map { " Feeding window \(GlanceText.clock($0, timeZoneID: glance.timeZoneID))." } ?? ""
            return "Last feed \(GlanceText.spokenElapsed(entry.date.timeIntervalSince(start))) ago.\(window)"
        }
        return "No feeds logged yet."
    }
}
