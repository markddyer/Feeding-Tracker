import FeedingCore
import SwiftUI

// Home's Sleep, Nappy and Medicine tiles (`06-more-than-feeds.md`, the users' choices A, K and Q,
// 17 Nov 2026). Each tap logs at once, with the 10-second bar: Undo, and Change time for a tap
// made late. None of it touches the feed alarms: `reconcile` counts feeds only.

/// "Change time" on the Undo bar: which entries, and which of their times.
struct TimeChange: Identifiable, Hashable {
    enum Field: Hashable { case start, end }

    /// One entry, or every sleep one "Woke up" ended.
    let ids: [String]
    let field: Field
    /// What was logged: "Woke up", "Wee".
    let title: String
    /// The time logged.
    let at: Date

    var id: String { ids.joined(separator: ",") + (field == .start ? "-start" : "-end") }
}

/// The poo whose colour and consistency are being asked.
struct PooDetailsTarget: Identifiable, Hashable {
    let id: String
    /// Logged a moment ago: the panel's Undo removes it.
    let isNew: Bool
}

/// The quick logs, each with its Undo.
@MainActor
struct CareLog {
    let me: MemberID
    let babyID: String
    let onUndo: (UndoAction) -> Void

    private var store: HouseholdStore { AppModel.shared.store }
    private var zoneID: String { TimeZone.current.identifier }

    func fellAsleep(at time: Date? = nil) {
        let now = Date()
        let at = time ?? now
        // A sleep already runs (logged on the other phone a moment ago): nothing to log or undo.
        guard store.data.sleepInProgress(babyID: babyID, now: now) == nil else { return }
        let id = store.change { $0.startSleep(babyID: babyID, startedAt: at, by: me, timeZoneID: zoneID, now: now) }
        onUndo(UndoAction(message: "Fell asleep logged", changeTime: TimeChange(ids: [id], field: .start, title: "Fell asleep", at: at),
                          swap: UndoSwap(eventID: id)) {
            removeNew(id)
        })
    }

    func wokeUp(at time: Date? = nil) {
        let now = Date()
        let at = time ?? now
        let before = store.data.snapshots.filter { $0.event.kind == .sleep && $0.event.endedAt == nil }
        let ended = store.change { $0.endSleep(babyID: babyID, at: at, by: me, now: now) }
        guard !ended.isEmpty else { return }
        let me = me
        // The swap changes who got up for this wake-up, every sleep it ended (R3).
        onUndo(UndoAction(message: "Woke up logged", changeTime: TimeChange(ids: ended, field: .end, title: "Woke up", at: at),
                          swap: UndoSwap(eventID: ended[0], gotUp: true)) {
            AppModel.shared.store.change { data in
                for sleep in before where ended.contains(sleep.id) {
                    data.edit(sleep.id, by: me, now: Date()) { $0.event.endedAt = nil }
                }
            }
        })
    }

    /// Logs a nappy and returns its ID (Poo and Both then ask for the details).
    @discardableResult
    func nappy(wee: Bool, poo: Bool) -> String {
        let now = Date()
        let id = store.change { $0.addNappy(babyID: babyID, wee: wee, poo: poo, by: me, timeZoneID: zoneID, now: now) }
        let title = CareText.nappyKind(wee: wee, poo: poo).capitalizedFirst
        onUndo(UndoAction(message: CareText.nappyLogged(wee: wee, poo: poo),
                          changeTime: TimeChange(ids: [id], field: .start, title: title, at: now), swap: UndoSwap(eventID: id)) {
            removeNew(id)
        })
        return id
    }

    func medicine(_ name: String) {
        let now = Date()
        let id = store.change { $0.addMedicine(babyID: babyID, MedicineDetails(name: name), by: me, timeZoneID: zoneID, now: now) }
        onUndo(UndoAction(message: "\(name) logged", changeTime: TimeChange(ids: [id], field: .start, title: name, at: now),
                          swap: UndoSwap(eventID: id)) {
            removeNew(id)
        })
    }

    /// A bath, logged at once (X5): it never ends a running sleep.
    func bath() {
        let now = Date()
        let id = store.change {
            $0.add(kind: .bath, babyID: babyID, startedAt: now, payload: EventPayload(), by: me, timeZoneID: zoneID, now: now)
        }
        onUndo(UndoAction(message: CareText.bathLogged, changeTime: TimeChange(ids: [id], field: .start, title: "Bath", at: now),
                          swap: UndoSwap(eventID: id)) {
            removeNew(id)
        })
    }

    /// Undo for a new entry: gone completely if it hasn't been sent yet, otherwise hidden.
    func removeNew(_ id: String) {
        let me = me
        AppModel.shared.store.change { data in
            if !data.undoAdd(id, now: Date()) { data.delete(id, by: me, now: Date()) }
        }
    }

    /// Moves the logged time. An end never goes before its start, and a start never after its end.
    static func apply(_ change: TimeChange, to time: Date, by me: MemberID) {
        let now = Date()
        let time = min(time, now)
        AppModel.shared.store.change { data in
            for id in change.ids {
                data.edit(id, by: me, now: now) { snapshot in
                    switch change.field {
                    case .start:
                        snapshot.event.startedAt = snapshot.event.endedAt.map { min(time, $0) } ?? time
                    case .end:
                        snapshot.event.endedAt = max(time, snapshot.event.startedAt)
                    }
                }
            }
        }
    }
}

// MARK: - The tiles

/// Asleep or awake, for how long, and one button: Woke up or Fell asleep. Holding the button
/// offers "about 10 / 20 / 30 min ago", for a tap made late.
struct SleepTile: View {
    let facts: HomeFacts
    let log: CareLog

    var body: some View {
        let state = sleepState(facts.visible, babyID: facts.babyID, now: facts.now)
        let elapsed = CareText.sleepElapsed(state, now: facts.now)
        Tile(label: "Sleep", tint: Theme.sleepTint) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    FeedMarkView(.sleep, size: 22, relativeTo: .title2)
                    if let elapsed {
                        Text(elapsed).feedText(.total).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                sinceLine(state)
                Spacer(minLength: 0)
                button(state)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func sinceLine(_ state: SleepState) -> some View {
        switch state {
        case .asleep(_, let since), .awake(let since):
            Text("\(CareText.sleepWord(state)) since \(Text(facts.clock(since)).foregroundStyle(Theme.text))")
                .feedText(.subheadline)
                .foregroundStyle(Theme.textMuted)
                .accessibilityLabel("\(CareText.sleepWord(state)) for \(HomeText.spokenElapsed(facts.now.timeIntervalSince(since))), since \(facts.clock(since))")
        case .notLogged:
            Text("No sleep logged yet")
                .feedText(.subheadline)
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func button(_ state: SleepState) -> some View {
        let asleep: Bool = { if case .asleep = state { return true } else { return false } }()
        let title = CareText.sleepButton(state)
        return PillButton(title) {
            asleep ? log.wokeUp() : log.fellAsleep()
        }
        .contextMenu {
            ForEach([10, 20, 30], id: \.self) { minutes in
                Button("\(title) about \(minutes) min ago") {
                    let at = Date().addingTimeInterval(-Double(minutes) * 60)
                    asleep ? log.wokeUp(at: at) : log.fellAsleep(at: at)
                }
            }
        }
        .accessibilityHint("Logs it now. Touch and hold for an earlier time.")
    }
}

/// The time since the last nappy and what it was, then Wee, Poo and Both. A poo with no
/// details yet shows "Add details".
struct NappyTile: View {
    let facts: HomeFacts
    let log: CareLog
    let askDetails: (PooDetailsTarget) -> Void

    var body: some View {
        let last = lastNappy(facts.visible, babyID: facts.babyID, now: facts.now)
        Tile(label: "Nappy", tint: Theme.nappyTint) {
            VStack(alignment: .leading, spacing: 6) {
                if let last {
                    HStack(spacing: 7) {
                        FeedMarkView(.nappy(wee: last.wee, poo: last.poo), size: 20, relativeTo: .title2)
                        Text(HomeText.elapsed(max(0, facts.now.timeIntervalSince(last.at))))
                            .feedText(.total).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    line(last)
                    if let details = last.details, details.poo, details.colour == nil, details.consistency == nil {
                        Button("Add details") { askDetails(PooDetailsTarget(id: last.id, isNew: false)) }
                            .feedText(.smallButton)
                            .underline()
                            .foregroundStyle(Theme.text)
                            .frame(minHeight: 32)
                            .accessibilityHint("Adds the poo's colour and consistency")
                    }
                } else {
                    Text("No nappy logged yet")
                        .feedText(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    nappyButton("Wee", .wee, wee: true, poo: false)
                    nappyButton("Poo", .poo, wee: false, poo: true)
                    nappyButton("Both", .weeAndPoo, wee: true, poo: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func line(_ last: NappyChange) -> some View {
        let kind = last.details.map { CareText.nappyKind(wee: $0.wee, poo: $0.poo) } ?? "nappy"
        let details = last.details.flatMap(CareText.pooDetails).map { " · \($0)" } ?? ""
        return Text("\(kind.capitalizedFirst), \(Text(facts.clock(last.at)).foregroundStyle(Theme.text))\(details)")
            .feedText(.subheadline)
            .foregroundStyle(Theme.textMuted)
            .lineLimit(2)
            .accessibilityLabel("Last nappy \(HomeText.spokenElapsed(facts.now.timeIntervalSince(last.at))) ago: \(kind)\(details), at \(facts.clock(last.at))")
    }

    private func nappyButton(_ title: String, _ mark: FeedMark, wee: Bool, poo: Bool) -> some View {
        NappyButton(title: title, mark: mark) {
            let id = log.nappy(wee: wee, poo: poo)
            // The users' choice Q: a poo asks its colour and consistency straight after.
            if poo { askDetails(PooDetailsTarget(id: id, isNew: true)) }
        }
        .accessibilityLabel("Log \(CareText.nappyKind(wee: wee, poo: poo))")
    }
}

/// Wee, Poo or Both on the Nappy tile: the shape above the word, in the background colour.
private struct NappyButton: View {
    let title: String
    let mark: FeedMark
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 2) {
                FeedMarkView(mark, size: 16, relativeTo: .subheadline)
                    .accessibilityHidden(true)
                Text(title)
                    .feedText(.smallButton)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.smallButton))
            .contentShape(RoundedRectangle(cornerRadius: Radius.smallButton))
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(Theme.text)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }
}

/// One row per medicine on the household's list: when it was last given, and Given. Never a
/// "next dose" time. Left out when the list is empty.
struct MedicineTile: View {
    let facts: HomeFacts
    let log: CareLog
    let editList: () -> Void

    var body: some View {
        let medicines = facts.data.medicines
        if !medicines.isEmpty {
            Tile(label: "Medicine", accessory: AnyView(editButton)) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(medicines, id: \.self) { name in
                        row(name)
                    }
                }
            }
        }
    }

    private var editButton: some View {
        Button(action: editList) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 44, height: 28)
                .contentShape(Rectangle())
        }
        .foregroundStyle(Theme.textMuted)
        .accessibilityLabel("Change the medicine list")
    }

    /// One medicine: its name, when it was last given, and Given. Side by side when they fit on
    /// one line; otherwise (half width beside Bath, design D6, or large text) Given goes under.
    private func row(_ name: String) -> some View {
        let last = facts.data.lastGiven(name, babyID: facts.babyID, now: facts.now)
        let zone = facts.settings.timeZone
        let when = last.map { "Last \(CareText.lastGiven($0, now: facts.now, in: zone))" } ?? "Not logged yet"
        let given = PillButton("Given") { log.medicine(name) }
            .accessibilityLabel("\(name) given")
            .accessibilityHint("Logs it now")
        func words(oneLine: Bool) -> some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).feedText(.body).fontWeight(.semibold).lineLimit(oneLine ? 1 : 3)
                Text(when).feedText(.small).foregroundStyle(Theme.textMuted).lineLimit(oneLine ? 1 : 3)
            }
            .fixedSize(horizontal: oneLine, vertical: false)
            .accessibilityElement(children: .combine)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                FeedMarkView(.medicine, size: 18, relativeTo: .body)
                words(oneLine: true)
                Spacer(minLength: 6)
                given
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    FeedMarkView(.medicine, size: 18, relativeTo: .body)
                    words(oneLine: false)
                }
                given
            }
        }
    }
}

/// Baths (X5, design D6): the tub in its own water-blue on its own tile, when the last bath was,
/// and one Bath button that logs it at once with the Undo card. Beside Medicine on Home.
struct BathTile: View {
    let facts: HomeFacts
    let log: CareLog

    var body: some View {
        let last = facts.data.allEvents
            .filter { $0.kind == .bath && $0.deletedAt == nil && $0.babyID == facts.babyID && $0.startedAt <= facts.now }
            .map(\.startedAt).max()
        let zone = facts.settings.timeZone
        Tile(label: "Bath", tint: Theme.bathTint) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    FeedMarkView(.bath, size: 22, relativeTo: .body)
                    Text(last.map { "Last \(CareText.lastGiven($0, now: facts.now, in: zone))" } ?? "Not logged yet")
                        .feedText(.small)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                PillButton("Bath") { log.bath() }
                    .accessibilityLabel("Bath given")
                    .accessibilityHint("Logs it now")
            }
        }
    }
}

// MARK: - Panels

/// "Change time": quick choices before the time logged, or any time on the wheel.
struct ChangeTimeSheet: View {
    let change: TimeChange
    let me: MemberID
    let zone: TimeZone
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(change: TimeChange, me: MemberID, zone: TimeZone) {
        self.change = change
        self.me = me
        self.zone = zone
        _time = State(initialValue: change.at)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(change.title).feedText(.dayHeading)
                Spacer()
                Text("Logged at \(clock(change.at))").feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
            Text("When was it?").feedText(.label).foregroundStyle(Theme.textMuted)
            HStack(spacing: 8) {
                ForEach([5, 10, 20, 30], id: \.self) { minutes in
                    DetailChoice(title: CareText.minutesEarlier(minutes), swatch: nil, chosen: false) {
                        save(change.at.addingTimeInterval(-Double(minutes) * 60))
                    }
                    .accessibilityLabel("\(minutes) minutes earlier")
                }
            }
            DatePicker("Time", selection: $time, in: change.at.addingTimeInterval(-24 * 3600)...max(Date(), change.at),
                       displayedComponents: [.hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.timeZone, zone)
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipped()
            HStack(spacing: 8) {
                BigButton(title: "Cancel", prominent: false) { dismiss() }
                    .frame(maxWidth: 130)
                BigButton(title: "Save", prominent: true) { save(time) }
            }
        }
        .padding(18)
        .foregroundStyle(Theme.text)
        .presentationDetents([.height(430)])
        .presentationBackground(Theme.background)
    }

    private func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }

    private func save(_ new: Date) {
        CareLog.apply(change, to: new, by: me)
        dismiss()
    }
}

/// The users' choice Q: straight after Poo or Both, the colour and the consistency. The nappy is
/// already saved; each tap saves at once, and swiping the panel away skips the rest.
struct PooDetailsSheet: View {
    let target: PooDetailsTarget
    let me: MemberID
    let zone: TimeZone
    let log: CareLog
    @Environment(\.dismiss) private var dismiss

    private var store: HouseholdStore { AppModel.shared.store }

    var body: some View {
        let snapshot = store.data.events[target.id]?.snapshot
        let nappy = snapshot?.payload?.nappy ?? NappyDetails(wee: false, poo: true)
        let at = snapshot?.event.startedAt ?? Date()
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                // The panel covers the Undo card, so it carries the same "done by" swap while the
                // nappy is new (X1; outside review, Codex 8).
                if target.isNew {
                    UndoSwapButton(swap: UndoSwap(eventID: target.id))
                }
                Text("\(CareText.nappyKind(wee: nappy.wee, poo: nappy.poo).capitalizedFirst), \(clock(at))")
                    .feedText(.dayHeading)
                Spacer()
                Text("Saved").feedText(.subheadline).foregroundStyle(Theme.textMuted)
            }
            Text("Colour").feedText(.label).foregroundStyle(Theme.textMuted)
            HStack(spacing: 8) {
                ForEach(PooColour.known, id: \.self) { colour in
                    DetailChoice(title: CareText.colourName(colour), swatch: swatch(colour), chosen: nappy.colour == colour) {
                        set { $0.colour = $0.colour == colour ? nil : colour }
                    }
                }
            }
            Text("Consistency").feedText(.label).foregroundStyle(Theme.textMuted)
            HStack(spacing: 8) {
                ForEach(PooConsistency.known, id: \.self) { consistency in
                    DetailChoice(title: CareText.consistencyName(consistency), swatch: nil, chosen: nappy.consistency == consistency) {
                        set { $0.consistency = $0.consistency == consistency ? nil : consistency }
                    }
                }
            }
            HStack(spacing: 8) {
                if target.isNew {
                    BigButton(title: "Undo", prominent: false) {
                        log.removeNew(target.id)
                        dismiss()
                    }
                    .frame(maxWidth: 130)
                    .accessibilityLabel("Undo: remove this nappy")
                }
                BigButton(title: "Done", prominent: true) { dismiss() }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .foregroundStyle(Theme.text)
        .presentationDetents([.height(390)])
        .presentationBackground(Theme.background)
        // Once both are chosen, the panel closes by itself.
        .onChange(of: nappy.colour != nil && nappy.consistency != nil) { _, both in
            guard both else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                dismiss()
            }
        }
    }

    private func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }

    private func swatch(_ colour: PooColour) -> Swatch {
        switch colour {
        case .brown: .colour(Theme.pooBrown)
        case .yellow: .colour(Theme.pooYellow)
        case .green: .colour(Theme.pooGreen)
        default: .ring
        }
    }

    private func set(_ change: @escaping (inout NappyDetails) -> Void) {
        let me = me
        store.change { data in
            data.edit(target.id, by: me, now: Date()) { snapshot in
                var nappy = snapshot.payload?.nappy ?? NappyDetails(wee: false, poo: true)
                change(&nappy)
                snapshot.payload?.nappy = nappy
            }
        }
    }
}

/// A colour's little circle beside its word: filled with the colour, or an empty ring for Other.
enum Swatch {
    case colour(Color)
    case ring
}

/// A colour or a consistency: a big chip, filled with the text colour once chosen. A colour has
/// its swatch, always beside its word, so it never relies on colour alone.
private struct DetailChoice: View {
    let title: String
    let swatch: Swatch?
    let chosen: Bool
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 4) {
                switch swatch {
                case .colour(let colour):
                    Circle().fill(colour).frame(width: 16, height: 16).accessibilityHidden(true)
                case .ring:
                    Circle().strokeBorder(Theme.textMuted, lineWidth: 2).frame(width: 16, height: 16).accessibilityHidden(true)
                case nil:
                    EmptyView()
                }
                Text(title)
                    .feedText(.smallButton)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(chosen ? Theme.background : Theme.text)
            .background(chosen ? Theme.text : Theme.surface, in: RoundedRectangle(cornerRadius: Radius.smallButton))
            .contentShape(RoundedRectangle(cornerRadius: Radius.smallButton))
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
