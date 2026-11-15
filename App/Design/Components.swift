import FeedingCore
import SwiftUI

/// The corner sizes from `DESIGN.md`. An inner corner is the outer corner minus the gap.
enum Radius {
    static let chip: CGFloat = 9
    static let smallButton: CGFloat = 14
    static let tile: CGFloat = 20
    static let hero: CGFloat = 26
}

/// A tinted card holding one fact: a small upper-case label, then the value. Tinted by what it
/// shows (a kind's tint, or plain `surface`). Never put a tile inside a tile.
struct Tile<Content: View>: View {
    var label: String?
    var tint: Color = Theme.surface
    var radius: CGFloat = Radius.tile
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let label {
                Text(label)
                    .feedText(.label)
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: radius))
    }
}

/// A small fact on a tile: a shape and a number ("◐ 12m", "bottle 30 ml"). Never a sentence.
/// It uses the background colour, so it reads as a hole in the tile.
struct Chip: View {
    let mark: FeedMark?
    let text: String
    /// What VoiceOver says, when the text alone would be unclear ("Left side, 12 minutes").
    var spoken: String?
    var background: Color = Theme.background

    init(_ mark: FeedMark?, _ text: String, spoken: String? = nil, background: Color = Theme.background) {
        self.mark = mark
        self.text = text
        self.spoken = spoken
        self.background = background
    }

    var body: some View {
        HStack(spacing: 5) {
            if let mark {
                FeedMarkView(mark)
            }
            Text(text)
                .feedText(.chip)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.chip))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? [mark?.spoken, text].compactMap { $0 }.joined(separator: ", "))
    }
}

/// A parent's colour, saved by name in their Member record so both phones show it.
///
/// `DESIGN.md` names the two defaults. The "Your colour" setting (build step 7) adds four more.
enum ParentColour: String, CaseIterable {
    case sunflower
    case teal

    /// Reads a saved name. "amber" is what the first builds saved for sunflower. A name from a
    /// newer app version gives nil, and the caller picks a default.
    init?(named name: String) {
        if name == "amber" {
            self = .sunflower
        } else {
            self.init(rawValue: name)
        }
    }

    var fill: Color {
        switch self {
        case .sunflower: Theme.parent1
        case .teal: Theme.parent2
        }
    }

    /// For the initial on an avatar.
    var onFill: Color {
        switch self {
        case .sunflower: Theme.onParent1
        case .teal: Theme.onParent2
        }
    }

    var tint: Color {
        switch self {
        case .sunflower: Theme.parent1Tint
        case .teal: Theme.parent2Tint
        }
    }
}

/// A parent's initial in their colour: who logged a feed, who is on each night.
struct Avatar: View {
    let name: String
    let colour: ParentColour
    @Environment(\.look) private var look
    @ScaledMetric private var size: CGFloat

    /// 30 points in the nights row, 26 in History rows.
    init(name: String, colour: ParentColour, size: CGFloat = 30) {
        self.name = name
        self.colour = colour
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Text(initial)
            // Fredoka, as names are, lighter at night; sized to the circle.
            .font(.custom(FeedTextStyle.title.fredokaName(look), fixedSize: size * 0.44))
            .fontDesign(nil)
            .foregroundStyle(colour.onFill)
            .frame(width: size, height: size)
            .background(colour.fill, in: Circle())
            .accessibilityElement()
            .accessibilityLabel(name)
    }
}
