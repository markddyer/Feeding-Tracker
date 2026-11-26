import FeedingCore
import SwiftUI

// The watch's colours (`WatchPalette`) are in `Watch/Shared/WatchPalette.swift`, shared with the
// watch face.

extension EnvironmentValues {
    /// The watch's look now: day or night, from the household's hours and the phone's setting.
    @Entry var watchLook: Look = .night
    /// False on a page that is out of sight, so a double tap can't press a button there.
    @Entry var watchDoubleTapAllowed = true
}

/// The watch's text styles: the phone's (`DESIGN.md`, "Typography") at watch sizes. Fredoka for
/// button labels; SF Rounded with fixed-width digits for every time and amount. Each grows with
/// the watch's text size, and every weight drops at night.
enum WatchText {
    /// "1h 40m", "12:04".
    case mainTime
    /// "1h 20m" asleep, on page two, beside the moon.
    case careTime
    /// "60" on the amount screen.
    case amount
    /// Big button labels.
    case button
    /// "Left", "Right".
    case side
    /// "Window 05:00".
    case line
    /// "ago, at 20:58" and the bar's line on page 1: a little larger than `line`, to read at a
    /// glance (Parent A, 21 Nov 2026).
    case note
    /// "LAST FEED".
    case label
    /// "suggested".
    case hint
    /// "3h 10m", "4": a fact on the "Last night" page (AI insights step 4, design D15 A).
    case fact
    /// The same on 41 and 42 mm.
    case factSmall

    var size: CGFloat {
        switch self {
        case .mainTime: 38
        case .careTime: 28
        case .amount: 40
        case .button: 17
        case .side: 15
        case .line: 13
        case .note: 15
        case .label: 10.5
        case .hint: 10
        case .fact: 22
        case .factSmall: 20
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .mainTime, .careTime, .amount: .largeTitle
        case .button, .side: .headline
        case .line, .note: .footnote
        case .label, .hint: .caption2
        case .fact, .factSmall: .title2
        }
    }

    var usesFredoka: Bool { self == .button || self == .side }

    func font(size: CGFloat, look: Look) -> Font {
        let night = look == .night
        if usesFredoka {
            return Font.custom(night ? "Fredoka-Regular" : "Fredoka-SemiBold", fixedSize: size)
        }
        let weight: Font.Weight = switch self {
        case .mainTime, .careTime, .amount, .fact, .factSmall: night ? .medium : .bold
        case .label: night ? .semibold : .heavy
        case .hint: .semibold
        default: .regular
        }
        return Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

private struct WatchTextModifier: ViewModifier {
    let style: WatchText
    @Environment(\.watchLook) private var look
    @ScaledMetric private var size: CGFloat

    init(_ style: WatchText) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(style.font(size: size, look: look))
            .tracking(style == .label ? size * 0.07 : (style == .mainTime || style == .careTime ? -size * 0.02 : 0))
            .textCase(style == .label ? .uppercase : nil)
    }
}

extension View {
    func watchText(_ style: WatchText) -> some View {
        modifier(WatchTextModifier(style))
    }
}
