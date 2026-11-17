import FeedingCore
import SwiftUI

/// Settings: this phone's own choices (how you feed, the look, alerts), your colour, the shared
/// household settings, the night rota, and the disclaimer. Shared changes that could silence the
/// other phone go through the acknowledgement rule in `HouseholdData`.
struct SettingsView: View {
    private let model = AppModel.shared
    @AppStorage(FeedingStyle.storageKey) private var feedingStyle = FeedingStyle.breastAndBottle.rawValue
    @AppStorage(LookSetting.storageKey) private var lookSetting = LookSetting.automatic.rawValue
    @State private var colourTaps = 0

    var body: some View {
        let settings = model.store.data.householdSettings
        List {
            Section {
                Text("Settings")
                    .feedText(.title)
                    .accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            Section {
                Picker("How you feed", selection: $feedingStyle) {
                    ForEach(FeedingStyle.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .tint(Theme.textMuted)
                Picker("Look", selection: $lookSetting) {
                    ForEach(LookSetting.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .tint(Theme.textMuted)
            } header: {
                header("This phone")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bottle only: Start feed asks expressed milk or formula, and there are no Left and Right buttons. The other phone keeps its own choice.")
                    Text("Look: Automatic uses the night look from \(settings.dayHours.nightStart.description) to \(settings.dayHours.dayStart.description), the night rota's hours. Match iPhone follows the phone's Dark Mode.")
                }
                .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.surface)

            colourSection

            Section {
                Picker("In the day", selection: style(\.dayStyle)) {
                    Text("Loud alarm").tag(AlertStyle.loudAlarm)
                    Text("Gentle nudge").tag(AlertStyle.gentleNudge)
                }
                .tint(Theme.textMuted)
                Picker("At night, when on duty", selection: style(\.nightStyle)) {
                    Text("Loud alarm").tag(AlertStyle.loudAlarm)
                    Text("Gentle nudge").tag(AlertStyle.gentleNudge)
                }
                .tint(Theme.textMuted)
                Toggle("Nudge when the window opens", isOn: Binding {
                    model.reconciler.preferences.windowOpensNudge
                } set: {
                    model.reconciler.preferences.windowOpensNudge = $0
                })
            } header: {
                header("Alerts on this phone")
            } footer: {
                Text("If no feed is logged \(Int(settings.window.backupAfterClose / 60)) minutes after the alert, a loud backup alarm rings on both phones, day or night.")
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle("Alerts", isOn: shared(\.window.alertsEnabled))
                Stepper("Window opens after \(hours(settings.window.opensAfter))",
                        value: shared(\.window.opensAfter), in: 3600...(5 * 3600), step: 15 * 60)
                Stepper("Alert after \(hours(settings.window.closesAfter))",
                        value: shared(\.window.closesAfter), in: (2 * 3600)...(6 * 3600), step: 15 * 60)
                Stepper("Backup alarm \(Int(settings.window.backupAfterClose / 60)) min later",
                        value: shared(\.window.backupAfterClose), in: (10 * 60)...(60 * 60), step: 5 * 60)
            } header: {
                header("Both phones")
            } footer: {
                Text("Times run from the start of the last feed.")
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.surface)

            rotaSection

            Section {
                NavigationLink {
                    MedicineListEditor()
                } label: {
                    HStack(spacing: 10) {
                        FeedMarkView(.medicine, size: 18, relativeTo: .body)
                        Text("Medicines")
                        Spacer(minLength: 8)
                        Text(AppModel.shared.store.data.medicines.joined(separator: ", "))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                    }
                }
            } header: {
                header("Both phones")
            } footer: {
                Text("Each medicine or vitamin on this list has a Given button on Home.")
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.surface)

            Section {
                Text("Records feeds; not medical advice. If you're worried, contact your midwife, health visitor or GP, or call NHS 111. In an emergency, call 999.")
                    .feedText(.subheadline)
            } header: {
                header("About")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        // The big Fredoka title is the first row; "Settings" stays the screen's name.
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .sensoryFeedback(.selection, trigger: colourTaps)
    }

    /// Six colours, each showing this parent's initial. The other parent's colour shows their
    /// initial and can't be picked, so the nights row always shows two colours.
    @ViewBuilder
    private var colourSection: some View {
        let me = model.me
        let colours = model.memberColours
        let names = model.memberNames
        let mine = me.flatMap { colours[$0] } ?? .sunflower
        let other = colours.first { $0.key != me }
        Section {
            HStack(spacing: 6) {
                ForEach(ParentColour.allCases, id: \.self) { colour in
                    let taken = other?.value == colour && colour != mine
                    let initialOf = taken ? (other.flatMap { names[$0.key] } ?? "Other parent") : (me.flatMap { names[$0] } ?? "You")
                    Button {
                        guard let me else { return }
                        colourTaps += 1
                        model.store.change { $0.setColour(colour.rawValue, of: me, now: Date()) }
                    } label: {
                        Avatar(name: initialOf, colour: colour, size: 36)
                            .overlay {
                                if colour == mine {
                                    Circle().stroke(Theme.text, lineWidth: 3).padding(-5)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(taken || me == nil)
                    .accessibilityLabel(taken ? "\(colour.title), the other parent's colour" : colour.title)
                    .accessibilityAddTraits(colour == mine ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
            // Six circles must fit across the phone, so the row stops growing here.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        } header: {
            header("Your colour")
        } footer: {
            Text("\(mine.title). It marks you in the nights row and in History, on both phones.")
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.surface)
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
                .tint(Theme.textMuted)
            } else {
                Text("The rota can be set once both parents are in the household.")
                    .foregroundStyle(Theme.textMuted)
            }
        } header: {
            header("Night rota")
        } footer: {
            Text("The parents take turns night by night from the night you choose. Either parent can take a night from the home screen.")
                .foregroundStyle(Theme.textMuted)
        }
        .listRowBackground(Theme.surface)
    }

    /// A section's small upper-case label, as on the tiles.
    private func header(_ title: String) -> some View {
        Text(title).feedText(.label).foregroundStyle(Theme.textMuted)
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
