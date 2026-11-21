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
    /// A crescent moon.
    case sleep
    /// One drop, a soft swirl, or both side by side (a nappy).
    case wee
    case poo
    case weeAndPoo
    /// A spoon.
    case medicine
    /// A line going up.
    case growth
    /// A four-point sparkle: one of the baby's firsts (design review D26).
    case first
    /// A bath tub (X5, design D6), in its own water-blue.
    case bath

    /// The nappy's shape: wee, poo or both. A dry nappy shows the drop in muted colour.
    static func nappy(wee: Bool, poo: Bool) -> FeedMark {
        switch (wee, poo) {
        case (true, true): .weeAndPoo
        case (false, true): .poo
        default: .wee
        }
    }

    /// The deep shade for small shapes, readable on the light tiles. At night it is the plain
    /// night colour.
    var colour: Color {
        switch self {
        case .side: Theme.breastMark
        case .bottle: Theme.bottleMark
        case .pump: Theme.pumpMark
        case .sleep: Theme.sleepMark
        case .wee, .weeAndPoo: Theme.weeMark
        case .poo: Theme.pooMark
        case .medicine, .growth, .first: Theme.textMuted
        case .bath: Theme.bathMark
        }
    }

    /// The tile or row colour for this kind.
    var tint: Color {
        switch self {
        case .side: Theme.breastTint
        case .bottle: Theme.bottleTint
        case .pump: Theme.pumpTint
        case .sleep: Theme.sleepTint
        case .wee, .poo, .weeAndPoo: Theme.nappyTint
        case .medicine, .growth, .first: Theme.surface
        case .bath: Theme.bathTint
        }
    }

    /// What VoiceOver says for the shape on its own.
    var spoken: String {
        switch self {
        case .side(.left): "Left side"
        case .side(.right): "Right side"
        case .bottle: "Bottle"
        case .pump: "Pumping"
        case .sleep: "Sleep"
        case .wee: "Wee"
        case .poo: "Poo"
        case .weeAndPoo: "Wee and poo"
        case .medicine: "Medicine"
        case .growth: "Growth"
        case .first: "First"
        case .bath: "Bath"
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
            case .sleep:
                MoonShape()
            case .wee:
                DropShape()
            case .poo:
                PooShape()
            case .weeAndPoo:
                // Two shapes in the space of one and a half, each in its own colour.
                HStack(spacing: -size * 0.2) {
                    DropShape().foregroundStyle(colour ?? Theme.weeMark)
                    PooShape().foregroundStyle(colour ?? Theme.pooMark)
                }
            case .medicine:
                SpoonShape()
            case .growth:
                GrowthShape()
            case .first:
                SparkleShape()
            case .bath:
                TubShape()
            }
        }
        .foregroundStyle(colour ?? mark.colour)
        .frame(width: mark == .weeAndPoo ? size * 1.8 : size, height: size)
        .accessibilityElement()
        .accessibilityLabel(mark.spoken)
    }
}

// The bottle and drops shapes are in `Shared/FeedShapes.swift`, shared with the watch.
