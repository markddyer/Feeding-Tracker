import FeedingCore
import SwiftUI

/// A feed's or pumping session's chips, wrapping onto more lines when narrow. While a feed runs,
/// the side being fed has a live clock ("◑ 4:02 running").
struct FeedChips: View {
    let snapshot: EventSnapshot
    /// History's chips: "Formula 30 ml" rather than "30 ml".
    var detailed = false

    var body: some View {
        let segments = snapshot.payload?.feed?.breast ?? []
        let running = snapshot.event.endedAt == nil
            ? segments.last.flatMap { segment in segment.durationSeconds == nil ? segment.startedAt : nil }
            : nil
        let chips = HomeText.chips(snapshot, detailed: detailed)
        FlowLayout(spacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                if let running, index == segments.count - 1, let mark = chip.mark {
                    // On a History row, which already has the kind's tint, it uses the
                    // background colour like the other chips.
                    LiveChip(mark: mark, since: running, background: detailed ? Theme.background : nil)
                } else {
                    Chip(chip.mark, chip.text, spoken: chip.spoken)
                }
            }
        }
    }
}

/// Who a row names: their initial, colour and name.
struct RowPerson {
    var name: String
    var colour: ParentColour
    /// "you", or their name, for VoiceOver.
    var spoken: String
}

/// One feed or pumping session in History (and later the Duo's second column): tinted by kind,
/// the time on the left, chips in the middle, and the avatar of who logged it on the right. A
/// second, smaller avatar shows who finished it, when that was the other parent.
struct HistoryRow: View {
    let snapshot: EventSnapshot
    let time: String
    let loggedBy: RowPerson
    var finishedBy: RowPerson?

    var body: some View {
        let tint = Self.tint(snapshot)
        HStack(alignment: .center, spacing: 10) {
            Text(time)
                .feedText(.smallButton)
                .fixedSize()
                .frame(minWidth: 50, alignment: .leading)
            FeedChips(snapshot: snapshot, detailed: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: -6) {
                Avatar(name: loggedBy.name, colour: loggedBy.colour, size: 26)
                if let finishedBy {
                    Avatar(name: finishedBy.name, colour: finishedBy.colour, size: 20)
                        .padding(2)
                        .background(tint, in: Circle())
                        .offset(y: 6)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The row's colour: pumping green, a feed with the breast pink, a bottle-only feed blue.
    static func tint(_ snapshot: EventSnapshot) -> Color {
        if snapshot.event.kind == .pump { return Theme.pumpTint }
        let feed = snapshot.payload?.feed
        if !(feed?.breast.isEmpty ?? true) { return Theme.breastTint }
        if !(feed?.bottles.isEmpty ?? true) { return Theme.bottleTint }
        return Theme.surface
    }

    private var spoken: String {
        let chips = HomeText.chips(snapshot, detailed: true).map(\.spoken).joined(separator: ", ")
        let running = snapshot.event.kind == .feed && snapshot.event.endedAt == nil ? ", running" : ""
        let finished = finishedBy.map { ", finished by \($0.spoken)" } ?? ""
        return "\(time): \(chips)\(running). Logged by \(loggedBy.spoken)\(finished)."
    }
}
