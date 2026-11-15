import FeedingCore
import SwiftUI

/// Logs an earlier feed or a pumping session, or corrects one already logged.
///
/// A correction saves only the parts changed here, put onto the newest copy. So if the other
/// phone changed something else in the meantime, that change stays.
struct EventEditor: View {
    enum Mode: Hashable, Identifiable {
        case newFeed
        case newPump
        case edit(id: String)

        var id: Self { self }
    }

    let mode: Mode
    let me: MemberID
    let babyID: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage(FeedingStyle.storageKey) private var feedingStyle = ""
    @State private var draft: EventSnapshot
    @State private var finished: Bool
    private let original: EventSnapshot

    init(mode: Mode, me: MemberID, babyID: String) {
        self.mode = mode
        self.me = me
        self.babyID = babyID
        let now = Date()
        let snapshot: EventSnapshot
        switch mode {
        case .edit(let id):
            snapshot = AppModel.shared.store.data.events[id]?.snapshot ?? Self.blank(.feed, babyID: babyID, me: me, now: now)
        case .newFeed:
            snapshot = Self.blank(.feed, babyID: babyID, me: me, now: now)
        case .newPump:
            var pump = Self.blank(.pump, babyID: babyID, me: me, now: now)
            pump.payload = EventPayload(pump: PumpDetails(side: .both))
            snapshot = pump
        }
        original = snapshot
        _draft = State(initialValue: snapshot)
        _finished = State(initialValue: snapshot.event.endedAt != nil)
    }

    private static func blank(_ kind: EventKind, babyID: String, me: MemberID, now: Date) -> EventSnapshot {
        let start = now.addingTimeInterval(-30 * 60)
        return EventSnapshot(
            event: Event(id: "draft", babyID: babyID, kind: kind, startedAt: start, endedAt: start.addingTimeInterval(20 * 60),
                         timeZoneID: TimeZone.current.identifier, loggedBy: me, createdAt: now, modifiedAt: now),
            payload: EventPayload(feed: kind == .feed ? FeedDetails() : nil))
    }

    private var isPump: Bool { draft.event.kind == .pump }

    var body: some View {
        NavigationStack {
            Form {
                timesSection
                if isPump {
                    pumpSection
                } else {
                    // A bottle-only parent sees sides only on a feed that already has them.
                    if feedingStyle != FeedingStyle.bottleOnly.rawValue || !(original.payload?.feed?.breast.isEmpty ?? true) {
                        breastSection
                    }
                    bottlesSection
                }
                Section("Note") {
                    TextField("Optional", text: Binding {
                        draft.payload?.note ?? ""
                    } set: {
                        draft.payload?.note = $0.isEmpty ? nil : $0
                    }, axis: .vertical)
                }
                if case .edit = mode {
                    Section {
                        if draft.event.deletedAt == nil {
                            Button("Delete", role: .destructive) { save { $0.event.deletedAt = Date() } }
                        } else {
                            Button("Bring back") { save { $0.event.deletedAt = nil } }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(problem != nil)
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .newFeed: "Earlier feed"
        case .newPump: "Pumping"
        case .edit: isPump ? "Pumping" : "Feed"
        }
    }

    /// Why Save is off, if it is.
    private var problem: String? {
        if draft.event.startedAt > Date().addingTimeInterval(60) { return "The start is in the future." }
        if finished, let end = draft.event.endedAt, end < draft.event.startedAt { return "The end is before the start." }
        return nil
    }

    // MARK: Sections

    private var timesSection: some View {
        Section {
            DatePicker("Started", selection: $draft.event.startedAt, in: ...Date().addingTimeInterval(60))
            Toggle("Finished", isOn: $finished)
            if finished {
                DatePicker("Ended", selection: Binding {
                    draft.event.endedAt ?? draft.event.startedAt.addingTimeInterval(20 * 60)
                } set: {
                    draft.event.endedAt = $0
                }, in: draft.event.startedAt...)
            }
        } footer: {
            if let problem { Text(problem).foregroundStyle(Theme.warning) }
        }
    }

    private var breastSection: some View {
        Section("Breast") {
            ForEach(Array((draft.payload?.feed?.breast ?? []).enumerated()), id: \.element.id) { index, segment in
                Stepper(value: Binding {
                    (draft.payload?.feed?.breast[index].durationSeconds ?? 0) / 60
                } set: { minutes in
                    draft.payload?.feed?.breast[index].durationSeconds = minutes == 0 ? nil : minutes * 60
                }, in: 0...90) {
                    let minutes = (segment.durationSeconds ?? 0) / 60
                    Text("\(segment.side == .left ? "Left" : "Right") · \(minutes == 0 ? "time not set" : "\(minutes) min")")
                }
            }
            .onDelete { draft.payload?.feed?.breast.remove(atOffsets: $0) }
            HStack {
                Button("+ Left") { draft.payload?.feed?.breast.append(BreastSegment(side: .left)) }
                Spacer()
                Button("+ Right") { draft.payload?.feed?.breast.append(BreastSegment(side: .right)) }
            }
            .buttonStyle(.borderless)
        }
    }

    private var bottlesSection: some View {
        Section("Bottles") {
            ForEach(Array((draft.payload?.feed?.bottles ?? []).enumerated()), id: \.element.id) { index, bottle in
                Stepper(value: Binding {
                    draft.payload?.feed?.bottles[index].ml ?? 0
                } set: { ml in
                    draft.payload?.feed?.bottles[index].ml = ml == 0 ? nil : ml
                }, in: 0...300, step: 10) {
                    Text("\(bottle.milk == .formula ? "Formula" : "Expressed") · \(bottle.ml.map { "\($0) ml" } ?? "amount not set")")
                }
            }
            .onDelete { draft.payload?.feed?.bottles.remove(atOffsets: $0) }
            HStack {
                Button("+ Expressed") { draft.payload?.feed?.bottles.append(Bottle(milk: .expressed)) }
                Spacer()
                Button("+ Formula") { draft.payload?.feed?.bottles.append(Bottle(milk: .formula)) }
            }
            .buttonStyle(.borderless)
        }
    }

    private var pumpSection: some View {
        let side = draft.payload?.pump?.side ?? .both
        return Section("Pumping") {
            Picker("Side", selection: Binding {
                side
            } set: { newSide in
                draft.payload?.pump?.side = newSide
                if newSide == .left { draft.payload?.pump?.rightML = nil }
                if newSide == .right { draft.payload?.pump?.leftML = nil }
            }) {
                Text("Left").tag(PumpSide.left)
                Text("Right").tag(PumpSide.right)
                Text("Both").tag(PumpSide.both)
            }
            .pickerStyle(.segmented)
            if side != .right { mlStepper("Left", \.leftML) }
            if side != .left { mlStepper("Right", \.rightML) }
        }
    }

    private func mlStepper(_ label: String, _ keyPath: WritableKeyPath<PumpDetails, Int?>) -> some View {
        let value = draft.payload?.pump?[keyPath: keyPath]
        return Stepper(value: Binding {
            value ?? 0
        } set: { ml in
            draft.payload?.pump?[keyPath: keyPath] = ml == 0 ? nil : ml
        }, in: 0...400, step: 10) {
            Text("\(label) · \(value.map { "\($0) ml" } ?? "not set")")
        }
    }

    // MARK: Saving

    private func save(_ lastChange: ((inout EventSnapshot) -> Void)? = nil) {
        var final = draft
        if !finished { final.event.endedAt = nil }
        lastChange?(&final)
        let store = AppModel.shared.store
        let me = me
        switch mode {
        case .newFeed, .newPump:
            store.change {
                $0.add(kind: final.event.kind, babyID: babyID, startedAt: final.event.startedAt, endedAt: final.event.endedAt,
                       payload: final.payload ?? EventPayload(), by: me, timeZoneID: TimeZone.current.identifier, now: Date())
            }
        case .edit(let id):
            let changed = EventSnapshot.changedFields(from: original, to: final)
            store.change {
                $0.edit(id, by: me, now: Date()) { current in
                    for field in changed { current.copy(field, from: final) }
                }
            }
        }
        dismiss()
    }
}
