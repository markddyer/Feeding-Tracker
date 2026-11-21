import FeedingCore
import SwiftUI

/// Changes a sleep, nappy, medicine or growth entry from History, or adds a growth entry (the
/// weight graph's Add, the users' choice K). Like `EventEditor`, it saves only the parts changed
/// here, put onto the newest copy, so the other phone's changes stay.
struct CareEditor: View {
    enum Mode: Hashable, Identifiable {
        case edit(id: String)
        case newGrowth

        var id: Self { self }
    }

    let mode: Mode
    let me: MemberID
    let babyID: String

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EventSnapshot
    @State private var running: Bool
    /// A parent tapped in "Settled by" / "Who did it", or "Got up" (DD8); nil until then.
    @State private var pickedDoneBy: MemberID?
    @State private var pickedGotUp: MemberID?
    /// Who the entry counted for, and who got up, when the editor opened.
    private let storedDoneBy: WhoDidIt.Answer?
    private let storedGotUp: WhoDidIt.Answer?
    /// The growth fields as typed: kilograms and centimetres.
    @State private var weightText: String
    @State private var lengthText: String
    @State private var headText: String
    private let original: EventSnapshot
    /// The growth fields as first shown, so a measurement nobody changed keeps its exact value.
    private let shownWeight: String
    private let shownLength: String
    private let shownHead: String

    init(mode: Mode, me: MemberID, babyID: String) {
        self.mode = mode
        self.me = me
        self.babyID = babyID
        let now = Date()
        let snapshot: EventSnapshot
        switch mode {
        case .edit(let id):
            snapshot = AppModel.shared.store.data.events[id]?.snapshot ?? Self.blankGrowth(babyID: babyID, me: me, now: now)
        case .newGrowth:
            snapshot = Self.blankGrowth(babyID: babyID, me: me, now: now)
        }
        original = snapshot
        _draft = State(initialValue: snapshot)
        _running = State(initialValue: snapshot.event.kind == .sleep && snapshot.event.endedAt == nil)
        if case .edit(let id) = mode, snapshot.event.kind.countsAsWork {
            let who = AppModel.shared.store.data.whoDidIt(babyID: babyID, now: now)
            storedDoneBy = who.doneBy(id)
            storedGotUp = who.gotUp(sleep: id)
        } else {
            storedDoneBy = nil
            storedGotUp = nil
        }
        let growth = snapshot.payload?.growth
        // Three decimals only when the weight needs them ("3.853"), so nothing is rounded away.
        shownWeight = growth?.weightGrams.map { $0 % 10 == 0 ? String(format: "%.2f", Double($0) / 1000)
                                                              : String(format: "%.3f", Double($0) / 1000) } ?? ""
        shownLength = growth?.lengthMM.map { String(format: "%.1f", Double($0) / 10) } ?? ""
        shownHead = growth?.headMM.map { String(format: "%.1f", Double($0) / 10) } ?? ""
        _weightText = State(initialValue: shownWeight)
        _lengthText = State(initialValue: shownLength)
        _headText = State(initialValue: shownHead)
    }

    private static func blankGrowth(babyID: String, me: MemberID, now: Date) -> EventSnapshot {
        EventSnapshot(
            event: Event(id: "draft", babyID: babyID, kind: .growth, startedAt: now, timeZoneID: TimeZone.current.identifier,
                         loggedBy: me, createdAt: now, modifiedAt: now),
            payload: EventPayload(growth: GrowthDetails()))
    }

    private var kind: EventKind { draft.event.kind }

    var body: some View {
        NavigationStack {
            Form {
                timeSection
                switch kind {
                case .nappy: nappySection
                case .medicine: medicineSection
                case .growth: growthSection
                default: EmptyView()
                }
                whoSection
                Section {
                    TextField("Optional", text: Binding {
                        draft.payload?.note ?? ""
                    } set: {
                        draft.payload?.note = $0.isEmpty ? nil : $0
                    }, axis: .vertical)
                } header: {
                    header("Note")
                }
                .listRowBackground(Theme.surface)
                if case .edit = mode {
                    Section {
                        Button("Delete", role: .destructive) { save { $0.event.deletedAt = Date() } }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .foregroundStyle(Theme.text)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).feedText(.dayHeading).accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.text) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(problem != nil).tint(Theme.text)
                }
            }
        }
    }

    private var title: String {
        switch kind {
        case .sleep: "Sleep"
        case .bath: "Bath"
        case .nappy: "Nappy"
        case .medicine: "Medicine"
        case .growth: mode == .newGrowth ? "Add a measurement" : "Growth"
        default: "Entry"
        }
    }

    /// Why Save is off, if it is.
    private var problem: String? {
        if draft.event.startedAt > Date().addingTimeInterval(60) { return "The time is in the future." }
        if kind == .sleep, !running, let end = draft.event.endedAt, end < draft.event.startedAt {
            return "Woke up is before fell asleep."
        }
        if kind == .growth {
            if !weightText.isEmpty && CareText.grams(fromKilograms: weightText) == nil { return "Type the weight in kilograms, like 3.85." }
            if !lengthText.isEmpty && CareText.millimetres(fromCentimetres: lengthText) == nil { return "Type the length in centimetres, like 52.5." }
            if !headText.isEmpty && CareText.millimetres(fromCentimetres: headText) == nil { return "Type the head in centimetres, like 36.0." }
            if growth.isEmpty { return "Add a weight, a length or a head measurement." }
        }
        if kind == .medicine, (draft.payload?.medicine?.name ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            return "Add the medicine's name."
        }
        return nil
    }

    // MARK: Sections

    private var timeSection: some View {
        Section {
            if kind == .sleep {
                DatePicker("Fell asleep", selection: $draft.event.startedAt, in: ...latest)
                Toggle("Still asleep", isOn: $running)
                if !running {
                    DatePicker("Woke up", selection: Binding {
                        draft.event.endedAt ?? Date()
                    } set: {
                        draft.event.endedAt = $0
                    }, in: draft.event.startedAt...max(latest, draft.event.startedAt))
                }
            } else {
                DatePicker(kind == .growth ? "Measured" : "Time", selection: $draft.event.startedAt, in: ...latest)
            }
        } header: {
            header("Time")
        } footer: {
            if let problem { Text(problem).feedText(.subheadline).foregroundStyle(Theme.notice) }
        }
        .listRowBackground(Theme.surface)
    }

    /// The latest time a picker offers: a minute from now, or the time already saved if the
    /// clock has been set back since, so a picker's range is never upside down.
    private var latest: Date {
        max(Date().addingTimeInterval(60), original.event.startedAt, original.event.endedAt ?? .distantPast)
    }

    private var nappyBinding: Binding<NappyDetails> {
        Binding {
            draft.payload?.nappy ?? NappyDetails(wee: true, poo: false)
        } set: { nappy in
            var nappy = nappy
            // A wee-only nappy has no poo details.
            if !nappy.poo { nappy.colour = nil; nappy.consistency = nil }
            draft.payload?.nappy = nappy
        }
    }

    private var nappySection: some View {
        let nappy = nappyBinding
        return Section {
            Toggle(isOn: nappy.wee) { Label { Text("Wee") } icon: { FeedMarkView(.wee, size: 18, relativeTo: .body) } }
            Toggle(isOn: nappy.poo) { Label { Text("Poo") } icon: { FeedMarkView(.poo, size: 18, relativeTo: .body) } }
            if nappy.wrappedValue.poo {
                Picker("Colour", selection: Binding { nappy.wrappedValue.colour } set: { nappy.wrappedValue.colour = $0 }) {
                    Text("Not set").tag(PooColour?.none)
                    ForEach(PooColour.known, id: \.self) { Text(CareText.colourName($0)).tag(PooColour?.some($0)) }
                }
                Picker("Consistency", selection: Binding { nappy.wrappedValue.consistency } set: { nappy.wrappedValue.consistency = $0 }) {
                    Text("Not set").tag(PooConsistency?.none)
                    ForEach(PooConsistency.known, id: \.self) { Text(CareText.consistencyName($0)).tag(PooConsistency?.some($0)) }
                }
            }
        } header: {
            header("Nappy")
        }
        .tint(Theme.primary)
        .listRowBackground(Theme.surface)
    }

    private var medicineSection: some View {
        Section {
            TextField("Name", text: Binding {
                draft.payload?.medicine?.name ?? ""
            } set: {
                draft.payload?.medicine = MedicineDetails(name: $0, amount: draft.payload?.medicine?.amount)
            })
            TextField("Amount (optional)", text: Binding {
                draft.payload?.medicine?.amount ?? ""
            } set: {
                draft.payload?.medicine?.amount = $0.isEmpty ? nil : $0
            })
        } header: {
            header("Medicine")
        }
        .listRowBackground(Theme.surface)
    }

    /// What was typed, with each measurement nobody changed kept exactly as it was, so another
    /// parent's correction of it isn't overwritten either.
    private var growth: GrowthDetails {
        let before = original.payload?.growth
        return GrowthDetails(
            weightGrams: weightText == shownWeight ? before?.weightGrams : CareText.grams(fromKilograms: weightText),
            lengthMM: lengthText == shownLength ? before?.lengthMM : CareText.millimetres(fromCentimetres: lengthText),
            headMM: headText == shownHead ? before?.headMM : CareText.millimetres(fromCentimetres: headText))
    }

    private var growthSection: some View {
        Section {
            measureRow("Weight", "kg", $weightText, extra: growth.weightGrams.map(CareText.poundsAndOunces))
            measureRow("Length", "cm", $lengthText, extra: nil)
            measureRow("Head", "cm", $headText, extra: nil)
        } header: {
            header("Growth")
        } footer: {
            Text("Any of the three. The weight in kilograms, as in the red book.")
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.surface)
    }

    /// "Weight   3.85 kg  · 8 lb 8 oz".
    private func measureRow(_ name: String, _ unit: String, _ text: Binding<String>, extra: String?) -> some View {
        HStack(spacing: 8) {
            Text(name)
            Spacer(minLength: 8)
            TextField(unit == "kg" ? "3.85" : "52.5", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                .accessibilityLabel("\(name) in \(unit == "kg" ? "kilograms" : "centimetres")")
            Text(unit).foregroundStyle(Theme.textMuted)
            if let extra {
                Text("· \(extra)").foregroundStyle(Theme.textMuted).lineLimit(1).fixedSize()
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).feedText(.label).foregroundStyle(Theme.textMuted)
    }

    /// "Who did it" (DD8): for a sleep, "Settled by" and, once it has ended, "Got up". A parent's
    /// choice, else the saved one, else the starting rule. A sleep ended here counts for this
    /// phone's parent until another is chosen, as on Home.
    @ViewBuilder
    private var whoSection: some View {
        let sides = ShareSides.current()
        if draft.event.kind.countsAsWork, sides.right != nil {
            let doneBy = pickedDoneBy.map { WhoDidIt.Answer(member: $0, saved: true) }
                ?? (storedDoneBy?.saved == true ? storedDoneBy
                    : WhoDidIt.answer(for: draft, breastfeeder: AppModel.shared.store.data.breastfeeder))
            Section {
                WhoDidItPicker(sides: sides, shown: doneBy) { pickedDoneBy = $0 }
            } header: {
                header(kind == .sleep ? EditorWhoText.settledBy : EditorWhoText.doneBy)
            } footer: {
                Text(EditorWhoText.loggedBy(RowPerson(draft.event.loggedBy).name))
                    .feedText(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.surface)
            if kind == .sleep, !running {
                let gotUp = pickedGotUp.map { WhoDidIt.Answer(member: $0, saved: true) }
                    ?? (original.event.endedAt == nil ? WhoDidIt.Answer(member: me, saved: true) : storedGotUp)
                Section {
                    WhoDidItPicker(sides: sides, shown: gotUp) { pickedGotUp = $0 }
                } header: {
                    header(EditorWhoText.gotUp)
                }
                .listRowBackground(Theme.surface)
            }
        }
    }

    // MARK: Saving

    private func save(_ lastChange: ((inout EventSnapshot) -> Void)? = nil) {
        var final = draft
        if kind == .sleep, running { final.event.endedAt = nil }
        // "Still asleep" turned off, with the Woke up time left as shown (now).
        if kind == .sleep, !running, final.event.endedAt == nil { final.event.endedAt = max(Date(), final.event.startedAt) }
        if kind == .growth { final.payload?.growth = growth }
        if kind == .medicine {
            let name = (final.payload?.medicine?.name ?? "").trimmingCharacters(in: .whitespaces)
            final.payload?.medicine?.name = name
        }
        lastChange?(&final)
        let store = AppModel.shared.store
        let me = me
        switch mode {
        case .newGrowth:
            let payload = final.payload ?? EventPayload(growth: growth)
            store.change {
                $0.add(kind: .growth, babyID: babyID, startedAt: final.event.startedAt, payload: payload, by: me,
                       timeZoneID: TimeZone.current.identifier, now: Date())
            }
        case .edit(let id):
            let changed = EventSnapshot.changedFields(from: original, to: final)
            let doer = pickedDoneBy
            let riser = final.event.endedAt == nil ? nil : pickedGotUp
            store.change {
                $0.edit(id, by: me, now: Date()) { current in
                    for field in changed { current.copy(field, from: final) }
                }
                if let doer { $0.setDoneBy(id, to: doer, by: me, now: Date()) }
                // After the edit, so it is given for the sleep's ending as saved.
                if let riser { $0.setGotUp(id, to: riser, by: me, now: Date()) }
            }
        }
        dismiss()
    }
}
