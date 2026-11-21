import FeedingCore
import SwiftUI
import WidgetKit

/// The window bar on the watch, as on the phone (`DESIGN.md`, "Window bar"; the users' choices of
/// 21 Nov 2026): the wait after the feed in misty blue, the feeding window in coral, the stretch up
/// to the backup alarm in terracotta (striped while still to come, with a bell), each pale while
/// still to come and full once the time has passed it, and a needle at now. Its rules are the
/// phone's (`WindowSteps`, `Shared/WindowSteps.swift`). Used by the watch app and the watch face.
///
/// On a watch face that tints its pieces (rather than showing them in full colour), the parts are
/// shades of the face's colour instead: the passed parts in the accent, the rest faint.
struct WatchWindowTrack: View {
    let steps: WindowSteps
    let palette: WatchPalette
    var height: CGFloat = 12
    /// The bell inside the backup part, when the bar is tall enough for it.
    var bell = true
    /// Behind the needle's edge: the screen's colour.
    var edge: Color = .black
    @Environment(\.widgetRenderingMode) private var renderingMode

    static let gap: CGFloat = 2
    /// The narrowest a part gets, so the backup's short stretch stays visible.
    static let minimumPart: CGFloat = 20

    /// How far the needle stands out over and under the bar.
    var overhang: CGFloat { max(3, (height * 0.35).rounded()) }

    private var fullColour: Bool { renderingMode == .fullColor }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let frames = steps.frames(width: width, gap: Self.gap, minimum: Self.minimumPart)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.element.part.kind) { index, frame in
                    let kind = frame.part.kind
                    let first = index == 0, last = index == frames.count - 1
                    let outer = height / 2, inner = min(4, height / 3)
                    let shape = UnevenRoundedRectangle(topLeadingRadius: first ? outer : inner,
                                                       bottomLeadingRadius: first ? outer : inner,
                                                       bottomTrailingRadius: last ? outer : inner,
                                                       topTrailingRadius: last ? outer : inner)
                    let filled = steps.filled(frame.part)
                    ZStack(alignment: .leading) {
                        empty(kind)
                        full(kind).frame(width: frame.width * filled)
                        if bell, kind == .backup, height >= 10 {
                            Image(systemName: "bell.fill")
                                .font(.system(size: height * 0.62, weight: .semibold))
                                .foregroundStyle(filled > 0.5 ? (fullColour ? palette.onBackup : .black) : palette.text)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: frame.width, height: height)
                    .clipShape(shape)
                    .offset(x: frame.x)
                }
                needle(at: steps.nowX(width: width, gap: Self.gap, minimum: Self.minimumPart), width: width)
            }
        }
        .frame(height: height)
        .padding(.vertical, overhang)
        .accessibilityHidden(true)
    }

    /// A part still to come.
    @ViewBuilder
    private func empty(_ kind: WindowSteps.PartKind) -> some View {
        if fullColour {
            switch kind {
            case .sinceFeed: palette.waitTint
            case .window: palette.window
            case .backup: WatchStripes(base: palette.backupTint, stripe: palette.backupStripe)
            }
        } else {
            switch kind {
            case .backup: WatchStripes(base: Color.white.opacity(0.12), stripe: Color.white.opacity(0.3))
            default: Color.white.opacity(0.22)
            }
        }
    }

    /// A part the time has passed.
    @ViewBuilder
    private func full(_ kind: WindowSteps.PartKind) -> some View {
        if fullColour {
            switch kind {
            case .sinceFeed: palette.wait
            case .window: palette.primary
            case .backup: palette.backup
            }
        } else {
            switch kind {
            case .sinceFeed: Color.white.opacity(0.55)
            case .window: Color.white.widgetAccentable()
            case .backup: Color.white.opacity(0.75).widgetAccentable()
            }
        }
    }

    /// The needle at now: a line in the text colour, taller than the bar, with a thin edge in the
    /// screen's colour so it shows on every part. Kept inside the bar's ends.
    private func needle(at x: CGFloat, width: CGFloat) -> some View {
        let line: CGFloat = height >= 10 ? 3 : 2.5, rim: CGFloat = 1.5
        let centre = min(max(x, line / 2 + 1), width - line / 2 - 1)
        return RoundedRectangle(cornerRadius: line / 2)
            .fill(fullColour ? palette.text : .white)
            .frame(width: line, height: height + 2 * (overhang - rim))
            .padding(rim)
            .background(fullColour ? edge : .clear, in: RoundedRectangle(cornerRadius: line / 2 + rim))
            .offset(x: centre - line / 2 - rim, y: -overhang)
    }

    /// The same parts as a ring, for the round watch face pieces: hard stops at the window's
    /// opening and at the alert, so each stretch keeps its colour.
    static func ringGradient(_ steps: WindowSteps, palette: WatchPalette) -> Gradient {
        let parts = steps.parts
        guard let total = parts.last?.to, total > 0 else { return Gradient(colors: [palette.primary]) }
        var stops: [Gradient.Stop] = []
        for part in parts {
            let colour: Color = switch part.kind {
            case .sinceFeed: palette.wait
            case .window: palette.primary
            case .backup: palette.backup
            }
            stops.append(.init(color: colour, location: part.from / total))
            stops.append(.init(color: colour, location: part.to / total))
        }
        return Gradient(stops: stops)
    }

    /// How far round the ring now is: the whole bar's length, from the feed to the backup alarm.
    static func ringProgress(_ steps: WindowSteps) -> Double {
        guard let total = steps.parts.last?.to, total > 0 else { return 0 }
        return min(1, max(0, steps.elapsed / total))
    }
}

/// The backup's stretch still to come: stripes on a base.
struct WatchStripes: View {
    let base: Color
    let stripe: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            var x = -size.height
            while x < size.width + size.height {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height))
                line.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(line, with: .color(stripe), lineWidth: 2)
                x += 5
            }
        }
    }
}

extension WatchState {
    /// The window bar's facts now, once there is a feed (`WindowSteps`, shared with the phone).
    func windowSteps(at now: Date) -> WindowSteps? {
        feedWindow.map { WindowSteps(window: $0, settings: window, now: now) }
    }

    /// A time on the household's clock, for the bar's words.
    func clock(_ date: Date) -> String {
        GlanceText.clock(date, timeZoneID: timeZoneID)
    }
}
