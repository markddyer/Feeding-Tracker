import FeedingCore
import SwiftUI
import WatchKit

// The watch's pages, step 1 of `docs/planning/11-watch-parity.md` (the parents' choices of
// 21 Nov 2026, `designs/watch-parity-20261121/round5-square.html`): every main page fits the
// screen with no scrolling, on 42 mm and on 49 mm. The big number has its main button beside it
// (round on page 1, oblong on page 2); the buttons under it are about square, and spare room is
// spread between the rows, never stretching the buttons. Page 3 (Bath and medicine) may scroll
// when the household has many medicines (the parents' choice B).

/// Sizes for the screen a page has.
struct WatchMetrics {
    let size: CGSize

    /// 41 and 42 mm (and smaller): a little smaller type and buttons.
    var small: Bool { size.width < 180 }
    var margins: WatchPageMargins { WatchPageMargins(small: small) }
    var round: CGFloat { small ? 48 : 54 }
    var gap: CGFloat { small ? 5 : 6 }
    /// A button in a row of three, about square.
    var tileWidth: CGFloat { ((size.width - 2 * gap) / 3).rounded(.down) }
    var tileHeight: CGFloat { (tileWidth * 0.88).rounded() }
    /// Page 1's small buttons under the bar: shorter, as Start and the bar matter most there and
    /// the 42 mm screen has no room for square ones (21 Nov 2026).
    var shortTileHeight: CGFloat { max(40, (tileWidth * 0.68).rounded()) }
}

/// How far a page keeps from the screen's edges. The bottom row must sit inside the curve of the
/// screen's rounded corners, which is a long, soft curve, not a quarter circle: on the 49 mm Ultra
/// it starts about 67 pt up the side, and on 42 mm about 47 pt (measured from the simulators' screen
/// masks, `xcrun simctl io <watch> screenshot --mask=alpha`, 22 Nov 2026). With these margins a
/// tile's or a wide button's corner keeps about 3 pt inside the curve; 6 pt at the sides and 18 pt
/// at the bottom let the curve cut "Just finished" on the Ultra (Parent A, 22 Nov 2026). The room
/// the system keeps free at the bottom is not used: it left an unused band on 42 mm.
struct WatchPageMargins {
    let small: Bool

    var side: CGFloat { small ? 7 : 8 }
    var bottom: CGFloat { small ? 14 : 24 }
    /// How far the page reaches up into the room kept under the clock.
    var pullUp: CGFloat { small ? 8 : 12 }
    /// More room at the sides for a line of words in the bottom row, whose letters would
    /// otherwise reach into the curve.
    var bottomLineSide: CGFloat { small ? 5 : 6 }

    /// Room kept at the right of a first line that is level with the clock.
    var clockRoom: CGFloat { small ? 52 : 56 }

    /// This watch's, for a screen that isn't a `WatchPageFrame`.
    static var current: WatchPageMargins { WatchPageMargins(small: WKInterfaceDevice.current().screenBounds.width < 190) }
}

/// A page: fills the screen it has, with its rows from the top and spare room spread between them.
struct WatchPageFrame<Content: View>: View {
    let label: String
    @ViewBuilder let content: (WatchMetrics) -> Content
    @Environment(\.watchLook) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { proxy in
            let small = proxy.size.width < 190
            let margins = WatchPageMargins(small: small)
            if typeSize.isAccessibilitySize {
                // At the largest text sizes the words grow rather than being cut off, so the page
                // may scroll, as Apple asks.
                let width = max(0, proxy.size.width - 2 * margins.side)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) { content(WatchMetrics(size: CGSize(width: width, height: max(0, proxy.size.height - margins.bottom)))) }
                        .frame(width: width, alignment: .leading)
                        .padding(.bottom, margins.bottom)
                }
                .padding(.horizontal, margins.side)
            } else {
                // The page starts a little way up into the room the system keeps under the clock:
                // the label sits beside the clock, so most of that room was an empty band (Parent A,
                // on the Ultra, 22 Nov 2026). Moved, not laid out there, as the system says that
                // room is none when a page ignores it.
                let inner = CGSize(width: max(0, proxy.size.width - 2 * margins.side),
                                   height: max(0, proxy.size.height + margins.pullUp - margins.bottom))
                VStack(alignment: .leading, spacing: 0) {
                    content(WatchMetrics(size: inner))
                }
                .frame(width: inner.width, height: inner.height, alignment: .top)
                .padding(.horizontal, margins.side)
                .offset(y: -margins.pullUp)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        // No room kept for a large title: the label sits beside the clock, and the page starts just
        // under it (a large gap showed on the Ultra, 21 Nov 2026).
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text(label)
                    .watchText(.label)
                    .foregroundStyle(WatchPalette.of(look).textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// The big number and, beside it, the page's main button.
struct WatchHero<Number: View, Action: View>: View {
    @ViewBuilder let number: () -> Number
    @ViewBuilder let button: () -> Action

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            number()
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            button()
        }
        // Its full height first: the rows under it share what is left. Without this the page gave
        // it less, and the big number shrank to fit.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// "3h 04m" with "ago, at 18:36" under it.
struct WatchBigNumber: View {
    let text: String
    let note: Text
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .watchText(.mainTime)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            note
                .watchText(.note)
                .foregroundStyle(palette.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// The round main button on page 1: Start (or the milk used last) and Finish. The double tap
/// presses it.
struct WatchRoundButton: View {
    let title: String
    let metrics: WatchMetrics
    var systemImage: String?
    var bottle = false
    var doubleTap = true
    let action: () -> Void
    @State private var taps = 0
    @Environment(\.watchLook) private var look
    @Environment(\.watchDoubleTapAllowed) private var doubleTapAllowed

    var body: some View {
        let palette = WatchPalette.of(look)
        SwiftUI.Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 1) {
                if bottle {
                    BottleShape().fill(palette.onPrimary).frame(width: 16, height: 16)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).watchText(.side).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 3)
            .foregroundStyle(palette.onPrimary)
            .frame(width: metrics.round, height: metrics.round)
            .background(palette.primary, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction, isEnabled: doubleTap && doubleTapAllowed)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }
}

/// A button in a row of three, about square: a shape above its word.
struct WatchTile<Mark: View>: View {
    let title: String
    let metrics: WatchMetrics
    /// Shorter than square, for page 1's small buttons.
    var short = false
    /// The width of the row: a tile alone in it, so no space is left unused.
    var wide = false
    /// Another width than a third of the row.
    var width: CGFloat?
    var selected = false
    var selectedColour: Color?
    var hint: String?
    @ViewBuilder let mark: () -> Mark
    let action: () -> Void
    @State private var taps = 0
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 2) {
                mark().frame(height: 17)
                // One line in a short tile, so its words get smaller rather than cut ("Just finis…"
                // on 42 mm, 22 Nov 2026).
                Text(title).watchText(.side).lineLimit(short ? 1 : 2).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                if let hint {
                    Text(hint).watchText(.hint).foregroundStyle(palette.textMuted).lineLimit(1)
                }
            }
            // A little room at the sides, so the words of a tile in the bottom row's corner stay
            // inside the screen's curve ("Just finished" lost its J on the Ultra, 22 Nov 2026).
            .padding(.horizontal, 3)
            .frame(width: wide ? nil : width ?? metrics.tileWidth, height: short ? metrics.shortTileHeight : metrics.tileHeight)
            .frame(maxWidth: wide ? .infinity : nil)
            .foregroundStyle(selected ? palette.onBreast : palette.text)
            .background(selected ? (selectedColour ?? palette.breast) : palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row of up to three tiles; fewer keep the same size, from the left.
struct WatchTileRow<Content: View>: View {
    let metrics: WatchMetrics
    var short = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: metrics.gap) {
            content()
            Spacer(minLength: 0)
        }
        .frame(height: short ? metrics.shortTileHeight : metrics.tileHeight)
    }
}

// MARK: - Page 1, Feeds

/// No feed running: the time since the last feed with Start beside it, the bar's words and the
/// bar, then the small buttons (Pumping in step 1; Just finished and Earlier come in step 2).
struct WatchIdlePage: View {
    let state: WatchState
    let now: Date
    let waiting: Bool
    /// Just finished and Earlier (step 2), when the phone understands them.
    var justFinished: (() -> Void)?
    var earlier: (() -> Void)?
    let start: (MilkKind?) -> Void
    /// A bottle-only watch's Start: "Formula or expressed?" (and "Breastfeed (Sam)" when named),
    /// never assuming the milk (Parent A, 21 Nov 2026).
    let askMilk: () -> Void
    let pumping: () -> Void

    var body: some View {
        WatchPageFrame(label: "Last feed") { metrics in
            let palette = WatchPalette.of(state.look(at: now))
            WatchHero {
                if let last = state.lastFeedStart {
                    WatchBigNumber(text: GlanceText.elapsed(now.timeIntervalSince(last)),
                                   note: Text("ago, at \(Text(state.clock(last)).foregroundStyle(palette.text))"))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Last feed \(GlanceText.spokenElapsed(now.timeIntervalSince(last))) ago")
                } else {
                    Text("No feeds logged yet").watchText(.line).foregroundStyle(palette.textMuted)
                }
            } button: {
                if state.bottleOnly {
                    WatchRoundButton(title: "Start", metrics: metrics, bottle: true) { askMilk() }
                        .accessibilityLabel("Start feed, then choose the milk")
                } else {
                    WatchRoundButton(title: "Start", metrics: metrics, bottle: true) { start(nil) }
                        .accessibilityLabel("Start feed")
                }
            }
            Spacer(minLength: 3)
            if let steps = state.windowSteps(at: now) {
                // One line on a small watch, so page 1 fits; two on a large one, except while
                // "Sends when your phone is near" shows: then the buttons fell into the corners.
                let oneLine = metrics.small || waiting
                let line = steps.line(state.clock, short: oneLine)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Text(line.main).fontWeight(.semibold).foregroundStyle(palette.text))\(Text(line.more).foregroundStyle(palette.textMuted))")
                        .watchText(.note)
                        .lineLimit(oneLine ? 1 : 2)
                        .minimumScaleFactor(oneLine ? 0.7 : 0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    // No times under the bar: the line above it says when the alert is, and the
                    // larger words need the room (Parent A, 21 Nov 2026).
                    WatchWindowTrack(steps: steps, palette: palette, height: metrics.small ? 10 : 12)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(steps.spoken(state.clock))
            }
            if waiting { WaitingLine() }
            Spacer(minLength: 3)
            // On a small watch "Just finished" is a little wider than the two beside it, so it fits
            // whole with room kept from the screen's corner ("Just finis…" on 42 mm, 22 Nov 2026).
            let three = justFinished != nil && earlier != nil && state.understands(WatchCapability.pump)
            let narrow: CGFloat? = metrics.small && three ? metrics.tileWidth - 4 : nil
            let wider = narrow.map { metrics.size.width - 2 * $0 - 2 * metrics.gap }
            WatchTileRow(metrics: metrics, short: true) {
                if let justFinished {
                    WatchTile(title: "Just finished", metrics: metrics, short: true, width: wider) {
                        Image(systemName: "checkmark").foregroundStyle(palette.textMuted)
                    } action: { justFinished() }
                    .accessibilityLabel("Log a feed that just finished")
                }
                if let earlier {
                    WatchTile(title: "Earlier", metrics: metrics, short: true, width: narrow) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(palette.textMuted)
                    } action: { earlier() }
                    .accessibilityLabel("Log an earlier feed")
                }
                if state.understands(WatchCapability.pump) {
                    // The width of the row when it is alone (a phone without step 2).
                    WatchTile(title: "Pumping", metrics: metrics, short: true, wide: justFinished == nil && earlier == nil, width: narrow) {
                        DropsShape().fill(palette.textMuted).frame(width: 15, height: 15)
                    } action: { pumping() }
                }
            }
        }
    }
}

/// This parent's feed running: its time with Finish beside it, Left and Right (not on a
/// bottle-only watch, unless it is a breastfeed), and Stop · discard under them.
struct WatchRunningPage: View {
    let state: WatchState
    let feed: WatchFeed
    let waiting: Bool
    /// Bottle, beside Left and Right while the feed has none (step 2), when the phone understands it.
    var addBottle: (() -> Void)?
    let send: (WatchCommand) -> Void
    @State private var discarding = false
    @Environment(\.watchLook) private var look

    var body: some View {
        WatchPageFrame(label: "Your feed") { metrics in
            let palette = WatchPalette.of(look)
            WatchHero {
                VStack(alignment: .leading, spacing: 0) {
                    Text(timerInterval: feed.startedAt...Date.distantFuture, countsDown: false)
                        .watchText(.mainTime)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(startedNote(palette))
                        .watchText(.note)
                        .foregroundStyle(palette.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } button: {
                WatchRoundButton(title: "Finish", metrics: metrics, systemImage: "stopwatch") {
                    send(.finish(feedID: feed.id))
                }
                .accessibilityLabel("Finish feed")
            }
            if waiting { WaitingLine() }
            Spacer(minLength: 3)
            if !state.bottleOnly || feed.breastfeed == true {
                WatchTileRow(metrics: metrics) {
                    ForEach(BreastSide.allCases, id: \.self) { side in
                        let title = side == .left ? "Left" : "Right"
                        WatchTile(title: title, metrics: metrics, selected: feed.side == side,
                                  hint: feed.side == nil && state.nextSide == side ? "suggested" : nil) {
                            Image(systemName: side == .left ? "circle.lefthalf.filled" : "circle.righthalf.filled")
                        } action: {
                            guard feed.side != side else { return }
                            send(.switchSide(feedID: feed.id, side: side))
                        }
                        .accessibilityLabel(feed.side == nil && state.nextSide == side ? "\(title), suggested" : title)
                    }
                    // Goes once a bottle is added, as on the phone; more after Finish.
                    if let addBottle, feed.bottles.isEmpty {
                        WatchTile(title: "Bottle", metrics: metrics) {
                            BottleShape().fill(palette.bottle).frame(width: 16, height: 16)
                        } action: { addBottle() }
                        .accessibilityLabel("Add a bottle to this feed")
                    }
                }
            }
            Spacer(minLength: 3)
            // For a feed started by mistake (a stray double tap): asks first, as on the phone.
            WatchBigButton(title: "Stop · discard", prominent: false, compact: true) { discarding = true }
                .accessibilityLabel("Stop and discard this feed")
        }
        .confirmationDialog("Remove this feed?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Remove feed", role: .destructive) { send(.discard(feedID: feed.id)) }
        } message: {
            Text("It will not be logged. To end a real feed, tap Finish.")
        }
    }

    private func startedNote(_ palette: WatchPalette) -> AttributedString {
        var note = AttributedString("started ")
        var time = AttributedString(state.clock(feed.startedAt))
        time.foregroundColor = palette.text
        note += time
        if let milk = feed.bottles.first?.milk {
            note += AttributedString(milk == .formula ? " · formula" : " · expressed")
        }
        return note
    }
}

/// The other parent's feed: its time, what it has so far in an outlined box, and a soft "Finish for
/// Sam" (normal-sized, so it isn't pressed by mistake; no double tap).
struct WatchOthersFeedPage: View {
    let state: WatchState
    let feed: WatchFeed
    let waiting: Bool
    let finish: () -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        WatchPageFrame(label: "\(feed.byName)'s feed") { metrics in
            let palette = WatchPalette.of(look)
            HStack(spacing: 6) {
                Circle().fill(WatchPalette.parent(feed.byColour, look: look)).frame(width: 10, height: 10)
                Text(timerInterval: feed.startedAt...Date.distantFuture, countsDown: false)
                    .watchText(.mainTime)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Text("started \(Text(state.clock(feed.startedAt)).foregroundStyle(palette.text))")
                .watchText(.line)
                .foregroundStyle(palette.textMuted)
            if waiting { WaitingLine() }
            Spacer(minLength: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(sofar).watchText(.line).fontWeight(.semibold).foregroundStyle(palette.text)
                Text("\(feed.byName) adds the sides and bottles.").watchText(.hint).foregroundStyle(palette.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.surface, lineWidth: 1.5))
            Spacer(minLength: 3)
            WatchBigButton(title: "Finish for \(feed.byName)", prominent: false, compact: true, action: finish)
                .accessibilityHint("\(feed.byName) adds the sides and bottles. Their phone offers to add them after.")
        }
    }

    private var sofar: String {
        if let side = feed.side { return side == .left ? "Left side now" : "Right side now" }
        if let milk = feed.bottles.first?.milk { return milk == .formula ? "Formula bottle" : "Expressed milk bottle" }
        return "No side yet"
    }
}

// MARK: - Page 2, Sleep and nappy

/// The sleep time with an oblong Fell asleep or Woke up beside it, then Wee, Poo and Both, then the
/// last nappy (with its details, or "Add details" for a poo without them).
struct WatchCarePage: View {
    let state: WatchState
    let now: Date
    let waiting: Bool
    let sleepTap: () -> Void
    let nappy: (Bool, Bool) -> Void
    let addDetails: (String) -> Void
    @State private var sleepTaps = 0
    @Environment(\.watchLook) private var look
    @Environment(\.watchDoubleTapAllowed) private var doubleTapAllowed

    var body: some View {
        let asleep = state.sleep?.asleep == true
        WatchPageFrame(label: CareText.sleepLabel(state.sleep)) { metrics in
            let palette = WatchPalette.of(look)
            WatchHero {
                if let sleep = state.sleep {
                    WatchBigNumber(text: GlanceText.elapsed(now.timeIntervalSince(sleep.since)),
                                   note: Text("since \(Text(state.clock(sleep.since)).foregroundStyle(palette.text))"))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(CareText.spokenSleep(sleep, now: now))
                } else {
                    Text("No sleep logged yet").watchText(.line).foregroundStyle(palette.textMuted)
                }
            } button: {
                Button {
                    sleepTaps += 1
                    sleepTap()
                } label: {
                    VStack(spacing: 2) {
                        if asleep {
                            Image(systemName: "sun.max.fill").foregroundStyle(palette.wee)
                        } else {
                            MoonShape().fill(palette.sleep).frame(width: 16, height: 16)
                        }
                        Text(asleep ? "Woke up" : "Fell asleep").watchText(.side).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: metrics.round * 0.85)
                    .foregroundStyle(palette.text)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .handGestureShortcut(.primaryAction, isEnabled: doubleTapAllowed)
                .sensoryFeedback(.impact(weight: .medium), trigger: sleepTaps)
                .accessibilityLabel(asleep ? "Woke up, log it now" : "Fell asleep, log it now")
            }
            if waiting { WaitingLine() }
            Spacer(minLength: 3)
            WatchTileRow(metrics: metrics) {
                WatchTile(title: "Wee", metrics: metrics) {
                    NappyMark(wee: true, poo: false, size: 16, weeColour: palette.wee, pooColour: palette.poo)
                } action: { nappy(true, false) }
                    .accessibilityLabel("Log a wet nappy")
                WatchTile(title: "Poo", metrics: metrics) {
                    NappyMark(wee: false, poo: true, size: 16, weeColour: palette.wee, pooColour: palette.poo)
                } action: { nappy(false, true) }
                    .accessibilityLabel("Log a dirty nappy")
                WatchTile(title: "Both", metrics: metrics) {
                    NappyMark(wee: true, poo: true, size: 14, weeColour: palette.wee, pooColour: palette.poo)
                } action: { nappy(true, true) }
                    .accessibilityLabel("Log a wet and dirty nappy")
            }
            Spacer(minLength: 3)
            // In from both sides, as its words would reach into the screen's corners (Parent A, on
            // the Ultra, 22 Nov 2026).
            nappyLine(palette, metrics: metrics)
                .padding(.horizontal, metrics.margins.bottomLineSide)
        }
    }

    @ViewBuilder
    private func nappyLine(_ palette: WatchPalette, metrics: WatchMetrics) -> some View {
        // The size of page 1's notes on a large watch, to read at a glance (Parent A, 22 Nov
        // 2026); a small one keeps the smaller size, so "Add details ›" still fits beside it.
        let style: WatchText = metrics.small ? .line : .note
        if let last = state.lastNappy {
            let details = [last.colour.map(CareText.colourName), last.consistency.map(CareText.consistencyName)]
                .compactMap { $0 }.joined(separator: ", ")
            let kind = last.wee && last.poo ? "wee and poo" : last.poo ? "poo" : "wee"
            let line = Text("Nappy \(Text(CareText.ago(last.at, now: now)).foregroundStyle(palette.text)) · \(details.isEmpty ? kind : details)")
            if last.poo, last.colour == nil, last.consistency == nil, state.understands(WatchCapability.pooDetails) {
                Button { addDetails(last.id) } label: {
                    HStack(spacing: 4) {
                        Text("Nappy \(Text(CareText.ago(last.at, now: now)).foregroundStyle(palette.text))")
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 2)
                        Text("Add details ›").foregroundStyle(palette.primary).lineLimit(1).layoutPriority(1)
                    }
                }
                .buttonStyle(.plain)
                .watchText(style)
                .foregroundStyle(palette.textMuted)
            } else {
                line.watchText(style).foregroundStyle(palette.textMuted).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityLabel(CareText.spokenNappy(last, now: now))
            }
        } else {
            Text("No nappy logged yet").watchText(style).foregroundStyle(palette.textMuted)
        }
    }
}

// MARK: - Page 3, Bath and medicine

/// Bath and the medicines, as rows that always fit (the parents' choice A, 21 Nov 2026): one
/// medicine has its own Given; two or more share one "Medicine ›" row that opens a list. Tonight's
/// rota joins as a third row in step 3.
struct WatchTodayPage: View {
    let state: WatchState
    let now: Date
    /// The rows with a tap the phone hasn't saved yet: "bath", or a medicine's name (outside review
    /// of step 1, P2). They say so until it has.
    var waiting: Set<String> = []
    /// Tonight's row opens the Tonight screen (step 3), when the phone understands it.
    var tonight: (() -> Void)?
    let bath: () -> Void
    let medicine: (String) -> Void
    let medicineList: () -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        WatchPageFrame(label: "Today") { metrics in
            let palette = WatchPalette.of(look)
            let medicines = state.understands(WatchCapability.medicine) ? state.medicines ?? [] : []
            if state.understands(WatchCapability.bath) {
                WatchCareRow(title: "Bath", note: waiting.contains("bath") ? waitingText : lastText(state.lastBath), metrics: metrics) {
                    Image(systemName: "bathtub.fill").foregroundStyle(palette.bottle)
                } trailing: {
                    WatchPill(title: "Bath", action: bath).accessibilityLabel("Bath, log it now")
                }
            }
            Spacer(minLength: metrics.gap)
            if medicines.count == 1, let item = medicines.first {
                WatchCareRow(title: item.name, note: waiting.contains(item.name) ? waitingText : lastText(item.lastGiven),
                             metrics: metrics) {
                    Image(systemName: "pills.fill").foregroundStyle(palette.textMuted)
                } trailing: {
                    WatchPill(title: "Given") { medicine(item.name) }.accessibilityLabel("\(item.name) given, log it now")
                }
            } else if medicines.count > 1 {
                Button(action: medicineList) {
                    WatchCareRow(title: "Medicine", note: medicines.contains { waiting.contains($0.name) } ? waitingText : listNote(medicines),
                                 metrics: metrics) {
                        Image(systemName: "pills.fill").foregroundStyle(palette.textMuted)
                    } trailing: {
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textMuted)
                            .padding(.trailing, 8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Medicine: \(medicines.count) on your list. Opens the list")
            }
            if let open = tonight, let night = state.tonight, state.understands(WatchCapability.tonight) {
                // Out of date once the night has changed and the phone hasn't said who is on: never
                // last night's rota (outside review of step 3). A tap not yet saved says so.
                let stale = night.night != state.currentNight(at: now)
                let note = stale || waiting.contains("tonight") ? "Waiting for iPhone" : TonightText.short(night, state: state)
                Spacer(minLength: metrics.gap)
                Button(action: open) {
                    WatchCareRow(title: "Tonight", note: note, metrics: metrics) {
                        MoonShape().fill(palette.sleep).frame(width: 15, height: 15)
                    } trailing: {
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textMuted)
                            .padding(.trailing, 8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(stale)
                .accessibilityLabel("Tonight: \(note). Opens tonight's choices")
            }
            Spacer(minLength: 0)
        }
    }

    private var waitingText: String { "Waiting for iPhone" }

    private func lastText(_ date: Date?) -> String {
        date.map { "Last \(CareText.lastGiven($0, now: now, timeZoneID: state.timeZoneID))" } ?? "Not logged yet"
    }

    /// "3 on your list · last 09:10": the latest given among them.
    private func listNote(_ medicines: [WatchMedicine]) -> String {
        let last = medicines.compactMap(\.lastGiven).max()
        return "\(medicines.count) on your list" + (last.map { " · last \(CareText.lastGiven($0, now: now, timeZoneID: state.timeZoneID))" } ?? "")
    }
}

/// A row on page 3 and in the medicine list: a shape, the name and when it was last, and its button.
struct WatchCareRow<Icon: View, Trailing: View>: View {
    let title: String
    let note: String
    let metrics: WatchMetrics
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        HStack(spacing: 6) {
            icon().frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                // Two lines, so two medicines whose names differ near the end can't look the same
                // (outside review of step 1, P2).
                Text(title).watchText(.line).fontWeight(.semibold).foregroundStyle(palette.text).lineLimit(2)
                    .minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                Text(note).watchText(.hint).foregroundStyle(palette.textMuted).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(minHeight: metrics.small ? 46 : 52)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// The medicine list, from page 3's "Medicine ›": each with its Given. A list a tap opens, so it
/// may scroll when it is long.
struct WatchMedicineListScreen: View {
    let state: WatchState
    let now: Date
    var waiting: Set<String> = []
    let given: (String) -> Void
    let close: () -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        WatchPageFrame(label: "Medicine") { metrics in
            let palette = WatchPalette.of(look)
            ScrollView {
                VStack(spacing: metrics.gap) {
                    ForEach(state.medicines ?? [], id: \.name) { item in
                        let last = item.lastGiven.map { "Last \(CareText.lastGiven($0, now: now, timeZoneID: state.timeZoneID))" }
                        WatchCareRow(title: item.name, note: waiting.contains(item.name) ? "Waiting for iPhone" : last ?? "Not logged yet",
                                     metrics: metrics) {
                            Image(systemName: "pills.fill").foregroundStyle(palette.textMuted)
                        } trailing: {
                            WatchPill(title: "Given") { given(item.name) }.accessibilityLabel("\(item.name) given, log it now")
                        }
                    }
                    WatchBigButton(title: "Back", prominent: false, compact: true, action: close)
                }
            }
        }
    }
}

/// A small coral pill: Bath, Given.
struct WatchPill: View {
    let title: String
    let action: () -> Void
    @State private var taps = 0
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        Button {
            taps += 1
            action()
        } label: {
            Text(title)
                .watchText(.side)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(minHeight: 34)
                .foregroundStyle(palette.onPrimary)
                .background(palette.primary, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: taps)
    }
}

// MARK: - "Formula or expressed?"

/// A bottle-only watch's Start (on page 1 or the watch face): the milk, as three buttons that fit
/// the screen, the feed starting from the tap. The double tap presses the milk used last. Not now
/// logs nothing.
struct WatchMilkPage: View {
    let state: WatchState
    let tappedAt: Date
    let choose: (MilkKind?) -> Void
    /// "Breastfeed (Sam)" (design DD15, 4B), offered when the phone names who breastfeeds.
    let breastfeed: () -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        WatchPageFrame(label: state.breastfeederName == nil ? "Which milk?" : "Start a feed") { metrics in
            let palette = WatchPalette.of(look)
            let time = state.clock(tappedAt)
            Text("Feed from \(Text(time).foregroundStyle(palette.text))")
                .watchText(.note)
                .foregroundStyle(palette.textMuted)
                .accessibilityLabel("The feed starts at \(time)")
            Spacer(minLength: 4)
            WatchTileRow(metrics: metrics) {
                ForEach([MilkKind.formula, .expressed], id: \.self) { milk in
                    WatchTile(title: milk == .formula ? "Formula" : "Expressed", metrics: metrics) {
                        BottleShape().fill(palette.bottle).frame(width: 16, height: 16)
                    } action: { choose(milk) }
                    .handGestureShortcut(.primaryAction, isEnabled: milk == (state.lastMilk ?? .formula))
                    .accessibilityLabel(milk == .formula ? "Start a formula feed" : "Start an expressed milk feed")
                }
                if let name = state.breastfeederName {
                    WatchTile(title: "Breastfeed (\(name))", metrics: metrics) {
                        Image(systemName: "circle.lefthalf.filled").foregroundStyle(palette.breast)
                    } action: { breastfeed() }
                    .accessibilityLabel("Start \(name)'s breastfeed")
                }
            }
            Spacer(minLength: 4)
            WatchBigButton(title: "Not now", prominent: false, compact: true) { choose(nil) }
                .accessibilityLabel("Not now, log no feed")
        }
    }
}
