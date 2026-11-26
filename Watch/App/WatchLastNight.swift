import FeedingCore
import SwiftUI

// The watch's fourth page, "Last night" (AI insights step 4: D4 A, D11 A; design D2 B, D8 A, D9 A,
// D15 A, D16 B, D19 A, D20 A; DESIGN.md, "Page 4"). The phone writes every word (`WatchCard`);
// the watch never calls a model, and nothing here goes on the watch face.

/// The watch's AI mark: "AI" on a small pill in the button colour (the phone's sits on the page
/// colour, which on the watch is black). It never shrinks.
struct WatchAIMark: View {
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        Text("AI")
            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
            .foregroundStyle(palette.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 6))
            .fixedSize()
            .accessibilityLabel("Picked by AI")
    }
}

/// Page 4: the three night facts, or the state the check with the phone is in. A tap anywhere
/// opens the card screen.
struct WatchLastNightPage: View {
    let card: WatchCard?
    let check: PhoneLink.CardCheck
    let open: () -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        // The mark sits only on what the AI picked: never on "Nothing logged last night."
        let showsAI = check == .current && card?.mode == .card && !(card?.facts.isEmpty ?? true)
        WatchPageFrame(label: "Last night", aiMark: showsAI) { metrics in
            let palette = WatchPalette.of(look)
            switch check {
            case .checking:
                message(icon: AnyView(ProgressView().tint(palette.textMuted)), title: "Checking with iPhone…", note: nil)
            case .unreachable:
                message(icon: AnyView(Image(systemName: "iphone").font(.system(size: 26)).foregroundStyle(palette.textMuted)),
                        title: "The card is on your iPhone", note: "Your watch can't reach it now.")
            case .takenBack:
                message(icon: nil, title: card?.why ?? "No card today.", note: nil)
            case .current:
                if let card {
                    content(card, metrics: metrics)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ card: WatchCard, metrics: WatchMetrics) -> some View {
        let palette = WatchPalette.of(look)
        if card.facts.isEmpty {
            message(icon: nil, title: "Nothing logged last night.", note: card.mode == .factsOnly ? card.why : nil)
        } else if card.mode == .card {
            Button(action: open) {
                facts(card, metrics: metrics)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.spokenPage)
            .accessibilityAddTraits(.isButton)
        } else {
            // Facts only: no card to open, and the facts at full strength (a turned-off button
            // would dim them).
            facts(card, metrics: metrics)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(card.spokenPage)
        }
    }

    private func facts(_ card: WatchCard, metrics: WatchMetrics) -> some View {
        let palette = WatchPalette.of(look)
        return VStack(alignment: .leading, spacing: 0) {
            if card.mode == .factsOnly {
                Text("Facts only today").watchText(.label).foregroundStyle(palette.textMuted)
                Spacer(minLength: metrics.gap)
            }
            ForEach(Array(card.facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 { Spacer(minLength: metrics.gap) }
                FactRow(fact: fact, small: metrics.small)
            }
            Spacer(minLength: metrics.gap)
            Text(card.mode == .factsOnly ? (card.why ?? "") : "Open the card ›")
                .watchText(.line)
                .foregroundStyle(palette.textMuted)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                // A line of words in the bottom row keeps clear of the rounded corners.
                .padding(.leading, metrics.margins.bottomLineSide)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private func message(icon: AnyView?, title: String, note: String?) -> some View {
        let palette = WatchPalette.of(look)
        return VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            if let icon { icon }
            Text(title).watchText(.note).fontWeight(.semibold).foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note).watchText(.line).foregroundStyle(palette.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One fact: its shape, the number in the `fact` style, and its words beside it, or under it when
/// they don't fit (design D15 A).
private struct FactRow: View {
    let fact: WatchCard.Fact
    let small: Bool
    @Environment(\.watchLook) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let palette = WatchPalette.of(look)
        HStack(alignment: .center, spacing: 7) {
            shape(palette).frame(width: 20, height: 18)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { number(palette); words(palette) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) { number(palette); words(palette).lineLimit(1) }
                    VStack(alignment: .leading, spacing: 0) { number(palette); words(palette) }
                }
            }
        }
    }

    @ViewBuilder
    private func number(_ palette: WatchPalette) -> some View {
        if let number = fact.number {
            Text(number).watchText(small ? .factSmall : .fact).foregroundStyle(palette.text).lineLimit(1).fixedSize()
        }
    }

    private func words(_ palette: WatchPalette) -> some View {
        Text(fact.words).watchText(.line).foregroundStyle(fact.number == nil ? palette.textMuted : palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func shape(_ palette: WatchPalette) -> some View {
        switch fact.kind {
        case .sleep:
            MoonShape().fill(palette.sleep).frame(width: 15, height: 15)
        case .feeds:
            // A plain feed shape in muted: the count holds every feed, not only bottles (design D8 A).
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 15)).foregroundStyle(palette.textMuted)
        case .nappies:
            HStack(spacing: 1) {
                DropShape().fill(palette.wee).frame(width: 8, height: 11)
                PooShape().fill(palette.poo).frame(width: 10, height: 10)
            }
        }
    }
}

/// The card screen (design D16 B): the only watch screen that scrolls. Last night's and
/// yesterday's sentences, each part with the AI mark, the patterns, yesterday's medicines, when it
/// was made, the foot, and Back.
struct WatchLastNightCardScreen: View {
    let card: WatchCard
    let timeZoneID: String
    let back: () -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.sections, id: \.title) { section in
                    HStack(spacing: 4) {
                        Text(section.title).watchText(.label).foregroundStyle(palette.textMuted)
                        WatchAIMark()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(section.lines, id: \.self) { line in
                        Text(line).watchText(.line).foregroundStyle(palette.text).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(section.patterns, id: \.self) { pattern in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Pattern").watchText(.label).foregroundStyle(palette.textMuted)
                            Text(pattern).watchText(.line).foregroundStyle(palette.text).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityElement(children: .combine)
                    }
                }
                if !card.medicines.isEmpty {
                    ForEach(card.medicines, id: \.self) { chip in
                        Text(chip).watchText(.hint).fontWeight(.heavy).foregroundStyle(palette.text)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if let made = card.madeAt {
                    Text("Made at \(made.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: TimeZone(identifier: timeZoneID) ?? .current)))")
                        .watchText(.hint).foregroundStyle(palette.textMuted)
                }
                Text("Picked by AI from your log. Every sentence and number is written by Little Log. NHS information is on your iPhone.")
                    .watchText(.hint).foregroundStyle(palette.textMuted).fixedSize(horizontal: false, vertical: true)
                WatchBigButton(title: "Back", prominent: false, compact: true, action: back)
                    .padding(.top, 4)
            }
            .padding(.horizontal, WatchPageMargins.current.side)
            .padding(.bottom, WatchPageMargins.current.bottom)
        }
        .navigationTitle("Last night")
        .navigationBarTitleDisplayMode(.inline)
    }
}
