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
    /// A first being deleted from here: it asks first (outside review O9, design review D15).
    @State private var deletingFirst: String?
    /// A first's delete that couldn't be written to this phone (task T17).
    @State private var deleteProblem: String?
    @State private var undo: UndoAction?
    /// Small buttons at the top show one kind only (settled with round two, 17 Nov 2026).
    @AppStorage("history.filter") private var filterName = HistoryFilter.all.rawValue

    var body: some View {
        let data = model.store.data
        let zone = data.householdSettings.timeZone
        // A feed logged on both phones shows once: the copy is left out, and the feed logged
        // first says so (the user's choice, 15 Nov 2026).
        let pairs = data.duplicatePairs(babyID: model.baby?.name ?? "")
        let copyOf = Dictionary(pairs.map { ($0.kept, $0.duplicate) }, uniquingKeysWith: { first, _ in first })
        let filter = HistoryFilter(rawValue: filterName) ?? .all
        let events = filter.entries(in: data, hidden: Set(pairs.map(\.duplicate)))
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
        .navigationDestination(for: JournalView.Route.self) { route in
            if let me = model.me {
                FirstPage(id: route.id, me: me, babyID: model.baby?.name ?? "")
            }
        }
        .confirmationDialog(JournalText.deleteQuestion, isPresented: Binding {
            deletingFirst != nil
        } set: {
            if !$0 { deletingFirst = nil }
        }, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteFirst() }
            Button("Keep it", role: .cancel) { deletingFirst = nil }
        } message: {
            Text(JournalText.deleteWarning)
        }
        .alert("Not deleted", isPresented: Binding {
            deleteProblem != nil
        } set: {
            if !$0 { deleteProblem = nil }
        }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteProblem ?? "")
        }
        // The Undo card at the top (DD7), and a first's Undo, from here or from its page.
        .undoCard(undo) { shown in
            if undo?.id == shown.id { undo = nil }
        }
        .undoCenterCard()
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

    /// A first's delete from here, with its question; held for Undo like the Journal's.
    private func deleteFirst() {
        guard let id = deletingFirst, let me = model.me else { return }
        deletingFirst = nil
        let title = model.store.data.events[id]?.snapshot.payload?.milestone?.title ?? "First"
        // Checked, as in the Journal: a delete this phone couldn't write isn't shown or sent.
        let (deleted, onPhone) = model.store.changeChecked { $0.deleteMilestone(id, by: me, now: Date()) }
        guard onPhone else {
            deleteProblem = FirstEditor.notOnPhone
            return
        }
        if deleted { UndoCenter.shared.show(JournalUndo.action(for: .deleted(id: id, title: title), me: me)) }
    }

    @ViewBuilder
    private func row(_ stored: StoredEvent, zone: TimeZone, copy: String?) -> some View {
        if stored.event.kind == .milestone {
            firstRow(stored, zone: zone)
        } else {
            entryRow(stored, zone: zone, copy: copy)
        }
    }

    /// A first: its row opens its page; a swipe deletes it after asking.
    private func firstRow(_ stored: StoredEvent, zone: TimeZone) -> some View {
        // A real link, so VoiceOver and Switch Control open it; no ">", like every other row.
        NavigationLink(value: JournalView.Route(id: stored.event.id)) {
            FirstRow(snapshot: stored.snapshot, zone: zone, loggedBy: RowPerson(stored.event.loggedBy))
        }
        .navigationLinkIndicatorVisibility(.hidden)
        .buttonStyle(.plain)
        .accessibilityHint("Opens it. Swipe left to delete.")
        .swipeActions(allowsFullSwipe: false) {
            Button("Delete", role: .destructive) { deletingFirst = stored.event.id }
        }
    }

    private func entryRow(_ stored: StoredEvent, zone: TimeZone, copy: String?) -> some View {
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
    case all, feeds, sleep, nappies, medicine, growth, firsts

    var title: String {
        switch self {
        case .all: "All"
        case .feeds: "Feeds"
        case .sleep: "Sleep"
        case .nappies: "Nappies"
        case .medicine: "Medicine"
        case .growth: "Growth"
        case .firsts: "Firsts"
        }
    }

    var kinds: Set<EventKind> {
        switch self {
        case .all: [.feed, .pump, .sleep, .nappy, .medicine, .growth, .milestone]
        case .feeds: [.feed, .pump]
        case .sleep: [.sleep]
        case .nappies: [.nappy]
        case .medicine: [.medicine]
        case .growth: [.growth]
        case .firsts: [.milestone]
        }
    }

    /// What History shows with this filter, newest first: the entries of its kinds that aren't
    /// deleted, with a feed logged on both phones shown once (`hidden`: each pair's copy).
    func entries(in data: HouseholdData, hidden: Set<String>) -> [StoredEvent] {
        data.events.values
            .filter { kinds.contains($0.event.kind) && $0.event.deletedAt == nil && !hidden.contains($0.event.id) }
            .sorted { ($0.event.startedAt, $0.event.id) > ($1.event.startedAt, $1.event.id) }
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
