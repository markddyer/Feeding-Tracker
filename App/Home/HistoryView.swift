import FeedingCore
import SwiftUI

/// The timeline, grouped by day in the household time zone. A deleted entry doesn't show at all
/// (the user's decision, 15 Nov 2026); it stays in iCloud only so the other phone learns of the
/// delete. Every change goes through the store, so the alerts are worked out again.
struct HistoryView: View {
    private let model = AppModel.shared
    @State private var editing: EventEditor.Mode?

    var body: some View {
        let data = model.store.data
        let zone = data.householdSettings.timeZone
        let names = model.memberNames
        let events = data.events.values
            .filter { ($0.event.kind == .feed || $0.event.kind == .pump) && $0.event.deletedAt == nil }
            .sorted { $0.event.startedAt > $1.event.startedAt }
        let days = Dictionary(grouping: events) { PlainDate($0.event.startedAt, in: zone) }
        List {
            if events.isEmpty {
                Text("Nothing logged yet.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Section(dayTitle(day, zone: zone)) {
                    ForEach(days[day] ?? [], id: \.event.id) { stored in
                        row(stored, zone: zone, names: names)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("History")
        .sheet(item: $editing) { mode in
            if let me = model.me {
                EventEditor(mode: mode, me: me, babyID: model.baby?.name ?? "")
            }
        }
    }

    private func row(_ stored: StoredEvent, zone: TimeZone, names: [MemberID: String]) -> some View {
        let snapshot = stored.snapshot
        let event = snapshot.event
        let me = model.me
        func name(_ member: MemberID) -> String { member == me ? "you" : (names[member] ?? "the other parent") }
        var who = name(event.loggedBy)
        if event.endedAt != nil, let finisher = snapshot.payload?.stamp(.endedAt)?.by, finisher != event.loggedBy {
            who += ", finished by \(name(finisher))"
        }
        return Button {
            // Details from a newer app version can't be edited here.
            if snapshot.payload != nil { editing = .edit(id: event.id) }
        } label: {
            rowLabel(snapshot, zone: zone, who: who)
        }
        .foregroundStyle(Theme.text)
        .listRowBackground(Theme.surface)
        // No full swipe: a delete can't be brought back from here, so it takes a swipe and a tap.
        .swipeActions(allowsFullSwipe: false) {
            if let me = model.me {
                Button("Delete", role: .destructive) { model.store.change { $0.delete(event.id, by: me, now: Date()) } }
            }
        }
    }

    private func rowLabel(_ snapshot: EventSnapshot, zone: TimeZone, who: String) -> some View {
        let event = snapshot.event
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(event.startedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                    .monospacedDigit()
                Text(HomeFacts.details(snapshot))
            }
            Text("Logged by \(who)")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func dayTitle(_ day: PlainDate, zone: TimeZone) -> String {
        let today = PlainDate(Date(), in: zone)
        if day == today { return "Today" }
        if day == today.adding(days: -1) { return "Yesterday" }
        return day.description
    }
}
