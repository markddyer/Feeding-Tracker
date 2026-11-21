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
    /// Worked out by the starting rule, not chosen by a parent: a dashed ring (design 7A).
    var workedOut = false
}

extension View {
    /// The dashed ring of a worked-out "done by" or "got up" (design 7A).
    func workedOutRing(_ shown: Bool) -> some View {
        overlay {
            if shown {
                Circle()
                    .stroke(Theme.text, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                    .padding(-3)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// One feed or pumping session in History (and later the Duo's second column): tinted by kind,
/// the time on the left, chips in the middle, and the avatar of who logged it on the right. A
/// second, smaller avatar shows who finished it, when that was the other parent.
struct HistoryRow: View {
    let snapshot: EventSnapshot
    let time: String
    let loggedBy: RowPerson
    var finishedBy: RowPerson?
    /// The other phone logged this feed too, and the screens show it once.
    var loggedTwice = false
    /// What the avatar means, for VoiceOver: "Logged by", or "Done by" in a list behind a number.
    var role = "Logged by"
    /// A line under the chips: the time this row added to a number (X2).
    var note: String?

    var body: some View {
        let tint = Self.tint(snapshot)
        HStack(alignment: .center, spacing: 10) {
            Text(time)
                .feedText(.smallButton)
                .fixedSize()
                .frame(minWidth: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                FeedChips(snapshot: snapshot, detailed: true)
                if loggedTwice {
                    Label("Logged on both phones", systemImage: "arrow.triangle.merge")
                        .feedText(.small)
                        .foregroundStyle(Theme.textMuted)
                }
                if let note {
                    Text(note)
                        .feedText(.small)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: -6) {
                Avatar(name: loggedBy.name, colour: loggedBy.colour, size: 26)
                    .workedOutRing(loggedBy.workedOut)
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
        let twice = loggedTwice ? " Logged on both phones, shown once." : ""
        let worked = loggedBy.workedOut ? ", worked out" : ""
        let added = note.map { " \($0)." } ?? ""
        return "\(time): \(chips)\(running). \(role) \(loggedBy.spoken)\(worked)\(finished).\(twice)\(added)"
    }
}

extension HistoryRow {
    /// A row for a feed or pumping session, with the household's clock and both phones' names
    /// and colours. History and the Duo's second column both use it.
    @MainActor
    init(_ snapshot: EventSnapshot, zone: TimeZone, loggedTwice: Bool = false) {
        let event = snapshot.event
        let finisher = event.endedAt == nil ? nil : snapshot.payload?.stamp(.endedAt)?.by
        self.init(snapshot: snapshot,
                  time: event.startedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)),
                  loggedBy: RowPerson(event.loggedBy),
                  finishedBy: finisher.flatMap { $0 == event.loggedBy ? nil : RowPerson($0) },
                  loggedTwice: loggedTwice)
    }
}

extension RowPerson {
    /// A parent as this phone knows them: their name, their colour, and "you" for this phone.
    @MainActor
    init(_ member: MemberID) {
        let model = AppModel.shared
        let names = model.memberNames
        let isMe = member == model.me
        self.init(name: names[member] ?? (isMe ? "You" : "Other parent"),
                  colour: model.memberColours[member] ?? (isMe ? .sunflower : .teal),
                  spoken: isMe ? "you" : (names[member] ?? "the other parent"))
    }
}

// MARK: - Sleep, nappies, medicine and growth in History (06-more-than-feeds.md)

/// One sleep, nappy, medicine or growth entry in History: tinted by kind, the time on the left,
/// its shape and facts in the middle, and the avatar of who logged it on the right.
struct CareRow: View {
    let snapshot: EventSnapshot
    let zone: TimeZone
    let loggedBy: RowPerson
    let now: Date
    /// What the avatar means, for VoiceOver: "Logged by", "Done by" or "Got up".
    var role = "Logged by"
    /// The time shown on the left, when not the start: a wake-up shows its end.
    var at: Date?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(clock(at ?? snapshot.event.startedAt))
                .feedText(.smallButton)
                .fixedSize()
                .frame(minWidth: 50, alignment: .leading)
            HStack(spacing: 7) {
                FeedMarkView(mark, size: 18, relativeTo: .subheadline)
                    .accessibilityHidden(true)
                Text(line)
                    .feedText(.subheadline)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Avatar(name: loggedBy.name, colour: loggedBy.colour, size: 26)
                .workedOutRing(loggedBy.workedOut)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mark.tint, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clock(at ?? snapshot.event.startedAt)): \(spoken). \(role) \(loggedBy.spoken)\(loggedBy.workedOut ? ", worked out" : "").")
    }

    private func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }

    private var mark: FeedMark {
        switch snapshot.event.kind {
        case .sleep: .sleep
        case .nappy: .nappy(wee: snapshot.payload?.nappy?.wee ?? false, poo: snapshot.payload?.nappy?.poo ?? false)
        case .medicine: .medicine
        case .bath: .bath
        default: .growth
        }
    }

    /// "Asleep 1h 20m, to 11:25", "Poo · yellow, loose", "Vitamin D", "3.85 kg (8 lb 8 oz)".
    private var line: String {
        let event = snapshot.event
        guard let payload = snapshot.payload else { return "Details need a newer version of the app" }
        switch event.kind {
        case .sleep:
            if let end = event.endedAt {
                return "Asleep \(HomeText.elapsed(max(0, end.timeIntervalSince(event.startedAt)))), to \(clock(end))"
            }
            return "Asleep \(HomeText.elapsed(max(0, now.timeIntervalSince(event.startedAt)))) so far"
        case .nappy:
            return payload.nappy.map(CareText.nappyLine) ?? "Nappy"
        case .medicine:
            return payload.medicine.map(CareText.medicineLine) ?? "Medicine"
        case .bath:
            return "Bath"
        default:
            return payload.growth.map(CareText.growthLine) ?? "Growth"
        }
    }

    private var spoken: String {
        line.replacingOccurrences(of: " · ", with: ", ")
    }
}

extension CareRow {
    @MainActor
    init(_ snapshot: EventSnapshot, zone: TimeZone, now: Date = Date()) {
        self.init(snapshot: snapshot, zone: zone, loggedBy: RowPerson(snapshot.event.loggedBy), now: now)
    }
}
