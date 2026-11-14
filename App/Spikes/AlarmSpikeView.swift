#if FEEDING_DEV
import AlarmKit
import SwiftUI

struct AlarmSpikeView: View {
    private let store = AlarmSpikeStore.shared

    /// Test times as minutes after midnight, comma-separated.
    @AppStorage("spike.alarm.times") private var timesRaw = "300"
    @AppStorage("spike.alarm.followUp") private var withFollowUp = true
    @AppStorage("spike.alarm.withNotification") private var withNotification = true
    @AppStorage("spike.alarm.watchWorn") private var watchWorn = false
    @State private var overnightMessage: String?
    @State private var confirmClear = false

    private var times: [Int] {
        timesRaw.split(separator: ",").compactMap { Int($0) }
    }

    var body: some View {
        List {
            Section("1. Permissions") {
                LabeledContent("Alarms", value: authorizationText)
                LabeledContent("Notifications", value: store.notificationStatus)
                LabeledContent("Time Sensitive", value: store.timeSensitiveStatus)
                if let error = store.permissionError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Ask for permissions") {
                    Task { await store.requestPermissions() }
                }
            }

            quickSection
            overnightSection

            Section("4. Results") {
                if store.log.tests.isEmpty {
                    Text("No tests yet.").foregroundStyle(.secondary)
                }
                ForEach(store.log.tests.sorted { $0.dueAt > $1.dueAt }) { test in
                    AlarmTestRow(test: test) { value in store.setRangAloud(testID: test.id, value) }
                }
                ShareLink(item: SpikeFile.url(AlarmSpikeStore.fileName)) {
                    Label("Share the results file", systemImage: "square.and.arrow.up")
                }
                Button("Cancel test alarms that haven't rung yet", role: .destructive) {
                    store.cancelAllPending()
                }
                Button("Clear all results", role: .destructive) {
                    confirmClear = true
                }
                .confirmationDialog("Clear all results?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Clear all results", role: .destructive) { store.clearResults() }
                } message: {
                    Text("This also cancels any test alarm that hasn't rung yet.")
                }
            }
        }
        .navigationTitle("Alarm test")
        .task {
            await store.refreshPermissions()
            await store.collectDeliveredNotifications()
        }
    }

    // MARK: 2. Quick test

    private var quickSection: some View {
        let waiting = store.activeQuickTest()
        let busy = store.isScheduling || waiting != nil
        return Section {
            Button("A) Alarm only") {
                Task { _ = await store.scheduleQuickTest(notificationDelay: nil, followUpAfter: 120, watchWorn: watchWorn) }
            }
            .disabled(busy)
            Button("B) Alarm and notification together") {
                Task { _ = await store.scheduleQuickTest(notificationDelay: 0, followUpAfter: 120, watchWorn: watchWorn) }
            }
            .disabled(busy)
            Button("C) Alarm, then a notification 30 seconds later") {
                Task { _ = await store.scheduleQuickTest(notificationDelay: 30, followUpAfter: nil, watchWorn: watchWorn) }
            }
            .disabled(busy)
            if let waiting {
                Text("Test \(waiting.letter) is set. It rings at \(waiting.dueAt.formatted(date: .omitted, time: .standard)). Lock the phone now.")
                    .bold()
            }
        } header: {
            Text("2. Check it works now")
        } footer: {
            Text("Tap once. The alarm rings 2 minutes later. A and B: let it ring for 30 seconds and listen, then press Stop. A follow-up alarm is set 2 minutes after the first, and Stop cancels it. C: no follow-up. Don't press Stop until 30 seconds after the notification arrives.")
        }
    }

    // MARK: 3. Overnight test

    private var overnightSection: some View {
        let waiting = store.waitingOvernightTests()
        return Section {
            ForEach(Array(times.enumerated()), id: \.offset) { index, _ in
                HStack {
                    DatePicker("Test \(index + 1)", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                    Button(role: .destructive) {
                        var list = times
                        list.remove(at: index)
                        timesRaw = list.map(String.init).joined(separator: ",")
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            Button("Add a time") {
                timesRaw = (times + [360]).map(String.init).joined(separator: ",")
            }
            Toggle("Send a notification with each alarm", isOn: $withNotification)
            Toggle("Follow-up alarm 10 minutes later", isOn: $withFollowUp)
            Toggle("Watch on the wrist tonight", isOn: $watchWorn)
            Button("Set tonight's test alarms") {
                Task { await scheduleTonight() }
            }
            .bold()
            .disabled(store.isScheduling || !waiting.isEmpty)
            if !waiting.isEmpty {
                let list = waiting.map(\.dueAt).sorted().map { $0.formatted(date: .abbreviated, time: .shortened) }.joined(separator: ", ")
                Text("Set for \(list). Lock the phone and leave it. To change them, cancel them under Results first.")
                    .bold()
            } else if let overnightMessage {
                Text(overnightMessage)
            }
        } header: {
            Text("3. Overnight test")
        } footer: {
            Text("When it rings, press Stop. In the morning, open this screen before you clear any notifications.")
        }
    }

    private var authorizationText: String {
        switch store.alarmAuthorization {
        case .authorized: "allowed"
        case .denied: "denied"
        case .notDetermined: "not asked yet"
        @unknown default: "unknown"
        }
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding {
            let minutes = times.indices.contains(index) ? times[index] : 0
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            var list = times
            guard list.indices.contains(index) else { return }
            list[index] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            timesRaw = list.map(String.init).joined(separator: ",")
        }
    }

    private func scheduleTonight() async {
        let now = Date()
        // The same time twice would ring two alarms at once, so each time is used once.
        let dates = Set(times).sorted().compactMap { minutes in
            Calendar.current.nextDate(after: now, matching: DateComponents(hour: minutes / 60, minute: minutes % 60, second: 0),
                                      matchingPolicy: .nextTime)
        }
        let set = await store.scheduleOvernight(at: dates, followUpAfter: withFollowUp ? 600 : nil,
                                                withNotification: withNotification, watchWorn: watchWorn)
        overnightMessage = set.isEmpty ? "Nothing set. Add a time first." : nil
    }
}

private extension AlarmTest {
    /// The quick test's button letter: A alarm only, B together, C notification later.
    var letter: String {
        guard notificationID != nil else { return "A" }
        return (notificationDelay ?? 0) > 0 ? "C" : "B"
    }
}

private struct AlarmTestRow: View {
    let test: AlarmTest
    let setRangAloud: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(test.dueAt.formatted(date: .abbreviated, time: .standard) + kindText)
                .font(.headline)
            line("Notification", notificationText)
            line("Alarm", alarmText)
            if test.followUpAlarmID != nil, test.cancelledAt == nil {
                line("Follow-up", followUpText)
            }
            if test.watchWorn { line("Watch", "on the wrist") }
            ForEach(test.errors, id: \.self) { error in
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Text("Phone rang out loud?").font(.footnote)
                Spacer()
                Button("Yes") { setRangAloud(true) }
                    .buttonStyle(.bordered)
                    .tint(test.phoneRangAloud == true ? .accentColor : .gray)
                Button("No") { setRangAloud(false) }
                    .buttonStyle(.bordered)
                    .tint(test.phoneRangAloud == false ? .accentColor : .gray)
            }
        }
        .padding(.vertical, 4)
    }

    private var kindText: String {
        let delay = Int(test.notificationDelay ?? 0)
        let what = test.notificationID == nil ? "alarm only"
            : delay > 0 ? "alarm, then notification \(delay) s later" : "alarm and notification"
        return test.isQuickTest ? " (quick test \(test.letter), \(what))" : " (\(what))"
    }

    private var notificationText: String {
        guard test.notificationID != nil else { return "none set" }
        if let delivered = test.notificationDeliveredAt {
            let setFor = test.dueAt.addingTimeInterval(test.notificationDelay ?? 0)
            return "arrived \(delivered.formatted(date: .omitted, time: .standard)) (\(delivered.offset(from: setFor)))"
        }
        return "no record yet"
    }

    private var alarmText: String {
        if let stopped = test.mainStoppedAt {
            return "Stop pressed \(stopped.formatted(date: .omitted, time: .standard)) (\(stopped.offset(from: test.dueAt)))"
        }
        if let cancelled = test.cancelledAt {
            return "cancelled at \(cancelled.formatted(date: .omitted, time: .standard)) before Stop"
        }
        if let seen = test.mainSeenAlertingAt {
            return "app saw it ringing \(seen.formatted(date: .omitted, time: .standard)) (\(seen.offset(from: test.dueAt)))"
        }
        return test.dueAt > Date() ? "waiting" : "no record"
    }

    private var followUpText: String {
        if let cancelled = test.followUpCancelledAt {
            let early = (test.followUpDueAt ?? .distantFuture) > cancelled
            return "cancelled by Stop at \(cancelled.formatted(date: .omitted, time: .standard))" + (early ? ", before it rang" : ", after its ring time")
        }
        if let stopped = test.followUpStoppedAt, let due = test.followUpDueAt {
            return "rang; Stop pressed \(stopped.formatted(date: .omitted, time: .standard)) (\(stopped.offset(from: due)))"
        }
        if let seen = test.followUpSeenAlertingAt {
            return "app saw it ringing \(seen.formatted(date: .omitted, time: .standard))"
        }
        return (test.followUpDueAt ?? .distantPast) > Date() ? "waiting" : "no record"
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.footnote.bold()).frame(width: 90, alignment: .leading)
            Text(value).font(.footnote)
        }
    }
}
#endif
