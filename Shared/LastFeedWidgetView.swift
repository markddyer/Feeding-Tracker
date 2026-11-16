import FeedingCore
import SwiftUI
import WidgetKit

// Shared by the widget extension and the app, so the app's tests can draw it.

/// One moment of the Lock Screen widget.
struct LastFeedEntry: TimelineEntry {
    let date: Date
    /// Nil before the household is set up on this phone.
    let glance: FeedGlance?
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

    // MARK: Rectangular: three lines

    @ViewBuilder
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let glance, let since = glance.runningSince {
                Label("Feed running", systemImage: "stopwatch")
                    .font(.caption.weight(.semibold))
                Text(GlanceText.elapsed(entry.date.timeIntervalSince(since)))
                    .font(.title2.weight(.semibold))
                Text("started \(GlanceText.clock(since, timeZoneID: glance.timeZoneID))")
                    .font(.caption)
            } else if let glance, let start = glance.lastFeedStart {
                Label("Last feed", systemImage: "waterbottle")
                    .font(.caption.weight(.semibold))
                Text("\(GlanceText.elapsed(entry.date.timeIntervalSince(start))) ago")
                    .font(.title2.weight(.semibold))
                if let opens = glance.windowOpens {
                    Text("Feeding window \(GlanceText.clock(opens, timeZoneID: glance.timeZoneID))")
                        .font(.caption)
                }
            } else {
                Label("Feeding", systemImage: "waterbottle")
                    .font(.caption.weight(.semibold))
                Text(glance == nil ? "Open the app to set up" : "No feeds logged yet")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
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
