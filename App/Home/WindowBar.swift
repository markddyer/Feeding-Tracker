import FeedingCore
import SwiftUI

// The feeding window bar, in Home's top tile under the time since the last feed (the users'
// choice C, 21 Nov 2026, from `hero-bar-20261121/round1.html` in the gstack design folder; it
// took the ring's place). One line in words says where the time since the last feed is (choice B,
// `window-bar-20261121/round1.html`), then one thick bar in parts: after the feed, the feeding
// window with its name inside, and (with alerts on) a short striped part up to the backup alarm
// with a bell inside, each in its own colour (choice B of `hero-bar-20261121/round2-colours.html`:
// misty blue, coral, terracotta), pale still to come and full up to now; the edge is now. The
// times sit under their parts. Facts only: "opens", "alert at", "closed at", "backup alarm". Never "due", "missed" or
// "overdue".

/// Where now is against the window: the parts of the bar, and the words for them.
struct WindowSteps {
    enum Phase: Equatable {
        case beforeWindow
        case inWindow
        case afterWindow
    }

    enum PartKind: Equatable {
        case sinceFeed
        case window
        case backup
    }

    /// One part of the bar, in seconds after the last feed started.
    struct Part: Equatable, Identifiable {
        let kind: PartKind
        let from: TimeInterval
        let to: TimeInterval
        var id: PartKind { kind }
    }

    let lastFeed: Date
    let opensAt: Date
    let closesAt: Date
    /// When the backup alarm rings on both phones; nil with alerts off.
    let backupAt: Date?
    let alertsEnabled: Bool
    let now: Date

    init(window: FeedWindow, settings: FeedWindowSettings, now: Date) {
        lastFeed = window.lastFeedStart
        opensAt = window.opensAt
        closesAt = window.closesAt
        alertsEnabled = settings.alertsEnabled
        backupAt = settings.alertsEnabled && settings.backupAfterClose > 0
            ? window.closesAt.addingTimeInterval(settings.backupAfterClose) : nil
        self.now = now
    }

    var elapsed: TimeInterval { max(0, now.timeIntervalSince(lastFeed)) }

    var phase: Phase {
        if now >= closesAt { return .afterWindow }
        if now >= opensAt { return .inWindow }
        return .beforeWindow
    }

    /// The bar's parts, oldest first. A window that opens when it closes (or later) has no part
    /// of its own.
    var parts: [Part] {
        let opens = max(0, opensAt.timeIntervalSince(lastFeed))
        let closes = max(0, closesAt.timeIntervalSince(lastFeed))
        var parts: [Part] = []
        if min(opens, closes) > 0 { parts.append(Part(kind: .sinceFeed, from: 0, to: min(opens, closes))) }
        if closes > opens { parts.append(Part(kind: .window, from: opens, to: closes)) }
        if let backupAt, backupAt > closesAt {
            parts.append(Part(kind: .backup, from: closes, to: backupAt.timeIntervalSince(lastFeed)))
        }
        return parts
    }

    /// The parts with their times under the bar: the window and the backup. The last feed's time
    /// is in the tile, over the bar.
    var labelled: [Part] { parts.filter { $0.kind != .sinceFeed } }

    /// How full a part is now, from 0 to 1.
    func filled(_ part: Part) -> Double {
        guard part.to > part.from else { return elapsed >= part.to ? 1 : 0 }
        return min(1, max(0, (elapsed - part.from) / (part.to - part.from)))
    }

    /// The part now is in: the last one once the bar is full.
    var currentPart: PartKind? {
        parts.first { elapsed < $0.to }?.kind ?? parts.last?.kind
    }

    /// Each part's place on a bar `width` wide, with `gap` between parts. A part is never
    /// narrower than `minimum`, so the backup's short stretch stays visible.
    func frames(width: CGFloat, gap: CGFloat = 3, minimum: CGFloat = 26) -> [(part: Part, x: CGFloat, width: CGFloat)] {
        let parts = parts
        guard let total = parts.last?.to, total > 0 else { return [] }
        let room = max(0, width - gap * CGFloat(parts.count - 1))
        var widths = parts.map { room * CGFloat(($0.to - $0.from) / total) }
        // Give a short part its minimum, taken from the others in proportion.
        let short = widths.indices.filter { widths[$0] < minimum }
        let added = short.reduce(CGFloat(0)) { $0 + minimum - widths[$1] }
        let others = widths.indices.filter { !short.contains($0) }
        let othersWidth = others.reduce(CGFloat(0)) { $0 + widths[$1] }
        if added > 0, othersWidth > added {
            for i in short { widths[i] = minimum }
            for i in others { widths[i] -= added * widths[i] / othersWidth }
        }
        var x: CGFloat = 0
        return zip(parts, widths).map { part, partWidth in
            defer { x += partWidth + gap }
            return (part, x, partWidth)
        }
    }

    /// The line over the bar: the words that matter, then the times after them.
    /// "Window opens in 20m" · "at 15:22"; "In the feeding window" · "alert at 17:22";
    /// "Window closed at 17:22" · "backup alarm 17:52".
    func line(_ clock: (Date) -> String) -> (main: String, more: String) {
        switch phase {
        case .beforeWindow:
            return ("Window opens in \(HomeText.elapsed(untilOpens))", " · at \(clock(opensAt))" + (alertsEnabled ? "" : " · alerts off"))
        case .inWindow:
            return ("In the feeding window", alertsEnabled ? " · alert at \(clock(closesAt))" : " · until \(clock(closesAt)) · alerts off")
        case .afterWindow:
            let more = backupAt.map { " · backup alarm \(clock($0))" } ?? (alertsEnabled ? "" : " · alerts off")
            return ("Window closed at \(clock(closesAt))", more)
        }
    }

    /// The minutes to the window's opening, rounded up, so "in 0m" never shows before it opens.
    private var untilOpens: TimeInterval {
        (max(0, opensAt.timeIntervalSince(now)) / 60).rounded(.up) * 60
    }

    /// A part's name and times, under the bar.
    func label(_ kind: PartKind, _ clock: (Date) -> String) -> (name: String, time: String) {
        switch kind {
        case .sinceFeed: ("Last feed", clock(lastFeed))
        case .window: ("Feeding window", "\(clock(opensAt))–\(clock(closesAt))")
        case .backup: ("Backup", backupAt.map(clock) ?? "")
        }
    }

    /// The bar as sentences, for VoiceOver, after the tile's own "Last feed started …".
    func spoken(_ clock: (Date) -> String) -> String {
        let place = switch phase {
        case .beforeWindow: "The window opens in \(HomeText.spokenElapsed(untilOpens))."
        case .inWindow: "Now in the feeding window."
        case .afterWindow: "The window closed at \(clock(closesAt))."
        }
        let alerts = backupAt.map { " Alert at \(clock(closesAt)), backup alarm at \(clock($0))." }
            ?? (alertsEnabled ? " Alert at \(clock(closesAt))." : " Alerts are off.")
        return "Feeding window \(clock(opensAt)) to \(clock(closesAt)). \(place)\(alerts)"
    }
}

/// The window bar, under the time in Home's top tile: the line in words, one thick bar in parts
/// with coral up to now (its edge is now), and the times under their parts.
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
            }
        }
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
