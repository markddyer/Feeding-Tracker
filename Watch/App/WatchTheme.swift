import FeedingCore
import SwiftUI

/// The watch's colours (`DESIGN.md`, "Apple Watch"). A black background by day as well as at
/// night (the user's choice, 16 Nov 2026: Apple's advice for watches, so the screen's edge
/// disappears into the watch and nothing is bright when a wrist is lifted). By day the coral and
/// the feed colours are the phone's day colours; at night they are the phone's night colours, and
/// the letters are thinner.
struct WatchPalette {
    let background: Color
    let surface: Color
    let text: Color
    let textMuted: Color
    let primary: Color
    let onPrimary: Color
    let track: Color
    let window: Color
    let breast: Color
    let onBreast: Color
    let bottle: Color

    static let day = WatchPalette(
        background: Color(hex: 0x000000), surface: Color(hex: 0x2A1F18), text: Color(hex: 0xFFF4E2),
        textMuted: Color(hex: 0xBFA995), primary: Color(hex: 0xFF8E6E), onPrimary: Color(hex: 0x3A1A0E),
        track: Color(hex: 0x3A2C22), window: Color(hex: 0x7A4A35), breast: Color(hex: 0xF07C8F),
        onBreast: Color(hex: 0x3A1A0E), bottle: Color(hex: 0x5FA8E8))

    static let night = WatchPalette(
        background: Color(hex: 0x000000), surface: Color(hex: 0x1C1612), text: Color(hex: 0xE8D6C2),
        textMuted: Color(hex: 0x978472), primary: Color(hex: 0xB9714F), onPrimary: Color(hex: 0x120A06),
        track: Color(hex: 0x231B15), window: Color(hex: 0x4A3022), breast: Color(hex: 0xA85A68),
        onBreast: Color(hex: 0xE8D6C2), bottle: Color(hex: 0x4A7299))

    static func of(_ look: Look) -> WatchPalette { look == .night ? .night : .day }

    /// A parent's colour by its saved name, for the dot beside the other parent's feed.
    static func parent(_ name: String, look: Look) -> Color {
        let night = look == .night
        switch name {
        case "sunflower", "amber": return Color(hex: night ? 0x9C7A30 : 0xF2B33D)
        case "lavender": return Color(hex: night ? 0x68568A : 0xA78BDF)
        case "plum": return Color(hex: night ? 0x6F375F : 0x9E4F88)
        case "caramel": return Color(hex: night ? 0x79583A : 0xC99260)
        case "stone": return Color(hex: night ? 0x615D58 : 0x9A948C)
        default: return Color(hex: night ? 0x2A695E : 0x3FA796)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension EnvironmentValues {
    /// The watch's look now: day or night, from the household's hours and the phone's setting.
    @Entry var watchLook: Look = .night
}

/// The watch's text styles: the phone's (`DESIGN.md`, "Typography") at watch sizes. Fredoka for
/// button labels; SF Rounded with fixed-width digits for every time and amount. Each grows with
/// the watch's text size, and every weight drops at night.
enum WatchText {
    /// "1h 40m", "12:04".
    case mainTime
    /// "60" on the amount screen.
    case amount
    /// Big button labels.
    case button
    /// "Left", "Right".
    case side
    /// "Window 05:00".
    case line
    /// "LAST FEED".
    case label
    /// "suggested".
    case hint

    var size: CGFloat {
        switch self {
        case .mainTime: 38
        case .amount: 40
        case .button: 17
        case .side: 15
        case .line: 13
        case .label: 10.5
        case .hint: 10
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .mainTime, .amount: .largeTitle
        case .button, .side: .headline
        case .line: .footnote
        case .label, .hint: .caption2
        }
    }

    var usesFredoka: Bool { self == .button || self == .side }

    func font(size: CGFloat, look: Look) -> Font {
        let night = look == .night
        if usesFredoka {
            return Font.custom(night ? "Fredoka-Regular" : "Fredoka-SemiBold", fixedSize: size)
        }
        let weight: Font.Weight = switch self {
        case .mainTime, .amount: night ? .medium : .bold
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
            .tracking(style == .label ? size * 0.07 : (style == .mainTime ? -size * 0.02 : 0))
            .textCase(style == .label ? .uppercase : nil)
    }
}

extension View {
    func watchText(_ style: WatchText) -> some View {
        modifier(WatchTextModifier(style))
    }
}
