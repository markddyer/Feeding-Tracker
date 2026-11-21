import FeedingCore
import SwiftUI

/// The list behind one number (X2, DD10, engineering D1 A): its own screen, back returns to the
/// page. Headed by the kind, with chips (parent · kind · range), the count or total on top, and
/// the entries grouped by day, each with the parent it was counted for (a worked-out "got up" dashed,
/// 7A). For a time number each row shows the time it added. A row opens its editor, where "who did
/// it" can be changed. Built from the same items as the number, so the two always agree.
struct ShareEntriesList: View {
    let request: ShareListRequest
    private let model = AppModel.shared
    @State private var editing: EventEditor.Mode?
    @State private var careEditing: CareEditor.Mode?
    /// Every row shown since the list opened. A row given to another parent here stays, with its
    /// new picture, until the list is left; the count is the list's own (design 2C, the screens
    /// table; Codex review of the build, 21 Nov 2026). A deleted entry leaves at once.
    @State private var seen: Set<String> = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let data = model.store.data
            let zone = data.householdSettings.timeZone
            let who = data.whoDidIt(babyID: model.baby?.name ?? "", now: context.date)
            let sides = ShareSides.current()
            let current = Self.items(who, request: request, sides: sides)
            let currentIDs = Set(current.map(\.id))
            let moved = who.items.filter { seen.contains($0.id) && !currentIDs.contains($0.id) }
            let items = (current + moved).sorted { ($0.at, $0.id) > ($1.at, $1.id) }
            let tally = current.reduce(into: ShareTally()) { $0.count += 1; $0.seconds += $1.seconds ?? 0 }
            let today = PlainDate(context.date, in: zone)
            let days = Dictionary(grouping: items, by: \.day)
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(chips(sides), id: \.self) { Chip(nil, $0, background: Theme.surface) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    Text(ShareText.number(tally, kind: request.kind, time: request.time))
                        .feedText(.title)
                        .monospacedDigit()
                        .accessibilityLabel(ShareText.listCount(tally, kind: request.kind, time: request.time))
                    if items.isEmpty {
                        Text(ShareText.nothingHere)
                            .feedText(.body)
                            .foregroundStyle(Theme.textMuted)
                    }
                    ForEach(days.keys.sorted(by: >), id: \.self) { day in
                        Text(request.kind.isNight ? ShareText.nightTitle(day, slept: 0, in: zone)
                             : ShareText.dayName(day, today: today, in: zone))
                            .feedText(.label)
                            .foregroundStyle(Theme.textMuted)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4)
                        ForEach(days[day] ?? []) { item in
                            row(item, data: data, zone: zone, now: context.date)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .onChange(of: currentIDs, initial: true) { _, ids in seen.formUnion(ids) }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(ShareText.kindTitle(request.kind, time: request.time, alone: true))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { mode in
            if let me = model.me { EventEditor(mode: mode, me: me, babyID: model.baby?.name ?? "") }
        }
        .sheet(item: $careEditing) { mode in
            if let me = model.me { CareEditor(mode: mode, me: me, babyID: model.baby?.name ?? "") }
        }
    }

    /// The items behind the number: one parent, every parent, or the "Other" part.
    static func items(_ who: WhoDidIt, request: ShareListRequest, sides: ShareSides) -> [ShareItem] {
        let all = who.entries(request.kind, member: request.member, range: request.range)
        return request.others ? all.filter { sides.isOther($0.member) } : all
    }

    private func chips(_ sides: ShareSides) -> [String] {
        // A list from a bar has every parent's entries: "Everyone".
        let member = request.others ? "Other" : request.member.map { sides.name($0) } ?? "Everyone"
        return ShareText.chips(member: member, kind: ShareText.kindTitle(request.kind, time: request.time, alone: true),
                               range: request.rangeTitle)
    }

    /// The parent an item was counted for; a "got up" worked out from the log is dashed (7A).
    /// A "done by" isn't: it starts as who logged it, by the agreed rule (R2), not a guess.
    @MainActor static func person(_ item: ShareItem) -> RowPerson {
        var person = RowPerson(item.member)
        person.workedOut = item.kind == .gotUpAtNight && !item.saved
        return person
    }

    @ViewBuilder
    private func row(_ item: ShareItem, data: HouseholdData, zone: TimeZone, now: Date) -> some View {
        if let id = item.eventIDs.first, let snapshot = data.events[id]?.snapshot {
            let person = Self.person(item)
            let isFeed = snapshot.event.kind == .feed || snapshot.event.kind == .pump
            let role = item.kind == .gotUpAtNight ? "Got up" : "Done by"
            Button {
                // Details from a newer app version can't be edited here.
                guard snapshot.payload != nil else { return }
                if isFeed { editing = .edit(id: id) } else { careEditing = .edit(id: id) }
            } label: {
                if isFeed {
                    HistoryRow(snapshot: snapshot, time: item.at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)),
                               loggedBy: person, loggedTwice: item.eventIDs.count > 1, role: role,
                               note: request.time || ShareText.showsTime(request.kind)
                                   ? item.seconds.map { ShareText.added($0) } ?? ShareText.stillRunning : nil)
                } else {
                    CareRow(snapshot: snapshot, zone: zone, loggedBy: person, now: now, role: role,
                            at: item.kind == .gotUpAtNight ? item.at : nil)
                }
            }
            .buttonStyle(PressStyle())
            .accessibilityHint(snapshot.payload == nil ? "" : "Opens it to change who did it")
        }
    }
}
