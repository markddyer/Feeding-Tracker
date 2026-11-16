import FeedingCore
import SwiftUI

/// Something the last tap did that Undo can take back, for 10 seconds.
struct UndoAction {
    let message: String
    let expiresAt: Date
    let perform: @MainActor () -> Void

    init(message: String, perform: @escaping @MainActor () -> Void) {
        self.message = message
        expiresAt = Date().addingTimeInterval(HouseholdData.undoWindow)
        self.perform = perform
    }
}

struct UndoBanner: View {
    let action: UndoAction
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Text(action.message).feedText(.subheadline)
            Spacer()
            Button("Undo") {
                action.perform()
                dismiss()
            }
            .feedText(.smallButton)
            .foregroundStyle(Theme.text)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 48)
        .background(Theme.surface, in: Capsule())
    }
}

/// The big buttons at the bottom of the home screen. Ordinary buttons in the content, pinned to
/// the bottom so they stay in reach, away from the Duo's fold in the laptop pose (plan v1).
struct FeedControls: View {
    let facts: HomeFacts
    let me: MemberID
    let babyID: String
    let onUndo: (UndoAction) -> Void

    /// The feed whose details are being filled in after it finished. Kept on the phone, so a feed
    /// finished from the Lock Screen or Siri (`QuickFeedRunner`) opens the panel here too.
    @AppStorage(Self.detailsKey) private var detailsForID = ""
    static let detailsKey = "home.detailsFor"
    private var detailsFor: String? {
        get { detailsForID.isEmpty ? nil : detailsForID }
        nonmutating set { detailsForID = newValue ?? "" }
    }
    @State private var choosingBottle = false
    /// The running feed that Stop asks about removing.
    @State private var stopping: String?
    @State private var editor: EventEditor.Mode?
    /// The feed whose "add the details?" offer was answered, so it doesn't come back.
    @AppStorage("home.detailsOfferAnswered") private var detailsOfferAnswered = ""
    @AppStorage(FeedingStyle.storageKey) private var feedingStyle = ""
    @State private var choosingStartBottle = false

    private var store: HouseholdStore { AppModel.shared.store }
    private var bottleOnly: Bool { feedingStyle == FeedingStyle.bottleOnly.rawValue }

    var body: some View {
        VStack(spacing: 10) {
            if let feed = facts.feedInProgress {
                if feed.event.loggedBy == me {
                    duringFeed(feed)
                } else {
                    othersFeed(feed)
                }
            } else if let id = detailsFor, let feed = store.data.events[id]?.snapshot, feed.event.deletedAt == nil,
                      let ended = feed.event.endedAt, facts.now.timeIntervalSince(ended) < 2 * 3600 {
                FeedDetailsPanel(feed: feed, me: me, bottleOnly: bottleOnly) { detailsFor = nil }
            } else if let offer = facts.feedFinishedForMe, offer.feed.id != detailsOfferAnswered {
                let who = facts.name(offer.by).capitalizedFirst
                FeedDetailsPanel(feed: offer.feed, me: me, bottleOnly: bottleOnly,
                                 note: bottleOnly ? "\(who) finished your feed. Add the bottle amount?"
                                                  : "\(who) finished your feed. Add the sides and bottles?") {
                    detailsOfferAnswered = offer.feed.id
                }
            } else {
                idle
            }
        }
        .confirmationDialog("Which bottle?", isPresented: $choosingBottle) {
            Button("Expressed milk") { addBottle(.expressed) }
            Button("Formula") { addBottle(.formula) }
        }
        .confirmationDialog("Which bottle?", isPresented: $choosingStartBottle) {
            Button("Expressed milk") { startFeed(bottle: .expressed) }
            Button("Formula") { startFeed(bottle: .formula) }
        }
        .confirmationDialog("Remove this feed?",
                            isPresented: Binding { stopping != nil } set: { if !$0 { stopping = nil } },
                            titleVisibility: .visible, presenting: stopping) { id in
            Button("Remove feed", role: .destructive) { undoAdd(id) }
        } message: { _ in
            Text("It will not be logged. To end a real feed, tap Finish.")
        }
        .sheet(item: $editor) { mode in
            EventEditor(mode: mode, me: me, babyID: babyID)
        }
    }

    // MARK: No feed running

    private var idle: some View {
        VStack(spacing: 10) {
            BigButton(title: "Start feed", prominent: true, mark: .bottle) {
                if bottleOnly {
                    choosingStartBottle = true
                } else {
                    startFeed(bottle: nil)
                }
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach([10, 20, 30, 45], id: \.self) { minutes in
                        Button("Started about \(minutes) min ago") { logJustFinished(minutesAgo: minutes) }
                    }
                } label: {
                    smallLabel("Just finished")
                }
                .buttonStyle(PressStyle())
                Button { editor = .newFeed } label: { smallLabel("Earlier") }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Log an earlier feed")
                Button { editor = .newPump } label: { smallLabel("Pumping") }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Log pumping")
            }
            .foregroundStyle(Theme.text)
        }
    }

    private func smallLabel(_ title: String) -> some View {
        Text(title)
            .feedText(.smallButton)
            // Two lines at the biggest text sizes, rather than cutting a word off.
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.smallButton))
    }

    private func startFeed(bottle: MilkKind?) {
        // No Undo bar here: the feed has a Stop button for as long as it runs.
        store.change {
            _ = $0.startFeed(babyID: babyID, side: nil, bottle: bottle, by: me, timeZoneID: TimeZone.current.identifier, now: Date())
        }
    }

    private func logJustFinished(minutesAgo: Int) {
        let now = Date()
        let id = store.change {
            $0.add(kind: .feed, babyID: babyID, startedAt: now.addingTimeInterval(-Double(minutesAgo) * 60), endedAt: now,
                   payload: EventPayload(feed: FeedDetails()), by: me, timeZoneID: TimeZone.current.identifier, now: now)
        }
        detailsFor = id
        onUndo(UndoAction(message: "Feed logged") { undoAdd(id) })
    }

    // MARK: A feed running

    private func duringFeed(_ feed: EventSnapshot) -> some View {
        let current = feed.payload?.feed?.breast.last.flatMap { $0.durationSeconds == nil ? $0 : nil }
        let suggested = facts.nextSide
        let bottles = feed.payload?.feed?.bottles ?? []
        return VStack(spacing: 8) {
            // A bottle-only parent has no side buttons: the bottle was chosen at Start feed, and
            // the hero shows it.
            if !bottleOnly {
                HStack(spacing: 8) {
                    ForEach(BreastSide.allCases, id: \.self) { side in
                        SideButton(mark: .side(side), title: side == .left ? "Left" : "Right",
                                   selected: current?.side == side,
                                   hint: current == nil && suggested == side ? "suggested" : nil) {
                            guard current?.side != side else { return }
                            change(feed, message: "\(side == .left ? "Left" : "Right") side") {
                                $0.switchSide(feed.id, to: side, by: me, now: Date())
                            }
                        }
                    }
                    // Goes once a bottle is added, so a second tap can't add it twice. A second
                    // bottle can be added after Finish.
                    if bottles.isEmpty {
                        SideButton(mark: .bottle, title: "Bottle", selected: false) { choosingBottle = true }
                    }
                }
            }
            HStack(spacing: 8) {
                // For a feed started by mistake: removes it, after asking (the user's decision,
                // 15 Nov 2026). Narrower than Finish, so a sleepy tap lands on Finish.
                BigButton(title: "Stop · discard", prominent: false) { stopping = feed.id }
                    .frame(maxWidth: 150)
                    .accessibilityLabel("Stop and discard this feed")
                BigButton(title: "Finish", prominent: true) {
                    change(feed, message: "Feed finished") { $0.finishFeed(feed.id, by: me, now: Date()) }
                    detailsFor = feed.id
                }
            }
        }
    }

    /// A feed the other parent started. Only they add sides and bottles while it runs, as they
    /// know what the feed is. If they're busy, this phone can finish it for them, and their phone
    /// then offers to add the details. The hero says who started it.
    private func othersFeed(_ feed: EventSnapshot) -> some View {
        let name = facts.name(feed.event.loggedBy)
        return BigButton(title: "Finish for \(name)", prominent: false) {
            change(feed, message: "Feed finished for \(name)") { $0.finishFeed(feed.id, by: me, now: Date()) }
        }
        .accessibilityHint("\(name.capitalizedFirst) adds the sides and bottles. Their phone offers to add them after.")
    }

    private func addBottle(_ milk: MilkKind) {
        guard let feed = facts.feedInProgress else { return }
        change(feed, message: milk == .formula ? "Formula bottle added" : "Expressed milk bottle added") {
            $0.edit(feed.id, by: me, now: Date()) { snapshot in
                var details = snapshot.payload?.feed ?? FeedDetails()
                details.bottles.append(Bottle(milk: milk))
                snapshot.payload?.feed = details
            }
        }
    }

    // MARK: Undo

    /// Makes a change to a feed, with Undo putting the feed back as it was.
    private func change(_ feed: EventSnapshot, message: String, _ body: @escaping (inout HouseholdData) -> Bool) {
        let before = feed
        store.change { _ = body(&$0) }
        let me = me
        onUndo(UndoAction(message: message) {
            AppModel.shared.store.change { data in
                data.edit(before.id, by: me, now: Date()) { $0 = before }
            }
        })
    }

    /// Undo for a new feed: gone completely if it hasn't been sent yet, otherwise hidden.
    private func undoAdd(_ id: String) {
        let me = me
        store.change { data in
            if !data.undoAdd(id, now: Date()) {
                data.delete(id, by: me, now: Date())
            }
        }
        if detailsFor == id { detailsFor = nil }
    }
}

/// Which questions the details panel still asks. Each choice goes once it is made, so a second
/// tap can't log the same side or bottle twice. Anything more is added in History.
struct DetailChoices: Equatable {
    /// Sides not logged yet.
    let sides: [BreastSide]
    /// Kinds of bottle not logged yet.
    let milks: [MilkKind]
    /// Bottles still waiting for their amount.
    let unmeasured: [Bottle]

    init(_ details: FeedDetails, bottleOnly: Bool) {
        let loggedSides = Set(details.breast.map(\.side))
        let loggedMilks = Set(details.bottles.map(\.milk))
        unmeasured = details.bottles.filter { $0.ml == nil }
        if bottleOnly {
            // One bottle, chosen at Start feed or here, then its amount.
            sides = []
            milks = details.bottles.isEmpty ? MilkKind.allCases : []
        } else {
            sides = BreastSide.allCases.filter { !loggedSides.contains($0) }
            milks = MilkKind.allCases.filter { !loggedMilks.contains($0) }
        }
    }

    /// Nothing left to ask, so the panel closes by itself.
    var isComplete: Bool { sides.isEmpty && milks.isEmpty && unmeasured.isEmpty }
}

/// After Finish, or after logging a finished feed: add sides and bottles, and bottle amounts.
struct FeedDetailsPanel: View {
    let feed: EventSnapshot
    let me: MemberID
    /// True on a bottle-only parent's phone: no side buttons.
    var bottleOnly = false
    var note: String?
    let done: () -> Void

    private var store: HouseholdStore { AppModel.shared.store }

    var body: some View {
        let choices = DetailChoices(feed.payload?.feed ?? FeedDetails(), bottleOnly: bottleOnly)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("This feed").feedText(.label).foregroundStyle(Theme.textMuted)
                if let note {
                    Text(note).feedText(.subheadline).foregroundStyle(Theme.textMuted)
                }
                FeedChips(snapshot: feed)
            }
            if !choices.sides.isEmpty || !choices.milks.isEmpty {
                question(bottleOnly ? "Which bottle?" : "Add to this feed") {
                    if !choices.sides.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(choices.sides, id: \.self) { side in
                                ChoiceChip(mark: .side(side), title: side == .left ? "Left" : "Right",
                                           spoken: "Add the \(side == .left ? "left" : "right") side") {
                                    edit { $0.breast.append(BreastSegment(side: side)) }
                                }
                            }
                        }
                    }
                    if !choices.milks.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(choices.milks, id: \.self) { milk in
                                ChoiceChip(mark: .bottle, title: HomeText.milkName(milk),
                                           spoken: "Add a \(HomeText.milkName(milk).lowercased()) bottle") {
                                    edit { $0.bottles.append(Bottle(milk: milk)) }
                                }
                            }
                        }
                    }
                }
            }
            // One bottle at a time, so the panel holds one wheel. Its Save is the main button and
            // Done the soft one beside it, so a sleepy tap saves the amount on the wheel.
            if let bottle = choices.unmeasured.first {
                let babyID = feed.event.babyID
                let last = lastBottleAmount(store.data.visibleSnapshots(babyID: babyID), babyID: babyID, milk: bottle.milk)
                AmountQuestion(milk: bottle.milk, start: AmountWheel.start(last), done: done) { setAmount(bottle.id, $0) }
                    .id(bottle.id)
            } else {
                BigButton(title: "Done", prominent: true, action: done)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile))
        .onChange(of: choices.isComplete, initial: true) { _, complete in
            if complete { done() }
        }
    }

    /// A question as a small label, then its answers as big chips.
    private func question<Answers: View>(_ title: String, @ViewBuilder answers: () -> Answers) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).feedText(.label).foregroundStyle(Theme.textMuted)
            answers()
        }
    }

    private func edit(_ change: @escaping (inout FeedDetails) -> Void) {
        let me = me
        store.change { data in
            data.edit(feed.id, by: me, now: Date()) { snapshot in
                var details = snapshot.payload?.feed ?? FeedDetails()
                change(&details)
                snapshot.payload?.feed = details
            }
        }
    }

    private func setAmount(_ bottleID: String, _ ml: Int) {
        edit { details in
            if let index = details.bottles.firstIndex(where: { $0.id == bottleID }) {
                details.bottles[index].ml = ml
            }
        }
    }
}

/// "How much formula?": the amount wheel, then Save beside a soft Done. Turning the wheel saves
/// nothing, so a bottle never gets an amount nobody chose; Save does. Done closes the panel with
/// no amount, as before.
private struct AmountQuestion: View {
    let milk: MilkKind
    let done: () -> Void
    let save: (Int) -> Void
    @State private var ml: Int

    init(milk: MilkKind, start: Int, done: @escaping () -> Void, save: @escaping (Int) -> Void) {
        self.milk = milk
        self.done = done
        self.save = save
        _ml = State(initialValue: start)
    }

    var body: some View {
        let title = "How much \(HomeText.milkName(milk).lowercased())?"
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).feedText(.label).foregroundStyle(Theme.textMuted)
                AmountWheel(ml: $ml, label: title)
                    .frame(maxWidth: .infinity)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.smallButton))
            }
            HStack(spacing: 8) {
                BigButton(title: "Done", prominent: false, action: done)
                    .frame(maxWidth: 120)
                    .accessibilityLabel("Done, with no amount")
                BigButton(title: "Save", prominent: true, mark: .bottle, amount: "\(ml) ml") { save(ml) }
                    .accessibilityLabel("Save \(ml) millilitres")
            }
        }
    }
}

/// A large, easy target for one hand in the dark (DESIGN.md, "Big button"): `primary` for the
/// main action, `surface` for the soft one, with a Fredoka label and an optional feed shape.
struct BigButton: View {
    let title: String
    let prominent: Bool
    var hint: String?
    var mark: FeedMark?
    /// A number after the title ("30 ml"), in SF Pro Rounded: never a number in Fredoka.
    var amount: String?
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        let foreground = prominent ? Theme.onPrimary : Theme.text
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 10) {
                    if let mark {
                        FeedMarkView(mark, size: 24, relativeTo: .title3, colour: foreground)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .feedText(.button)
                        // Two lines at the biggest text sizes, rather than cutting a word off.
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75)
                    if let amount {
                        Text(amount)
                            .feedText(.total)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                if let hint {
                    Text(hint).feedText(.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(foreground)
            .background(prominent ? Theme.primary : Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile))
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile))
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }
}

/// Left, Right and Bottle during a feed (DESIGN.md, "Side buttons"): 64 points tall, the shape
/// above the label. The side being fed fills with the breast colour.
struct SideButton: View {
    let mark: FeedMark
    let title: String
    let selected: Bool
    var hint: String?
    let action: () -> Void
    @Environment(\.look) private var look
    @State private var taps = 0

    var body: some View {
        let fill = selected ? (mark == .bottle ? Theme.bottle : Theme.breast) : Theme.surface
        // Dark letters on the pink by day; the night text colour at night (DESIGN.md mockup).
        let foreground = selected ? (look == .night ? Theme.text : Theme.onPrimary) : Theme.text
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 2) {
                FeedMarkView(mark, size: 22, relativeTo: .title3, colour: selected ? foreground : nil)
                    .accessibilityHidden(true)
                Text(title)
                    .feedText(.tileValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let hint {
                    Text(hint).feedText(.small).foregroundStyle(selected ? foreground : Theme.textMuted)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.tile))
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile))
        }
        .buttonStyle(PressStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityLabel(hint.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An answer in the details panel ("Formula", "60 ml"): a big chip in the background colour,
/// so it reads as a hole in the panel, at least 48 points tall.
struct ChoiceChip: View {
    let mark: FeedMark?
    let title: String
    var spoken: String?
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: 6) {
                if let mark {
                    FeedMarkView(mark, size: 18, relativeTo: .subheadline)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .feedText(.smallButton)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.smallButton))
            .contentShape(RoundedRectangle(cornerRadius: Radius.smallButton))
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(Theme.text)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityLabel(spoken ?? title)
    }
}
