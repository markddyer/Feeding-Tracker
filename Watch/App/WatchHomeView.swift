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
    /// Feeds, sleep and nappies (pick I, 17 Nov 2026), or bath and medicine (step 1 of
    /// `11-watch-parity.md`).
    @State private var page = WatchPage.feeds
    /// The Logged card after a tap, with Undo, Earlier and who did it.
    @State private var logged: LoggedCard?
    /// After Poo or Both: its colour and consistency.
    @State private var pooAsk: PooAsk?
    /// Pumping, from page 1.
    @State private var pumping = false
    /// The medicine list, from page 3 when there are two or more.
    @State private var medicineList = false
    /// "Add to this feed" after Finish, Just finished or Earlier (step 2).
    @State private var addTo: AddToFeed?
    /// Just finished's question, and Earlier's (from when it opened).
    @State private var justFinishedAsk = false
    @State private var earlierAsk: Date?
    /// Bottle during this parent's feed: which milk.
    @State private var bottleAsk: String?
    /// Tonight's choices, from page 3 (step 3).
    @State private var tonightOpen = false
    /// The "Last night" card screen (AI insights step 4, design D16 B).
    @State private var lastNightOpen = false
    /// The last feed finished for this parent by the other parent whose details were offered, so
    /// the offer comes once (outside review of step 2).
    @AppStorage("watch.detailsOffered") private var detailsOffered = ""
    /// Undo, Earlier and Done by sent from a Logged card, by tap, until the phone answers: one it
    /// turns down after the card has closed opens a card that says so (outside review of step 1, P2).
    @State private var corrections: [String: LoggedCard] = [:]
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if FEEDING_DEV
        _question = State(initialValue: WatchSamples.question())
        _milkAsk = State(initialValue: WatchSamples.milkAsk())
        _page = State(initialValue: WatchSamples.page())
        _logged = State(initialValue: WatchSamples.logged())
        _pooAsk = State(initialValue: WatchSamples.pooAsk())
        _pumping = State(initialValue: WatchSamples.screen == "pump")
        _medicineList = State(initialValue: WatchSamples.screen == "medicines")
        _tonightOpen = State(initialValue: WatchSamples.screen == "tonight")
        _lastNightOpen = State(initialValue: WatchSamples.screen == "lastNightCard")
        // Step 2: `-watchScreen addToFeed`, `justFinished`, `earlierFeed` or `bottle`.
        _addTo = State(initialValue: WatchSamples.screen == "addToFeed" ? AddToFeed(feedID: "sample-last", tap: nil, finishedAt: Date()) : nil)
        _justFinishedAsk = State(initialValue: WatchSamples.screen == "justFinished")
        _earlierAsk = State(initialValue: WatchSamples.screen == "earlierFeed" ? Date() : nil)
        _bottleAsk = State(initialValue: WatchSamples.screen == "bottle" ? "sample" : nil)
        #endif
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let state = link.shown
            let look = state?.look(at: now) ?? .night
            // No title: on a 41 or 42 mm watch it takes a row of its own, and the big number and
            // the button need that room. The label above the number says what it is.
            // The navigation stack places each screen's small label beside the clock.
            NavigationStack {
                screen(state, now: now)
            }
            .environment(\.watchLook, look)
            .tint(WatchPalette.of(look).primary)
            .animation(.easeOut(duration: 0.3), value: look)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                link.appOpened()
                link.refresh()
                if page == .lastNight { link.checkCard() }
            }
        }
        // Page 4 checks with the phone each time it comes into sight (step 4 D11 A).
        .onChange(of: page) { _, page in
            if page == .lastNight { link.checkCard() }
        }
        // A card taken back while its screen is open closes it (D11 A).
        .onChange(of: link.cardCheck) { _, check in
            if check != .current { lastNightOpen = false }
        }
        // A changed card (taken back, facts only, or another day's) closes the card screen: the
        // next tap opens what the phone says now.
        .onChange(of: link.card) { lastNightOpen = false }
        .onChange(of: link.saved) { _, _ in
            noticeRefusedCorrections()
            offerDetailsFinishedForMe()
        }
        // The phone refused a Finish (it can't read that feed's details): its answer shows the feed
        // still running and the tap handled, so the amount question goes (engineering review of
        // "who does what", A2).
        .onChange(of: link.shown) { _, shown in
            guard let question, shown?.running?.id == question.feedID else { return }
            let finishWaiting = link.saved.pending.contains {
                if case .finish(let id) = $0.command { return id == question.feedID }
                return false
            }
            if !finishWaiting { self.question = nil }
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

    /// Page 3's rows with a tap the phone hasn't saved yet: "bath", a medicine's name, or
    /// "tonight" for a rota tap. One undone before the phone heard isn't waiting to be shown.
    private var waitingRows: Set<String> {
        let actions = link.saved.actions
        let undone = Set(actions.compactMap { if case .undo(let id) = $0.action { id } else { nil } })
        return Set(actions.compactMap { request in
            guard !undone.contains(request.entryID) else { return nil }
            if request.capability == WatchCapability.tonight { return "tonight" }
            switch request.action {
            case .bath: return "bath"
            case .medicine(_, let name): return name
            default: return nil
            }
        })
    }

    /// A correction the phone has answered is no longer followed; one it turned down shows its
    /// card, unless another card is open (that one's own correction says so itself).
    private func noticeRefusedCorrections() {
        for (id, notice) in corrections {
            let outcome = link.result(of: id)
            guard outcome != .waiting, outcome != nil || !link.isWaiting(id) else { continue }
            corrections[id] = nil
            if outcome == .refused, logged == nil, addTo?.tap != id { logged = notice }
        }
    }

    /// The other parent finished this parent's feed: "Add to this feed" once, as the phone does.
    private func offerDetailsFinishedForMe() {
        guard let feed = link.shown?.lastFeed, feed.finishedForMe == true, feed.id != detailsOffered,
              addTo == nil, logged == nil, question == nil else { return }
        detailsOffered = feed.id
        addTo = AddToFeed(feedID: feed.id, tap: nil)
    }

    /// A past feed sent from the watch: if the phone turns it down after "Add to this feed" has
    /// closed, a card says so (outside review of step 2).
    private func followPastFeed(_ tap: String, id: String, start: Date) {
        corrections[tap] = LoggedCard(id: tap, entryID: id, title: "Feed from \(link.shown?.clock(start) ?? "")", at: start,
                                      mark: .feed, canUndo: false, canEarlier: false, canDoneBy: false,
                                      notice: "Not saved: a feed is already logged then")
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

    /// Finish, then "Add to this feed" (step 2), or on an older phone each bottle's amount.
    private func finish(_ feed: WatchFeed) {
        let at = Date()
        let tap = link.sendFinish(feedID: feed.id, now: at)
        if link.shown?.understands(WatchCapability.feedExtras) == true {
            addTo = AddToFeed(feedID: feed.id, tap: tap, finishedAt: at)
        } else {
            question = AmountAsk(feedID: feed.id, bottles: feed.bottles.filter { $0.ml == nil })
        }
    }

    @ViewBuilder
    private func screen(_ state: WatchState?, now: Date) -> some View {
        #if FEEDING_DEV
        if WatchFaceGallery.isOn, let state {
            WatchFaceGallery(state: state)
        } else {
            mainScreen(state, now: now)
        }
        #else
        mainScreen(state, now: now)
        #endif
    }

    @ViewBuilder
    private func mainScreen(_ state: WatchState?, now: Date) -> some View {
        if let card = logged, let state {
            WatchLoggedScreen(card: card, state: state, send: { action, after in
                let id = link.send(action, after: after)
                corrections[id] = card.notice(LoggedCard.correctionName(action) + " not saved", tap: id)
                return id
            }) {
                logged = nil
            }
            .id(card.id)
        } else if let ask = pooAsk, let state {
            WatchPooDetailsScreen { colour, consistency in
                if colour != nil || consistency != nil {
                    link.send(.pooDetails(nappyID: ask.nappyID, colour: colour, consistency: consistency), after: ask.requestID)
                }
                pooAsk = nil
                logged = ask.card
            }
            .environment(\.watchLook, state.look(at: now))
        } else if medicineList, let state {
            WatchMedicineListScreen(state: state, now: now, waiting: waitingRows) { name in
                medicineList = false
                given(name)
            } close: {
                medicineList = false
            }
        } else if pumping, let state {
            WatchPumpScreen(start: state.lastExpressedML ?? 60) { side, left, right in
                let id = UUID().uuidString
                let at = Date()
                let request = link.send(.pump(id: id, side: side, leftML: left, rightML: right), now: at)
                pumping = false
                logged = LoggedCard(id: request, entryID: id, title: "Pumping logged", at: at,
                                    start: at.addingTimeInterval(-30 * 60), mark: .pump)
            } cancel: {
                pumping = false
            }
        } else if addTo != nil, let state {
            WatchAddToFeedScreen(state: state, ask: $addTo) { tap, feed in
                // An Undo of Finish the phone turns down after the panel has gone says so.
                corrections[tap] = LoggedCard(id: tap, entryID: feed, title: "Feed finished", at: Date(), mark: .feed,
                                              canUndo: false, canEarlier: false, canDoneBy: false,
                                              notice: "Undo not saved: the feed stays finished")
            }
        } else if justFinishedAsk, let state {
            WatchJustFinishedScreen { minutes in
                justFinishedAsk = false
                guard let minutes else { return }
                let id = UUID().uuidString
                let at = Date()
                let tap = link.send(.justFinished(feedID: id, minutesAgo: minutes), now: at)
                addTo = AddToFeed(feedID: id, tap: tap, past: true)
                followPastFeed(tap, id: id, start: at.addingTimeInterval(-Double(minutes) * 60))
            }
        } else if let opened = earlierAsk, let state {
            WatchEarlierFeedScreen(state: state, opened: opened) { start in
                earlierAsk = nil
                guard let start else { return }
                let id = UUID().uuidString
                let tap = link.send(.earlierFeed(feedID: id, start: start))
                addTo = AddToFeed(feedID: id, tap: tap, past: true)
                followPastFeed(tap, id: id, start: start)
            }
        } else if lastNightOpen, let card = link.card, link.cardCheck == .current, card.mode == .card,
                  card.isCurrent(at: now), let state {
            // Only a current AI card: one past its day, or turned to facts only, never stays open
            // (Codex step 4 review, 13).
            WatchLastNightCardScreen(card: card, timeZoneID: state.timeZoneID) { lastNightOpen = false }
        } else if tonightOpen, let state, let tonight = state.tonight {
            WatchTonightScreen(state: state, tonight: tonight) { choice in
                tonightOpen = false
                if let choice { night(choice, tonight) }
            }
        } else if let feedID = bottleAsk {
            WatchBottleChoiceScreen { milk in
                bottleAsk = nil
                guard let milk else { return }
                link.sendFeedExtra(.addBottle(feedID: feedID, bottleID: UUID().uuidString, milk: milk, ml: nil), feedID: feedID)
            }
        } else if let question, let state {
            WatchAmountPicker(title: "How much \(question.bottle.milk == .formula ? "formula" : "expressed milk")?",
                              start: state.startAmount(for: question.bottle.milk) ?? 60) { ml in
                if let ml {
                    link.send(.setAmount(feedID: question.feedID, bottleID: question.bottle.id, ml: ml))
                    link.rememberAmount(ml, milk: question.bottle.milk)
                }
                self.question = question.next
            }
            .id(question.bottle.id)
        } else if let tap = milkAsk, let state, state.faceStart == .askMilk,
                  now.timeIntervalSince(tap) < WatchFaceStart.questionLifetime {
            WatchMilkPage(state: state, tappedAt: tap) { milk in
                if let milk {
                    link.send(.start(feedID: UUID().uuidString, bottle: milk, bottleID: UUID().uuidString), now: tap)
                }
                milkAsk = nil
            } breastfeed: {
                link.send(.start(feedID: UUID().uuidString, bottle: nil, bottleID: UUID().uuidString,
                                 doneBy: state.breastfeeder), now: tap)
                milkAsk = nil
            }
        } else if let state, state.setUp {
            // Three pages, one above the other, each one screen (`11-watch-parity.md`). A page's
            // double tap works only while it is in sight.
            Group {
                TabView(selection: $page) {
                    feedPage(state, now: now)
                        .environment(\.watchDoubleTapAllowed, page == .feeds)
                        .tag(WatchPage.feeds)
                    WatchCarePage(state: state, now: now, waiting: link.waitingForPhone) {
                        sleepTap(state)
                    } nappy: { wee, poo in
                        nappy(state, wee: wee, poo: poo)
                    } addDetails: { id in
                        pooAsk = PooAsk(nappyID: id, requestID: nil, card: nil)
                    }
                    .environment(\.watchDoubleTapAllowed, page == .care)
                    .tag(WatchPage.care)
                    if state.understands(WatchCapability.bath) || state.understands(WatchCapability.medicine) {
                        WatchTodayPage(state: state, now: now, waiting: waitingRows, tonight: { tonightOpen = true }) {
                            let id = UUID().uuidString
                            let at = Date()
                            let request = link.send(.bath(id: id), now: at)
                            logged = LoggedCard(id: request, entryID: id, title: "Bath logged", at: at, mark: .bath)
                        } medicine: { name in
                            given(name)
                        } medicineList: {
                            medicineList = true
                        }
                        .environment(\.watchDoubleTapAllowed, false)
                        .tag(WatchPage.today)
                    }
                    if link.showsLastNight(at: now) {
                        WatchLastNightPage(card: link.card, check: link.cardCheck) { lastNightOpen = true }
                            .environment(\.watchDoubleTapAllowed, false)
                            .tag(WatchPage.lastNight)
                    }
                }
                .tabViewStyle(.verticalPage)
            }
        } else {
            MessageScreen(text: state == nil ? "Open Little Log on your iPhone, with this watch nearby."
                                             : "Set up Little Log on your iPhone first.")
        }
    }

    /// Page one: the feed screen.
    @ViewBuilder
    private func feedPage(_ state: WatchState, now: Date) -> some View {
        if let running = state.running, running.mine {
            WatchRunningPage(state: state, feed: running, waiting: link.waitingForPhone,
                             addBottle: state.understands(WatchCapability.feedExtras) ? { bottleAsk = running.id } : nil) { command in
                if case .finish = command {
                    finish(running)
                } else {
                    link.send(command)
                }
            }
        } else if let running = state.running {
            WatchOthersFeedPage(state: state, feed: running, waiting: link.waitingForPhone) {
                link.send(.finish(feedID: running.id))
            }
        } else {
            let extras = state.understands(WatchCapability.feedExtras)
            WatchIdlePage(state: state, now: now, waiting: link.waitingForPhone,
                          justFinished: extras ? { justFinishedAsk = true } : nil,
                          earlier: extras ? { earlierAsk = Date() } : nil) { bottle in
                link.send(.start(feedID: UUID().uuidString, bottle: bottle, bottleID: UUID().uuidString))
            } askMilk: {
                milkAsk = Date()
            } pumping: {
                pumping = true
            }
        }
    }

    /// Fell asleep or Woke up, with its Logged card. Woke up's Earlier, Undo and "who got up" are
    /// step 3 (they need the wake-up's own identity).
    private func sleepTap(_ state: WatchState) {
        guard let command = state.sleepTap() else { return }
        let at = Date()
        let request = link.send(command, now: at)
        switch command {
        case .fellAsleep(let id):
            logged = LoggedCard(id: request, entryID: id, title: "Fell asleep logged", at: at, mark: .asleep)
        case .wokeUp(let id):
            // Undo, Earlier and "who got up" (step 3), on a phone that understands them.
            let ends = state.understands(WatchCapability.ends)
            logged = LoggedCard(id: request, entryID: id, title: "Woke up logged", at: at, mark: .awake,
                                canUndo: ends, canEarlier: ends, canDoneBy: ends, undo: .undoWake(sleepID: id, wakeTap: request),
                                gotUpEnd: at)
        default:
            break
        }
    }

    /// A rota tap from the Tonight screen. "I'll take it" and an ask get the Logged card, with an
    /// Undo that takes them back, as the phone's Undo bar does.
    private func night(_ choice: WatchTonight.Choice, _ tonight: WatchTonight) {
        let at = Date()
        let other = TonightText.name(tonight.other, in: link.shown ?? WatchState(madeAt: at, setUp: false))
        let night = tonight.night
        switch choice {
        case .take:
            let tap = link.send(.claimNight(night: night), now: at)
            logged = LoggedCard(id: tap, entryID: "night-\(night)", title: "You're on tonight", at: at, mark: .night,
                                canEarlier: false, canDoneBy: false, undo: .undoTake(night: night, claimTap: tap))
        case .ask:
            let tap = link.send(.askNight(night: night), now: at)
            logged = LoggedCard(id: tap, entryID: "night-\(night)", title: "You asked \(other)", at: at, mark: .night,
                                canEarlier: false, canDoneBy: false, undo: .withdrawAsk(night: night, askTap: tap))
        case .decline:
            // "Not tonight" to the ask the watch showed, never a later one.
            link.send(.declineAsk(night: night, askedAt: tonight.askedAt ?? .distantPast), now: at)
        case .bothPhones:
            link.send(.bothPhones(night: night), now: at)
        }
    }

    /// A medicine given, with its Logged card.
    private func given(_ name: String) {
        let id = UUID().uuidString
        let at = Date()
        let request = link.send(.medicine(id: id, name: name), now: at)
        logged = LoggedCard(id: request, entryID: id, title: "\(name) given", at: at, mark: .medicine)
    }

    /// Wee, Poo or Both: a poo asks its colour and consistency first, then the Logged card.
    private func nappy(_ state: WatchState, wee: Bool, poo: Bool) {
        let id = UUID().uuidString
        let at = Date()
        let request = link.send(.nappy(nappyID: id, wee: wee, poo: poo), now: at)
        let title = wee && poo ? "Wee and poo logged" : poo ? "Poo logged" : "Wee logged"
        let card = LoggedCard(id: request, entryID: id, title: title, at: at, mark: .nappy(wee: wee, poo: poo))
        if poo, state.understands(WatchCapability.pooDetails) {
            pooAsk = PooAsk(nappyID: id, requestID: request, card: card)
        } else {
            logged = card
        }
    }
}

/// A poo waiting for its details: the nappy, the tap that logged it (nil for "Add details" on an
/// older one), and the Logged card to show after.
struct PooAsk: Equatable {
    let nappyID: String
    let requestID: String?
    let card: LoggedCard?
}

/// The watch app's pages (pick I, 17 Nov 2026, and step 1 of `11-watch-parity.md`).
enum WatchPage: Hashable {
    case feeds
    case care
    case today
    /// "Last night", on days with a morning AI card (AI insights step 4).
    case lastNight
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

/// Under the bar: "from 22:58" where the window starts, and the backup alarm's time at the end;
/// "from" goes when the two would touch.
struct WatchBarTimes: View {
    let steps: WindowSteps
    let state: WatchState
    let palette: WatchPalette

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let frames = steps.frames(width: width, gap: WatchWindowTrack.gap, minimum: WatchWindowTrack.minimumPart)
            let windowX = frames.first { $0.part.kind == .window }?.x
            let backup = steps.labelled.first { $0.kind == .backup }.map { steps.label($0.kind, state.clock).time }
            ZStack(alignment: .topLeading) {
                if let windowX {
                    ViewThatFits(in: .horizontal) {
                        Text(steps.label(.window, state.clock).time)
                        Text(state.clock(steps.opensAt))
                    }
                    .frame(width: max(0, width - windowX - (backup == nil ? 0 : 44)), alignment: .leading)
                    .offset(x: windowX)
                }
                if let backup {
                    Text(backup).frame(width: width, alignment: .trailing)
                }
            }
        }
        .frame(height: 15)
        .watchText(.line)
        .foregroundStyle(palette.text)
        .lineLimit(1)
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
    /// Lower than usual, for a screen of three on a small watch.
    var minHeight: CGFloat?
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
            .frame(maxWidth: .infinity, minHeight: minHeight ?? (compact ? 46 : 50))
            .foregroundStyle(foreground)
            .background(prominent ? palette.primary : palette.surface, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction, isEnabled: doubleTap && doubleTapAllowed)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }
}

/// Shown while a tap waits for the phone.
struct WaitingLine: View {
    @Environment(\.watchLook) private var look

    var body: some View {
        Label("Sends when your phone is near", systemImage: "iphone.slash")
            .watchText(.line)
            .foregroundStyle(WatchPalette.of(look).textMuted)
            // Smaller rather than cut off, where a page has little room left ("…phone is ne…" on
            // page 1, 22 Nov 2026).
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
                .padding(.horizontal, WatchPageMargins.current.side)
        }
    }
}
