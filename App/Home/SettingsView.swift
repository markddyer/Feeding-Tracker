import FeedingCore
import SwiftUI

/// Settings: this phone's own alert choices, the shared household settings, the night rota, and
/// the disclaimer. Shared changes that could silence the other phone go through the
/// acknowledgement rule in `HouseholdData`.
struct SettingsView: View {
    private let model = AppModel.shared
    @AppStorage(FeedingStyle.storageKey) private var feedingStyle = FeedingStyle.breastAndBottle.rawValue

    var body: some View {
        let settings = model.store.data.householdSettings
        List {
            Section {
                Picker("How you feed", selection: $feedingStyle) {
                    ForEach(FeedingStyle.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("This phone")
            } footer: {
                Text("Bottle only: Start feed asks expressed milk or formula, and there are no Left and Right buttons. The other phone keeps its own choice.")
            }

            Section {
                Picker("In the day", selection: style(\.dayStyle)) {
                    Text("Loud alarm").tag(AlertStyle.loudAlarm)
                    Text("Gentle nudge").tag(AlertStyle.gentleNudge)
                }
                Picker("At night, when on duty", selection: style(\.nightStyle)) {
                    Text("Loud alarm").tag(AlertStyle.loudAlarm)
                    Text("Gentle nudge").tag(AlertStyle.gentleNudge)
                }
                Toggle("Nudge when the window opens", isOn: Binding {
                    model.reconciler.preferences.windowOpensNudge
                } set: {
                    model.reconciler.preferences.windowOpensNudge = $0
                })
            } header: {
                Text("Alerts on this phone")
            } footer: {
                Text("If no feed is logged \(Int(settings.window.backupAfterClose / 60)) minutes after the alert, a loud backup alarm rings on both phones, day or night.")
            }

            Section {
                Toggle("Alerts", isOn: shared(\.window.alertsEnabled))
                Stepper("Window opens after \(hours(settings.window.opensAfter))",
                        value: shared(\.window.opensAfter), in: 3600...(5 * 3600), step: 15 * 60)
                Stepper("Alert after \(hours(settings.window.closesAfter))",
                        value: shared(\.window.closesAfter), in: (2 * 3600)...(6 * 3600), step: 15 * 60)
                Stepper("Backup alarm \(Int(settings.window.backupAfterClose / 60)) min later",
                        value: shared(\.window.backupAfterClose), in: (10 * 60)...(60 * 60), step: 5 * 60)
            } header: {
                Text("Both phones")
            } footer: {
                Text("Times run from the start of the last feed.")
            }

            rotaSection

            Section("About") {
                Text("Records feeds; not medical advice. If you're worried, contact your midwife, health visitor or GP, or call NHS 111. In an emergency, call 999.")
                    .font(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private var rotaSection: some View {
        let data = model.store.data
        let members = data.plainRecords(of: .member).map { MemberID(rawValue: $0.name) }
        let names = model.memberNames
        Section {
            if let me = model.me, members.count == 2, let other = members.first(where: { $0 != me }) {
                let tonight = HomeFacts(data: data, babyID: model.baby?.name ?? "", me: me, names: names, now: Date()).tonight
                let onDuty = data.householdState.roster(for: me).onDuty(night: tonight)
                Picker("On tonight", selection: Binding {
                    data.rota == nil ? nil : onDuty
                } set: { (chosen: MemberID?) in
                    guard let chosen else { return }
                    let rota = Rota(startDate: tonight, firstOnDuty: chosen, secondOnDuty: chosen == me ? other : me)
                    model.store.change { $0.setRota(rota, by: me, now: Date()) }
                }) {
                    Text("Not set").tag(MemberID?.none)
                    Text(names[me] ?? "You").tag(MemberID?.some(me))
                    Text(names[other] ?? "The other parent").tag(MemberID?.some(other))
                }
            } else {
                Text("The rota can be set once both parents are in the household.")
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("Night rota")
        } footer: {
            Text("The parents take turns night by night from the night you choose. Either parent can take a night from the home screen.")
        }
    }

    private func style(_ keyPath: WritableKeyPath<MemberPreferences, AlertStyle>) -> Binding<AlertStyle> {
        Binding {
            model.reconciler.preferences[keyPath: keyPath]
        } set: { value in
            model.reconciler.preferences[keyPath: keyPath] = value
        }
    }

    /// A shared setting. The change is recorded with the acknowledgement rule.
    private func shared<Value: Equatable>(_ keyPath: WritableKeyPath<HouseholdSettings, Value>) -> Binding<Value> {
        Binding {
            model.store.data.householdSettings[keyPath: keyPath]
        } set: { value in
            guard let me = model.me else { return }
            model.store.change { $0.updateHouseholdSettings(by: me, now: Date()) { $0[keyPath: keyPath] = value } }
        }
    }

    private func hours(_ seconds: TimeInterval) -> String {
        AlertText.duration(seconds)
    }
}
