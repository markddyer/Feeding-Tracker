#if FEEDING_DEV
import FeedingCore
import SwiftUI

/// Feeding Dev only: drives the real household store and sync before the real screens exist.
struct HouseholdDebugView: View {
    private let store = AppModel.shared.store
    private let sync = AppModel.shared.sync
    @State private var pastedLink = ""
    @State private var lastAdded: (id: String, at: Date)?

    private var baby: PlainRecord? { store.data.plainRecords(of: .baby).first { $0.archivedAt == nil } }

    var body: some View {
        List {
            statusSection
            setupSection
            peopleSection
            if let baby, let me = sync.memberID {
                logSection(babyID: baby.name, me: me)
                alertsSection
                eventsSection(babyID: baby.name, me: me)
            }
        }
        .navigationTitle("Household sync test")
        .task {
            await sync.refreshAccount()
            await sync.fetchNow()
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section("1. This phone") {
            LabeledContent("iCloud", value: sync.accountStatus)
            LabeledContent("Household", value: roleText)
            LabeledContent("Parent ID", value: sync.memberID.map { "…" + $0.rawValue.suffix(6) } ?? "not known yet")
            LabeledContent("Waiting to send", value: "\(store.data.eventsToUpload(now: .distantFuture).count + store.data.plainRecordsToUpload().count)")
            if let at = sync.lastFetchAt {
                LabeledContent("Last fetch", value: at.formatted(date: .omitted, time: .standard))
            }
            if let at = sync.lastSendAt {
                LabeledContent("Last send", value: at.formatted(date: .omitted, time: .standard))
            }
            if let problem = sync.problem ?? store.problem {
                Text(problem).foregroundStyle(.orange)
                Button("Clear the message") { sync.clearProblem() }
            }
            if let detail = sync.errorDetail {
                Text("Last error in full: \(detail)")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private var roleText: String {
        switch sync.role {
        case .notSetUp: "not set up"
        case .owner: "this phone shares it"
        case .member: "this phone joined it"
        }
    }

    @ViewBuilder
    private var setupSection: some View {
        Section("2. Set up") {
            switch sync.role {
            case .notSetUp:
                Button("Create the household and invite") {
                    Task { await sync.createHouseholdAndInvite() }
                }
                .disabled(sync.busy)
                TextField("Or paste an invite link", text: $pastedLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Join with the pasted link") {
                    Task { await sync.acceptPastedLink(pastedLink) }
                }
                .disabled(pastedLink.isEmpty || sync.busy)
            case .owner:
                Button("Invite the other phone again") {
                    Task { await sync.createHouseholdAndInvite() }
                }
                .disabled(sync.busy)
            case .member:
                Text("Joined. Nothing to set up.")
            }
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        Section("3. Baby and parents") {
            if let baby {
                LabeledContent("Baby", value: PayloadCoder.decode(BabyPayload.self, from: baby.payload)?.name ?? "details unreadable")
            } else {
                Button("Add a test baby") {
                    store.change {
                        $0.put(PlainRecord(type: .baby, name: UUID().uuidString, modifiedAt: Date(),
                                           payload: try? PayloadCoder.encode(BabyPayload(name: "Test baby"))))
                    }
                }
                // Only the phone that shares the household adds the baby, so there is only one.
                .disabled(sync.role != .owner)
            }
            ForEach(store.data.plainRecords(of: .member), id: \.name) { member in
                LabeledContent(member.name == sync.memberID?.rawValue ? "This phone" : "Other phone",
                               value: PayloadCoder.decode(MemberPayload.self, from: member.payload)?.displayName ?? "?")
            }
            if let me = sync.memberID, store.data.plainRecord(.member, me.rawValue) == nil {
                Button("Add this phone's parent") {
                    let owner = sync.role == .owner
                    store.change {
                        $0.put(PlainRecord(type: .member, name: me.rawValue, modifiedAt: Date(), payload: try? PayloadCoder.encode(
                            MemberPayload(displayName: owner ? "Parent A" : "Parent B", colour: owner ? "amber" : "teal"))))
                    }
                }
                .disabled(sync.role == .notSetUp)
            }
        }
    }

    private func logSection(babyID: String, me: MemberID) -> some View {
        let now = Date()
        let summary = summarise(store.data.snapshots, babyID: babyID, from: now.addingTimeInterval(-24 * 3600), to: now)
        let next = suggestedNextSide(store.data.snapshots, babyID: babyID, now: now)
        return Section {
            if let feed = store.data.feedInProgress(babyID: babyID) {
                Text("Feed in progress since \(feed.event.startedAt.formatted(date: .omitted, time: .shortened))")
                HStack {
                    Button("Left") { store.change { $0.switchSide(feed.id, to: .left, by: me, now: Date()) } }
                    Spacer()
                    Button("Right") { store.change { $0.switchSide(feed.id, to: .right, by: me, now: Date()) } }
                    Spacer()
                    Button("Finish") { store.change { $0.finishFeed(feed.id, by: me, now: Date()) } }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Start a feed on the \(next == .right ? "right" : "left")") {
                    let id = store.change {
                        $0.startFeed(babyID: babyID, side: next ?? .left, by: me, timeZoneID: TimeZone.current.identifier, now: Date())
                    }
                    lastAdded = (id, Date())
                }
            }
            Button("Log a 60 ml formula bottle, 20 minutes ago") {
                let start = Date().addingTimeInterval(-20 * 60)
                let id = store.change {
                    $0.add(kind: .feed, babyID: babyID, startedAt: start, endedAt: start.addingTimeInterval(10 * 60),
                           payload: EventPayload(feed: FeedDetails(bottles: [Bottle(milk: .formula, ml: 60)])),
                           by: me, timeZoneID: TimeZone.current.identifier, now: Date())
                }
                lastAdded = (id, Date())
            }
            if let lastAdded, Date().timeIntervalSince(lastAdded.at) < HouseholdData.undoWindow {
                Button("Undo the last one (within 10 seconds)") {
                    store.change { $0.undoAdd(lastAdded.id, now: Date()) }
                    self.lastAdded = nil
                }
            }
        } header: {
            Text("4. Log")
        } footer: {
            Text("Next side: \(next.map { $0 == .left ? "left" : "right" } ?? "no breastfeed yet"). Last 24 hours: \(summary.feeds) feeds, \(summary.breastFeeds) at the breast, \(summary.expressedML) ml expressed, \(summary.formulaML) ml formula.")
        }
    }

    private var alertsSection: some View {
        let reconciler = AppModel.shared.reconciler
        let zone = store.data.householdSettings.timeZone
        return Section {
            LabeledContent("Alarms allowed", value: reconciler.alarmsAllowed ? "yes" : "no")
            Button("Ask for alarm and notification permission") {
                Task { await reconciler.requestPermissions() }
            }
            Picker("Day style", selection: styleBinding(\.dayStyle)) {
                Text("Loud alarm").tag(AlertStyle.loudAlarm)
                Text("Gentle nudge").tag(AlertStyle.gentleNudge)
            }
            Picker("Night style", selection: styleBinding(\.nightStyle)) {
                Text("Loud alarm").tag(AlertStyle.loudAlarm)
                Text("Gentle nudge").tag(AlertStyle.gentleNudge)
            }
            if reconciler.alerts.isEmpty {
                Text("No alerts set.").foregroundStyle(.secondary)
            }
            ForEach(reconciler.alerts, id: \.key) { alert in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(alert.fireDate.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))) · \(alert.purpose.rawValue) · \(alert.mechanism.rawValue)")
                    Text(AlertText.title(for: alert)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let error = reconciler.lastError {
                Text(error).foregroundStyle(.orange)
            }
        } header: {
            Text("5. Alerts on this phone")
        } footer: {
            Text("Worked out again after every change, from either phone.")
        }
    }

    private func styleBinding(_ keyPath: WritableKeyPath<MemberPreferences, AlertStyle>) -> Binding<AlertStyle> {
        Binding {
            AppModel.shared.reconciler.preferences[keyPath: keyPath]
        } set: { style in
            AppModel.shared.reconciler.preferences[keyPath: keyPath] = style
        }
    }

    private func eventsSection(babyID: String, me: MemberID) -> some View {
        let events = store.data.events.values
            .filter { $0.event.babyID == babyID && ($0.event.kind == .feed || $0.event.kind == .pump) }
            .sorted { $0.event.startedAt > $1.event.startedAt }
        return Section("6. Feeds, newest first") {
            if events.isEmpty {
                Text("None yet.").foregroundStyle(.secondary)
            }
            ForEach(events, id: \.event.id) { stored in
                EventRow(stored: stored, me: me, members: store.data.plainRecords(of: .member))
                    .swipeActions {
                        if stored.event.deletedAt == nil {
                            Button("Delete", role: .destructive) { store.change { $0.delete(stored.event.id, by: me, now: Date()) } }
                        } else {
                            Button("Restore") { store.change { $0.restore(stored.event.id, by: me, now: Date()) } }
                        }
                    }
            }
        }
    }
}

private struct EventRow: View {
    let stored: StoredEvent
    let me: MemberID
    let members: [PlainRecord]

    var body: some View {
        let snapshot = stored.snapshot
        VStack(alignment: .leading, spacing: 2) {
            Text("\(snapshot.event.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(details(snapshot))")
                .strikethrough(snapshot.event.deletedAt != nil)
            Text(statusLine(snapshot))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func details(_ snapshot: EventSnapshot) -> String {
        guard let payload = snapshot.payload else { return "details from a newer app" }
        var parts: [String] = []
        if let pump = payload.pump {
            parts.append("Pump \(pump.side.rawValue) \(pump.totalML) ml")
        }
        for segment in payload.feed?.breast ?? [] {
            let side = segment.side == .left ? "L" : "R"
            parts.append(segment.durationSeconds.map { "\(side) \($0 / 60)m" } ?? side)
        }
        for bottle in payload.feed?.bottles ?? [] {
            parts.append("\(bottle.milk == .formula ? "Formula" : "Expressed") \(bottle.ml.map { "\($0) ml" } ?? "")")
        }
        return parts.isEmpty ? "feed" : parts.joined(separator: " · ")
    }

    private func statusLine(_ snapshot: EventSnapshot) -> String {
        let who = snapshot.event.loggedBy == me ? "this phone"
            : members.first { $0.name == snapshot.event.loggedBy.rawValue }
                .flatMap { PayloadCoder.decode(MemberPayload.self, from: $0.payload)?.displayName } ?? "the other phone"
        var parts = ["by \(who)"]
        if snapshot.event.endedAt == nil, snapshot.event.kind == .feed { parts.append("in progress") }
        if snapshot.event.deletedAt != nil { parts.append("deleted") }
        parts.append(stored.needsUpload ? "waiting to send" : (stored.systemFields == nil ? "not sent" : "in iCloud"))
        return parts.joined(separator: " · ")
    }
}
#endif
