import AppIntents
import FeedingCore
import Foundation

// Hands-free logging with Siri on the watch (`docs/planning/15-hands-free-siri.md`, step 2, V1):
// the phone's phrases and questions, said to the watch. The watch keeps no log of its own: each
// action sends the watch's own taps (`PhoneLink`), chosen from the phone's last state, exactly as
// the watch's buttons do. When the phone answers within a few seconds, Siri says what was saved;
// if not, the tap waits in the watch's queue and Siri says it's on its way.

struct WatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WatchStartFeedIntent(),
                    phrases: ["Start a feed in \(.applicationName)", "Start feed in \(.applicationName)",
                              "Start a \(\.$milk) feed in \(.applicationName)",
                              "Start an \(\.$milk) feed in \(.applicationName)",
                              "Start \(\.$milk) in \(.applicationName)"],
                    shortTitle: "Start feed", systemImageName: "waterbottle")
        AppShortcut(intent: WatchFinishFeedIntent(),
                    phrases: ["Finish the feed in \(.applicationName)", "Finish feed in \(.applicationName)",
                              "Finish a feed in \(.applicationName)", "End the feed in \(.applicationName)",
                              "Feed finished in \(.applicationName)"],
                    shortTitle: "Finish feed", systemImageName: "stopwatch")
        AppShortcut(intent: WatchAddBottleIntent(),
                    phrases: ["Add a bottle in \(.applicationName)", "Add a bottle to the feed in \(.applicationName)",
                              "Add \(\.$milk) in \(.applicationName)", "Add a \(\.$milk) bottle in \(.applicationName)",
                              "Add an \(\.$milk) bottle in \(.applicationName)"],
                    shortTitle: "Add a bottle", systemImageName: "waterbottle.fill")
        AppShortcut(intent: WatchAsleepIntent(),
                    phrases: ["Baby's asleep in \(.applicationName)", "Asleep in \(.applicationName)",
                              "Fell asleep in \(.applicationName)", "Log a sleep in \(.applicationName)"],
                    shortTitle: "Fell asleep", systemImageName: "moon.zzz")
        AppShortcut(intent: WatchAwakeIntent(),
                    phrases: ["Baby's awake in \(.applicationName)", "Awake in \(.applicationName)",
                              "Woke up in \(.applicationName)"],
                    shortTitle: "Woke up", systemImageName: "sun.max")
        AppShortcut(intent: WatchNappyIntent(),
                    phrases: ["Log a nappy in \(.applicationName)", "Nappy change in \(.applicationName)",
                              "Log a \(\.$kind) in \(.applicationName)", "Log a \(\.$kind) nappy in \(.applicationName)"],
                    shortTitle: "Log a nappy", systemImageName: "drop")
        AppShortcut(intent: WatchMedicineIntent(),
                    phrases: ["Log a medicine in \(.applicationName)", "Log \(\.$medicine) in \(.applicationName)",
                              "Gave \(\.$medicine) in \(.applicationName)"],
                    shortTitle: "Log a medicine", systemImageName: "pills")
    }
}

struct WatchStartFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Start feed"
    static let description = IntentDescription("Starts a feed now.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Bottle")
    var milk: MilkChoice?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await WatchVoice.start(self))")
    }
}

struct WatchFinishFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish feed"
    static let description = IntentDescription("Finishes the feed running now. Siri then asks for the sides or the amount.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Sides")
    var sides: SidesChoice?

    @Parameter(title: "Bottle")
    var milk: MilkChoice?

    @Parameter(title: "Amount (ml)")
    var ml: Int?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await WatchVoice.finish(self))")
    }
}

struct WatchAddBottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a bottle"
    static let description = IntentDescription("Adds a bottle and its amount to the feed running now, or to the last feed.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Bottle")
    var milk: MilkChoice?

    @Parameter(title: "Amount (ml)")
    var ml: Int?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await WatchVoice.addBottle(self))")
    }
}

struct WatchAsleepIntent: AppIntent {
    static let title: LocalizedStringResource = "Fell asleep"
    static let description = IntentDescription("Logs that the baby fell asleep now.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await WatchVoice.sleep(asleep: true))")
    }
}

struct WatchAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Woke up"
    static let description = IntentDescription("Ends the sleep running now.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await WatchVoice.sleep(asleep: false))")
    }
}

struct WatchNappyIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a nappy"
    static let description = IntentDescription("Logs a nappy change now. For a poo, Siri asks its colour and texture.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Nappy")
    var kind: NappyKindChoice?

    @Parameter(title: "Colour")
    var colour: PooColourChoice?

    @Parameter(title: "Texture")
    var texture: PooTextureChoice?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await WatchVoice.nappy(self))")
    }
}

struct WatchMedicineIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a medicine"
    static let description = IntentDescription("Logs a medicine or vitamin from your list, given now.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Medicine")
    var medicine: WatchMedicineEntity?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(await WatchVoice.medicine(self))")
    }
}

/// A medicine on the household's list, as the phone last sent it.
struct WatchMedicineEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Medicine"
    static let defaultQuery = WatchMedicineQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }

    init(id: String) {
        self.id = id
    }
}

struct WatchMedicineQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WatchMedicineEntity] {
        let list = await Self.list()
        return identifiers.filter { list.contains($0) }.map(WatchMedicineEntity.init)
    }

    func entities(matching string: String) async throws -> [WatchMedicineEntity] {
        let wanted = string.lowercased()
        return await Self.list().filter { $0.lowercased().contains(wanted) }.map(WatchMedicineEntity.init)
    }

    func suggestedEntities() async throws -> [WatchMedicineEntity] {
        await Self.list().map(WatchMedicineEntity.init)
    }

    /// The household's list as the phone last sent it: an empty list stays empty (Codex review, 1).
    @MainActor
    static func list() -> [String] {
        PhoneLink.shared.shown?.medicines?.map(\.name) ?? []
    }
}

@MainActor
enum WatchVoice {
    private static var link: PhoneLink { PhoneLink.shared }

    /// The phone's last state, once the link is up (Siri may have just woken the app). Nil before
    /// the phone has set the watch up.
    private static func ready() async -> WatchState? {
        link.activate()
        for _ in 0..<20 where link.shown?.setUp != true {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let state = link.shown, state.setUp else { return nil }
        return state
    }

    /// Waits a few seconds for the phone's answers to the taps, then says `said`; or that some are
    /// still on their way; or that the phone turned one down (Codex review of doc 15, 8).
    private static func answer(_ taps: [String], _ said: String) async -> String {
        for _ in 0..<20 {
            let results = taps.map { link.result(of: $0) }
            if results.contains(.refused) { return taps.count == 1 ? SiriText.phoneRefused : SiriText.notAllSaved }
            if results.allSatisfy({ $0 == .applied || $0 == .unchanged }) { return said }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return "\(said) \(SiriText.onItsWay)"
    }

    private static func answer(_ tap: String, _ said: String) async -> String {
        await answer([tap], said)
    }

    /// A bottle's amount, read back, sent after `after` and only while the phone's last word has
    /// it empty (Codex review of doc 15, 2). Returns the tap, or a note for Siri's reply.
    private static func sendAmount(_ parameter: IntentParameter<Int?>, feedID: String, bottleID: String, milk: MilkKind,
                                   state: WatchState, after: String, given: Int? = nil) async throws -> (tap: String?, note: String?, ml: Int?) {
        guard let ml = try await SiriAmount.ask(parameter, milk: milk, baby: baby(state), given: given) else {
            return (nil, SiriText.amountNotSaved, nil)
        }
        let latest = link.shown
        let bottles = (latest?.running?.id == feedID ? latest?.running?.bottles : nil)
            ?? latest?.recentFeeds?.first(where: { $0.id == feedID })?.details.bottles
            ?? (latest?.lastFeed?.id == feedID ? latest?.lastFeed?.details.bottles : nil) ?? []
        if let saved = bottles.first(where: { $0.id == bottleID })?.ml { return (nil, SiriText.amountAlreadySaved(saved, milk), nil) }
        link.rememberAmount(ml, milk: milk)
        return (link.send(.amount(feedID: feedID, bottleID: bottleID, ml: ml), after: after), nil, ml)
    }

    private static func baby(_ state: WatchState) -> String {
        let name = state.babyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "the baby" : name
    }

    private static func details(of running: WatchFeed) -> FeedDetails {
        let sides = running.sides ?? running.side.map { [$0] } ?? []
        return FeedDetails(breast: sides.map { BreastSegment(side: $0) }, bottles: running.bottles)
    }

    // MARK: Start and finish

    static func start(_ intent: WatchStartFeedIntent) async -> String {
        guard let state = await ready() else { return SiriText.watchNotSetUp }
        if let running = state.running {
            return SiriText.running(by: running.mine ? nil : running.byName, since: running.startedAt, timeZoneID: state.timeZoneID)
        }
        var milk = intent.milk?.kind
        if milk == nil, state.bottleOnly {
            guard let said = try? await intent.$milk.requestValue(IntentDialog(stringLiteral: SiriText.whichMilk)) else { return "" }
            milk = said.kind
        }
        let now = Date()
        let tap = link.send(.start(feedID: UUID().uuidString, bottle: milk, bottleID: UUID().uuidString), now: now)
        let said = GlanceText.said(.started(id: "", at: now, bottle: milk), me: "", names: [:], timeZoneID: state.timeZoneID, now: now)
        return await answer(tap, said)
    }

    static func finish(_ intent: WatchFinishFeedIntent) async -> String {
        guard let state = await ready() else { return SiriText.watchNotSetUp }
        guard let running = state.running else { return "No feed is running." }
        let now = Date()
        var details = details(of: running)
        // Each answer is sent after the tap before it, so the phone applies them in order.
        var taps = [link.sendFinish(feedID: running.id, now: now)]
        var notes: [String] = []
        // As the watch's buttons: a bottle-only watch still asks the sides of a breastfeed (Codex, 7).
        let bottleOnly = state.bottleOnly && running.breastfeed != true
        do {
            for question in VoiceLog.questions(for: details, bottleOnly: bottleOnly) {
                switch question {
                case .amount(let bottleID, let milk):
                    let sent = try await sendAmount(intent.$ml, feedID: running.id, bottleID: bottleID, milk: milk,
                                                    state: state, after: taps.last!)
                    if let tap = sent.tap {
                        taps.append(tap)
                        if let index = details.bottles.firstIndex(where: { $0.id == bottleID }) {
                            details.bottles[index].ml = sent.ml
                        }
                    }
                    if let note = sent.note { notes.append(note) }
                case .sides:
                    let choice = try await intent.$sides.requestValue(IntentDialog(stringLiteral: SiriText.whichSides))
                    for side in choice.sides?.sides ?? [] {
                        taps.append(link.send(.addSide(feedID: running.id, side: side), after: taps.last!))
                        details.breast.append(BreastSegment(side: side))
                    }
                case .milkAndAmount:
                    let milk = try await intent.$milk.requestValue(IntentDialog(stringLiteral: SiriText.whichMilk)).kind
                    // The bottle goes as soon as its milk is known; the amount follows (Codex, 6).
                    let bottle = Bottle(id: UUID().uuidString, milk: milk, ml: nil)
                    taps.append(link.send(.addBottle(feedID: running.id, bottleID: bottle.id, milk: milk, ml: nil),
                                          after: taps.last!))
                    details.bottles.append(bottle)
                    let sent = try await sendAmount(intent.$ml, feedID: running.id, bottleID: bottle.id, milk: milk,
                                                    state: state, after: taps.last!)
                    if let tap = sent.tap {
                        taps.append(tap)
                        details.bottles[details.bottles.count - 1].ml = sent.ml
                    }
                    if let note = sent.note { notes.append(note) }
                }
            }
        } catch {
            // Gone quiet or Cancel: the feed is finished; the rest is added on the watch or phone.
        }
        let said = SiriText.finished(by: running.mine ? nil : running.byName, start: running.startedAt, end: now,
                                     details: details, timeZoneID: state.timeZoneID)
        return await answer(taps, ([said] + notes).joined(separator: " "))
    }

    // MARK: Add a bottle

    static func addBottle(_ intent: WatchAddBottleIntent) async -> String {
        guard let state = await ready() else { return SiriText.watchNotSetUp }
        let milk: MilkKind
        if let named = intent.milk {
            milk = named.kind
        } else {
            guard let said = try? await intent.$milk.requestValue(IntentDialog(stringLiteral: SiriText.whichMilk)) else { return "" }
            milk = said.kind
        }
        let now = Date()
        let running = state.running.map { VoiceFeedFacts(id: $0.id, endedAt: nil, mine: $0.mine, details: details(of: $0)) }
        let last = state.lastFeed.map { VoiceFeedFacts(id: $0.id, endedAt: $0.end, mine: $0.mine, details: $0.details) }
        switch VoiceLog.bottleTarget(running: running, last: last, milk: milk, now: now) {
        case .runningNotMine: return SiriText.runningNotMine
        case .runningHasBottle: return SiriText.runningHasBottle
        case .alreadyHas: return SiriText.alreadyHas(milk, feedStart: state.lastFeed?.start ?? now, timeZoneID: state.timeZoneID)
        case .noFeed: return SiriText.noFeed
        case .feed(let id):
            let finished = state.running?.id != id
            // The bottle goes first, so going quiet at the amount keeps it (Codex review, 6).
            let bottleID = UUID().uuidString
            var taps = [link.sendFeedExtra(.addBottle(feedID: id, bottleID: bottleID, milk: milk, ml: nil), feedID: id)]
            var note: String?
            var ml: Int?
            if finished {
                do {
                    let sent = try await sendAmount(intent.$ml, feedID: id, bottleID: bottleID, milk: milk, state: state,
                                                    after: taps[0], given: intent.ml)
                    if let tap = sent.tap {
                        taps.append(tap)
                        ml = sent.ml
                    }
                    note = sent.note
                } catch {
                    note = SiriText.amountNotSaved
                }
            }
            let start = finished ? state.lastFeed?.start ?? now : state.running?.startedAt ?? now
            let said = SiriText.bottleAdded(ml: ml, milk: milk, feedStart: start, timeZoneID: state.timeZoneID)
            return await answer(taps, [said, note].compactMap { $0 }.joined(separator: " "))
        }
    }

    // MARK: Sleep, nappy, medicine

    static func sleep(asleep: Bool) async -> String {
        guard let state = await ready() else { return SiriText.watchNotSetUp }
        let now = Date()
        let running = state.sleep.flatMap { $0.asleep ? $0 : nil }
        if asleep {
            if let running { return GlanceText.said(.alreadyAsleep(since: running.start), timeZoneID: state.timeZoneID) }
            let tap = link.send(.fellAsleep(sleepID: UUID().uuidString), now: now)
            return await answer(tap, GlanceText.said(.fellAsleep(at: now), timeZoneID: state.timeZoneID))
        }
        guard let running else { return GlanceText.said(.notAsleep, timeZoneID: state.timeZoneID) }
        let tap = link.send(.wokeUp(sleepID: running.id), now: now)
        let said = GlanceText.said(.wokeUp(at: now, asleepFor: max(0, now.timeIntervalSince(running.start))),
                                   timeZoneID: state.timeZoneID)
        return await answer(tap, said)
    }

    static func nappy(_ intent: WatchNappyIntent) async -> String {
        guard let state = await ready() else { return SiriText.watchNotSetUp }
        let kind: NappyKindChoice
        if let named = intent.kind {
            kind = named
        } else {
            guard let said = try? await intent.$kind.requestValue(IntentDialog(stringLiteral: SiriText.weeOrPoo)) else { return "" }
            kind = said
        }
        let now = Date()
        let id = UUID().uuidString
        var last = link.send(.nappy(nappyID: id, wee: kind.wee, poo: kind.poo), now: now)
        var colour: PooColour?
        var consistency: PooConsistency?
        if kind.poo {
            do {
                if let given = intent.colour {
                    colour = given.colour
                } else {
                    colour = try await intent.$colour.requestValue(IntentDialog(stringLiteral: SiriText.whatColour)).colour
                }
                if let given = intent.texture {
                    consistency = given.consistency
                } else {
                    consistency = try await intent.$texture.requestValue(IntentDialog(stringLiteral: SiriText.whatTexture)).consistency
                }
            } catch {}
            if colour != nil || consistency != nil {
                last = link.send(.pooDetails(nappyID: id, colour: colour, consistency: consistency), after: last)
            }
        }
        let said = SiriText.nappy(at: now, wee: kind.wee, poo: kind.poo, colour: colour, consistency: consistency,
                                  timeZoneID: state.timeZoneID)
        return await answer(last, said)
    }

    static func medicine(_ intent: WatchMedicineIntent) async -> String {
        guard let state = await ready() else { return SiriText.watchNotSetUp }
        let list = WatchMedicineQuery.list()
        guard !list.isEmpty else { return SiriText.noMedicines }
        let name: String
        if let named = intent.medicine?.id, list.contains(named) {
            name = named
        } else if list.count == 1 {
            name = list[0]
        } else {
            guard let chosen = try? await intent.$medicine.requestDisambiguation(
                among: list.map(WatchMedicineEntity.init), dialog: IntentDialog(stringLiteral: SiriText.whichMedicine))
            else { return "" }
            name = chosen.id
        }
        let now = Date()
        let tap = link.send(.medicine(id: UUID().uuidString, name: name), now: now)
        return await answer(tap, SiriText.medicine(name, at: now, timeZoneID: state.timeZoneID))
    }
}
