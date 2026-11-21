import FeedingCore
import SwiftUI

// The feeding window bar, in Home's top tile under the time since the last feed (the users'
// choice C, 21 Nov 2026, from `hero-bar-20261121/round1.html` in the gstack design folder; it
// took the ring's place). One line in words says where the time since the last feed is (choice B,
// `window-bar-20261121/round1.html`), then one thick bar in parts: after the feed, the feeding
// window with its name inside, and (with alerts on) a short striped part up to the backup alarm
// with a bell inside, each in its own colour (choice B of `hero-bar-20261121/round2-colours.html`:
// misty blue, coral, terracotta), pale still to come and full up to now, with a needle at now. The
// times sit under their parts. The window opens and never closes: past the alert it stays "In the
// feeding window" and only the colours deepen (the users' choice A, 21 Nov 2026). Facts only:
// "opens", "alert at", "backup alarm", "since". Never "closed", "due", "missed" or "overdue".

/// The window bar, under the time in Home's top tile: the line in words, one thick bar in parts
/// filled up to now, a needle at now, and the times under their parts.
struct WindowBar: View {
    let steps: WindowSteps
    let clock: (Date) -> String
    @Environment(\.look) private var look
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 34

    /// The narrowest a part gets, so the backup's short stretch keeps room for its bell.
    static let minimumPart: CGFloat = 40

    var body: some View {
        let line = steps.line(clock)
        let strong: Font.Weight = look == .night ? .semibold : .bold
        let height = min(barHeight, 52)
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Text(line.main).fontWeight(strong).foregroundStyle(Theme.text))\(Text(line.more))")
                .foregroundStyle(Theme.textMuted)
                .feedText(.subheadline)
            WindowTrack(steps: steps, height: height)
                .frame(height: height)
                // Room for the needle, which stands out over and under the bar.
                .padding(.vertical, WindowTrack.overhang - 4)
            times
        }
    }

    /// The times under the window and the backup part, each starting where its part starts.
    private var times: some View {
        let parts = steps.labelled
        return StepLabels(steps: steps, kinds: parts.map(\.kind), minimum: Self.minimumPart) {
            ForEach(parts) { part in
                Text(steps.label(part.kind, clock).time)
                    .feedText(.smallButton)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }
}

/// The bar: each part in its own colour (the users' choice B, 21 Nov 2026): the wait before the
/// window misty blue, the window coral, the stretch to the backup alarm terracotta; pale while
/// still to come, full up to now. The window's name is written inside its part and the bell inside
/// the backup's, in `text`, or in the full colour's own ink where the time has reached them.
private struct WindowTrack: View {
    let steps: WindowSteps
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let frames = steps.frames(width: proxy.size.width, minimum: WindowBar.minimumPart)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.element.part.kind) { index, frame in
                    let outer = height / 2
                    let first = index == 0, last = index == frames.count - 1
                    let shape = UnevenRoundedRectangle(topLeadingRadius: first ? outer : 8,
                                                       bottomLeadingRadius: first ? outer : 8,
                                                       bottomTrailingRadius: last ? outer : 8,
                                                       topTrailingRadius: last ? outer : 8)
                    let fill = frame.width * steps.filled(frame.part)
                    let kind = frame.part.kind
                    ZStack(alignment: .leading) {
                        base(kind)
                        inside(kind, colour: Theme.text)
                        Rectangle()
                            .fill(Self.full(kind))
                            .frame(width: fill)
                        inside(kind, colour: Self.ink(kind))
                            .mask(alignment: .leading) { Rectangle().frame(width: fill) }
                    }
                    .frame(width: frame.width, height: height)
                    .clipShape(shape)
                    .offset(x: frame.x)
                }
                needle(at: steps.nowX(width: proxy.size.width, minimum: WindowBar.minimumPart), width: proxy.size.width)
            }
        }
    }

    /// How far the needle stands out over and under the bar, with its edge.
    static let overhang: CGFloat = 9

    /// The needle at now (the users' choice A, 21 Nov 2026, `hero-bar-20261121/round3-now.html`):
    /// a 5 pt line in `text`, taller than the bar, edged in `surface` so it shows on every colour.
    /// It stays inside the bar's ends; once the bar is full it sits at its end.
    private func needle(at x: CGFloat, width: CGFloat) -> some View {
        let line: CGFloat = 5, edge: CGFloat = 2
        let centre = min(max(x, line / 2 + 1), width - line / 2 - 1)
        return RoundedRectangle(cornerRadius: line / 2)
            .fill(Theme.text)
            .frame(width: line, height: height + 2 * (Self.overhang - edge))
            .padding(edge)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: line / 2 + edge))
            .offset(x: centre - line / 2 - edge, y: -Self.overhang)
    }

    /// A part still to come.
    @ViewBuilder
    private func base(_ kind: WindowSteps.PartKind) -> some View {
        switch kind {
        case .sinceFeed: Theme.waitTint
        case .window: Theme.window
        case .backup: Stripes()
        }
    }

    /// A part the time has passed.
    static func full(_ kind: WindowSteps.PartKind) -> Color {
        switch kind {
        case .sinceFeed: Theme.wait
        case .window: Theme.primary
        case .backup: Theme.backup
        }
    }

    /// What is written on a full part.
    static func ink(_ kind: WindowSteps.PartKind) -> Color {
        kind == .backup ? Theme.onBackup : Theme.onPrimary
    }

    /// What is written inside a part: the window's name (shorter, or nothing, when the part is
    /// too narrow, as at the largest text sizes), the backup's bell.
    @ViewBuilder
    private func inside(_ kind: WindowSteps.PartKind, colour: Color) -> some View {
        switch kind {
        case .sinceFeed:
            Color.clear
        case .window:
            ViewThatFits(in: .horizontal) {
                Text("Feeding window")
                Text("Window")
                Color.clear.frame(width: 0, height: 0)
            }
            .lineLimit(1)
            .feedText(.chip)
            .foregroundStyle(colour)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .backup:
            Image(systemName: "bell.fill")
                .feedText(.chip)
                .foregroundStyle(colour)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The backup's stretch still to come: `backup-stripe` stripes on `backup-tint`.
private struct Stripes: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.backupTint))
            var x = -size.height
            while x < size.width + size.height {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height))
                line.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(line, with: .color(Theme.backupStripe), lineWidth: 3)
                x += 7
            }
        }
    }
}

/// The labels under the bar in a row, each starting where its part starts (the last one ending at
/// the bar's end), pushed apart when they would touch; one under another when the row is too
/// narrow, as at the largest text sizes.
struct StepLabels: Layout {
    let steps: WindowSteps
    /// The parts with a label, in order.
    let kinds: [WindowSteps.PartKind]
    var minimum: CGFloat = 26
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        if Self.positions(starts: starts(width), width: width, sizes: sizes, spacing: spacing) != nil {
            return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
        }
        return CGSize(width: width, height: sizes.map(\.height).reduce(0, +) + 4 * CGFloat(max(0, sizes.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        if let xs = Self.positions(starts: starts(bounds.width), width: bounds.width, sizes: sizes, spacing: spacing) {
            for (index, subview) in subviews.enumerated() {
                subview.place(at: CGPoint(x: bounds.minX + xs[index], y: bounds.minY), proposal: .unspecified)
            }
        } else {
            var y = bounds.minY
            for (index, subview) in subviews.enumerated() {
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: .unspecified)
                y += sizes[index].height + 4
            }
        }
    }

    private func starts(_ width: CGFloat) -> [CGFloat] {
        steps.frames(width: width, minimum: minimum).filter { kinds.contains($0.part.kind) }.map(\.x)
    }

    /// Each label's x in one row, or nil when they don't fit side by side. With more than one
    /// label, the last one ends at the bar's end.
    static func positions(starts: [CGFloat], width: CGFloat, sizes: [CGSize], spacing: CGFloat) -> [CGFloat]? {
        guard !sizes.isEmpty else { return [] }
        guard sizes.count == starts.count else { return nil }
        var xs = zip(starts, sizes).map { min($0, width - $1.width) }
        if xs.count > 1, let last = sizes.last { xs[xs.count - 1] = width - last.width }
        // Push apart from the left, then pull back from the right.
        for i in xs.indices.dropFirst() { xs[i] = max(xs[i], xs[i - 1] + sizes[i - 1].width + spacing) }
        for i in xs.indices.reversed().dropFirst() { xs[i] = min(xs[i], xs[i + 1] - spacing - sizes[i].width) }
        guard zip(xs, sizes).allSatisfy({ $0 >= -0.5 && $0 + $1.width <= width + 0.5 }) else { return nil }
        for i in xs.indices.dropFirst() where xs[i] < xs[i - 1] + sizes[i - 1].width + spacing - 0.5 { return nil }
        return xs.map { max(0, $0) }
    }
}
