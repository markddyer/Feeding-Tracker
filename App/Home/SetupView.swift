import FeedingCore
import SwiftUI

/// First launch: the disclaimer, iCloud, making or joining the household, names, the invite, and
/// permission for alarms. Each step shows only while it is still needed, so the flow picks up
/// where it left off, on either parent's phone.
struct SetupView: View {
    @AppStorage("setup.disclaimerSeen") private var disclaimerSeen = false
    @AppStorage("setup.inviteOffered") private var inviteOffered = false
    @AppStorage("setup.permissionsAsked") private var permissionsAsked = false
    @AppStorage(FeedingStyle.storageKey) private var feedingStyle = ""

    @State private var babyName = ""
    @State private var addBirthDate = false
    @State private var birthDate = Date()
    @State private var myName = ""
    @State private var pastedLink = ""

    private let model = AppModel.shared

    /// True once every step is done, so the home screen can show.
    static func isComplete(disclaimerSeen: Bool, inviteOffered: Bool, permissionsAsked: Bool, feedingStyle: String) -> Bool {
        let model = AppModel.shared
        guard disclaimerSeen, permissionsAsked, FeedingStyle(rawValue: feedingStyle) != nil,
              let me = model.me, model.baby != nil,
              model.store.data.plainRecord(.member, me.rawValue) != nil else { return false }
        return model.sync.role != .owner || inviteOffered
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                step
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder
    private var step: some View {
        let sync = model.sync
        if !disclaimerSeen {
            disclaimer
        } else if !AppConfig.syncEnabled {
            title("Not ready yet")
            Text("This version of Feeding doesn't share feeds between phones yet. Use Feeding Dev for now.")
        } else if sync.accountAvailable == false {
            title("Sign in to iCloud")
            Text("Feeding keeps everything in your own iCloud, and shares it only with the other parent. Open Settings, tap your name at the top, and sign in. Then come back here.")
            Button("Check again") { Task { await sync.refreshAccount() } }
                .buttonStyle(.bordered)
        } else if model.me == nil {
            ProgressView("Checking iCloud…")
        } else {
            switch sync.role {
            case .notSetUp: chooseHousehold
            case .owner: ownerSteps
            case .member: memberSteps
            }
        }
        // The iCloud step already says what the not-signed-in message says.
        if disclaimerSeen, let problem = sync.problem, problem != HouseholdSync.notSignedIn {
            Text(problem).font(.footnote).foregroundStyle(Theme.warning)
        }
    }

    // MARK: Steps

    private var disclaimer: some View {
        Group {
            title("Feeding")
            Text("Logs your baby's feeds on both parents' phones, and alerts as a safety net when a long time has passed since the last feed started. The parents can take turns at night.")
            Text("Records feeds; not medical advice. If you're worried, contact your midwife, health visitor or GP, or call NHS 111. In an emergency, call 999.")
                .font(.callout)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            BigButton(title: "Continue", prominent: true) { disclaimerSeen = true }
        }
    }

    private var chooseHousehold: some View {
        Group {
            title("Set up the household")
            Text("One parent starts the household and invites the other.")
            BigButton(title: "Start a new household", prominent: true) {
                Task { await model.sync.createHousehold() }
            }
            .disabled(model.sync.busy)
            Text("Joining instead? Ask the other parent to send the invite from their phone, then tap the link in Messages. If the link doesn't open Feeding, copy it and paste it here:")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
            TextField("Invite link", text: $pastedLink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Join with this link") { Task { await model.sync.acceptPastedLink(pastedLink) } }
                .disabled(pastedLink.isEmpty || model.sync.busy)
        }
    }

    @ViewBuilder
    private var ownerSteps: some View {
        if model.baby == nil || !hasMyMember {
            title("About you and the baby")
            TextField("Baby's name", text: $babyName)
            Toggle("Add the birth date", isOn: $addBirthDate)
            if addBirthDate {
                DatePicker("Born", selection: $birthDate, in: ...Date(), displayedComponents: .date)
            }
            TextField("Your name, as the other parent sees it", text: $myName)
            Text("Names stay in your iCloud and the other parent's. Alerts on the Lock Screen don't show the baby's name.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            BigButton(title: "Save", prominent: true) { saveOwnerDetails() }
                .disabled(babyName.trimmed.isEmpty || myName.trimmed.isEmpty)
        } else if !inviteOffered {
            title("Invite the other parent")
            Text("Send the invite in Messages. When they tap it on their phone, Feeding opens and joins this household.")
            BigButton(title: "Send the invite", prominent: true) {
                Task {
                    await model.sync.invite()
                    inviteOffered = true
                }
            }
            Button("Later, from Settings") { inviteOffered = true }
        } else if FeedingStyle(rawValue: feedingStyle) == nil {
            howYouFeed
        } else {
            permissions
        }
    }

    @ViewBuilder
    private var memberSteps: some View {
        if !hasMyMember {
            title("Joined")
            TextField("Your name, as the other parent sees it", text: $myName)
            BigButton(title: "Save", prominent: true) { saveMember(colour: "teal") }
                .disabled(myName.trimmed.isEmpty)
        } else if model.baby == nil {
            title("Joined")
            ProgressView("Waiting for the household's details from the other phone…")
        } else if FeedingStyle(rawValue: feedingStyle) == nil {
            howYouFeed
        } else {
            permissions
        }
    }

    private var howYouFeed: some View {
        Group {
            title("How do you feed?")
            Text("This sets the buttons on this phone only. Each parent chooses on their own phone, and can change it in Settings.")
            BigButton(title: FeedingStyle.breastAndBottle.title, prominent: true) {
                feedingStyle = FeedingStyle.breastAndBottle.rawValue
            }
            BigButton(title: FeedingStyle.bottleOnly.title, prominent: true) {
                feedingStyle = FeedingStyle.bottleOnly.rawValue
            }
            Text("Bottle only: Start feed asks expressed milk or formula, and there are no Left and Right buttons.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
    }

    private var permissions: some View {
        Group {
            title("Alarms and alerts")
            Text("Feeding sets an alarm or a notification for when the time you choose has passed since the last feed started. Each parent picks loud or gentle in Settings. If nobody logs a feed, a loud backup alarm rings on both phones.")
            Text("Never hide Feeding or lock it with Face ID. Apple says alarms from hidden or locked apps can fail without warning.")
                .font(.callout)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            BigButton(title: "Allow alarms and notifications", prominent: true) {
                Task {
                    await model.reconciler.requestPermissions()
                    permissionsAsked = true
                }
            }
        }
    }

    // MARK: Helpers

    private var hasMyMember: Bool {
        guard let me = model.me else { return false }
        return model.store.data.plainRecord(.member, me.rawValue) != nil
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.largeTitle.bold())
    }

    private func saveOwnerDetails() {
        let now = Date()
        let birth = addBirthDate ? PlainDate(birthDate, in: .current) : nil
        let name = babyName.trimmed
        if model.baby == nil {
            model.store.change {
                $0.put(PlainRecord(type: .baby, name: UUID().uuidString, modifiedAt: now,
                                   payload: try? PayloadCoder.encode(BabyPayload(name: name, birthDate: birth))))
            }
        }
        saveMember(colour: "amber")
    }

    private func saveMember(colour: String) {
        guard let me = model.me else { return }
        let name = myName.trimmed
        model.store.change {
            $0.put(PlainRecord(type: .member, name: me.rawValue, modifiedAt: Date(),
                               payload: try? PayloadCoder.encode(MemberPayload(displayName: name, colour: colour))))
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
