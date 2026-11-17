import FeedingCore
import SwiftUI

/// The watch app's pages (pick I, 17 Nov 2026): feeds, as before, then sleep and nappies. Swipe
/// up, or turn the Digital Crown past the end of the feed page, for the second.
enum WatchPage: Hashable {
    case feeds
    case care
}

/// Page two, "Sleep and nappy": how long the baby has slept (or been awake), a big Woke up or Fell
/// asleep, then Wee, Poo and Both, and when the last nappy was. Each tap logs at once, as Start
/// feed does: there is no Undo bar on the watch, and the phone's History can remove a mistake.
struct CareScreen: View {
    let state: WatchState
    let now: Date
    let waiting: Bool
    let send: (WatchCommand) -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        let sleep = state.sleep
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(CareText.sleepLabel(sleep)).watchText(.label).foregroundStyle(palette.textMuted)
                if let sleep {
                    HStack(spacing: 6) {
                        MoonShape()
                            .fill(sleep.asleep ? palette.sleep : palette.textMuted)
                            .frame(width: 22, height: 22)
                        Text(GlanceText.elapsed(now.timeIntervalSince(sleep.since)))
                            .watchText(.careTime)
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                } else {
                    Text("No sleep logged yet").watchText(.line).foregroundStyle(palette.text)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CareText.spokenSleep(sleep, now: now))
            if waiting { WaitingLine() }
            // Soft, with no double tap: the double tap stays Start feed's, on page one.
            WatchBigButton(title: sleep?.asleep == true ? "Woke up" : "Fell asleep", prominent: false, compact: true) {
                if let command = state.sleepTap() { send(command) }
            }
            .accessibilityLabel(sleep?.asleep == true ? "Woke up, log it now" : "Fell asleep, log it now")
            HStack(spacing: 6) {
                NappyButton(title: "Wee", wee: true, poo: false, spoken: "Log a wet nappy") { log(wee: true, poo: false) }
                NappyButton(title: "Poo", wee: false, poo: true, spoken: "Log a dirty nappy") { log(wee: false, poo: true) }
                NappyButton(title: "Both", wee: true, poo: true, spoken: "Log a wet and dirty nappy") { log(wee: true, poo: true) }
            }
            nappyLine(palette)
        }
    }

    private func log(wee: Bool, poo: Bool) {
        send(.nappy(nappyID: UUID().uuidString, wee: wee, poo: poo))
    }

    @ViewBuilder
    private func nappyLine(_ palette: WatchPalette) -> some View {
        Group {
            if let nappy = state.lastNappy {
                HStack(spacing: 5) {
                    NappyMark(wee: nappy.wee, poo: nappy.poo, size: 13, weeColour: palette.wee, pooColour: palette.poo)
                    Text("Nappy \(Text(CareText.ago(nappy.at, now: now)).foregroundStyle(palette.text))")
                        .foregroundStyle(palette.textMuted)
                }
            } else {
                Text("No nappy logged yet").foregroundStyle(palette.textMuted)
            }
        }
        .watchText(.line)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CareText.spokenNappy(state.lastNappy, now: now))
    }
}

/// Wee, Poo or Both: the shape above the word, like Left and Right.
private struct NappyButton: View {
    let title: String
    let wee: Bool
    let poo: Bool
    let spoken: String
    let action: () -> Void
    @State private var taps = 0
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 1) {
                NappyMark(wee: wee, poo: poo, size: wee && poo ? 15 : 17, weeColour: palette.wee, pooColour: palette.poo)
                    .frame(height: 17)
                Text(title).watchText(.side).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(palette.text)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: taps)
        .accessibilityLabel(spoken)
    }
}
