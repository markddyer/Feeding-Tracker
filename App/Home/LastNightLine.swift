import FeedingCore
import SwiftUI

/// "Last night" at the top of Home (X3, DD4, 3A): one slim line on `sleep-tint`, from the night's
/// end until 12:00. A moon, "Last night", each night entry's own shape (feed, nappy, wake-up) in the
/// colour of who did it (who got up, for a wake-up), in time order, at most 8 then "+N", and
/// "Slept 6h 40m ›". A tap opens the night's entries. A handover, not a score: no counts per
/// parent here.
struct LastNightLine: View {
    let night: LastNight
    let zone: TimeZone
    @State private var open = false
    @ScaledMetric(relativeTo: .body) private var shape: CGFloat = 15

    static let shownShapes = 8

    var body: some View {
        let sides = ShareSides.current()
        Button { open = true } label: {
            HStack(spacing: 8) {
                FeedMarkView(.sleep, size: 16, relativeTo: .body)
                Text(ShareText.lastNight)
                    .feedText(.smallButton)
                // The shapes may wrap at large text (3A).
                FlowShapes(items: Array(night.items.prefix(Self.shownShapes)), more: max(0, night.items.count - Self.shownShapes),
                           sides: sides, size: shape)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if night.sleptSeconds > 0 {
                    Text(ShareText.slept(night.sleptSeconds))
                        .feedText(.small)
                        .monospacedDigit()
                        .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.sleepTint, in: RoundedRectangle(cornerRadius: Radius.tile))
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShareText.spokenLastNight(night))
        .accessibilityHint("Shows last night's entries")
        .sheet(isPresented: $open) {
            LastNightSheet(night: night, zone: zone, sides: sides)
        }
    }
}

/// The shapes in a row that wraps.
private struct FlowShapes: View {
    let items: [ShareItem]
    let more: Int
    let sides: ShareSides
    let size: CGFloat

    var body: some View {
        WrapLayout(spacing: 4) {
            ForEach(items) { item in
                FeedMarkView(ShareBar.mark(item.kind), size: size, relativeTo: .body, colour: sides.mark(item.member))
            }
            if more > 0 {
                Text("+\(more)")
                    .feedText(.small)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }
}

/// Lays its children out left to right, starting a new row when the width runs out.
private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// The night's entries (DD4, `round2.html` B): time, shape, what, and who.
private struct LastNightSheet: View {
    let night: LastNight
    let zone: TimeZone
    let sides: ShareSides

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(ShareText.nightTitle(night.night, slept: night.sleptSeconds, in: zone))
                    .feedText(.title)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(night.items) { item in
                        NightLine(item: item, sides: sides, zone: zone)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Theme.sleepTint, in: RoundedRectangle(cornerRadius: Radius.tile))
            }
            .padding(20)
        }
        .foregroundStyle(Theme.text)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }
}
