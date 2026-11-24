import FeedingCore
import SwiftUI

// Home's care list: Sleep, Nappy, Medicine and Bath (`06-more-than-feeds.md`, the users' choices A, K and Q,
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
                          swap: UndoSwap(eventID: ended[0], gotUp: true, wakeID: store.data.events[ended[0]]?.event.wakeID)) {
            AppModel.shared.store.change { data in
                for sleep in before where ended.contains(sleep.id) {
                    data.edit(sleep.id, by: me, now: Date()) { $0.event.endedAt = nil }
                }
            }
        })
    }

    /// Logs a nappy and returns its ID. A wee shows its Undo card at once. Poo and Both ask the
    /// details first, and their card comes when that panel closes (`nappyFinished`), so its 10
    /// seconds start only once the nappy is fully logged (the user's ask, 24 Nov 2026).
    @discardableResult
    func nappy(wee: Bool, poo: Bool) -> String {
        let now = Date()
        let id = store.change { $0.addNappy(babyID: babyID, wee: wee, poo: poo, by: me, timeZoneID: zoneID, now: now) }
        if !poo { nappyFinished(id) }
        return id
    }

    /// The Undo card for a nappy just logged, with the poo's details once given ("Poo logged ·
    /// yellow, loose"). Nothing if it was undone in the details panel.
    func nappyFinished(_ id: String) {
        guard let snapshot = store.data.events[id]?.snapshot, snapshot.event.deletedAt == nil,
              let nappy = snapshot.payload?.nappy else { return }
        let title = CareText.nappyKind(wee: nappy.wee, poo: nappy.poo).capitalizedFirst
        let details = CareText.pooDetails(nappy).map { " · \($0)" } ?? ""
        onUndo(UndoAction(message: CareText.nappyLogged(wee: nappy.wee, poo: nappy.poo) + details,
                          changeTime: TimeChange(ids: [id], field: .start, title: title, at: snapshot.event.startedAt),
                          swap: UndoSwap(eventID: id)) {
            removeNew(id)
        })
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

// MARK: - The care list (`13-calm-home.md`, CH2)

/// Home's one plain box (the users' choice B, 24 Nov 2026): a row each for Sleep, Nappy, each
/// medicine on the list and Bath, with its buttons on the right. Colour only on the shapes. Each
/// tap logs at once, with the Undo card.
struct CareList: View {
    let facts: HomeFacts
    let log: CareLog
    let askDetails: (PooDetailsTarget) -> Void
    let editMedicines: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SleepRow(facts: facts, log: log)
            CareDivider()
            NappyRow(facts: facts, log: log, askDetails: askDetails)
            ForEach(facts.data.medicines, id: \.self) { name in
                CareDivider()
                MedicineRow(name: name, facts: facts, log: log, editList: editMedicines)
            }
            CareDivider()
            BathRow(facts: facts, log: log)
        }
        .padding(.horizontal, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile))
    }
}

/// The thin line between two rows: the page's own colour, so it reads as a gap.
struct CareDivider: View {
    var body: some View {
        Rectangle().fill(Theme.background).frame(height: 1.5).accessibilityHidden(true)
    }
}

/// A row's shape and words: bold, then muted.
private struct RowLead: View {
    let mark: FeedMark
    let title: String
    var detail: String?
    var spoken: String?

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            FeedMarkView(mark, size: 22, relativeTo: .body)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).feedText(.body).fontWeight(.semibold)
                if let detail {
                    Text(detail).feedText(.subheadline).foregroundStyle(Theme.textMuted)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken ?? [title, detail].compactMap { $0 }.joined(separator: ", "))
        }
    }
}

/// A row with one round button: beside the words, or under them when there isn't room.
private struct PillRow<Action: View>: View {
    let lead: RowLead
    @ViewBuilder let action: Action

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                lead
                Spacer(minLength: 8)
                action
            }
            VStack(alignment: .leading, spacing: 6) {
                lead
                action.padding(.leading, 39)
            }
        }
        .padding(.vertical, 9)
        .frame(minHeight: 64)
    }
}

/// Asleep or awake, for how long, and one button: Woke up or Fell asleep. Holding the button
/// offers "about 10 / 20 / 30 min ago", for a tap made late.
private struct SleepRow: View {
    let facts: HomeFacts
    let log: CareLog

    var body: some View {
        let state = sleepState(facts.visible, babyID: facts.babyID, now: facts.now)
        PillRow(lead: RowLead(mark: .sleep, title: CareFacts.sleepTitle(state, now: facts.now),
                              detail: CareFacts.sleepDetail(state, facts: facts))) {
            SleepButton(state: state, log: log)
        }
    }
}

/// Woke up or Fell asleep, with earlier times on a long press.
struct SleepButton: View {
    let state: SleepState
    let log: CareLog

    var body: some View {
        let asleep: Bool = { if case .asleep = state { return true } else { return false } }()
        let title = CareText.sleepButton(state)
        PillButton(title) {
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

/// The time since the last nappy and what it was, then Wee, Poo and Both under the words. A poo
/// with no details yet shows "Add details".
private struct NappyRow: View {
    let facts: HomeFacts
    let log: CareLog
    let askDetails: (PooDetailsTarget) -> Void

    var body: some View {
        let last = lastNappy(facts.visible, babyID: facts.babyID, now: facts.now)
        VStack(alignment: .leading, spacing: 8) {
            RowLead(mark: last.map { .nappy(wee: $0.wee, poo: $0.poo) } ?? .nappy(wee: true, poo: true),
                    title: CareFacts.nappyTitle(last, now: facts.now), detail: CareFacts.nappyDetail(last, facts: facts),
                    spoken: CareFacts.nappySpoken(last, facts: facts))
            if let last, CareFacts.needsDetails(last) {
                AddDetailsButton { askDetails(PooDetailsTarget(id: last.id, isNew: false)) }
                    .padding(.leading, 39)
                    .padding(.top, -6)
            }
            HStack(spacing: 6) {
                NappyButton(title: "Wee", mark: .wee) { logNappy(wee: true, poo: false) }
                    .accessibilityLabel("Log wee")
                NappyButton(title: "Poo", mark: .poo) { logNappy(wee: false, poo: true) }
                    .accessibilityLabel("Log poo")
                NappyButton(title: "Both", mark: .weeAndPoo) { logNappy(wee: true, poo: true) }
                    .accessibilityLabel("Log wee and poo")
            }
            .padding(.leading, 39)
        }
        .padding(.vertical, 11)
    }

    private func logNappy(wee: Bool, poo: Bool) {
        let id = log.nappy(wee: wee, poo: poo)
        // The users' choice Q: a poo asks its colour and consistency straight after.
        if poo { askDetails(PooDetailsTarget(id: id, isNew: true)) }
    }
}

/// "Add details" for a poo logged without them: underlined, 32 points tall.
struct AddDetailsButton: View {
    let action: () -> Void

    var body: some View {
        Button("Add details", action: action)
            .feedText(.smallButton)
            .underline()
            .foregroundStyle(Theme.text)
            .frame(minHeight: 32)
            .accessibilityHint("Adds the poo's colour and consistency")
    }
}

/// One medicine on the household's list: when it was last given, and Given. Never a "next dose"
/// time. Touch and hold changes the list.
private struct MedicineRow: View {
    let name: String
    let facts: HomeFacts
    let log: CareLog
    let editList: () -> Void

    var body: some View {
        PillRow(lead: RowLead(mark: .medicine, title: name, detail: CareFacts.medicineDetail(name, facts: facts))) {
            PillButton("Given") { log.medicine(name) }
                .accessibilityLabel("\(name) given")
                .accessibilityHint("Logs it now")
        }
        .contextMenu {
            Button("Change the medicine list", systemImage: "pencil", action: editList)
        }
    }
}

/// When the last bath was, and Bath, which logs it at once (X5). It never ends a running sleep.
private struct BathRow: View {
    let facts: HomeFacts
    let log: CareLog

    var body: some View {
        PillRow(lead: RowLead(mark: .bath, title: "Bath", detail: CareFacts.bathDetail(facts))) {
            PillButton("Bath") { log.bath() }
                .accessibilityLabel("Bath given")
                .accessibilityHint("Logs it now")
        }
    }
}

/// Wee, Poo or Both: the shape above the word, in the background colour.
struct NappyButton: View {
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

// MARK: - The open Duo's facts (`13-calm-home.md`, CH7)

/// The Book's left page: sleep, nappy, each medicine and bath as plain facts, two to a row, with
/// no buttons (they are along the bottom of the right page). One to a row at the largest sizes.
struct CareFacts: View {
    let facts: HomeFacts
    let askDetails: (PooDetailsTarget) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let state = sleepState(facts.visible, babyID: facts.babyID, now: facts.now)
        let last = lastNappy(facts.visible, babyID: facts.babyID, now: facts.now)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
                            count: typeSize.isAccessibilitySize ? 1 : 2)
        LazyVGrid(columns: columns, spacing: 8) {
            fact(.sleep, Self.sleepTitle(state, now: facts.now), Self.sleepDetail(state, facts: facts))
            fact(last.map { .nappy(wee: $0.wee, poo: $0.poo) } ?? .nappy(wee: true, poo: true),
                 Self.nappyTitle(last, now: facts.now), Self.nappyDetail(last, facts: facts),
                 spoken: Self.nappySpoken(last, facts: facts)) {
                if let last, Self.needsDetails(last) {
                    AddDetailsButton { askDetails(PooDetailsTarget(id: last.id, isNew: false)) }
                }
            }
            ForEach(facts.data.medicines, id: \.self) { name in
                fact(.medicine, name, Self.medicineDetail(name, facts: facts))
            }
            fact(.bath, "Bath", Self.bathDetail(facts))
        }
    }

    private func fact(_ mark: FeedMark, _ title: String, _ detail: String?, spoken: String? = nil) -> some View {
        fact(mark, title, detail, spoken: spoken) { EmptyView() }
    }

    private func fact<Extra: View>(_ mark: FeedMark, _ title: String, _ detail: String?, spoken: String? = nil,
                                   @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            RowLead(mark: mark, title: title, detail: detail, spoken: spoken)
            extra().padding(.leading, 39)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // The words, shared by the phone's rows and these facts.

    /// "Asleep 1h 20m", "Awake 40m", or "No sleep logged yet".
    static func sleepTitle(_ state: SleepState, now: Date) -> String {
        [CareText.sleepWord(state), CareText.sleepElapsed(state, now: now)].compactMap { $0 }.joined(separator: " ")
    }

    /// "since 12:03", or nothing before the first sleep.
    static func sleepDetail(_ state: SleepState, facts: HomeFacts) -> String? {
        switch state {
        case .asleep(_, let since), .awake(let since): "since \(facts.clock(since))"
        case .notLogged: nil
        }
    }

    /// "Nappy 40m ago", or "No nappy logged yet".
    static func nappyTitle(_ last: NappyChange?, now: Date) -> String {
        guard let last else { return "No nappy logged yet" }
        return "Nappy \(HomeText.elapsed(max(0, now.timeIntervalSince(last.at)))) ago"
    }

    /// "Wee and poo, 12:43 · yellow, loose".
    static func nappyDetail(_ last: NappyChange?, facts: HomeFacts) -> String? {
        guard let last else { return nil }
        let kind = last.details.map { CareText.nappyKind(wee: $0.wee, poo: $0.poo) } ?? "nappy"
        let details = last.details.flatMap(CareText.pooDetails).map { " · \($0)" } ?? ""
        return "\(kind.capitalizedFirst), \(facts.clock(last.at))\(details)"
    }

    static func nappySpoken(_ last: NappyChange?, facts: HomeFacts) -> String {
        guard let last else { return "No nappy logged yet" }
        let kind = last.details.map { CareText.nappyKind(wee: $0.wee, poo: $0.poo) } ?? "nappy"
        let details = last.details.flatMap(CareText.pooDetails).map { ", \($0)" } ?? ""
        return "Last nappy \(HomeText.spokenElapsed(facts.now.timeIntervalSince(last.at))) ago: \(kind)\(details), at \(facts.clock(last.at))"
    }

    /// A poo logged with no colour and no consistency.
    static func needsDetails(_ last: NappyChange) -> Bool {
        guard let details = last.details else { return false }
        return details.poo && details.colour == nil && details.consistency == nil
    }

    /// "last 10:04", "last Yesterday 20:00", or "Not logged yet".
    static func medicineDetail(_ name: String, facts: HomeFacts) -> String {
        guard let last = facts.data.lastGiven(name, babyID: facts.babyID, now: facts.now) else { return "Not logged yet" }
        return "last \(CareText.lastGiven(last, now: facts.now, in: facts.settings.timeZone))"
    }

    /// When the last bath was, or "Not logged yet".
    static func bathDetail(_ facts: HomeFacts) -> String {
        let last = facts.data.allEvents
            .filter { $0.kind == .bath && $0.deletedAt == nil && $0.babyID == facts.babyID && $0.startedAt <= facts.now }
            .map(\.startedAt).max()
        return last.map { "last \(CareText.lastGiven($0, now: facts.now, in: facts.settings.timeZone))" } ?? "Not logged yet"
    }
}

// MARK: - The open Duo's log buttons (`13-calm-home.md`, CH7)

/// Along the bottom of the Book's right page, under the right thumb: Woke up (or Fell asleep),
/// Wee, Poo, Both, the medicine (a menu when there are several) and Bath. Each logs at once, as
/// the phone's rows do.
struct LogDock: View {
    let facts: HomeFacts
    let log: CareLog
    let askDetails: (PooDetailsTarget) -> Void

    var body: some View {
        let state = sleepState(facts.visible, babyID: facts.babyID, now: facts.now)
        let asleep: Bool = { if case .asleep = state { return true } else { return false } }()
        let medicines = facts.data.medicines
        HStack(spacing: 6) {
            DockButton(title: CareText.sleepButton(state), mark: .sleep, wide: true) {
                asleep ? log.wokeUp() : log.fellAsleep()
            }
            .contextMenu {
                ForEach([10, 20, 30], id: \.self) { minutes in
                    Button("\(CareText.sleepButton(state)) about \(minutes) min ago") {
                        let at = Date().addingTimeInterval(-Double(minutes) * 60)
                        asleep ? log.wokeUp(at: at) : log.fellAsleep(at: at)
                    }
                }
            }
            DockButton(title: "Wee", mark: .wee) { _ = log.nappy(wee: true, poo: false) }
                .accessibilityLabel("Log wee")
            DockButton(title: "Poo", mark: .poo) { pooLogged(log.nappy(wee: false, poo: true)) }
                .accessibilityLabel("Log poo")
            DockButton(title: "Both", mark: .weeAndPoo) { pooLogged(log.nappy(wee: true, poo: true)) }
                .accessibilityLabel("Log wee and poo")
            if medicines.count == 1, let name = medicines.first {
                DockButton(title: name, mark: .medicine, wide: true) { log.medicine(name) }
                    .accessibilityLabel("\(name) given")
            } else if medicines.count > 1 {
                Menu {
                    ForEach(medicines, id: \.self) { name in
                        Button("\(name) · \(CareFacts.medicineDetail(name, facts: facts))") { log.medicine(name) }
                    }
                } label: {
                    DockLabel(title: "Medicine", mark: .medicine)
                }
                .buttonStyle(PressStyle())
                .frame(maxWidth: .infinity)
                .layoutPriority(1.25)
                .accessibilityLabel("Medicine given")
            }
            DockButton(title: "Bath", mark: .bath, wide: true) { log.bath() }
                .accessibilityLabel("Bath given")
        }
    }

    private func pooLogged(_ id: String) {
        askDetails(PooDetailsTarget(id: id, isNew: true))
    }
}

/// One of the dock's buttons: the shape above the word, on `surface`.
private struct DockButton: View {
    let title: String
    let mark: FeedMark
    var wide = false
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            DockLabel(title: title, mark: mark)
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .frame(maxWidth: wide ? .infinity : 50)
    }
}

private struct DockLabel: View {
    let title: String
    let mark: FeedMark

    var body: some View {
        VStack(spacing: 3) {
            FeedMarkView(mark, size: 18, relativeTo: .subheadline)
                .accessibilityHidden(true)
            Text(title)
                .feedText(.chip)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, minHeight: 62)
        .foregroundStyle(Theme.text)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
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
                // While the nappy is new, the panel carries the "done by" swap too (X1; outside
                // review, Codex 8). The Undo card comes once the panel closes.
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
        // However it closes (Done, a swipe, or by itself), a new nappy's Undo card starts now,
        // with its full 10 seconds. Undo in the panel removed it, so then nothing shows.
        .onDisappear {
            if target.isNew { log.nappyFinished(target.id) }
        }
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
        case .pale: .edged(Theme.pooPale)
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
    /// A light colour, with a thin edge so it shows on a light chip.
    case edged(Color)
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
                case .edged(let colour):
                    Circle().fill(colour)
                        .overlay(Circle().strokeBorder(Theme.textMuted, lineWidth: 1))
                        .frame(width: 16, height: 16).accessibilityHidden(true)
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
