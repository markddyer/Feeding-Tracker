import FeedingCore
import SwiftUI

/// The timeline, grouped by day in the household time zone (`05-visual-redesign.md`,
/// "History"): a big title, a heading per day, and one tinted row per feed or pumping session.
/// A deleted entry doesn't show at all (the user's decision, 15 Nov 2026); it stays in iCloud
/// only so the other phone learns of the delete. Every change goes through the store, so the
/// alerts are worked out again.
struct HistoryView: View {
    private let model = AppModel.shared
    @State private var editing: EventEditor.Mode?
    @State private var careEditing: CareEditor.Mode?
    /// Small buttons at the top show one kind only (settled with round two, 17 Nov 2026).
    @AppStorage("history.filter") private var filterName = HistoryFilter.all.rawValue

    var body: some View {
        let data = model.store.data
        let zone = data.householdSettings.timeZone
        // A feed logged on both phones shows once: the copy is left out, and the feed logged
        // first says so (the user's choice, 15 Nov 2026).
        let pairs = data.duplicatePairs(babyID: model.baby?.name ?? "")
        let copyOf = Dictionary(pairs.map { ($0.kept, $0.duplicate) }, uniquingKeysWith: { first, _ in first })
        let hidden = Set(pairs.map(\.duplicate))
        let filter = HistoryFilter(rawValue: filterName) ?? .all
        let events = data.events.values
            .filter { filter.kinds.contains($0.event.kind) && $0.event.deletedAt == nil }
            .filter { !hidden.contains($0.event.id) }
            .sorted { ($0.event.startedAt, $0.event.id) > ($1.event.startedAt, $1.event.id) }
        let days = Dictionary(grouping: events) { PlainDate($0.event.startedAt, in: zone) }
        let today = PlainDate(Date(), in: zone)
        List {
            Text("History")
                .feedText(.title)
                .accessibilityAddTraits(.isHeader)
                .historyRow()
            filterButtons(filter)
                .historyRow()
            if events.isEmpty {
                Text(filter == .all ? "Nothing logged yet." : "Nothing of this kind logged yet.")
                    .feedText(.body)
                    .foregroundStyle(Theme.textMuted)
                    .historyRow()
            }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Text(HomeText.dayTitle(day, today: today, in: zone))
                    .feedText(.dayHeading)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
                    .historyRow()
                ForEach(days[day] ?? [], id: \.event.id) { stored in
                    row(stored, zone: zone, copy: copyOf[stored.event.id])
                        .historyRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        // The big Fredoka title is the first row; "History" stays the screen's name.
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .sheet(item: $editing) { mode in
            if let me = model.me {
                EventEditor(mode: mode, me: me, babyID: model.baby?.name ?? "")
            }
        }
        .sheet(item: $careEditing) { mode in
            if let me = model.me {
                CareEditor(mode: mode, me: me, babyID: model.baby?.name ?? "")
            }
        }
    }

    /// All, Feeds, Sleep, Nappies, Medicine, Growth: one kind at a time, in a row that scrolls
    /// sideways when the text is large.
    private func filterButtons(_ chosen: HistoryFilter) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    Button {
                        filterName = filter.rawValue
                    } label: {
                        Text(filter.title)
                            .feedText(.chip)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(filter == chosen ? Theme.background : Theme.text)
                            .background(filter == chosen ? Theme.text : Theme.surface, in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(filter == chosen ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }

    private func row(_ stored: StoredEvent, zone: TimeZone, copy: String?) -> some View {
        let snapshot = stored.snapshot
        let event = snapshot.event
        let isFeed = event.kind == .feed || event.kind == .pump
        return Button {
            // Details from a newer app version can't be edited here.
            guard snapshot.payload != nil else { return }
            if isFeed { editing = .edit(id: event.id) } else { careEditing = .edit(id: event.id) }
        } label: {
            if isFeed {
                HistoryRow(snapshot, zone: zone, loggedTwice: copy != nil)
            } else {
                CareRow(snapshot, zone: zone)
            }
        }
        // Undo a merge: both feeds show again, on both phones.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let copy, let me = model.me {
                Button("Two feeds", systemImage: "arrow.triangle.branch") {
                    model.store.change { $0.markDistinct(event.id, copy, by: me, now: Date()) }
                }
                .tint(Theme.primary)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityHint(snapshot.payload == nil ? "" : "Opens it to change. Swipe left to delete.")
        // No full swipe: a delete can't be brought back from here, so it takes a swipe and a tap.
        .swipeActions(allowsFullSwipe: false) {
            if let me = model.me {
                Button("Delete", role: .destructive) { model.store.change { $0.delete(event.id, by: me, now: Date()) } }
            }
        }
    }
}

/// Which kinds History shows.
enum HistoryFilter: String, CaseIterable {
    case all, feeds, sleep, nappies, medicine, growth

    var title: String {
        switch self {
        case .all: "All"
        case .feeds: "Feeds"
        case .sleep: "Sleep"
        case .nappies: "Nappies"
        case .medicine: "Medicine"
        case .growth: "Growth"
        }
    }

    var kinds: Set<EventKind> {
        switch self {
        case .all: [.feed, .pump, .sleep, .nappy, .medicine, .growth]
        case .feeds: [.feed, .pump]
        case .sleep: [.sleep]
        case .nappies: [.nappy]
        case .medicine: [.medicine]
        case .growth: [.growth]
        }
    }
}

private extension View {
    /// A History row: no separator, no row background, the page's 16 point gutter.
    func historyRow() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
