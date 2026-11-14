#if FEEDING_DEV
import AlarmKit
import CloudKit
import Foundation
import Observation
import UIKit

// Phase 0, spike 2: the shared household on two phones, through CKSyncEngine as the plan says.
// - Parent A's phone makes a Household zone in its private database and shares the whole zone.
// - Parent B's phone accepts the invite and syncs from its shared database, writing with the
//   shared zone ID (which carries the owner's name).
// - Each test record is timed from the tap, to iCloud, to the other phone, with the other app's
//   state (open, in the background, or force-quit and opened later).
// - A "ring" record asks the other phone to set an AlarmKit alarm. Cancelling it asks the other
//   phone to remove the alarm. This answers whether a background push can set or cancel alarms.

/// The Event fields the spike writes. Only fields that are already in schema.ckdb: in the
/// Development environment CloudKit adds any new field to the schema by itself, and a deploy
/// would then copy that field to Production for ever.
struct SpikeEventFields {
    var kind: String
    var startedAt: Date
    var createdAt: Date
    var modifiedAt: Date
    var deletedAt: Date?
    var loggedBy: String

    init(kind: String, startedAt: Date, createdAt: Date, modifiedAt: Date, deletedAt: Date?, loggedBy: String) {
        self.kind = kind
        self.startedAt = startedAt
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.loggedBy = loggedBy
    }

    init?(record: CKRecord) {
        guard let kind = record["kind"] as? String,
              let startedAt = record["startedAt"] as? Date,
              let loggedBy = record["loggedBy"] as? String else { return nil }
        self.kind = kind
        self.startedAt = startedAt
        self.createdAt = record["createdAt"] as? Date ?? startedAt
        self.modifiedAt = record["modifiedAt"] as? Date ?? createdAt
        self.deletedAt = record["deletedAt"] as? Date
        self.loggedBy = loggedBy
    }

    func apply(to record: CKRecord) {
        record["babyID"] = "spike"
        record["kind"] = kind
        record["startedAt"] = startedAt
        record["createdAt"] = createdAt
        record["modifiedAt"] = modifiedAt
        record["deletedAt"] = deletedAt
        record["loggedBy"] = loggedBy
        record["timeZoneID"] = TimeZone.current.identifier
        record["schemaVersion"] = Int64(1)
    }
}

/// What stays between runs: who this phone is and where the sync engines got to.
struct SyncSpikeSetup: Codable {
    var memberID = UUID().uuidString
    var privateEngineState: CKSyncEngine.State.Serialization?
    var sharedEngineState: CKSyncEngine.State.Serialization?
    var ownsHousehold = false
    var sharedZoneOwner: String?
    var shareURL: URL?
}

struct SyncSentItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var recordName: String
    /// ping, ring or cancel.
    var kind: String
    var tappedAt: Date
    var ringAt: Date?
    /// iCloud's clock when it saved the record.
    var savedAt: Date?
    var error: String?
}

struct SyncReceivedItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var recordName: String
    var kind: String
    /// The other phone's clock when it was tapped.
    var tappedAt: Date
    /// iCloud's clock when it saved the record.
    var savedAt: Date?
    /// This phone's clock when the record arrived.
    var receivedAt: Date
    var appState: String
    var afterPush: Bool
}

struct SyncRingItem: Codable, Identifiable, Hashable {
    var id: String { recordName }
    var recordName: String
    var ringAt: Date
    var scheduledAt: Date?
    var scheduledAppState: String?
    var cancelledAt: Date?
    var cancelledAppState: String?
    var tooLateAt: Date?
    var stoppedAt: Date?
    var errors: [String] = []
}

struct SyncPushItem: Codable, Hashable {
    var at: Date
    var appState: String
    var database: String
}

struct SyncNote: Codable, Hashable {
    var at: Date
    var text: String
}

struct SyncSpikeLog: Codable {
    var sent: [SyncSentItem] = []
    var received: [SyncReceivedItem] = []
    var rings: [SyncRingItem] = []
    var pushes: [SyncPushItem] = []
    var notes: [SyncNote] = []
}

@MainActor
@Observable
final class SyncSpikeStore {
    static let shared = SyncSpikeStore()
    static let setupFile = "sync-spike-setup.json"
    static let logFile = "sync-spike.json"
    static let zoneName = "Household"

    private(set) var setup: SyncSpikeSetup
    private(set) var log: SyncSpikeLog
    private(set) var accountStatus = "checking"
    private(set) var busy = false

    /// Nil unless the app's container is the Dev one: the spikes never touch the real data.
    let container: CKContainer?
    private let privateDelegate = SyncSpikeEngineDelegate(scope: .private)
    private let sharedDelegate = SyncSpikeEngineDelegate(scope: .shared)
    @ObservationIgnored private var privateEngine: CKSyncEngine?
    @ObservationIgnored private var sharedEngine: CKSyncEngine?
    /// Records waiting to be sent, handed to the sync engine when it asks.
    @ObservationIgnored private var pending: [CKRecord.ID: CKRecord] = [:]
    /// The last copy iCloud saved, so a change goes out with the right version.
    @ObservationIgnored private var lastSaved: [String: CKRecord] = [:]
    @ObservationIgnored private var lastPushAt: Date?
    @ObservationIgnored private var sharingDelegate: SpikeSharingDelegate?

    private init() {
        let id = Bundle.main.object(forInfoDictionaryKey: "FeedingCloudKitContainer") as? String ?? ""
        container = id.hasSuffix(".dev") ? CKContainer(identifier: id) : nil
        setup = SpikeFile.load(SyncSpikeSetup.self, from: Self.setupFile) ?? SyncSpikeSetup()
        log = SpikeFile.load(SyncSpikeLog.self, from: Self.logFile) ?? SyncSpikeLog()
        saveSetup()
    }

    private func saveSetup() { SpikeFile.save(setup, to: Self.setupFile) }
    private func saveLog() { SpikeFile.save(log, to: Self.logFile) }

    /// Starts both sync engines. Called at launch, also when a push wakes the app.
    func start() {
        guard let container, privateEngine == nil else { return }
        privateEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: setup.privateEngineState, delegate: privateDelegate))
        sharedEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase, stateSerialization: setup.sharedEngineState, delegate: sharedDelegate))
    }

    func refreshAccountStatus() async {
        guard let container else {
            accountStatus = "not the Dev container"
            return
        }
        do {
            accountStatus = switch try await container.accountStatus() {
            case .available: "signed in"
            case .noAccount: "not signed in"
            case .restricted: "restricted"
            case .couldNotDetermine: "could not check"
            case .temporarilyUnavailable: "temporarily unavailable"
            @unknown default: "unknown"
            }
        } catch {
            accountStatus = "error: \(error.localizedDescription)"
        }
    }

    // MARK: The household

    var isInHousehold: Bool { setup.ownsHousehold || setup.sharedZoneOwner != nil }

    var roleText: String {
        if setup.ownsHousehold { return "This phone shares the test household." }
        if setup.sharedZoneOwner != nil { return "This phone joined the test household." }
        return "Not in a test household yet."
    }

    private var ownZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Where this phone writes: its own private zone, or the shared zone it joined.
    private var writeTarget: (engine: CKSyncEngine, zoneID: CKRecordZone.ID)? {
        if setup.ownsHousehold, let privateEngine {
            return (privateEngine, ownZoneID)
        }
        if let owner = setup.sharedZoneOwner, let sharedEngine {
            return (sharedEngine, CKRecordZone.ID(zoneName: Self.zoneName, ownerName: owner))
        }
        return nil
    }

    /// Parent A's phone: makes the zone if needed, shares the whole zone, opens Apple's invite sheet.
    func createHouseholdAndInvite() async {
        guard let container, let privateEngine, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if !setup.ownsHousehold {
                privateEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: ownZoneID))])
                try await privateEngine.sendChanges()
            }
            let share = try await zoneShare(database: container.privateCloudDatabase)
            setup.ownsHousehold = true
            setup.shareURL = share.url
            saveSetup()
            presentInviteSheet(share: share, container: container)
        } catch {
            note("Could not set up the household: \(error.localizedDescription)")
        }
    }

    /// The zone's one share: fetched if it exists, made if not.
    private func zoneShare(database: CKDatabase) async throws -> CKShare {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownZoneID)
        if let existing = try? await database.record(for: shareID) as? CKShare {
            return existing
        }
        let share = CKShare(recordZoneID: ownZoneID)
        share[CKShare.SystemFieldKey.title] = "Feeding Dev test household"
        share.publicPermission = .none
        guard let saved = try await database.save(share) as? CKShare else { throw CKError(.internalError) }
        note("Made the share.")
        return saved
    }

    private func presentInviteSheet(share: CKShare, container: CKContainer) {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        let delegate = SpikeSharingDelegate()
        sharingDelegate = delegate
        controller.delegate = delegate
        guard let presenter = topViewController() else {
            note("Could not open the invite sheet.")
            return
        }
        presenter.present(controller, animated: true)
    }

    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// Parent B's phone: accepts an invite from the link (system hand-off or pasted).
    func accept(_ metadata: CKShare.Metadata, how: String) async {
        guard let container else { return }
        do {
            _ = try await container.accept(metadata)
            note("Joined the household (\(how)).")
            try await sharedEngine?.fetchChanges()
        } catch {
            note("Could not join (\(how)): \(error.localizedDescription)")
        }
    }

    func acceptPastedLink(_ text: String) async {
        guard let container, !busy else { return }
        busy = true
        defer { busy = false }
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https" else {
            note("That is not an invite link.")
            return
        }
        do {
            let metadata = try await container.shareMetadata(for: url)
            await accept(metadata, how: "pasted link")
        } catch {
            note("Could not read the invite link: \(error.localizedDescription)")
        }
    }

    // MARK: Sending

    func sendPing() async {
        await send(kind: "spike.ping", startedAt: Date(), label: "ping")
    }

    func sendRing() async {
        await send(kind: "spike.ring", startedAt: Date().addingTimeInterval(120), label: "ring")
    }

    /// The newest ring this phone sent that is still in the future and not cancelled.
    var cancellableRing: SyncSentItem? {
        let now = Date()
        return log.sent.last { item in
            item.kind == "ring" && (item.ringAt ?? .distantPast) > now
                && !log.sent.contains { $0.kind == "cancel" && $0.recordName == item.recordName }
        }
    }

    func cancelRing() async {
        guard let ring = cancellableRing else { return }
        await send(kind: "spike.ring", startedAt: ring.ringAt ?? Date(), label: "cancel", recordName: ring.recordName, deleted: true)
    }

    private func send(kind: String, startedAt: Date, label: String, recordName: String = UUID().uuidString, deleted: Bool = false) async {
        guard let target = writeTarget else {
            note("Make or join the household first.")
            return
        }
        let now = Date()
        let recordID = CKRecord.ID(recordName: recordName, zoneID: target.zoneID)
        let record = lastSaved[recordName] ?? CKRecord(recordType: "Event", recordID: recordID)
        let fields = SpikeEventFields(
            kind: kind, startedAt: startedAt, createdAt: record["createdAt"] as? Date ?? now, modifiedAt: now,
            deletedAt: deleted ? now : nil, loggedBy: setup.memberID)
        fields.apply(to: record)
        pending[recordID] = record
        log.sent.append(SyncSentItem(recordName: recordName, kind: label, tappedAt: now, ringAt: kind == "spike.ring" ? startedAt : nil))
        saveLog()
        target.engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        do {
            try await target.engine.sendChanges(CKSyncEngine.SendChangesOptions(scope: .recordIDs([recordID])))
        } catch {
            note("Send failed: \(error.localizedDescription)")
        }
    }

    func pendingRecord(_ id: CKRecord.ID) -> CKRecord? { pending[id] }

    // MARK: Receiving

    /// A push came in. Fetch at once, as the real app will, within the time iOS allows.
    func handlePush(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let now = Date()
        lastPushAt = now
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        let database = switch (notification as? CKDatabaseNotification)?.databaseScope {
        case .private: "private"
        case .shared: "shared"
        case .public: "public"
        default: "not CloudKit"
        }
        log.pushes.append(SyncPushItem(at: now, appState: appStateText, database: database))
        if log.pushes.count > 300 { log.pushes.removeFirst(log.pushes.count - 300) }
        saveLog()
        let before = log.received.count
        await fetchNow()
        return log.received.count > before ? .newData : .noData
    }

    func fetchNow() async {
        do {
            try await privateEngine?.fetchChanges()
            try await sharedEngine?.fetchChanges()
        } catch {
            note("Fetch failed: \(error.localizedDescription)")
        }
    }

    func handle(_ event: CKSyncEngine.Event, scope: CKDatabase.Scope) async {
        let where_ = scope == .private ? "private" : "shared"
        switch event {
        case .stateUpdate(let update):
            if scope == .private {
                setup.privateEngineState = update.stateSerialization
            } else {
                setup.sharedEngineState = update.stateSerialization
            }
            saveSetup()
        case .accountChange:
            note("The iCloud account changed (\(where_) database).")
            await refreshAccountStatus()
        case .fetchedDatabaseChanges(let changes):
            for modification in changes.modifications where modification.zoneID.zoneName == Self.zoneName {
                if scope == .shared, setup.sharedZoneOwner != modification.zoneID.ownerName {
                    setup.sharedZoneOwner = modification.zoneID.ownerName
                    note("Found the shared household.")
                } else if scope == .private, !setup.ownsHousehold {
                    setup.ownsHousehold = true
                    note("Found this phone's own household.")
                }
            }
            for deletion in changes.deletions where deletion.zoneID.zoneName == Self.zoneName {
                note("The household left the \(where_) database (\(deletion.reason)).")
                if scope == .shared { setup.sharedZoneOwner = nil } else { setup.ownsHousehold = false }
            }
            saveSetup()
        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                await receive(modification.record)
            }
        case .sentDatabaseChanges(let sent):
            for zone in sent.savedZones where zone.zoneID.zoneName == Self.zoneName {
                setup.ownsHousehold = true
                note("Made the household zone.")
            }
            for failure in sent.failedZoneSaves {
                note("Could not make the zone: \(failure.error.localizedDescription)")
            }
            saveSetup()
        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                pending[record.recordID] = nil
                lastSaved[record.recordID.recordName] = record
                if let i = log.sent.lastIndex(where: { $0.recordName == record.recordID.recordName && $0.savedAt == nil }) {
                    log.sent[i].savedAt = record.modificationDate ?? Date()
                }
            }
            for failure in sent.failedRecordSaves {
                handleFailedSave(failure.record, error: failure.error, scope: scope)
            }
            saveLog()
        default:
            break
        }
    }

    private func handleFailedSave(_ record: CKRecord, error: CKError, scope: CKDatabase.Scope) {
        let engine = scope == .private ? privateEngine : sharedEngine
        let id = record.recordID
        switch error.code {
        case .serverRecordChanged:
            // The spike's own fields win: put them on iCloud's copy and send again.
            guard let server = error.serverRecord, let fields = SpikeEventFields(record: record) else { return }
            fields.apply(to: server)
            pending[id] = server
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            if let engine { Task { try? await engine.sendChanges() } }
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited,
             .notAuthenticated, .accountTemporarilyUnavailable:
            note("Send will retry: \(error.localizedDescription)")
        default:
            note("Send failed: \(error.localizedDescription)")
            pending[id] = nil
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            if let i = log.sent.lastIndex(where: { $0.recordName == id.recordName && $0.savedAt == nil }) {
                log.sent[i].error = error.localizedDescription
            }
        }
    }

    private func receive(_ record: CKRecord) async {
        guard record.recordType == "Event", let fields = SpikeEventFields(record: record), fields.kind.hasPrefix("spike.") else { return }
        // This phone's own change coming back.
        guard fields.loggedBy != setup.memberID else { return }
        let now = Date()
        let state = appStateText
        let name = record.recordID.recordName
        let cancelled = fields.deletedAt != nil
        let label = fields.kind == "spike.ring" ? (cancelled ? "cancel" : "ring") : "ping"
        if !log.received.contains(where: { $0.recordName == name && $0.kind == label }) {
            log.received.append(SyncReceivedItem(
                recordName: name, kind: label, tappedAt: fields.modifiedAt, savedAt: record.modificationDate,
                receivedAt: now, appState: state, afterPush: lastPushAt.map { now.timeIntervalSince($0) < 60 } ?? false))
        }
        if fields.kind == "spike.ring" {
            await handleRing(name: name, ringAt: fields.startedAt, cancelled: cancelled, appState: state)
        }
        saveLog()
    }

    /// Sets or cancels the alarm the other phone asked for. Records whether it worked, and in
    /// which app state: this is the "can a background push set an alarm" question.
    private func handleRing(name: String, ringAt: Date, cancelled: Bool, appState: String) async {
        guard let alarmID = UUID(uuidString: name) else { return }
        var ring = log.rings.first { $0.recordName == name } ?? SyncRingItem(recordName: name, ringAt: ringAt)
        let now = Date()
        if cancelled {
            guard ring.cancelledAt == nil else { return }
            ring.cancelledAt = now
            ring.cancelledAppState = appState
            if ring.scheduledAt != nil {
                do {
                    try AlarmManager.shared.cancel(id: alarmID)
                } catch {
                    ring.errors.append("cancel: \(error.localizedDescription)")
                }
            } else {
                ring.errors.append("It arrived already cancelled, so no alarm was set.")
            }
        } else if ring.scheduledAt == nil, ring.tooLateAt == nil, ring.cancelledAt == nil, ring.errors.isEmpty {
            if ringAt > now.addingTimeInterval(5) {
                do {
                    try await SpikeAlarm.schedule(id: alarmID, at: ringAt, title: "Feeding Dev: ring from the other phone")
                    ring.scheduledAt = now
                    ring.scheduledAppState = appState
                } catch {
                    ring.errors.append("set the alarm (app \(appState)): \(error.localizedDescription)")
                }
            } else {
                ring.tooLateAt = now
            }
        }
        if let i = log.rings.firstIndex(where: { $0.recordName == name }) {
            log.rings[i] = ring
        } else {
            log.rings.append(ring)
        }
    }

    /// Called by the alarm's Stop button.
    func recordRingStop(alarmID: String, at date: Date) {
        guard let i = log.rings.firstIndex(where: { $0.recordName == alarmID }), log.rings[i].stoppedAt == nil else { return }
        log.rings[i].stoppedAt = date
        saveLog()
    }

    // MARK: Helpers

    private var appStateText: String {
        switch UIApplication.shared.applicationState {
        case .active: "open"
        case .inactive: "opening or closing"
        case .background: "in the background"
        @unknown default: "unknown"
        }
    }

    func note(_ text: String) {
        log.notes.append(SyncNote(at: Date(), text: text))
        if log.notes.count > 300 { log.notes.removeFirst(log.notes.count - 300) }
        saveLog()
    }

    func clearResults() {
        log = SyncSpikeLog()
        saveLog()
    }
}

/// Hands sync engine calls to the store on the main actor. One per database.
final class SyncSpikeEngineDelegate: CKSyncEngineDelegate {
    let scope: CKDatabase.Scope

    init(scope: CKDatabase.Scope) {
        self.scope = scope
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await SyncSpikeStore.shared.handle(event, scope: scope)
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await SyncSpikeStore.shared.pendingRecord(recordID)
        }
    }
}

/// Apple's invite sheet reports here.
@MainActor
final class SpikeSharingDelegate: NSObject, UICloudSharingControllerDelegate {
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
        SyncSpikeStore.shared.note("The invite sheet could not save the share: \(error.localizedDescription)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        "Feeding Dev test household"
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        SyncSpikeStore.shared.note("The invite sheet saved the share.")
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        SyncSpikeStore.shared.note("Sharing was stopped from the invite sheet.")
    }
}
#endif
