import FeedingCore
import SwiftUI

/// The second column on the unfolded iPhone Duo: the last 24 hours as a timeline, newest first.
/// It scrolls, so it doesn't need to avoid the fold.
struct DayTimelineView: View {
    let me: MemberID
    let babyID: String

    private let model = AppModel.shared
    @State private var editing: EventEditor.Mode?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let data = model.store.data
            let settings = data.householdSettings
            let zone = settings.timeZone
            let since = context.date.addingTimeInterval(-24 * 3600)
            let entries = data.snapshots
                .filter { $0.event.babyID == babyID && $0.event.deletedAt == nil && $0.event.startedAt >= since }
                .filter { $0.event.kind == .feed || $0.event.kind == .pump }
                .sorted { $0.event.startedAt > $1.event.startedAt }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Only what happened. The window's times are on the home screen beside it
                    // (the user's decision, 15 Nov 2026: here they looked like feeds).
                    Text("Last 24 hours").font(.headline).padding(.bottom, 12)
                    if entries.isEmpty {
                        Text("Nothing logged in the last 24 hours.").foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(entries) { entry in
                        Button {
                            if entry.payload != nil { editing = .edit(id: entry.id) }
                        } label: {
                            row(entry, zone: zone)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.surface.ignoresSafeArea())
        .sheet(item: $editing) { mode in
            EventEditor(mode: mode, me: me, babyID: babyID)
        }
    }

    private func time(_ date: Date, zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }

    private func row(_ entry: EventSnapshot, zone: TimeZone) -> some View {
        let who = entry.event.loggedBy == me ? "you" : (model.memberNames[entry.event.loggedBy] ?? "the other parent")
        return HStack(alignment: .top, spacing: 10) {
            Text(time(entry.event.startedAt, zone: zone)).monospacedDigit().frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.event.kind == .pump ? "Pumping" : (entry.event.endedAt == nil ? "Feed in progress" : "Feed"))
                    .font(.subheadline.weight(.semibold))
                Text(HomeFacts.details(entry)).font(.subheadline)
                Text("by \(who)").font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
