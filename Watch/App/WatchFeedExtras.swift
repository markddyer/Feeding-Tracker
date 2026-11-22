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
    /// Finish on this watch, at this moment: the panel offers its Undo (step 3).
    var finishedAt: Date?
    /// Bottles whose amount was left out here: not asked again.
    var skipped: Set<String> = []
}

/// After Finish, Just finished or Earlier: each bottle's amount first, then the sides and kinds of
/// bottle not logged yet, and Done. It closes by itself once nothing is left to ask.
struct WatchAddToFeedScreen: View {
    let state: WatchState
    @Binding var ask: AddToFeed?
    /// Follows an Undo of Finish (its tap, the feed) after the panel has gone.
    var followUndo: (String, String) -> Void = { _, _ in }
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
            } else if feed != nil, choices.sides.isEmpty, choices.milks.isEmpty, !canUndoFinish(ask) {
                // Nothing left to ask, and no Undo to offer.
                Color.clear.onAppear { self.ask = nil }
            } else {
                choicesPage(feed: feed, choices: choices, ask: ask)
            }
        }
    }

    /// After Finish on this watch, the panel stays for its Undo even with nothing left to ask
    /// (a bottle-only feed, outside review of step 3), for as long as the phone would allow it.
    private func canUndoFinish(_ ask: AddToFeed) -> Bool {
        guard let end = ask.finishedAt, state.understands(WatchCapability.ends) else { return false }
        return Date().timeIntervalSince(end) < watchUndoWindow
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
            HStack(spacing: 6) {
                // Undo of Finish: the feed runs again, as the phone's Undo (step 3).
                if let end = ask.finishedAt, canUndoFinish(ask) {
                    WatchBigButton(title: "Undo", prominent: false, compact: true) {
                        let tap = link.sendFeedExtra(.undoFinish(feedID: ask.feedID, end: end), feedID: ask.feedID)
                        followUndo(tap, ask.feedID)
                        self.ask = nil
                    }
                    .frame(maxWidth: 76)
                    .accessibilityLabel("Undo Finish: the feed runs again")
                }
                WatchBigButton(title: "Done", compact: true) { self.ask = nil }
            }
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
        // Clear of the screen's rounded corners, as the amount screen is (22 Nov 2026).
        .padding(.horizontal, WatchPageMargins.current.side)
        .onAppear { crownFocused = true }
    }
}

// MARK: - Tonight (step 3)

/// Tonight's words, for page 3's row and the Tonight screen.
enum TonightText {
    static func name(_ member: MemberID?, in state: WatchState) -> String {
        state.members?.first { $0.id == member }?.name ?? "the other parent"
    }

    /// "You're on", "Alex's on", "Both phones alert", or the ask.
    static func short(_ tonight: WatchTonight, state: WatchState) -> String {
        let other = name(tonight.other, in: state)
        switch tonight.ask {
        case .askedOfMe: return "\(other) asks you to take it"
        case .waiting: return "Asked \(other)"
        case .declined: return "\(other) said not tonight"
        case .none: break
        }
        guard let onDuty = tonight.onDuty else { return "Both phones alert" }
        return onDuty == state.me ? "You're on" : "\(name(onDuty, in: state))'s on"
    }

    static func line(_ tonight: WatchTonight, state: WatchState) -> String {
        if tonight.ask == .askedOfMe { return "\(name(tonight.other, in: state)) asks you to take tonight" }
        guard let onDuty = tonight.onDuty else { return "Both phones alert tonight" }
        return onDuty == state.me ? "You're on tonight" : "\(name(onDuty, in: state))'s on tonight"
    }

    static func button(_ choice: WatchTonight.Choice, _ tonight: WatchTonight, state: WatchState) -> String {
        switch choice {
        case .take: tonight.onDuty == nil && tonight.ask != .askedOfMe ? "I'll take tonight" : "I'll take it"
        case .ask: "Ask \(name(tonight.other, in: state))"
        case .decline: "Not tonight"
        case .bothPhones: "Both phones tonight"
        }
    }
}

/// Tonight: who is on, and what the phone's Nights tile offers ("I'll take it", "Ask Alex",
/// "Both phones tonight", or an ask's two answers), one above the other.
struct WatchTonightScreen: View {
    let state: WatchState
    let tonight: WatchTonight
    let choose: (WatchTonight.Choice?) -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        WatchPageFrame(label: "Tonight") { metrics in
            let palette = WatchPalette.of(look)
            let choices = tonight.choices(me: state.me ?? MemberID(rawValue: ""))
            // One line on a small watch, or under it the ask's state, so three buttons still fit.
            let hint = tonight.ask == .waiting || tonight.ask == .declined
            let oneLine = metrics.small || hint
            Text(TonightText.line(tonight, state: state))
                .watchText(.note)
                .fontWeight(.semibold)
                .foregroundStyle(palette.text)
                .lineLimit(oneLine ? 1 : 2)
                .minimumScaleFactor(oneLine ? 0.65 : 0.8)
                .fixedSize(horizontal: false, vertical: !oneLine)
            if hint {
                Text(TonightText.short(tonight, state: state)).watchText(.hint).foregroundStyle(palette.textMuted)
            }
            Spacer(minLength: 2)
            // Lower buttons than usual: three of the usual height pushed Back into the screen's
            // corners (22 Nov 2026).
            let height: CGFloat = metrics.small ? 38 : 40
            VStack(spacing: metrics.gap) {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                    WatchBigButton(title: TonightText.button(choice, tonight, state: state), prominent: index == 0,
                                   compact: true, minHeight: height) { choose(choice) }
                }
                if choices.count < 3 {
                    WatchBigButton(title: "Back", prominent: false, compact: true, minHeight: height) { choose(nil) }
                }
            }
        }
    }
}
