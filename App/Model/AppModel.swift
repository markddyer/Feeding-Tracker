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

    private init() {
        store = HouseholdStore()
        sync = HouseholdSync(store: store)
        reconciler = Reconciler(store: store, sync: sync, defaults: UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard)
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
}
