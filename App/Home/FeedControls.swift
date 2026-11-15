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
            Text(action.message).font(.subheadline)
            Spacer()
            Button("Undo") {
                action.perform()
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(Theme.raisedSurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// The big buttons at the bottom of the home screen. Ordinary buttons in the content, pinned to
/// the bottom so they stay in reach, away from the Duo's fold in the laptop pose (plan v1).
struct FeedControls: View {
    let facts: HomeFacts
    let me: MemberID
    let babyID: String
    let onUndo: (UndoAction) -> Void

    /// The feed whose details are being filled in after it finished.
    @State private var detailsFor: String?
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
            } else if let id = detailsFor, let feed = store.data.events[id]?.snapshot, feed.event.deletedAt == nil {
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
            BigButton(title: "Start feed", prominent: true) {
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
                Button { editor = .newFeed } label: { smallLabel("Earlier feed") }
                Button { editor = .newPump } label: { smallLabel("Pumping") }
            }
            .foregroundStyle(Theme.text)
        }
    }

    private func smallLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
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
        let bottleLine = bottles.map { $0.milk == .formula ? "Formula" : "Expressed milk" }.joined(separator: " + ")
        return VStack(spacing: 10) {
            if bottleOnly {
                // A bottle-only parent: no sides. The bottle was chosen at Start feed.
                Text(bottles.isEmpty ? "Bottle" : bottleLine)
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                if let current, let started = current.startedAt {
                    HStack(spacing: 6) {
                        Text(current.side == .left ? "Left" : "Right")
                        Text(started, style: .timer).monospacedDigit()
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
                }
                if !bottles.isEmpty {
                    Text(bottleLine).font(.headline).foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 10) {
                    ForEach(BreastSide.allCases, id: \.self) { side in
                        BigButton(title: side == .left ? "Left" : "Right",
                                  prominent: current?.side == side,
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
                        BigButton(title: "Bottle", prominent: false) { choosingBottle = true }
                    }
                }
            }
            HStack(spacing: 10) {
                // For a feed started by mistake: removes it, after asking (the user's decision,
                // 15 Nov 2026). Narrower than Finish, so a sleepy tap lands on Finish.
                BigButton(title: "Stop", prominent: false) { stopping = feed.id }
                    .frame(width: 110)
                BigButton(title: "Finish", prominent: true) {
                    change(feed, message: "Feed finished") { $0.finishFeed(feed.id, by: me, now: Date()) }
                    detailsFor = feed.id
                }
            }
        }
    }

    /// A feed the other parent started. Only they add sides and bottles while it runs, as they
    /// know what the feed is. If they're busy, this phone can finish it for them, and their phone
    /// then offers to add the details.
    private func othersFeed(_ feed: EventSnapshot) -> some View {
        let name = facts.name(feed.event.loggedBy)
        return VStack(spacing: 10) {
            Text("\(name.capitalizedFirst) started this feed and adds the sides and bottles. If \(name) is busy, you can finish it.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            BigButton(title: "Finish for \(name)", prominent: false) {
                change(feed, message: "Feed finished for \(name)") { $0.finishFeed(feed.id, by: me, now: Date()) }
            }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            if let note {
                Text(note).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            Text(HomeFacts.details(feed)).font(.headline)
            if bottleOnly, !choices.milks.isEmpty {
                Text("Which bottle?").font(.subheadline)
            }
            if !choices.sides.isEmpty || !choices.milks.isEmpty {
                HStack(spacing: 8) {
                    ForEach(choices.sides, id: \.self) { side in
                        small(side == .left ? "+ Left" : "+ Right") { edit { $0.breast.append(BreastSegment(side: side)) } }
                    }
                    ForEach(choices.milks, id: \.self) { milk in
                        let title = milk == .formula ? "Formula" : (bottleOnly ? "Expressed milk" : "Expressed")
                        small(bottleOnly ? title : "+ \(title)") { edit { $0.bottles.append(Bottle(milk: milk)) } }
                    }
                }
            }
            ForEach(choices.unmeasured) { bottle in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(bottle.milk == .formula ? "Formula" : "Expressed milk"): how much?").font(.subheadline)
                    HStack(spacing: 8) {
                        ForEach([30, 60, 90, 120], id: \.self) { ml in
                            small("\(ml) ml") { setAmount(bottle.id, ml) }
                        }
                    }
                }
            }
            BigButton(title: "Done", prominent: true, action: done)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: choices.isComplete, initial: true) { _, complete in
            if complete { done() }
        }
    }

    private func small(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.raisedSurface, in: RoundedRectangle(cornerRadius: 10))
        }
        .foregroundStyle(Theme.text)
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

/// A large, easy target for one hand in the dark.
struct BigButton: View {
    let title: String
    let prominent: Bool
    var hint: String?
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                if let hint {
                    Text(hint).font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(prominent ? Color.black : Theme.text)
            .background(prominent ? Theme.accent : Theme.raisedSurface, in: RoundedRectangle(cornerRadius: 16))
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }
}
