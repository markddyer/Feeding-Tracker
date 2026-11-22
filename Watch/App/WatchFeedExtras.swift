import FeedingCore
import SwiftUI

// Step 2 of `docs/planning/11-watch-parity.md` (W-D1): the feed extras. A bottle during a feed,
// "Add to this feed" after Finish (the sides and kinds of bottle not logged, then each bottle's
// amount, as the phone's `DetailChoices`), Just finished and Earlier. Each fits the screen with no
// scrolling.

/// The feed "Add to this feed" is about, and the tap that logged or finished it (for its status).
struct AddToFeed: Equatable {
    let feedID: String
    let tap: String?
    /// Logged afterwards (Just finished or Earlier): turned down only when a feed is logged then.
    var past = false
    /// Bottles whose amount was left out here: not asked again.
    var skipped: Set<String> = []
}

/// After Finish, Just finished or Earlier: each bottle's amount first, then the sides and kinds of
/// bottle not logged yet, and Done. It closes by itself once nothing is left to ask.
struct WatchAddToFeedScreen: View {
    let state: WatchState
    @Binding var ask: AddToFeed?
    @Environment(\.watchLook) private var look
    @State private var milk: MilkKind?

    private var link: PhoneLink { PhoneLink.shared }

    var body: some View {
        if let ask {
            let feed = state.finishedFeed(ask.feedID)
            // A breastfeed asks for sides even on a bottle-only watch, as the phone's panel.
            let choices = DetailChoices(feed?.details ?? FeedDetails(), bottleOnly: state.bottleOnly && feed?.breastfeed != true)
            if let milk {
                // A new bottle: its amount, then it is sent with it.
                WatchAmountPicker(title: amountTitle(milk), start: state.startAmount(for: milk) ?? 60, noneTitle: "No amount") { ml in
                    let bottleID = UUID().uuidString
                    link.sendFeedExtra(.addBottle(feedID: ask.feedID, bottleID: bottleID, milk: milk, ml: ml), feedID: ask.feedID)
                    if let ml {
                        link.rememberAmount(ml, milk: milk)
                    } else {
                        // "No amount" means no amount: not asked again (outside review of step 2).
                        self.ask?.skipped.insert(bottleID)
                    }
                    self.milk = nil
                }
                .id(milk)
            } else if let bottle = choices.unmeasured.first(where: { !ask.skipped.contains($0.id) }) {
                WatchAmountPicker(title: amountTitle(bottle.milk), start: state.startAmount(for: bottle.milk) ?? 60) { ml in
                    if let ml {
                        link.sendFeedExtra(.amount(feedID: ask.feedID, bottleID: bottle.id, ml: ml), feedID: ask.feedID)
                        link.rememberAmount(ml, milk: bottle.milk)
                    } else {
                        self.ask?.skipped.insert(bottle.id)
                    }
                }
                .id(bottle.id)
            } else if feed != nil, choices.sides.isEmpty, choices.milks.isEmpty {
                // Nothing left to ask.
                Color.clear.onAppear { self.ask = nil }
            } else {
                choicesPage(feed: feed, choices: choices, ask: ask)
            }
        }
    }

    private func amountTitle(_ milk: MilkKind) -> String {
        "How much \(milk == .formula ? "formula" : "expressed milk")?"
    }

    private func choicesPage(feed: WatchLastFeed?, choices: DetailChoices, ask: AddToFeed) -> some View {
        WatchPageFrame(label: state.bottleOnly ? "Which bottle?" : "Add to this feed") { metrics in
            let palette = WatchPalette.of(look)
            status(feed: feed, ask: ask, palette: palette)
            Spacer(minLength: 2)
            if feed != nil {
                // One row of up to three, or two rows of two: each row filled, nothing left empty.
                let items = choices.sides.map(Choice.side) + choices.milks.map(Choice.milk)
                let rows = items.count > 3 ? [Array(items.prefix(2)), Array(items.dropFirst(2))] : [items]
                VStack(spacing: metrics.gap) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: metrics.gap) {
                            ForEach(row, id: \.self) { item in
                                choiceButton(item, ask: ask, metrics: metrics, palette: palette)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 2)
            WatchBigButton(title: "Done", compact: true) { self.ask = nil }
        }
    }

    /// "Feed 22:10 to 22:30", or why there is nothing to add to.
    @ViewBuilder
    private func status(feed: WatchLastFeed?, ask: AddToFeed, palette: WatchPalette) -> some View {
        let outcome = ask.tap.flatMap { link.result(of: $0) }
        if outcome == .refused {
            Text(ask.past ? "Not saved: a feed is already logged then" : "Not saved").watchText(.hint).foregroundStyle(palette.primary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let feed {
            HStack(spacing: 4) {
                Text("Feed \(Text(state.clock(feed.start)).foregroundStyle(palette.text)) to \(Text(state.clock(feed.end)).foregroundStyle(palette.text))")
                if ask.tap != nil, outcome == nil || outcome == .waiting {
                    Text("· waiting")
                }
            }
            .watchText(.hint)
            .foregroundStyle(palette.textMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            Text("Waiting for iPhone").watchText(.hint).foregroundStyle(palette.textMuted)
        }
    }

    enum Choice: Hashable {
        case side(BreastSide)
        case milk(MilkKind)
    }

    private func choiceButton(_ item: Choice, ask: AddToFeed, metrics: WatchMetrics, palette: WatchPalette) -> some View {
        let title = switch item {
        case .side(let side): side == .left ? "Left" : "Right"
        case .milk(let kind): kind == .formula ? "Formula" : "Expressed"
        }
        return WatchTile(title: title, metrics: metrics, wide: true) {
            switch item {
            case .side(let side):
                Image(systemName: side == .left ? "circle.lefthalf.filled" : "circle.righthalf.filled")
                    .foregroundStyle(palette.breast)
            case .milk:
                BottleShape().fill(palette.bottle).frame(width: 16, height: 16)
            }
        } action: {
            switch item {
            case .side(let side): link.sendFeedExtra(.addSide(feedID: ask.feedID, side: side), feedID: ask.feedID)
            case .milk(let kind): milk = kind
            }
        }
        .accessibilityLabel(accessibility(item))
    }

    private func accessibility(_ item: Choice) -> String {
        switch item {
        case .side(let side): "Add the \(side == .left ? "left" : "right") side"
        case .milk(let kind): "Add a \(kind == .formula ? "formula" : "expressed milk") bottle"
        }
    }
}

/// A bottle during this parent's feed: which milk. Its amount is asked after Finish.
struct WatchBottleChoiceScreen: View {
    let done: (MilkKind?) -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        WatchPageFrame(label: "Which bottle?") { metrics in
            let palette = WatchPalette.of(look)
            Spacer(minLength: 2)
            HStack(spacing: metrics.gap) {
                ForEach([MilkKind.formula, .expressed], id: \.self) { milk in
                    WatchTile(title: milk == .formula ? "Formula" : "Expressed", metrics: metrics, wide: true) {
                        BottleShape().fill(palette.bottle).frame(width: 16, height: 16)
                    } action: { done(milk) }
                    .accessibilityLabel(milk == .formula ? "Add a formula bottle" : "Add an expressed milk bottle")
                }
            }
            Spacer(minLength: 2)
            WatchBigButton(title: "Back", prominent: false, compact: true) { done(nil) }
        }
    }
}

/// "Just finished": started about 10, 20, 30 or 45 minutes ago, as the phone's menu.
struct WatchJustFinishedScreen: View {
    let done: (Int?) -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        WatchPageFrame(label: "Started about") { metrics in
            let palette = WatchPalette.of(look)
            Spacer(minLength: 2)
            VStack(spacing: metrics.gap) {
                ForEach([[10, 20], [30, 45]], id: \.self) { row in
                    HStack(spacing: metrics.gap) {
                        ForEach(row, id: \.self) { minutes in
                            Button { done(minutes) } label: {
                                Text("\(minutes) min ago")
                                    .watchText(.button)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: metrics.shortTileHeight)
                                    .foregroundStyle(palette.text)
                                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                                    .contentShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Started about \(minutes) minutes ago")
                        }
                    }
                }
            }
            Spacer(minLength: 2)
            WatchBigButton(title: "Back", prominent: false, compact: true) { done(nil) }
        }
    }
}

/// "Earlier": when the feed started, on the Digital Crown in 5-minute steps, back to 12 hours.
/// Turning saves nothing; Save does.
struct WatchEarlierFeedScreen: View {
    let state: WatchState
    /// When the screen opened: the times count back from here.
    let opened: Date
    let done: (Date?) -> Void
    @State private var minutesBack: Double = 30
    @FocusState private var crownFocused: Bool
    @Environment(\.watchLook) private var look

    private var start: Date { opened.addingTimeInterval(-minutesBack * 60) }
    private var most: Double { watchEarliestFeed / 60 }

    var body: some View {
        let palette = WatchPalette.of(look)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Feed started").watchText(.label).foregroundStyle(palette.textMuted)
                Spacer(minLength: 4)
                Text(GlanceText.elapsed(minutesBack * 60) + " ago").watchText(.hint).foregroundStyle(palette.textMuted)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.clock(start)).watchText(.amount).lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText(value: minutesBack))
                Spacer(minLength: 0)
                Image(systemName: "digitalcrown.horizontal.arrow.counterclockwise")
                    .foregroundStyle(palette.primary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.primary, lineWidth: 2))
            .focusable()
            .focused($crownFocused)
            // Turning the crown up goes further back.
            .digitalCrownRotation($minutesBack, from: 5, through: most, by: 5, sensitivity: .low, isContinuous: false,
                                  isHapticFeedbackEnabled: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Feed started")
            .accessibilityValue("\(state.clock(start)), \(GlanceText.spokenElapsed(minutesBack * 60)) ago")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: minutesBack = min(most, minutesBack + 5)
                case .decrement: minutesBack = max(5, minutesBack - 5)
                @unknown default: break
                }
            }
            HStack(spacing: 8) {
                AmountStepButton(symbol: "minus", label: "5 minutes earlier", enabled: minutesBack < most) {
                    minutesBack = min(most, minutesBack + 5)
                }
                AmountStepButton(symbol: "plus", label: "5 minutes later", enabled: minutesBack > 5) {
                    minutesBack = max(5, minutesBack - 5)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                WatchBigButton(title: "Back", prominent: false, compact: true) { done(nil) }
                    .frame(maxWidth: 76)
                // The start counts back from when the screen opened; at most 12 hours before the
                // Save itself, which is what the phone checks (outside review of step 2).
                WatchBigButton(title: "Save", doubleTap: true, compact: true) {
                    done(max(start, Date().addingTimeInterval(-watchEarliestFeed)))
                }
                    .accessibilityLabel("Save a feed that started at \(state.clock(start))")
            }
        }
        .onAppear { crownFocused = true }
    }
}
