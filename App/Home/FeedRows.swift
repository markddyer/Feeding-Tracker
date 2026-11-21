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
    /// A "got up" worked out from the log, not chosen by a parent: a dashed ring (design 7A).
    var workedOut = false
}

extension View {
    /// The dashed ring of a worked-out "got up" (design 7A).
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

/// One feed or pumping session in History (and the Duo's second column): tinted by kind, the time
/// on the left, chips in the middle, and on the right the big picture of who did it (DD12) and a
/// small one of the other parent when they logged it or finished it (7B).
struct HistoryRow: View {
    let snapshot: EventSnapshot
    let time: String
    let loggedBy: RowPerson
    var finishedBy: RowPerson?
    /// The other phone logged this feed too, and the screens show it once.
    var loggedTwice = false
    /// What the avatar means, for VoiceOver: "Logged by", or "Done by" in a list behind a number.
    var role = "Logged by"
    /// What the small picture means, for VoiceOver: "finished by", "logged by".
    var secondRole = "finished by"
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
            RowAvatars(main: loggedBy, second: finishedBy, tint: tint)
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
        let finished = finishedBy.map { ", \(secondRole) \($0.spoken)" } ?? ""
        let twice = loggedTwice ? " Logged on both phones, shown once." : ""
        let worked = loggedBy.workedOut ? ", probably" : ""
        let added = note.map { " \($0)." } ?? ""
        return "\(time): \(chips)\(running). \(role) \(loggedBy.spoken)\(worked)\(finished).\(twice)\(added)"
    }
}

extension HistoryRow {
    /// A row for a feed or pumping session, with the household's clock and both phones' names
    /// and colours. History and the Duo's second column both use it. With `answer`, the big
    /// picture is who did it (DD12); without, who logged it.
    @MainActor
    init(_ snapshot: EventSnapshot, zone: TimeZone, loggedTwice: Bool = false, answer: WhoDidIt.Answer? = nil) {
        let people = RowPeople(snapshot, answer: answer)
        self.init(snapshot: snapshot,
                  time: snapshot.event.startedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)),
                  loggedBy: people.main, finishedBy: people.second, loggedTwice: loggedTwice, role: people.role,
                  secondRole: people.secondRole)
    }
}

/// Who a History row shows (DD12, 7B): the big picture is who did it; a small one shows the other parent when they logged it or finished it, so at most two. "Finished
/// by" only when the end was set as Finish was tapped (`EventSnapshot.finishedBy`, TD1).
struct RowPeople {
    var main: RowPerson
    var role: String
    var second: RowPerson?
    var secondRole: String

    @MainActor
    init(_ snapshot: EventSnapshot, answer: WhoDidIt.Answer?) {
        let event = snapshot.event
        let logger = event.loggedBy
        let finisher = event.kind == .feed || event.kind == .pump ? snapshot.finishedBy : nil
        guard let answer else {
            main = RowPerson(logger)
            role = "Logged by"
            second = finisher.flatMap { $0 == logger ? nil : RowPerson($0) }
            secondRole = "finished by"
            return
        }
        main = RowPerson(answer.member)
        role = event.kind == .sleep ? "Settled by" : "Done by"
        let loggedByOther = logger != answer.member
        let finishedByOther = finisher.map { $0 != answer.member } ?? false
        if loggedByOther {
            second = RowPerson(logger)
            secondRole = finishedByOther && finisher == logger ? "logged and finished by" : "logged by"
        } else if finishedByOther, let finisher {
            second = RowPerson(finisher)
            secondRole = "finished by"
        } else {
            second = nil
            secondRole = ""
        }
    }
}

/// The big picture and, a little lower, the small one on the row's own colour.
struct RowAvatars: View {
    let main: RowPerson
    let second: RowPerson?
    let tint: Color

    var body: some View {
        HStack(spacing: -6) {
            Avatar(name: main.name, colour: main.colour, size: 26)
                .workedOutRing(main.workedOut)
            if let second {
                Avatar(name: second.name, colour: second.colour, size: 20)
                    .padding(2)
                    .background(tint, in: Circle())
                    .offset(y: 6)
            }
        }
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
    /// The small picture: the other parent, when they logged it (7B).
    var second: RowPerson?
    var secondRole = ""
    /// The other phone logged it too, and the screens show it once (D12 A).
    var loggedTwice = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(clock(at ?? snapshot.event.startedAt))
                .feedText(.smallButton)
                .fixedSize()
                .frame(minWidth: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    FeedMarkView(mark, size: 18, relativeTo: .subheadline)
                        .accessibilityHidden(true)
                    Text(line)
                        .feedText(.subheadline)
                        .lineLimit(3)
                }
                if loggedTwice {
                    Label("Logged on both phones", systemImage: "arrow.triangle.merge")
                        .feedText(.small)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RowAvatars(main: loggedBy, second: second, tint: mark.tint)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mark.tint, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clock(at ?? snapshot.event.startedAt)): \(spoken). \(role) \(loggedBy.spoken)\(loggedBy.workedOut ? ", probably" : "")"
            + (second.map { ", \(secondRole) \($0.spoken)" } ?? "") + "."
            + (loggedTwice ? " Logged on both phones, shown once." : ""))
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
    /// With `answer`, the big picture is who did it (DD12) and a small one who logged it, when
    /// that was the other parent; without, who logged it.
    @MainActor
    init(_ snapshot: EventSnapshot, zone: TimeZone, now: Date = Date(), loggedTwice: Bool = false,
         answer: WhoDidIt.Answer? = nil) {
        let people = RowPeople(snapshot, answer: answer)
        self.init(snapshot: snapshot, zone: zone, loggedBy: people.main, now: now, role: people.role,
                  second: people.second, secondRole: people.secondRole, loggedTwice: loggedTwice)
    }
}
