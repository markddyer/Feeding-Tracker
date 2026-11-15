import FeedingCore
import Foundation

/// Values from the generated Info.plist, which differ between Feeding and Feeding Dev.
enum AppConfig {
    static var containerID: String {
        Bundle.main.object(forInfoDictionaryKey: "FeedingCloudKitContainer") as? String ?? ""
    }

    static var appGroupID: String {
        Bundle.main.object(forInfoDictionaryKey: "FeedingAppGroup") as? String ?? ""
    }

    /// Syncing runs only in Feeding Dev for now. Feeding (the real app) starts syncing once the
    /// CloudKit Production schema is deployed, which needs the user's go-ahead.
    static var syncEnabled: Bool {
        #if FEEDING_DEV
        true
        #else
        false
        #endif
    }
}

/// The app's long-lived parts.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let store: HouseholdStore
    let sync: HouseholdSync
    let reconciler: Reconciler
    let nightAskNotifier: NightAskNotifier

    private init() {
        store = HouseholdStore()
        sync = HouseholdSync(store: store)
        let defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
        reconciler = Reconciler(store: store, sync: sync, defaults: defaults)
        nightAskNotifier = NightAskNotifier(defaults: defaults)
        // After any change, from this phone or the other: if both parents tapped Start feed at
        // once, this phone's copy (hidden on the screens) finishes when the first feed does. An
        // ask, or its answer, from the other phone becomes a notification.
        let reconcile = store.onDataChange
        store.onDataChange = { [weak self] in
            self?.finishStrandedDuplicates()
            reconcile?()
            Task { await self?.tellNightAskNews() }
        }
    }

    /// Notifications about asks to take a night. Also awaited after a push, so it runs before
    /// the app goes back to sleep.
    func tellNightAskNews() async {
        await nightAskNotifier.update(data: store.data, me: me, names: memberNames)
    }

    /// Ends this parent's hidden copies of a feed that has finished. Only this parent's own
    /// records, so the two phones never edit the same one.
    private func finishStrandedDuplicates() {
        guard let me, !store.data.strandedDuplicates(by: me).isEmpty else { return }
        store.change { $0.finishStrandedDuplicates(by: me, now: Date()) }
    }

    /// This parent: their iCloud user record name. The simulator has no iCloud, so Feeding Dev
    /// uses a stand-in there, to look at the screens.
    var me: MemberID? {
        #if FEEDING_DEV && targetEnvironment(simulator)
        sync.memberID ?? "simulator-parent"
        #else
        sync.memberID
        #endif
    }

    /// The baby the screens show: the first one not archived.
    var baby: PlainRecord? {
        store.data.plainRecords(of: .baby).first { $0.archivedAt == nil }
    }

    /// Display names by member ID, from the Member records.
    var memberNames: [MemberID: String] {
        var names: [MemberID: String] = [:]
        for record in store.data.plainRecords(of: .member) {
            if let payload = PayloadCoder.decode(MemberPayload.self, from: record.payload) {
                names[MemberID(rawValue: record.name)] = payload.displayName
            }
        }
        return names
    }

    /// Each parent's colour, from their Member record. A name this version can't read falls back
    /// to the defaults: sunflower for the first parent and teal for the second, in record-name
    /// order, so both phones agree.
    var memberColours: [MemberID: ParentColour] {
        var colours: [MemberID: ParentColour] = [:]
        let records = store.data.plainRecords(of: .member).sorted { $0.name < $1.name }
        for (index, record) in records.enumerated() {
            let saved = PayloadCoder.decode(MemberPayload.self, from: record.payload).flatMap { ParentColour(named: $0.colour) }
            colours[MemberID(rawValue: record.name)] = saved ?? (index == 0 ? .sunflower : .teal)
        }
        return colours
    }

    /// The baby's details (name, birth date), when this version can read them.
    var babyDetails: BabyPayload? {
        baby.flatMap { PayloadCoder.decode(BabyPayload.self, from: $0.payload) }
    }
}
