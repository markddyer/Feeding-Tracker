import AppIntents
import FeedingCore
import SwiftUI
import WidgetKit

// Shared by the widget extension and the app, so the app can draw it too.

/// One moment of the Sleep and nappy widget.
struct CareEntry: TimelineEntry {
    let date: Date
    /// Nil before the household is set up on this phone.
    let glance: CareGlance?
}

/// The Sleep and nappy widget on the Lock Screen (the users' choice F, 17 Nov 2026), beside Last
/// feed: how long the baby has slept or been awake, when the last nappy was, and four buttons:
/// Woke up (or Fell asleep), Wee, Poo and Both. Facts only. The Lock Screen draws it in one tint,
/// so it has no colours of its own. Its times update by themselves, so it needs one moment, as
/// the Last feed widget's wide size does (`LastFeedMoments`).
struct CareWidgetView: View {
    let entry: CareEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Group {
                headline
                    .font(.headline)
                caption
                    .font(.caption)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLive)
            if entry.glance != nil {
                buttons
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fontDesign(.rounded)
        .monospacedDigit()
    }

    private var glance: CareGlance? { entry.glance }

    // MARK: The two lines

    /// The moon and the time asleep or awake. The moon is filled while asleep and drawn as a line
    /// while awake.
    @ViewBuilder
    private var headline: some View {
        HStack(spacing: 5) {
            moon
            if let since = glance?.sleepSince {
                liveElapsed(since: since)
            } else {
                Text("Sleep and nappy")
            }
        }
    }

    @ViewBuilder
    private var moon: some View {
        Group {
            if glance?.isAsleep == true {
                MoonShape()
            } else {
                MoonShape().stroke(lineWidth: 1.6)
            }
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }

    /// "Asleep · nappy 10:45", "Awake · nappy 10:45", "Asleep since 10:05". The nappy's clock time,
    /// as the Last feed widget's line gives the window's: iOS's own ticking words for a time since
    /// ran to "40 min, 0 secs" or "2 hours, 1 minute", too long for this line.
    @ViewBuilder
    private var caption: some View {
        if let glance {
            let state: String? = switch glance.sleep {
            case .asleep: "Asleep"
            case .awake: "Awake"
            case .notLogged: nil
            }
            if let nappy = glance.lastNappyAt {
                let time = GlanceText.clock(nappy, timeZoneID: glance.timeZoneID)
                if let state {
                    Text("\(state) · nappy \(time)")
                } else {
                    Text("Last nappy \(time)")
                }
            } else if let state, let since = glance.sleepSince {
                Text("\(state) since \(GlanceText.clock(since, timeZoneID: glance.timeZoneID))")
            } else {
                Text("No sleep or nappy logged yet")
            }
        } else {
            Text("Open the app to set up")
        }
    }

    // MARK: The buttons

    /// Woke up (or Fell asleep) gets the room left over; the three nappy buttons are shapes only.
    private var buttons: some View {
        HStack(spacing: 4) {
            if glance?.isAsleep == true {
                wordButton("Woke up", WokeUpIntent())
            } else {
                wordButton("Fell asleep", FellAsleepIntent())
            }
            shapeButton(.wee) { DropShape().frame(width: 13, height: 13) }
            shapeButton(.poo) { PooShape().frame(width: 15, height: 15) }
            shapeButton(.both) {
                HStack(spacing: -2) {
                    DropShape().frame(width: 11, height: 11)
                    PooShape().frame(width: 13, height: 13)
                }
            }
        }
    }

    private func wordButton(_ title: String, _ intent: some AppIntent) -> some View {
        Button(intent: intent) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(.fill.secondary, in: Capsule())
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .accessibilityLabel(title)
    }

    private func shapeButton(_ kind: NappyChoice, @ViewBuilder _ shape: () -> some View) -> some View {
        Button(intent: NappyIntent(kind: kind)) {
            shape()
                .frame(width: 30, height: 22)
                .background(.fill.secondary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.spoken)
    }

    // MARK: Words

    /// The time since `start` in iOS's own words ("1 hour, 20 minutes"), kept up to date on the
    /// Lock Screen by iOS, as on the Last feed widget.
    private func liveElapsed(since start: Date) -> Text {
        Text(.currentDate, format: .offset(to: start, allowedFields: [.hour, .minute], maxFieldCount: 2))
    }

    /// What VoiceOver reads for the two lines, with the times kept up to date by iOS.
    private var spokenLive: Text {
        guard let glance else { return Text("Sleep and nappy. Open the app to set up.") }
        let sleep: Text = switch glance.sleep {
        case .asleep(_, let since): Text("Asleep for \(liveElapsed(since: since)).")
        case .awake(let since): Text("Awake for \(liveElapsed(since: since)).")
        case .notLogged: Text("No sleep logged yet.")
        }
        guard let nappy = glance.lastNappyAt else { return Text("\(sleep) No nappy logged yet.") }
        let kind = GlanceText.nappyKind(wee: glance.lastNappyWee, poo: glance.lastNappyPoo)
        return Text("\(sleep) Last nappy at \(GlanceText.clock(nappy, timeZoneID: glance.timeZoneID)), \(kind).")
    }
}
