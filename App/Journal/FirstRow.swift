import FeedingCore
import SwiftUI

/// A first in History (design review D43): a plain `surface` row, the sparkle and the time on the
/// left, the title in the middle, and the initial of the parent who logged it on the right. A tap
/// opens the first's page.
struct FirstRow: View {
    let snapshot: EventSnapshot
    let zone: TimeZone
    let loggedBy: RowPerson

    var body: some View {
        let title = snapshot.payload?.milestone?.title ?? "A first"
        HStack(alignment: .center, spacing: 10) {
            Text(clock(snapshot.event.startedAt))
                .feedText(.smallButton)
                .fixedSize()
                .frame(minWidth: 50, alignment: .leading)
            HStack(spacing: 7) {
                FeedMarkView(.first, size: 18, relativeTo: .subheadline)
                    .accessibilityHidden(true)
                Text(title)
                    .feedText(.subheadline)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Avatar(name: loggedBy.name, colour: loggedBy.colour, size: 26)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clock(snapshot.event.startedAt)): first, \(title). Logged by \(loggedBy.spoken).")
    }

    private func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }
}
