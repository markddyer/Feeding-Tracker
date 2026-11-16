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
    /// A small extra on the label's line, at the far end: a chart key, an avatar.
    var accessory: AnyView?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if label != nil || accessory != nil {
                HStack(alignment: .center, spacing: 8) {
                    if let label {
                        Text(label)
                            .feedText(.label)
                            .foregroundStyle(Theme.textMuted)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                    accessory
                }
            }
            content
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint, in: RoundedRectangle(cornerRadius: radius))
    }
}

/// Tiles side by side, sharing the width by the given shares and all as tall as the tallest
/// (Next side and Last feed: 1 to 1.35). At the accessibility text sizes they stack instead.
struct TileRow: Layout {
    var shares: [CGFloat]
    var spacing: CGFloat = 10

    private func widths(_ total: CGFloat, count: Int) -> [CGFloat] {
        let used = Array(shares.prefix(count)) + Array(repeating: 1, count: max(0, count - shares.count))
        let sum = used.reduce(0, +)
        let room = max(0, total - spacing * CGFloat(count - 1))
        return used.map { room * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 350
        let height = zip(subviews, widths(total, count: subviews.count))
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, count: subviews.count)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

/// Chips (or any small pieces) in a line, wrapping onto the next line when the line is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    private func rows(_ maxWidth: CGFloat, _ subviews: Subviews) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((index, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth, subviews)
        let width = rows.map { row in row.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1)) }.max() ?? 0
        let height = rows.map { $0.map(\.size.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            let height = row.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in row {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += height + spacing
        }
    }
}

/// A small round-ended button on a tile ("I'll take it"): the background colour, so it reads as
/// a hole in the tile, with a 44 point tap area.
struct PillButton: View {
    let title: String
    /// Button-sized letters, taller, filling its share of the width: for an answer a card waits
    /// for ("I'll take it" / "Not tonight").
    let large: Bool
    let action: () -> Void
    @State private var taps = 0

    init(_ title: String, large: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.large = large
        self.action = action
    }

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Text(title)
                .feedText(large ? .button : .chip)
                .lineLimit(1)
                .padding(.horizontal, large ? 18 : 12)
                .padding(.vertical, large ? 14 : 8)
                .frame(maxWidth: large ? .infinity : nil)
                .background(Theme.background, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(Theme.text)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}

/// The iOS wheel for a bottle amount (the user's choice of 16 Nov 2026, in place of the 30, 60, 90
/// and 120 ml buttons): every 5 ml from 5 to 300 ml. Amounts in SF Pro Rounded with fixed-width
/// digits (DESIGN.md).
struct AmountWheel: View {
    @Binding var ml: Int
    let label: String
    /// The form's first row, "Not set" (0), to take an amount off again.
    var allowsNotSet = false

    static let step = 5
    static let range = 5...300

    /// The amounts on the wheel, with `ml` added if it falls between them (an amount logged
    /// another way), so the wheel can show it.
    static func amounts(including ml: Int, allowsNotSet: Bool) -> [Int] {
        var amounts = Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
        if ml > 0, !amounts.contains(ml) {
            amounts.append(ml)
            amounts.sort()
        }
        return allowsNotSet ? [0] + amounts : amounts
    }

    /// Where the wheel starts: the last amount, moved onto the wheel's steps, or 60 ml.
    static func start(_ last: Int?) -> Int {
        guard let last else { return 60 }
        let onStep = Int((Double(last) / Double(step)).rounded()) * step
        return min(max(onStep, range.lowerBound), range.upperBound)
    }

    var body: some View {
        Picker(label, selection: $ml) {
            ForEach(Self.amounts(including: ml, allowsNotSet: allowsNotSet), id: \.self) { amount in
                Text(amount == 0 ? "Not set" : "\(amount) ml")
                    .feedText(.body)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 130)
        .clipped()
    }
}

/// The pressed feel from `DESIGN.md`: a quick shrink to 97% by day. At night, and with Reduce
/// Motion, nothing moves (the button's haptic does the job); it dims a little instead.
struct PressStyle: ButtonStyle {
    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let still = look == .night || reduceMotion
        configuration.label
            .scaleEffect(configuration.isPressed && !still ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed && still ? 0.8 : 1) : 0.4)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
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
            // A side with no time yet, or a bottle with no amount, shows its shape alone.
            if !text.isEmpty {
                Text(text)
                    .feedText(.chip)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.chip))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? [mark?.spoken, text].compactMap { $0 }.joined(separator: ", "))
    }
}

/// A parent's colour, saved by name in their Member record so both phones show it. Sunflower and
/// teal are the defaults; Settings offers all six ("Your colour", `DESIGN.md`).
enum ParentColour: String, CaseIterable {
    case sunflower
    case teal
    case lavender
    case plum
    case caramel
    case stone

    /// Reads a saved name. "amber" is what the first builds saved for sunflower. A name from a
    /// newer app version gives nil, and the caller picks a default.
    init?(named name: String) {
        if name == "amber" {
            self = .sunflower
        } else {
            self.init(rawValue: name)
        }
    }

    /// The name in Settings.
    var title: String { rawValue.capitalized }

    var fill: Color {
        switch self {
        case .sunflower: Theme.parent1
        case .teal: Theme.parent2
        case .lavender: Theme.lavender
        case .plum: Theme.plum
        case .caramel: Theme.caramel
        case .stone: Theme.stone
        }
    }

    /// For the initial on an avatar.
    var onFill: Color {
        switch self {
        case .sunflower: Theme.onParent1
        case .teal: Theme.onParent2
        case .lavender: Theme.onLavender
        case .plum: Theme.onPlum
        case .caramel: Theme.onCaramel
        case .stone: Theme.onStone
        }
    }

    var tint: Color {
        switch self {
        case .sunflower: Theme.parent1Tint
        case .teal: Theme.parent2Tint
        case .lavender: Theme.lavenderTint
        case .plum: Theme.plumTint
        case .caramel: Theme.caramelTint
        case .stone: Theme.stoneTint
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

/// The same circle as `Avatar`, empty: a night nobody has taken yet, with no rota.
struct EmptyAvatar: View {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat = 30) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Circle()
            .strokeBorder(Theme.textMuted.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            .frame(width: size, height: size)
    }
}
