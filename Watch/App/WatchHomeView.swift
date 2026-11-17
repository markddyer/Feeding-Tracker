import FeedingCore
import SwiftUI

/// The watch app's one screen (the user's choices of 16 Nov 2026, from the mockups): the time
/// since the last feed in big numbers with the window bar, and one big button. During a feed: the
/// time running, Left and Right, and Finish. After Finish, a bottle's amount on the Digital Crown.
/// A double tap presses the big button.
struct WatchHomeView: View {
    private var link: PhoneLink { PhoneLink.shared }
    /// After Finish on this watch: the bottles still without an amount.
    @State private var question: AmountAsk?
    /// The moment Start feed on the watch face was tapped, while "Formula or expressed?" waits.
    @State private var milkAsk: Date?
    /// Feeds, or sleep and nappies (pick I, 17 Nov 2026).
    @State private var page = WatchPage.feeds
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if FEEDING_DEV
        _question = State(initialValue: WatchSamples.question())
        _milkAsk = State(initialValue: WatchSamples.milkAsk())
        _page = State(initialValue: WatchSamples.page())
        #endif
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let state = link.shown
            let look = state?.look(at: now) ?? .night
            // No title: on a 41 or 42 mm watch it takes a row of its own, and the big number and
            // the button need that room. The label above the number says what it is.
            screen(state, now: now)
                .environment(\.watchLook, look)
            .tint(WatchPalette.of(look).primary)
            .animation(.easeOut(duration: 0.3), value: look)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { link.refresh() }
        }
        // Start feed on the watch face, and its Finish while this parent's feed runs. Its other
        // link (during the other parent's feed) only opens the app, which shows that feed.
        .onOpenURL { url in
            switch url.host {
            case WatchLinks.startFeedHost: startFromFace(at: Date())
            case WatchLinks.finishFeedHost: WatchLinks.feedID(in: url).map(finishFromFace)
            case WatchLinks.sleepHost: sleepFromFace(asleepID: WatchLinks.sleepID(in: url))
            case WatchLinks.careHost: page = .care
            default: break
            }
        }
        #if FEEDING_DEV
        // `-watchFaceTapTest YES`: what a tap on the watch face's Start feed does, four seconds
        // after launch, as the simulator can't open the watch face's link by command.
        // `-watchFaceTapTest finish`: the watch face's Finish, on the feed running then.
        .task {
            // `sleep`: the Sleep piece (Woke up while asleep, otherwise Fell asleep); `nappy`: the
            // Nappy piece, which opens page two.
            let test = UserDefaults.standard.string(forKey: "watchFaceTapTest")
            guard let test, ["YES", "finish", "sleep", "nappy"].contains(test) else { return }
            try? await Task.sleep(for: .seconds(4))
            switch test {
            case "finish": link.shown?.running.map { finishFromFace($0.id) }
            case "sleep": sleepFromFace(asleepID: link.shown?.sleep.flatMap { $0.asleep ? $0.id : nil })
            case "nappy": page = .care
            default: startFromFace(at: Date())
            }
        }
        #endif
    }

    /// Start feed on the watch face, as Start feed in the app: a bottle-only watch asks which milk
    /// first, and the feed starts from the tap; any other starts at once. A running feed is shown.
    private func startFromFace(at tap: Date) {
        guard let state = link.shown else { return }
        switch state.faceStart {
        case .askMilk:
            milkAsk = tap
        case .startNow:
            link.send(.start(feedID: UUID().uuidString, bottle: nil, bottleID: UUID().uuidString), now: tap)
        case .showRunning, .notReady:
            break
        }
    }

    /// Finish on the watch face: the same as Finish in the app, then the bottle's amount. Only
    /// this parent's feed, and only while it is still the one running; otherwise the app just
    /// shows what is running now.
    private func finishFromFace(_ feedID: String) {
        guard let feed = link.shown?.finishFromFace(feedID: feedID) else { return }
        milkAsk = nil
        finish(feed)
    }

    /// The Sleep piece on the watch face: Woke up for the sleep it showed running, or Fell asleep
    /// if it showed the baby awake. The face can be a little behind, so a tap that no longer
    /// matches what the watch knows logs nothing. Either way the app opens on page two.
    private func sleepFromFace(asleepID: String?) {
        page = .care
        guard let command = link.shown?.sleepTap() else { return }
        switch (command, asleepID) {
        case (.wokeUp(let running), let shown?) where running == shown: link.send(command)
        case (.fellAsleep, nil): link.send(command)
        default: break
        }
    }

    private func finish(_ feed: WatchFeed) {
        link.send(.finish(feedID: feed.id))
        question = AmountAsk(feedID: feed.id, bottles: feed.bottles.filter { $0.ml == nil })
    }

    @ViewBuilder
    private func screen(_ state: WatchState?, now: Date) -> some View {
        if let question, let state {
            AmountScreen(ask: question, start: state.startAmount(for: question.bottle.milk) ?? 60) { ml in
                if let ml {
                    link.send(.setAmount(feedID: question.feedID, bottleID: question.bottle.id, ml: ml))
                    link.rememberAmount(ml, milk: question.bottle.milk)
                }
                self.question = question.next
            }
            .id(question.bottle.id)
        } else if let tap = milkAsk, let state, state.faceStart == .askMilk,
                  now.timeIntervalSince(tap) < WatchFaceStart.questionLifetime {
            MilkScreen(state: state, tappedAt: tap) { milk in
                if let milk {
                    link.send(.start(feedID: UUID().uuidString, bottle: milk, bottleID: UUID().uuidString), now: tap)
                }
                milkAsk = nil
            }
        } else if let state, state.setUp {
            // Two pages, one above the other. The feed page is as it was; its double tap works
            // only while it is in sight.
            TabView(selection: $page) {
                ScrollView {
                    feedPage(state, now: now)
                        .padding(.horizontal, 2)
                }
                .environment(\.watchDoubleTapAllowed, page == .feeds)
                .tag(WatchPage.feeds)
                ScrollView {
                    CareScreen(state: state, now: now, waiting: link.waitingForPhone) { link.send($0) }
                        .padding(.horizontal, 2)
                }
                .environment(\.watchDoubleTapAllowed, page == .care)
                .tag(WatchPage.care)
            }
            .tabViewStyle(.verticalPage)
        } else {
            MessageScreen(text: state == nil ? "Open Feeding on your iPhone, with this watch nearby."
                                             : "Set up Feeding on your iPhone first.")
        }
    }

    /// Page one: the feed screen.
    @ViewBuilder
    private func feedPage(_ state: WatchState, now: Date) -> some View {
        Group {
            if let running = state.running, running.mine {
                RunningScreen(state: state, feed: running, waiting: link.waitingForPhone) { command in
                    if case .finish = command {
                        finish(running)
                    } else {
                        link.send(command)
                    }
                }
            } else if let running = state.running {
                OthersFeedScreen(state: state, feed: running, waiting: link.waitingForPhone) {
                    link.send(.finish(feedID: running.id))
                }
            } else {
                IdleScreen(state: state, now: now, waiting: link.waitingForPhone) { bottle in
                    link.send(.start(feedID: UUID().uuidString, bottle: bottle, bottleID: UUID().uuidString))
                }
            }
        }
    }
}

/// The bottles still waiting for their amount after Finish on this watch, asked one at a time.
struct AmountAsk: Equatable {
    let feedID: String
    let bottles: [Bottle]

    init?(feedID: String, bottles: [Bottle]) {
        guard !bottles.isEmpty else { return nil }
        self.feedID = feedID
        self.bottles = bottles
    }

    var bottle: Bottle { bottles[0] }
    var next: AmountAsk? { AmountAsk(feedID: feedID, bottles: Array(bottles.dropFirst())) }
}

// MARK: - No feed running

private struct IdleScreen: View {
    let state: WatchState
    let now: Date
    let waiting: Bool
    let start: (MilkKind?) -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        VStack(alignment: .leading, spacing: 7) {
            if let last = state.lastFeedStart, let window = state.feedWindow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last feed").watchText(.label).foregroundStyle(palette.textMuted)
                    Text(GlanceText.elapsed(now.timeIntervalSince(last)))
                        .watchText(.mainTime)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Last feed \(GlanceText.spokenElapsed(now.timeIntervalSince(last))) ago")
                WatchWindowBar(state: state, window: window, now: now)
            } else {
                Text("No feeds logged yet").watchText(.line).foregroundStyle(palette.textMuted)
            }
            if waiting { WaitingLine() }
            if state.bottleOnly {
                // One button per milk, as on the phone. The double tap presses the milk used last.
                HStack(spacing: 6) {
                    ForEach([MilkKind.formula, .expressed], id: \.self) { milk in
                        WatchBigButton(title: milk == .formula ? "Formula" : "Expressed", bottle: true,
                                       doubleTap: milk == (state.lastMilk ?? .formula), compact: true) { start(milk) }
                            .accessibilityLabel(milk == .formula ? "Start a formula feed" : "Start an expressed milk feed")
                    }
                }
                .padding(.top, 4)
            } else {
                WatchBigButton(title: "Start feed", bottle: true, doubleTap: true) { start(nil) }
                    .padding(.top, 4)
            }
        }
    }
}

/// The window bar, as on the phone: the time so far, the shaded window, then the window's time
/// and the alarm's.
private struct WatchWindowBar: View {
    let state: WatchState
    let window: FeedWindow
    let now: Date
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        let settings = state.window
        let opensShare = min(1, max(0, settings.opensAfter / max(1, settings.closesAfter)))
        let progress = state.glance?.windowProgress(at: now) ?? 0
        let clock = { (date: Date) in GlanceText.clock(date, timeZoneID: state.timeZoneID) }
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                        .fill(palette.window)
                        .frame(width: width * (1 - opensShare))
                        .offset(x: width * opensShare)
                    Capsule().fill(palette.primary).frame(width: max(8, width * progress))
                }
            }
            .frame(height: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Window \(Text(clock(window.opensAt)).foregroundStyle(palette.text))")
                    .foregroundStyle(palette.textMuted)
                Spacer(minLength: 4)
                if settings.alertsEnabled {
                    HStack(spacing: 3) {
                        Image(systemName: "bell").imageScale(.small)
                        Text(clock(window.closesAt))
                    }
                    .foregroundStyle(palette.text)
                } else {
                    Text("Alerts off").foregroundStyle(palette.textMuted)
                }
            }
            .watchText(.line)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.alertsEnabled
            ? "Feeding window opens at \(clock(window.opensAt)). Alert at \(clock(window.closesAt))."
            : "Feeding window opens at \(clock(window.opensAt)). Alerts are off.")
    }
}

// MARK: - A feed running

/// This parent's own feed: the time running, Left and Right (not for a bottle-only parent), Finish
/// and, lower down, Stop · discard.
private struct RunningScreen: View {
    let state: WatchState
    let feed: WatchFeed
    let waiting: Bool
    let send: (WatchCommand) -> Void
    @State private var discarding = false
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your feed · started \(GlanceText.clock(feed.startedAt, timeZoneID: state.timeZoneID))")
                    .watchText(.label)
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(2)
                RunningTime(since: feed.startedAt)
            }
            if let milk = feed.bottles.first?.milk {
                HStack(spacing: 5) {
                    BottleShape().fill(palette.bottle).frame(width: 15, height: 15)
                    Text(milk == .formula ? "Formula" : "Expressed milk").watchText(.line)
                }
                .foregroundStyle(palette.text)
            }
            if waiting { WaitingLine() }
            if !state.bottleOnly {
                HStack(spacing: 6) {
                    ForEach(BreastSide.allCases, id: \.self) { side in
                        WatchSideButton(side: side, selected: feed.side == side,
                                        suggested: feed.side == nil && state.nextSide == side) {
                            guard feed.side != side else { return }
                            send(.switchSide(feedID: feed.id, side: side))
                        }
                    }
                }
            }
            WatchBigButton(title: "Finish", systemImage: "stopwatch", doubleTap: true) {
                send(.finish(feedID: feed.id))
            }
            // For a feed started by mistake (a stray double tap): asks first, as on the phone.
            WatchBigButton(title: "Stop · discard", prominent: false, compact: true) { discarding = true }
                .padding(.top, 10)
                .accessibilityLabel("Stop and discard this feed")
        }
        .confirmationDialog("Remove this feed?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Remove feed", role: .destructive) { send(.discard(feedID: feed.id)) }
        } message: {
            Text("It will not be logged. To end a real feed, tap Finish.")
        }
    }
}

/// The other parent's feed: only they choose the sides, so this watch can only finish it for them.
private struct OthersFeedScreen: View {
    let state: WatchState
    let feed: WatchFeed
    let waiting: Bool
    let finish: () -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(WatchPalette.parent(feed.byColour, look: look)).frame(width: 9, height: 9)
                    Text("\(feed.byName)'s feed · started \(GlanceText.clock(feed.startedAt, timeZoneID: state.timeZoneID))")
                        .watchText(.label)
                        .foregroundStyle(palette.textMuted)
                        .lineLimit(2)
                }
                RunningTime(since: feed.startedAt)
            }
            if waiting { WaitingLine() }
            // Soft, and no double tap: the other parent is the one feeding.
            WatchBigButton(title: "Finish for \(feed.byName)", prominent: false, action: finish)
                .padding(.top, 4)
                .accessibilityHint("\(feed.byName) adds the sides and bottles. Their phone offers to add them after.")
        }
    }
}

/// "12:04", ticking.
private struct RunningTime: View {
    let since: Date
    @Environment(\.watchLook) private var look

    var body: some View {
        Text(timerInterval: since...Date.distantFuture, countsDown: false)
            .watchText(.mainTime)
            .foregroundStyle(WatchPalette.of(look).text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

// MARK: - Start feed from the watch face

/// "Formula or expressed?", after Start feed on the watch face on a bottle-only watch. The feed
/// starts from the tap on the face, so the time is right however long the answer takes. Not now
/// logs nothing.
private struct MilkScreen: View {
    let state: WatchState
    let tappedAt: Date
    let choose: (MilkKind?) -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        let time = GlanceText.clock(tappedAt, timeZoneID: state.timeZoneID)
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                Text("Formula or expressed?").watchText(.label).foregroundStyle(palette.textMuted)
                Text("Feed from \(Text(time).foregroundStyle(palette.text))")
                    .watchText(.line)
                    .foregroundStyle(palette.textMuted)
                    .accessibilityLabel("The feed starts at \(time)")
                ForEach([MilkKind.formula, .expressed], id: \.self) { milk in
                    // The double tap presses the milk used last, as on the main screen.
                    WatchBigButton(title: milk == .formula ? "Formula" : "Expressed milk", bottle: true,
                                   doubleTap: milk == (state.lastMilk ?? .formula)) { choose(milk) }
                        .accessibilityLabel(milk == .formula ? "Start a formula feed" : "Start an expressed milk feed")
                }
                WatchBigButton(title: "Not now", prominent: false, compact: true) { choose(nil) }
                    .padding(.top, 8)
                    .accessibilityLabel("Not now, log no feed")
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - After Finish

/// "How much formula?": the amount on the Digital Crown, every 5 ml from 5 to 300, starting at the
/// last bottle's amount. Turning saves nothing; Save does. Done closes with no amount, as on the
/// phone.
private struct AmountScreen: View {
    let ask: AmountAsk
    let done: (Int?) -> Void
    @State private var crown: Double
    @State private var saved = 0
    /// The amount box takes the crown as soon as the screen opens. Without this, nothing had it,
    /// so the crown did nothing (found on the real watch, 16 Nov 2026).
    @FocusState private var crownFocused: Bool
    @Environment(\.watchLook) private var look

    init(ask: AmountAsk, start: Int, done: @escaping (Int?) -> Void) {
        self.ask = ask
        self.done = done
        _crown = State(initialValue: Double(min(300, max(5, (start / 5) * 5))))
    }

    private var ml: Int { Int(crown.rounded()) }

    var body: some View {
        let palette = WatchPalette.of(look)
        let milk = ask.bottle.milk == .formula ? "formula" : "expressed milk"
        VStack(alignment: .leading, spacing: 8) {
            Text("How much \(milk)?").watchText(.label).foregroundStyle(palette.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(ml)").watchText(.amount).contentTransition(.numericText(value: crown))
                Text("ml").watchText(.line)
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
            .digitalCrownRotation($crown, from: 5, through: 300, by: 5, sensitivity: .low, isContinuous: false,
                                  isHapticFeedbackEnabled: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("How much \(milk)")
            .accessibilityValue("\(ml) millilitres")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: crown = min(300, crown + 5)
                case .decrement: crown = max(5, crown - 5)
                @unknown default: break
                }
            }
            // − and + for a finger, 5 ml a tap (the user's choice of 16 Nov 2026): the box
            // answered only the crown, and a finger on it did nothing.
            HStack(spacing: 8) {
                StepButton(symbol: "minus", label: "5 millilitres less", enabled: ml > 5) {
                    crown = max(5, crown - 5)
                }
                StepButton(symbol: "plus", label: "5 millilitres more", enabled: ml < 300) {
                    crown = min(300, crown + 5)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                WatchBigButton(title: "Done", prominent: false, compact: true) { done(nil) }
                    .frame(maxWidth: 70)
                    .accessibilityLabel("Done, with no amount")
                WatchBigButton(title: "Save", bottle: true, doubleTap: true, compact: true) {
                    saved += 1
                    done(ml)
                }
                .accessibilityLabel("Save \(ml) millilitres")
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .onAppear { crownFocused = true }
    }
}

/// − or + under the amount: a soft round-ended button with the symbol in coral.
private struct StepButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    let action: () -> Void
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: look == .night ? .semibold : .bold))
                .foregroundStyle(palette.primary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(palette.surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

// MARK: - Parts

/// A big button (`DESIGN.md`, "Big button"), at watch size: coral for the main action, the tile
/// colour for the soft one. `doubleTap` makes it the one a double tap presses.
struct WatchBigButton: View {
    let title: String
    var systemImage: String?
    var bottle = false
    var prominent = true
    var doubleTap = false
    var compact = false
    let action: () -> Void
    @State private var taps = 0
    @Environment(\.watchLook) private var look
    @Environment(\.watchDoubleTapAllowed) private var doubleTapAllowed

    var body: some View {
        let palette = WatchPalette.of(look)
        let foreground = prominent ? palette.onPrimary : palette.text
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: compact ? 4 : 7) {
                if bottle {
                    BottleShape().fill(foreground).frame(width: compact ? 14 : 18, height: compact ? 14 : 18)
                } else if let systemImage {
                    Image(systemName: systemImage).imageScale(.small)
                }
                Text(title)
                    .watchText(.button)
                    .lineLimit(1)
                    .minimumScaleFactor(compact ? 0.6 : 0.7)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: compact ? 46 : 50)
            .foregroundStyle(foreground)
            .background(prominent ? palette.primary : palette.surface, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction, isEnabled: doubleTap && doubleTapAllowed)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }
}

/// Left or Right during a feed (`DESIGN.md`, "Side buttons"): the half-moon above the word. The
/// side being fed fills with the breast colour.
private struct WatchSideButton: View {
    let side: BreastSide
    let selected: Bool
    let suggested: Bool
    let action: () -> Void
    @State private var taps = 0
    @Environment(\.watchLook) private var look

    var body: some View {
        let palette = WatchPalette.of(look)
        let title = side == .left ? "Left" : "Right"
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: side == .left ? "circle.lefthalf.filled" : "circle.righthalf.filled")
                    .imageScale(.small)
                Text(title).watchText(.side).lineLimit(1).minimumScaleFactor(0.7)
                if suggested {
                    Text("suggested").watchText(.hint).foregroundStyle(palette.textMuted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(selected ? palette.onBreast : palette.text)
            .background(selected ? palette.breast : palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityLabel(suggested ? "\(title), suggested" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Shown while a tap waits for the phone.
struct WaitingLine: View {
    @Environment(\.watchLook) private var look

    var body: some View {
        Label("Sends when your phone is near", systemImage: "iphone.slash")
            .watchText(.line)
            .foregroundStyle(WatchPalette.of(look).textMuted)
    }
}

private struct MessageScreen: View {
    let text: String
    @Environment(\.watchLook) private var look

    var body: some View {
        ScrollView {
            Text(text)
                .watchText(.line)
                .foregroundStyle(WatchPalette.of(look).text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
