import FeedingCore
import SwiftUI

/// The text styles from `DESIGN.md`, "Typography".
///
/// Two typefaces, each with one job. Fredoka (bundled, SIL Open Font License: see
/// `App/Fonts/Fredoka-OFL.txt`) for headings, names, tile values and button labels. SF Pro
/// Rounded for everything else and for every number, always with fixed-width digits, because
/// Fredoka's digits are not all the same width and a ticking time would wobble. Never set a
/// number in Fredoka.
///
/// Every style scales with Dynamic Type, and every weight drops at night, so fewer pixels light
/// up in a dark room.
enum FeedTextStyle: CaseIterable {
    /// "2h 05m", "12:04": the biggest thing on the home screen.
    case mainTime
    /// Screen titles and the baby's name.
    case title
    /// Big button labels.
    case button
    /// A tile's value, such as "Left".
    case tileValue
    /// "Today", "Yesterday" in History.
    case dayHeading
    /// The totals under the chart ("8", "240").
    case total
    case body
    /// Smaller body text and bar labels.
    case subheadline
    /// Chips ("12m", "30 ml").
    case chip
    /// A tile's small upper-case label ("NEXT SIDE").
    case label

    /// The bundled font's family name.
    static let fredoka = "Fredoka"

    var usesFredoka: Bool {
        switch self {
        case .title, .button, .tileValue, .dayHeading: true
        case .mainTime, .total, .body, .subheadline, .chip, .label: false
        }
    }

    /// The size at the default Dynamic Type size, in points.
    var size: CGFloat {
        switch self {
        case .mainTime: 38
        case .title: 26
        case .button: 20
        case .tileValue: 19
        case .dayHeading: 18
        case .total: 22
        case .body: 17
        case .subheadline: 15
        case .chip: 12.5
        case .label: 11
        }
    }

    /// The Dynamic Type style it grows with.
    var textStyle: Font.TextStyle {
        switch self {
        case .mainTime: .largeTitle
        case .title: .title
        case .button, .tileValue: .title3
        case .dayHeading: .headline
        case .total: .title2
        case .body: .body
        case .subheadline: .subheadline
        case .chip: .caption
        case .label: .caption2
        }
    }

    func weight(_ look: Look) -> Font.Weight {
        let night = look == .night
        switch self {
        case .mainTime, .total: return night ? .medium : .bold
        case .title, .button, .tileValue, .dayHeading: return night ? .regular : .semibold
        case .body, .subheadline: return .regular
        case .chip, .label: return night ? .semibold : .heavy
        }
    }

    /// Letter spacing, as a share of the size.
    var tracking: CGFloat {
        switch self {
        case .mainTime: -0.02
        case .label: 0.07
        default: 0
        }
    }

    /// The PostScript name of the Fredoka weight to use. Fredoka is one variable font file with
    /// named weights; naming the weight picks it exactly.
    func fredokaName(_ look: Look) -> String {
        switch weight(look) {
        case .regular: "Fredoka-Regular"
        case .medium: "Fredoka-Medium"
        case .bold, .heavy, .black: "Fredoka-Bold"
        case .ultraLight, .thin, .light: "Fredoka-Light"
        default: "Fredoka-SemiBold"
        }
    }

    func font(size: CGFloat, look: Look) -> Font {
        if usesFredoka {
            Font.custom(fredokaName(look), fixedSize: size)
        } else {
            Font.system(size: size, weight: weight(look), design: .rounded).monospacedDigit()
        }
    }
}

/// Applies a `FeedTextStyle`, sized for Dynamic Type and weighted for the look on screen.
struct FeedTextModifier: ViewModifier {
    let style: FeedTextStyle
    @Environment(\.look) private var look
    @ScaledMetric private var size: CGFloat

    init(_ style: FeedTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(style.font(size: size, look: look))
            // The app sets `.fontDesign(.rounded)` for all text, and that swaps a custom font
            // for SF Pro Rounded, so it is taken off for Fredoka.
            .fontDesign(style.usesFredoka ? nil : .rounded)
            .tracking(style.tracking * size)
            .textCase(style == .label ? .uppercase : nil)
    }
}

extension View {
    /// Sets text in one of the styles from `DESIGN.md`.
    func feedText(_ style: FeedTextStyle) -> some View {
        modifier(FeedTextModifier(style))
    }
}
