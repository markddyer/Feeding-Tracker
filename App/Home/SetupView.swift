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
        .textFieldStyle(.plain)
    }

    @ViewBuilder
    private var step: some View {
        let sync = model.sync
        #if FEEDING_DEV
        if let forced = UserDefaults.standard.string(forKey: "setupStep") {
            forcedStep(forced)
        } else {
            realStep(sync)
        }
        #else
        realStep(sync)
        #endif
    }

    #if FEEDING_DEV
    /// Feeding Dev only: launch with `-setupStep` and a step's name (`disclaimer`, `signIn`,
    /// `household`, `about`, `invite`, `howYouFeed`, `permissions`) to see it, for screenshots.
    @ViewBuilder
    private func forcedStep(_ name: String) -> some View {
        switch name {
        case "signIn": signIn(model.sync)
        case "household": chooseHousehold
        case "about": aboutYou
        case "invite": invite
        case "howYouFeed": howYouFeed
        case "permissions": permissions
        default: disclaimer
        }
    }
    #endif

    @ViewBuilder
    private func realStep(_ sync: HouseholdSync) -> some View {
        if !disclaimerSeen {
            disclaimer
        } else if !AppConfig.syncEnabled {
            title("Not ready yet")
            Text("This version of Feeding doesn't share feeds between phones yet. Use Feeding Dev for now.")
                .feedText(.body)
        } else if sync.accountAvailable == false {
            signIn(sync)
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
            Text(problem)
                .feedText(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.notice.opacity(0.22), in: RoundedRectangle(cornerRadius: Radius.smallButton))
        }
    }

    // MARK: Steps

    private var disclaimer: some View {
        Group {
            title("Feeding")
            Text("Logs your baby's feeds on both parents' phones, and alerts as a safety net when a long time has passed since the last feed started. The parents can take turns at night.")
                .feedText(.body)
            note("Records feeds; not medical advice. If you're worried, contact your midwife, health visitor or GP, or call NHS 111. In an emergency, call 999.")
            BigButton(title: "Continue", prominent: true) { disclaimerSeen = true }
        }
    }

    private func signIn(_ sync: HouseholdSync) -> some View {
        Group {
            title("Sign in to iCloud")
            Text("Feeding keeps everything in your own iCloud, and shares it only with the other parent. Open Settings, tap your name at the top, and sign in. Then come back here.")
                .feedText(.body)
            BigButton(title: "Check again", prominent: false) { Task { await sync.refreshAccount() } }
        }
    }

    private var chooseHousehold: some View {
        Group {
            title("Set up the household")
            Text("One parent starts the household and invites the other.")
                .feedText(.body)
            BigButton(title: "Start a new household", prominent: true) {
                Task { await model.sync.createHousehold() }
            }
            .disabled(model.sync.busy)
            Text("Joining instead? Ask the other parent to send the invite from their phone, then tap the link in Messages. If the link doesn't open Feeding, copy it and paste it here:")
                .feedText(.subheadline)
                .foregroundStyle(Theme.textMuted)
            TextField("Invite link", text: $pastedLink)
                .feedField()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            BigButton(title: "Join with this link", prominent: false) { Task { await model.sync.acceptPastedLink(pastedLink) } }
                .disabled(pastedLink.isEmpty || model.sync.busy)
        }
    }

    @ViewBuilder
    private var ownerSteps: some View {
        if model.baby == nil || !hasMyMember {
            aboutYou
        } else if !inviteOffered {
            invite
        } else if FeedingStyle(rawValue: feedingStyle) == nil {
            howYouFeed
        } else {
            permissions
        }
    }

    private var aboutYou: some View {
        Group {
            title("About you and the baby")
            TextField("Baby's name", text: $babyName)
                .feedField()
            Toggle("Add the birth date", isOn: $addBirthDate)
                .feedText(.body)
            if addBirthDate {
                DatePicker("Born", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    .feedText(.body)
            }
            TextField("Your name, as the other parent sees it", text: $myName)
                .feedField()
            Text("Names stay in your iCloud and the other parent's. Alerts on the Lock Screen don't show the baby's name.")
                .feedText(.subheadline).foregroundStyle(Theme.textMuted)
            BigButton(title: "Save", prominent: true) { saveOwnerDetails() }
                .disabled(babyName.trimmed.isEmpty || myName.trimmed.isEmpty)
        }
    }

    private var invite: some View {
        Group {
            title("Invite the other parent")
            Text("Send the invite in Messages. When they tap it on their phone, Feeding opens and joins this household.")
                .feedText(.body)
            BigButton(title: "Send the invite", prominent: true) {
                Task {
                    await model.sync.invite()
                    inviteOffered = true
                }
            }
            Button { inviteOffered = true } label: {
                Text("Later, from Settings")
                    .feedText(.smallButton)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .foregroundStyle(Theme.text)
        }
    }

    @ViewBuilder
    private var memberSteps: some View {
        if !hasMyMember {
            title("Joined")
            TextField("Your name, as the other parent sees it", text: $myName)
                .feedField()
            BigButton(title: "Save", prominent: true) { saveMember(colour: ParentColour.teal.rawValue) }
                .disabled(myName.trimmed.isEmpty)
        } else if model.baby == nil {
            title("Joined")
            ProgressView("Waiting for the household's details from the other phone…")
                .feedText(.body)
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
                .feedText(.body)
            choice(FeedingStyle.breastAndBottle, marks: [.side(.left), .bottle], tint: Theme.breastTint,
                   detail: "Left, Right and Bottle buttons during a feed.")
            choice(FeedingStyle.bottleOnly, marks: [.bottle], tint: Theme.bottleTint,
                   detail: "Start feed asks expressed milk or formula. No Left and Right buttons.")
        }
    }

    /// A big tinted choice with its feed shapes: tap to choose.
    private func choice(_ style: FeedingStyle, marks: [FeedMark], tint: Color, detail: String) -> some View {
        Button {
            feedingStyle = style.rawValue
        } label: {
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    ForEach(marks, id: \.self) { FeedMarkView($0, size: 28, relativeTo: .title3) }
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.title).feedText(.tileValue)
                    Text(detail).feedText(.subheadline).foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: Radius.tile))
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile))
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(Theme.text)
        .sensoryFeedback(.selection, trigger: feedingStyle)
    }

    private var permissions: some View {
        Group {
            title("Alarms and alerts")
            Text("Feeding sets an alarm or a notification for when the time you choose has passed since the last feed started. Each parent picks loud or gentle in Settings. If nobody logs a feed, a loud backup alarm rings on both phones.")
                .feedText(.body)
            note("Never hide Feeding or lock it with Face ID. Apple says alarms from hidden or locked apps can fail without warning.")
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
        Text(text)
            .feedText(.title)
            .accessibilityAddTraits(.isHeader)
    }

    /// Something to keep in mind, on a tile.
    private func note(_ text: String) -> some View {
        Text(text)
            .feedText(.subheadline)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.tile))
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
        saveMember(colour: ParentColour.sunflower.rawValue)
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

extension View {
    /// A text field on a tile: the `surface` colour, round corners, SF Pro Rounded.
    func feedField() -> some View {
        feedText(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.smallButton))
    }
}
