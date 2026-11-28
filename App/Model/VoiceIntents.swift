import AppIntents
import FeedingCore
import Foundation

// Hands-free logging with Siri on the phone (`docs/planning/15-hands-free-siri.md`, step 1). Every
// action runs on a locked phone with no Touch ID (V4), in the app's own process, and saves through
// the same changes as a tap: Finish's and Add a bottle's answers through the watch's taps
// (`applyWatchAction`), so they follow the app's rules exactly. Something saved is never undone by
// a later question: if the parent goes quiet or says Cancel, what was said so far stays, and the
// app asks the rest.
//
//   "Finish the feed" ─► finish, alarms set, send begins ─► each missing detail (VoiceLog.questions)
//        ─► the sides ─► addSide, in the order said
//        ─► an amount ─► "Is that right?" ─► amount (V2)
//   "Add a bottle" ─► the milk ─► VoiceLog.bottleTarget ─► the amount, read back ─► addBottle
//   "Log a nappy" ─► wee, poo or both ─► saved ─► a poo's colour and texture ─► pooDetails
//   "Log a medicine" ─► which one, from the household's list ─► saved

/// "Add a bottle": a bottle on the feed running now, or on the last feed (V1).
struct AddBottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a bottle"
    static let description = IntentDescription("Adds a bottle and its amount to the feed running now, or to the last feed.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Parameter(title: "Bottle")
    var milk: MilkChoice?

    @Parameter(title: "Amount (ml)")
    var ml: Int?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await VoiceRunner.addBottle(self)
        return .result(dialog: "\(said)")
    }
}

/// "Log a nappy", with a poo's colour and texture (V1).
struct LogNappyIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a nappy"
    static let description = IntentDescription("Logs a nappy change now. For a poo, Siri asks its colour and texture.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Parameter(title: "Nappy")
    var kind: NappyKindChoice?

    @Parameter(title: "Colour")
    var colour: PooColourChoice?

    @Parameter(title: "Texture")
    var texture: PooTextureChoice?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await VoiceRunner.nappy(self)
        return .result(dialog: "\(said)")
    }
}

/// "Log Vitamin D": a medicine from the household's list, given now (V1). Never a dose.
struct LogMedicineIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a medicine"
    static let description = IntentDescription("Logs a medicine or vitamin from your list, given now.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var allowedExecutionTargets: IntentExecutionTargets { [.main] }

    @Parameter(title: "Medicine")
    var medicine: MedicineEntity?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await VoiceRunner.medicine(self)
        return .result(dialog: "\(said)")
    }
}

/// A medicine on the household's list (Settings in the app), so Siri can hear its name in a phrase.
/// The phrases are refreshed when the app starts and whenever the list changes, on either phone
/// (`WidgetRefresher`, `updateAppShortcutParameters`).
struct MedicineEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Medicine"
    static let defaultQuery = MedicineQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }

    init(id: String) {
        self.id = id
    }
}

struct MedicineQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [MedicineEntity] {
        let list = await Self.list()
        return identifiers.filter { list.contains($0) }.map(MedicineEntity.init)
    }

    func entities(matching string: String) async throws -> [MedicineEntity] {
        let wanted = string.lowercased()
        return await Self.list().filter { $0.lowercased().contains(wanted) }.map(MedicineEntity.init)
    }

    func suggestedEntities() async throws -> [MedicineEntity] {
        await Self.list().map(MedicineEntity.init)
    }

    /// The household's list as Settings shows it (a new household's starts with Vitamin D).
    @MainActor
    static func list() -> [String] {
        AppModel.shared.store.data.medicines
    }
}

@MainActor
enum VoiceRunner {
    /// The baby's name for Siri's questions: "How much formula did Sam drink?"
    static var babyName: String {
        let name = AppModel.shared.babyDetails?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "the baby" : name
    }

    private static var timeZoneID: String { AppModel.shared.store.data.householdSettings.timeZoneID }

    // MARK: Finish the feed

    static func finish(_ intent: FinishFeedIntent) async -> String {
        let model = AppModel.shared
        guard let me = model.me, let result = await QuickFeedRunner.finishOnly() else { return GlanceText.notSetUp }
        guard case .finished(let feed) = result else {
            await QuickFeedRunner.settle()
            return GlanceText.said(result, me: me, names: model.memberNames, timeZoneID: timeZoneID, now: Date())
        }
        // Saved and the alarms set before any question, so going quiet loses nothing. The details
        // panel is set to open in the app now, and only cleared once every answer is in, so a
        // conversation Siri cuts short still leaves it (Codex review of doc 15, 6).
        await QuickFeedRunner.settleSoon()
        if feed.event.loggedBy == me { UserDefaults.standard.set(feed.id, forKey: FeedControls.detailsKey) }
        var notes: [String] = []
        do {
            for question in model.store.data.voiceQuestions(for: feed, bottleOnly: QuickFeedRunner.isBottleOnly) {
                switch question {
                case .amount(let bottleID, let milk):
                    if let note = try await askAmount(intent.$ml, feedID: feed.id, bottleID: bottleID, milk: milk) {
                        notes.append(note)
                    }
                case .sides:
                    let choice = try await intent.$sides.requestValue(IntentDialog(stringLiteral: SiriText.whichSides))
                    for side in choice.sides?.sides ?? [] { apply(.addSide(feedID: feed.id, side: side)) }
                case .milkAndAmount:
                    let milk = try await intent.$milk.requestValue(IntentDialog(stringLiteral: SiriText.whichMilk)).kind
                    // The bottle is saved as soon as its milk is known; the amount follows.
                    let bottleID = UUID().uuidString
                    apply(.addBottle(feedID: feed.id, bottleID: bottleID, milk: milk, ml: nil))
                    if let note = try await askAmount(intent.$ml, feedID: feed.id, bottleID: bottleID, milk: milk) {
                        notes.append(note)
                    }
                }
            }
            if notes.isEmpty, UserDefaults.standard.string(forKey: FeedControls.detailsKey) == feed.id {
                UserDefaults.standard.removeObject(forKey: FeedControls.detailsKey)
            }
        } catch {
            // Gone quiet or Cancel: what was said stays; the app's details panel asks the rest.
        }
        await QuickFeedRunner.settle()
        let saved = model.store.data.events[feed.id]?.snapshot ?? feed
        let said = SiriText.finished(saved, me: me, names: model.memberNames, timeZoneID: timeZoneID, now: Date())
        return ([said] + notes).joined(separator: " ")
    }

    /// Asks a bottle's amount, reads it back, and fills it only while it is still empty (Codex
    /// review of doc 15, 2). Returns what Siri adds to its reply, if anything.
    private static func askAmount(_ parameter: IntentParameter<Int?>, feedID: String, bottleID: String, milk: MilkKind,
                                  given: Int? = nil) async throws -> String? {
        guard let ml = try await SiriAmount.ask(parameter, milk: milk, baby: babyName, given: given) else {
            return SiriText.amountNotSaved
        }
        let gap = AppModel.shared.store.data.voiceAmountGap(feedID: feedID, bottleID: bottleID)
        guard gap.present else { return SiriText.amountNotSaved }
        if let saved = gap.ml { return SiriText.amountAlreadySaved(saved, milk) }
        apply(.amount(feedID: feedID, bottleID: bottleID, ml: ml))
        return nil
    }

    // MARK: Add a bottle

    static func addBottle(_ intent: AddBottleIntent) async -> String {
        let model = AppModel.shared
        guard let me = model.me, let baby = model.baby else { return GlanceText.notSetUp }
        let milk: MilkKind
        if let named = intent.milk {
            milk = named.kind
        } else {
            guard let said = try? await intent.$milk.requestValue(IntentDialog(stringLiteral: SiriText.whichMilk)) else { return "" }
            milk = said.kind
        }
        let feeds = model.store.data.voiceFeeds(babyID: baby.name, by: me, now: Date())
        switch VoiceLog.bottleTarget(running: feeds.running, last: feeds.last, milk: milk, now: Date()) {
        case .runningNotMine:
            return SiriText.runningNotMine
        case .runningHasBottle:
            return SiriText.runningHasBottle
        case .alreadyHas(let id):
            let start = model.store.data.events[id]?.event.startedAt ?? Date()
            return SiriText.alreadyHas(milk, feedStart: start, timeZoneID: timeZoneID)
        case .noFeed:
            return SiriText.noFeed
        case .feed(let id):
            guard let feed = model.store.data.events[id]?.event else { return SiriText.noFeed }
            // The bottle is saved first, so going quiet at the amount keeps it (Codex review, 6).
            let bottleID = UUID().uuidString
            guard apply(.addBottle(feedID: id, bottleID: bottleID, milk: milk, ml: nil)) == .applied else {
                await QuickFeedRunner.settle()
                return SiriText.noFeed
            }
            await QuickFeedRunner.settleSoon()
            // A bottle during a feed has its amount asked at Finish, as in the app.
            var note: String?
            var ml: Int?
            if feed.endedAt != nil {
                do {
                    note = try await askAmount(intent.$ml, feedID: id, bottleID: bottleID, milk: milk, given: intent.ml)
                } catch {
                    note = SiriText.amountNotSaved
                }
                ml = model.store.data.voiceAmountGap(feedID: id, bottleID: bottleID).ml
            }
            await QuickFeedRunner.settle()
            let said = SiriText.bottleAdded(ml: ml, milk: milk, feedStart: feed.startedAt, timeZoneID: timeZoneID)
            return [said, note].compactMap { $0 }.joined(separator: " ")
        }
    }

    // MARK: Nappy

    static func nappy(_ intent: LogNappyIntent) async -> String {
        let model = AppModel.shared
        guard let me = model.me, let baby = model.baby else { return GlanceText.notSetUp }
        let kind: NappyKindChoice
        if let named = intent.kind {
            kind = named
        } else {
            guard let said = try? await intent.$kind.requestValue(IntentDialog(stringLiteral: SiriText.weeOrPoo)) else { return "" }
            kind = said
        }
        let at = Date()
        let id = UUID().uuidString
        model.store.change { data in
            _ = data.addNappy(id: id, babyID: baby.name, wee: kind.wee, poo: kind.poo, by: me,
                              timeZoneID: TimeZone.current.identifier, now: at)
            data.events[id]?.uploadNotBefore = nil
        }
        // Saved before the details are asked, so going quiet loses nothing.
        await QuickFeedRunner.settleSoon()
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
                apply(.pooDetails(nappyID: id, colour: colour, consistency: consistency))
            }
        }
        await QuickFeedRunner.settle()
        return SiriText.nappy(at: at, wee: kind.wee, poo: kind.poo, colour: colour, consistency: consistency,
                              timeZoneID: timeZoneID)
    }

    // MARK: Medicine

    static func medicine(_ intent: LogMedicineIntent) async -> String {
        // The household's own list: an empty list stays empty, never Vitamin D by itself (Codex
        // review of doc 15, 1).
        let list = MedicineQuery.list()
        guard !list.isEmpty else { return SiriText.noMedicines }
        let name: String
        if let named = intent.medicine?.id, list.contains(named) {
            name = named
        } else if list.count == 1 {
            name = list[0]
        } else {
            guard let chosen = try? await intent.$medicine.requestDisambiguation(
                among: list.map(MedicineEntity.init), dialog: IntentDialog(stringLiteral: SiriText.whichMedicine)),
                list.contains(chosen.id)
            else { return "" }
            name = chosen.id
        }
        return await QuickFeedRunner.medicine(name)
    }

    // MARK: Saving

    /// Saves an answer as the watch's same tap would, on this phone, now.
    @discardableResult
    private static func apply(_ action: WatchAction) -> WatchOutcome {
        let model = AppModel.shared
        guard let me = model.me, let baby = model.baby else { return .refused }
        let now = Date()
        return model.store.change {
            $0.applyWatchAction(WatchActionRequest(action: action, at: now), babyID: baby.name, by: me,
                                timeZoneID: TimeZone.current.identifier, now: now)
        }
    }
}
