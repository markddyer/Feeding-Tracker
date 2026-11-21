import FeedingCore
import SwiftUI

// The feeding window bar on Home (the users' choice B, 21 Nov 2026, from
// `window-bar-20261121/round1.html` in the gstack design folder): one line in words says where
// the time since the last feed is, then the bar in named parts: after the feed, the feeding
// window, and (with alerts on) a short striped part up to the backup alarm. Facts only: "opens",
// "alert at", "closed at", "backup alarm". Never "due", "missed" or "overdue".

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

    /// Where now sits on a bar `width` wide: inside the part it is in.
    func nowX(width: CGFloat, gap: CGFloat = 3, minimum: CGFloat = 26) -> CGFloat {
        let frames = frames(width: width, gap: gap, minimum: minimum)
        guard let frame = frames.first(where: { $0.part.kind == currentPart }) else { return 0 }
        return frame.x + frame.width * filled(frame.part)
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

    /// The whole bar as one sentence, for VoiceOver.
    func spoken(_ clock: (Date) -> String) -> String {
        let place = switch phase {
        case .beforeWindow: "The window opens in \(HomeText.spokenElapsed(untilOpens))."
        case .inWindow: "Now in the feeding window."
        case .afterWindow: "The window closed at \(clock(closesAt))."
        }
        let alerts = backupAt.map { " Alert at \(clock(closesAt)), backup alarm at \(clock($0))." }
            ?? (alertsEnabled ? " Alert at \(clock(closesAt))." : " Alerts are off.")
        return "Last feed \(clock(lastFeed)). Feeding window \(clock(opensAt)) to \(clock(closesAt)). \(place)\(alerts)"
    }
}

/// The window bar: the line in words, the bar in parts with a dot for now, and the parts' names.
struct WindowBar: View {
    let facts: HomeFacts
    let window: FeedWindow
    @Environment(\.look) private var look

    var body: some View {
        let steps = WindowSteps(window: window, settings: facts.settings.window, now: facts.now)
        let line = steps.line(facts.clock)
        let strong: Font.Weight = look == .night ? .semibold : .bold
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Text(line.main).fontWeight(strong).foregroundStyle(Theme.text))\(Text(line.more))")
                .foregroundStyle(Theme.textMuted)
                .feedText(.subheadline)
            WindowTrack(steps: steps)
                .frame(height: 20)
            labels(steps)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(steps.spoken(facts.clock))
    }

    /// Each part's name and times, starting where its part starts.
    private func labels(_ steps: WindowSteps) -> some View {
        let parts = steps.parts
        return StepLabels(steps: steps) {
            ForEach(parts) { part in
                let label = steps.label(part.kind, facts.clock)
                let current = part.kind == steps.currentPart
                let atEnd = parts.count > 1 && part.kind == parts.last?.kind
                VStack(alignment: atEnd ? .trailing : .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(label.name)
                        if part.kind == .window, steps.alertsEnabled {
                            Image(systemName: "bell.fill").imageScale(.small)
                        }
                    }
                    .feedText(.small)
                    .foregroundStyle(current ? Theme.text : Theme.textMuted)
                    Text(label.time)
                        .feedText(.smallButton)
                        .monospacedDigit()
                }
                .fixedSize()
            }
        }
    }
}

/// The bar: each part on its own colour (after the feed on `track`, the window on `window`, the
/// backup striped), coral up to now, and a ringed dot for now.
private struct WindowTrack: View {
    let steps: WindowSteps

    var body: some View {
        GeometryReader { proxy in
            let frames = steps.frames(width: proxy.size.width)
            let nowX = steps.nowX(width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.element.part.kind) { index, frame in
                    let shape = UnevenRoundedRectangle(topLeadingRadius: index == 0 ? 7 : 4,
                                                       bottomLeadingRadius: index == 0 ? 7 : 4,
                                                       bottomTrailingRadius: index == frames.count - 1 ? 7 : 4,
                                                       topTrailingRadius: index == frames.count - 1 ? 7 : 4)
                    ZStack(alignment: .leading) {
                        base(frame.part.kind)
                        Rectangle()
                            .fill(Theme.primary)
                            .frame(width: frame.width * steps.filled(frame.part))
                    }
                    .frame(width: frame.width, height: 14)
                    .clipShape(shape)
                    .offset(x: frame.x, y: 3)
                }
                Circle()
                    .fill(Theme.background)
                    .overlay(Circle().strokeBorder(Theme.text, lineWidth: 4))
                    .frame(width: 20, height: 20)
                    .offset(x: min(max(0, nowX - 10), proxy.size.width - 20))
            }
        }
    }

    @ViewBuilder
    private func base(_ kind: WindowSteps.PartKind) -> some View {
        switch kind {
        case .sinceFeed: Theme.track
        case .window: Theme.window
        case .backup: Stripes()
        }
    }
}

/// The backup's stretch: `window` stripes on `track`.
private struct Stripes: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.track))
            var x = -size.height
            while x < size.width + size.height {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height))
                line.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(line, with: .color(Theme.window), lineWidth: 3)
                x += 7
            }
        }
    }
}

/// The parts' names in a row, each starting where its part starts (the last one ending at the
/// bar's end), pushed apart when they would touch; one under another when the row is too narrow,
/// as at the largest text sizes.
struct StepLabels: Layout {
    let steps: WindowSteps
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

    private func starts(_ width: CGFloat) -> [CGFloat] { steps.frames(width: width).map(\.x) }

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
