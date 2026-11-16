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

    @ViewBuilder
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Group {
                if let glance, let since = glance.runningSince {
                    Label("Feed running \(GlanceText.elapsed(entry.date.timeIntervalSince(since)))", systemImage: "stopwatch")
                        .font(.headline)
                    Text("started \(GlanceText.clock(since, timeZoneID: glance.timeZoneID))")
                        .font(.caption)
                } else if let glance, let start = glance.lastFeedStart {
                    Label("Last feed \(GlanceText.elapsed(entry.date.timeIntervalSince(start))) ago", systemImage: "waterbottle")
                        .font(.headline)
                    if let opens = glance.windowOpens {
                        Text("Feeding window \(GlanceText.clock(opens, timeZoneID: glance.timeZoneID))")
                            .font(.caption)
                    }
                } else {
                    Label("Feeding", systemImage: "waterbottle")
                        .font(.headline)
                    Text(glance == nil ? "Open the app to set up" : "No feeds logged yet")
                        .font(.caption)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            if glance != nil {
                buttons
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Finish while a feed runs; otherwise Start, or one button per milk on a bottle-only phone.
    /// They run in the app, as the Control Center button does (`FeedToggleIntent`).
    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 6) {
            if glance?.runningSince != nil {
                button("Finish feed", FeedToggleIntent(value: false, bottle: .later))
            } else if entry.bottleOnly {
                button("Formula", FeedToggleIntent(value: true, bottle: .formula), spoken: "Start a formula bottle")
                button("Expressed", FeedToggleIntent(value: true, bottle: .expressed), spoken: "Start an expressed milk bottle")
            } else {
                button("Start feed", FeedToggleIntent(value: true, bottle: .later))
            }
        }
    }

    private func button(_ title: String, _ intent: FeedToggleIntent, spoken: String? = nil) -> some View {
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
