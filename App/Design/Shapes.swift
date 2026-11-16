import FeedingCore
import SwiftUI

/// What a shape stands for: each kind of feed has a shape as well as a colour, so it reads at
/// night and without colour (`DESIGN.md`, "Shapes").
enum FeedMark: Hashable {
    /// A half-moon whose filled half is the side.
    case side(BreastSide)
    /// A tall baby bottle.
    case bottle
    /// Two drops.
    case pump

    /// The deep shade for small shapes, readable on the light tiles. At night it is the plain
    /// night colour.
    var colour: Color {
        switch self {
        case .side: Theme.breastMark
        case .bottle: Theme.bottleMark
        case .pump: Theme.pumpMark
        }
    }

    /// The tile or row colour for this kind.
    var tint: Color {
        switch self {
        case .side: Theme.breastTint
        case .bottle: Theme.bottleTint
        case .pump: Theme.pumpTint
        }
    }

    /// What VoiceOver says for the shape on its own.
    var spoken: String {
        switch self {
        case .side(.left): "Left side"
        case .side(.right): "Right side"
        case .bottle: "Bottle"
        case .pump: "Pumping"
        }
    }
}

/// A feed shape, drawn in its kind's colour unless told otherwise (the selected side button
/// draws it in the button's text colour). Grows with Dynamic Type.
struct FeedMarkView: View {
    let mark: FeedMark
    var colour: Color?
    @ScaledMetric private var size: CGFloat

    init(_ mark: FeedMark, size: CGFloat = 15, relativeTo textStyle: Font.TextStyle = .caption, colour: Color? = nil) {
        self.mark = mark
        self.colour = colour
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    var body: some View {
        Group {
            switch mark {
            case .side(let side):
                // Apple's own half-filled circle: `circle.lefthalf.filled` fills the left half.
                Image(systemName: side == .left ? "circle.lefthalf.filled" : "circle.righthalf.filled")
                    .font(.system(size: size * 0.92, weight: .semibold))
            case .bottle:
                BottleShape()
            case .pump:
                DropsShape()
            }
        }
        .foregroundStyle(colour ?? mark.colour)
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(mark.spoken)
    }
}

// The bottle and drops shapes are in `Shared/FeedShapes.swift`, shared with the watch.
