#if FEEDING_DEV
import AlarmKit
import SwiftUI

struct SyncSpikeView: View {
    private let store = SyncSpikeStore.shared
    private let alarms = AlarmSpikeStore.shared
    @State private var pastedLink = ""

    var body: some View {
        List {
            Section("1. This phone") {
                LabeledContent("iCloud", value: store.accountStatus)
                LabeledContent("Alarms", value: alarms.alarmAuthorization == .authorized ? "allowed" : "not allowed yet")
                if alarms.alarmAuthorization != .authorized {
                    Button("Ask for alarm permission") {
                        Task { await alarms.requestPermissions() }
                    }
                }
                Text(store.roleText).bold()
            }

            setupSection

            if store.isInHousehold {
                Section {
                    Button("A) Send a test ping") {
                        Task { await store.sendPing() }
                    }
                    Button("B) Ring the other phone in 2 minutes") {
                        Task { await store.sendRing() }
                    }
                    Button("C) Cancel that ring") {
                        Task { await store.cancelRing() }
                    }
                    .disabled(store.cancellableRing == nil)
                } header: {
                    Text("3. Tests")
                } footer: {
                    Text("Each test shows up on the other phone. The lists below show how long it took.")
                }
            }

            Section("4. Arrived from the other phone") {
                if store.log.received.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(store.log.received.reversed())) { item in
                    ReceivedRow(item: item)
                }
            }

            if !store.log.rings.isEmpty {
                Section("5. Alarms the other phone asked for") {
                    ForEach(Array(store.log.rings.reversed())) { ring in
                        RingRow(ring: ring)
                    }
                }
            }

            Section("6. Sent from this phone") {
                if store.log.sent.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(store.log.sent.reversed())) { item in
                    SentRow(item: item)
                }
            }

            Section("7. Pushes this phone got") {
                if store.log.pushes.isEmpty {
                    Text("None yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(store.log.pushes.suffix(10).reversed()), id: \.self) { push in
                    Text("\(push.at.formatted(date: .omitted, time: .standard)) · \(push.database) database · app \(push.appState)")
                        .font(.footnote)
                }
            }

            Section("Notes") {
                ForEach(Array(store.log.notes.suffix(15).reversed()), id: \.self) { note in
                    Text("\(note.at.formatted(date: .omitted, time: .standard)) \(note.text)")
                        .font(.footnote)
                }
                ShareLink(item: SpikeFile.url(SyncSpikeStore.logFile)) {
                    Label("Share the results file", systemImage: "square.and.arrow.up")
                }
                Button("Clear results", role: .destructive) {
                    store.clearResults()
                }
            }
        }
        .navigationTitle("Shared log test")
        .task {
            await alarms.refreshPermissions()
            await store.refreshAccountStatus()
            await store.fetchNow()
        }
    }

    @ViewBuilder
    private var setupSection: some View {
        Section {
            if store.setup.ownsHousehold {
                Button("Invite the other phone again") {
                    Task { await store.createHouseholdAndInvite() }
                }
                .disabled(store.busy)
                if let url = store.setup.shareURL {
                    ShareLink(item: url) {
                        Label("Send the invite link another way", systemImage: "square.and.arrow.up")
                    }
                }
            } else if !store.isInHousehold {
                Button("Create the household and invite") {
                    Task { await store.createHouseholdAndInvite() }
                }
                .disabled(store.busy)
                TextField("Or paste an invite link here", text: $pastedLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Join with the pasted link") {
                    Task { await store.acceptPastedLink(pastedLink) }
                }
                .disabled(pastedLink.isEmpty || store.busy)
            } else {
                Text("Joined. Nothing more to set up.")
            }
        } header: {
            Text("2. Set up, once")
        } footer: {
            Text("On one phone only, tap Create and send the invite in Messages. On the other phone, tap the link. If the link does not open Feeding Dev, copy it and paste it here.")
        }
    }
}

private struct ReceivedRow: View {
    let item: SyncReceivedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(item.kind.capitalized) · arrived \(item.receivedAt.formatted(date: .omitted, time: .standard))")
                .font(.headline)
            if let saved = item.savedAt {
                Text("\(item.receivedAt.offset(from: saved)) after iCloud saved it, \(item.receivedAt.offset(from: item.tappedAt)) after the tap")
                    .font(.footnote)
            }
            Text("This app was \(item.appState)" + (item.afterPush ? ", woken by a push" : ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SentRow: View {
    let item: SyncSentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(item.kind.capitalized) · tapped \(item.tappedAt.formatted(date: .omitted, time: .standard))")
                .font(.headline)
            if let ringAt = item.ringAt, item.kind == "ring" {
                Text("Asks the other phone to ring at \(ringAt.formatted(date: .omitted, time: .standard))").font(.footnote)
            }
            if let saved = item.savedAt {
                Text("iCloud saved it \(saved.offset(from: item.tappedAt)) after the tap").font(.footnote)
            } else if let error = item.error {
                Text("Failed: \(error)").font(.footnote)
            } else {
                Text("Not saved in iCloud yet").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RingRow: View {
    let ring: SyncRingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Ring for \(ring.ringAt.formatted(date: .omitted, time: .standard))").font(.headline)
            if let set = ring.scheduledAt {
                Text("Alarm set at \(set.formatted(date: .omitted, time: .standard)), app \(ring.scheduledAppState ?? "?")").font(.footnote)
            }
            if let cancelled = ring.cancelledAt {
                Text("Cancel arrived at \(cancelled.formatted(date: .omitted, time: .standard)), app \(ring.cancelledAppState ?? "?")").font(.footnote)
            }
            if ring.tooLateAt != nil {
                Text("Arrived after its ring time, so no alarm was set").font(.footnote)
            }
            if let stopped = ring.stoppedAt {
                Text("Stop pressed at \(stopped.formatted(date: .omitted, time: .standard)) (\(stopped.offset(from: ring.ringAt)))").font(.footnote)
            }
            ForEach(ring.errors, id: \.self) { error in
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
#endif
