import FeedingCore
import SwiftUI

/// The second column on the unfolded iPhone Duo (`05-visual-redesign.md`, "The Duo unfolded"):
/// the Last 24 hours tile, the Nights tile, and the last 24 hours' feeds as History rows. While
/// it shows, the home screen beside it leaves those two tiles out. It scrolls, so it doesn't need
/// to avoid the fold.
struct DayColumn: View {
    let me: MemberID
    let babyID: String
    /// "I'll take it" here puts its Undo bar under the buttons in the home column.
    let onUndo: (UndoAction) -> Void

    private let model = AppModel.shared
    @State private var editing: EventEditor.Mode?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let facts = HomeFacts(data: model.store.data, babyID: babyID, baby: model.babyDetails, me: me,
                                  names: model.memberNames, colours: model.memberColours, now: context.date)
            let zone = facts.settings.timeZone
            let since = context.date.addingTimeInterval(-24 * 3600)
            let entries = facts.data.snapshots
                .filter { $0.event.babyID == babyID && $0.event.deletedAt == nil && $0.event.startedAt >= since }
                .filter { $0.event.kind == .feed || $0.event.kind == .pump }
                .sorted { ($0.event.startedAt, $0.event.id) > ($1.event.startedAt, $1.event.id) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DayTile(facts: facts)
                    NightsTile(facts: facts, me: me, onUndo: onUndo)
                    Text("Recent")
                        .feedText(.label)
                        .foregroundStyle(Theme.textMuted)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 6)
                    if entries.isEmpty {
                        Text("Nothing logged in the last 24 hours.")
                            .feedText(.body)
                            .foregroundStyle(Theme.textMuted)
                    }
                    ForEach(entries) { entry in
                        Button {
                            // Details from a newer app version can't be edited here.
                            if entry.payload != nil { editing = .edit(id: entry.id) }
                        } label: {
                            HistoryRow(entry, zone: zone)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .sheet(item: $editing) { mode in
            EventEditor(mode: mode, me: me, babyID: babyID)
        }
    }
}

extension DayColumn {
    /// Whether the second column is showing, from the home column's width and the whole
    /// arrangement's. `ArrangementView` gives no direct signal; when it hides the second column the
    /// home column takes the whole width. Unknown widths (0) count as not showing, so nothing is
    /// hidden by mistake.
    static func isShowing(homeWidth: CGFloat, arrangementWidth: CGFloat) -> Bool {
        arrangementWidth > 0 && homeWidth > 0 && homeWidth < arrangementWidth * 0.8
    }
}

extension EnvironmentValues {
    /// True while the Duo's second column (`DayColumn`) shows beside the home screen, so the home
    /// screen can leave out the tiles that column holds. False everywhere else, so nothing is lost
    /// if the arrangement is ever misread: at worst a tile shows twice.
    @Entry var secondColumnShowing = false
}
