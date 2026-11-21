import FeedingCore
import SwiftUI
import WidgetKit

// The watch face's Sleep and Nappy pieces (`06-more-than-feeds.md`, settled with round two,
// 17 Nov 2026). A watch face piece can only open its app, so each tap goes through the watch app:
// the Sleep piece logs Fell asleep or Woke up at once, and the Nappy piece opens page two on
// "Wee, poo or both?".

struct CareEntry: TimelineEntry {
    let date: Date
    /// False before the watch has heard from a set-up phone.
    let setUp: Bool
    let sleep: WatchSleep?
    let nappy: WatchNappy?
    /// Day or night, for the pieces' colours on a full-colour face.
    var look: Look = .night
}

/// One entry a minute for two hours, then one every five minutes up to six hours, as for the
/// Last feed piece. The watch app reloads the pieces when the sleep or the last nappy changes.
struct CareProvider: TimelineProvider {
    func placeholder(in context: Context) -> CareEntry {
        let now = Date()
        return CareEntry(date: now, setUp: true, sleep: WatchSleep(id: "placeholder", start: now.addingTimeInterval(-80 * 60)),
                         nappy: WatchNappy(id: "placeholder", at: now.addingTimeInterval(-40 * 60), wee: true, poo: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (CareEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CareEntry>) -> Void) {
        let now = Date()
        let read = read(now: now)
        let start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        let offsets = Array(stride(from: 0, to: 120, by: 1)) + Array(stride(from: 120, through: 360, by: 5))
        let entries = offsets.map {
            CareEntry(date: start.addingTimeInterval(Double($0) * 60), setUp: read.setUp, sleep: read.sleep, nappy: read.nappy,
                      look: read.look)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func read(now: Date) -> CareEntry {
        let state = WatchFile.load().shown
        return CareEntry(date: now, setUp: state?.setUp ?? false, sleep: state?.sleep, nappy: state?.lastNappy,
                         look: state?.look(at: now) ?? .night)
    }
}

// MARK: - Sleep

struct WatchSleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchSleep", provider: CareProvider()) { entry in
            WatchSleepView(entry: entry)
                .widgetURL(entry.setUp ? WatchLinks.sleepTap(asleepID: entry.sleep.flatMap { $0.asleep ? $0.id : nil }) : nil)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Sleep")
        .description("How long the baby has slept, or been awake. A tap logs Fell asleep or Woke up.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// The moon and the time asleep ("1:20"). While awake, the sun and the time awake, so the two
/// can't be mixed up at a glance.
struct WatchSleepView: View {
    let entry: CareEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let sleep = entry.sleep
        let time = sleep.map { GlanceText.compactElapsed(entry.date.timeIntervalSince($0.since)) } ?? "Sleep"
        Group {
            if family == .accessoryCorner {
                icon(size: 22)
                    .widgetAccentable()
                    .widgetLabel(sleep.map { "\(CareText.sleepLabel($0)) \(GlanceText.elapsed(entry.date.timeIntervalSince($0.since)))" }
                                 ?? "Sleep")
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        icon(size: 17).widgetAccentable()
                        Text(time)
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The moon in the sleep colour, the sun in the wee's yellow, on a full-colour face (the
    /// users' ask, 21 Nov 2026); the face's own colour on a tinted one.
    @ViewBuilder
    private func icon(size: CGFloat) -> some View {
        let palette = WatchPalette.of(entry.look)
        let full = renderingMode == .fullColor
        if let sleep = entry.sleep, !sleep.asleep {
            Image(systemName: "sun.max.fill").font(.system(size: size * 0.82, weight: .semibold))
                .foregroundStyle(full ? AnyShapeStyle(palette.wee) : AnyShapeStyle(.primary))
        } else {
            MoonShape().fill(full ? AnyShapeStyle(palette.sleep) : AnyShapeStyle(.primary)).frame(width: size, height: size)
        }
    }

    private var spoken: String {
        guard entry.setUp else { return "Sleep" }
        let tap = entry.sleep?.asleep == true ? "Tap to log Woke up" : "Tap to log Fell asleep"
        return "\(CareText.spokenSleep(entry.sleep, now: entry.date)). \(tap)"
    }
}

// MARK: - Nappy

struct WatchNappyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchNappy", provider: CareProvider()) { entry in
            WatchNappyView(entry: entry)
                .widgetURL(WatchLinks.care)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Nappy")
        .description("The time since the last nappy. A tap opens Little Log to log wee, poo or both.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// The last nappy's shape and the time since it ("40m").
struct WatchNappyView: View {
    let entry: CareEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// The wee's yellow and the poo's brown on a full-colour face; the face's colour otherwise.
    private var colours: (wee: Color?, poo: Color?) {
        guard renderingMode == .fullColor else { return (nil, nil) }
        let palette = WatchPalette.of(entry.look)
        return (palette.wee, palette.poo)
    }

    var body: some View {
        let nappy = entry.nappy
        let time = nappy.map { GlanceText.compactElapsed(entry.date.timeIntervalSince($0.at)) } ?? "Nappy"
        Group {
            if family == .accessoryCorner {
                NappyMark(wee: nappy?.wee ?? true, poo: nappy?.poo ?? true, size: 18, weeColour: colours.wee, pooColour: colours.poo)
                    .widgetAccentable()
                    .widgetLabel(nappy.map { "Nappy \(CareText.ago($0.at, now: entry.date))" } ?? "Nappy")
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        NappyMark(wee: nappy?.wee ?? true, poo: nappy?.poo ?? true, size: 15, weeColour: colours.wee, pooColour: colours.poo)
                            .frame(height: 17)
                            .widgetAccentable()
                        Text(time)
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(CareText.spokenNappy(nappy, now: entry.date)). Tap to log a nappy")
    }
}
