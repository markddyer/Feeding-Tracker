import CloudKit
import FeedingCore
import Foundation
import Observation
import UIKit

/// Keeps the household store in step with iCloud, as plan v1 "Data and sync" says:
/// - Parent A owns a Household zone in their private database and shares the whole zone.
/// - Parent B accepts and syncs from the shared database, writing with the shared zone ID.
/// - One CKSyncEngine per database. A push triggers an explicit fetch; going to the background
///   ends the undo window and sends straight away inside a background task.
/// - A save clash merges field by field (`HouseholdData.receiveEvent`).
/// - Nothing is ever deleted automatically: not zones, and not local data when iCloud goes quiet.
///
/// Proven on two real phones in Phase 0, spike 2 (14 Nov 2026).
@MainActor
@Observable
final class HouseholdSync {
    static let zoneName = "Household"

    enum Role: Equatable {
        case notSetUp
        /// This phone's iCloud owns the household and shares it.
        case owner
        /// This phone joined a household shared by `ownerName`.
        case member(ownerName: String)
    }

    private(set) var role: Role = .notSetUp
    private(set) var accountStatus = "checking"
    /// Nil until checked. False means no iCloud on this phone, so nothing syncs.
    private(set) var accountAvailable: Bool?
    /// This parent's ID: their iCloud user record name.
    private(set) var memberID: MemberID?
    private(set) var lastFetchAt: Date?
    private(set) var lastSendAt: Date?
    /// Something the parents need to know, such as the household being removed.
    private(set) var problem: String?
    /// The last error in full, for the Tests screen in Feeding Dev. Never shown on the home screen.
    private(set) var errorDetail: String?
    private(set) var busy = false

    let container: CKContainer
    private let store: HouseholdStore
    private let privateDelegate: SyncEngineDelegate
    private let sharedDelegate: SyncEngineDelegate
    private let defaults: UserDefaults
    @ObservationIgnored private var privateEngine: CKSyncEngine?
    @ObservationIgnored private var sharedEngine: CKSyncEngine?
    /// The local revision sent for each record, to confirm exactly what iCloud saved.
    @ObservationIgnored private var inFlight: [String: Int] = [:]
    /// Records that failed for a reason a retry won't fix. Tried again on the next foreground.
    @ObservationIgnored private var blocked: Set<String> = []
    /// The message a failed send put up, so a later good send can take it down.
    @ObservationIgnored private var sendProblem: String?
    @ObservationIgnored private var undoWindowTask: Task<Void, Never>?
    @ObservationIgnored private var inviteDelegate: InviteSheetDelegate?

    init(store: HouseholdStore) {
        self.store = store
        container = CKContainer(identifier: AppConfig.containerID)
        privateDelegate = SyncEngineDelegate(scope: .private)
        sharedDelegate = SyncEngineDelegate(scope: .shared)
        defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
        memberID = defaults.string(forKey: "memberID").map(MemberID.init(rawValue:))
        if let owner = defaults.string(forKey: "householdOwner") {
            role = owner == CKCurrentUserDefaultName ? .owner : .member(ownerName: owner)
        }
    }

    var isStarted: Bool { privateEngine != nil }

    /// Starts both sync engines. Called at launch, also when a push wakes the app.
    func start() {
        guard AppConfig.syncEnabled, privateEngine == nil else { return }
        store.onLocalChange = { [weak self] in self?.scheduleUploads() }
        privateEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: savedState(for: .private), delegate: privateDelegate))
        sharedEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase, stateSerialization: savedState(for: .shared), delegate: sharedDelegate))
        Task { await refreshAccount() }
        scheduleUploads()
    }

    func refreshAccount() async {
        do {
            let status = try await container.accountStatus()
            accountStatus = switch status {
            case .available: "signed in"
            case .noAccount: "not signed in"
            case .restricted: "restricted"
            case .couldNotDetermine: "could not check"
            case .temporarilyUnavailable: "temporarily unavailable"
            @unknown default: "unknown"
            }
            accountAvailable = status == .available
            if status == .available {
                let id = MemberID(rawValue: try await container.userRecordID().recordName)
                memberID = id
                defaults.set(id.rawValue, forKey: "memberID")
            }
        } catch {
            accountStatus = "error: \(error.localizedDescription)"
        }
    }

    // MARK: The household

    private var ownZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// The engine and zone this phone writes to, once it is in a household.
    private var writeTarget: (engine: CKSyncEngine, zoneID: CKRecordZone.ID)? {
        switch role {
        case .owner:
            privateEngine.map { (engine: $0, zoneID: ownZoneID) }
        case .member(let owner):
            sharedEngine.map { (engine: $0, zoneID: CKRecordZone.ID(zoneName: Self.zoneName, ownerName: owner)) }
        case .notSetUp:
            nil
        }
    }

    private func setRole(_ newRole: Role) {
        guard role != newRole else { return }
        role = newRole
        switch newRole {
        case .owner: defaults.set(CKCurrentUserDefaultName, forKey: "householdOwner")
        case .member(let owner): defaults.set(owner, forKey: "householdOwner")
        case .notSetUp: defaults.removeObject(forKey: "householdOwner")
        }
        scheduleUploads()
    }

    /// Parent A: makes the Household zone in this parent's iCloud.
    func createHousehold() async {
        guard let privateEngine, !busy, role == .notSetUp else { return }
        busy = true
        defer { busy = false }
        privateEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: ownZoneID))])
        do {
            try await Self.outsideCallbacks { try await privateEngine.sendChanges() }
        } catch {
            report(error, doing: "set up the household")
        }
    }

    /// Parent A: shares the whole zone and opens Apple's invite sheet.
    func invite() async {
        guard role == .owner, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            presentInviteSheet(try await zoneShare())
        } catch {
            problem = Self.describe(error, doing: "make the invite")
        }
    }

    func createHouseholdAndInvite() async {
        if role == .notSetUp { await createHousehold() }
        await invite()
    }

    /// The zone's one share: fetched if it exists, made if not.
    private func zoneShare() async throws -> CKShare {
        let database = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownZoneID)
        if let existing = try? await database.record(for: shareID) as? CKShare {
            return existing
        }
        let share = CKShare(recordZoneID: ownZoneID)
        share[CKShare.SystemFieldKey.title] = "Feeding household"
        share.publicPermission = .none
        guard let saved = try await database.save(share) as? CKShare else { throw CKError(.internalError) }
        return saved
    }

    private func presentInviteSheet(_ share: CKShare) {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        let delegate = InviteSheetDelegate { [weak self] message in self?.problem = message }
        inviteDelegate = delegate
        controller.delegate = delegate
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(controller, animated: true)
    }

    /// Parent B: accepts an invite, from the link or pasted in.
    func accept(_ metadata: CKShare.Metadata) async {
        guard isStarted, let sharedEngine else { return }
        do {
            _ = try await container.accept(metadata)
            try await Self.outsideCallbacks { try await sharedEngine.fetchChanges() }
        } catch {
            errorDetail = Self.detail(error, doing: "join")
            problem = "Couldn't join the household: \(error.localizedDescription)"
        }
    }

    func acceptPastedLink(_ text: String) async {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https" else {
            problem = "That isn't an invite link."
            return
        }
        busy = true
        defer { busy = false }
        do {
            await accept(try await container.shareMetadata(for: url))
        } catch {
            problem = "Couldn't read the invite link: \(error.localizedDescription)"
        }
    }

    // MARK: Sending

    /// Queues everything that is waiting and past its undo window, then sends it.
    func scheduleUploads() {
        guard let target = writeTarget else { return }
        let now = Date()
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for stored in store.data.eventsToUpload(now: now) where !blocked.contains(stored.event.id) {
            changes.append(.saveRecord(CKRecord.ID(recordName: stored.event.id, zoneID: target.zoneID)))
        }
        for stored in store.data.plainRecordsToUpload() {
            let name = RecordMapping.cloudName(of: stored.record)
            guard !blocked.contains(name) else { continue }
            changes.append(.saveRecord(CKRecord.ID(recordName: name, zoneID: target.zoneID)))
        }
        let alreadyPending = Set(target.engine.state.pendingRecordZoneChanges)
        let new = changes.filter { !alreadyPending.contains($0) }
        if !new.isEmpty {
            target.engine.state.add(pendingRecordZoneChanges: new)
            Task { await sendNow() }
        }
        // Look again when the next undo window ends.
        let nextWindowEnd = store.data.events.values
            .compactMap { $0.needsUpload ? $0.uploadNotBefore : nil }
            .filter { $0 > now }
            .min()
        undoWindowTask?.cancel()
        if let nextWindowEnd {
            undoWindowTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(nextWindowEnd.timeIntervalSinceNow + 0.2))
                guard !Task.isCancelled else { return }
                self?.scheduleUploads()
            }
        }
    }

    func sendNow() async {
        guard let engine = writeTarget?.engine else { return }
        SyncLog.add("send: \(engine.state.pendingRecordZoneChanges.count) records waiting")
        do {
            try await Self.outsideCallbacks { try await engine.sendChanges() }
            SyncLog.add("send: done")
            clearSendProblem()
        } catch {
            SyncLog.add("send: threw \(String(reflecting: error))")
            report(error, doing: "send changes")
            sendProblem = problem
        }
    }

    /// A send problem goes once a later send works.
    private func clearSendProblem() {
        if let sendProblem, problem == sendProblem { problem = nil }
        sendProblem = nil
    }

    /// CKSyncEngine stops the app ("BUG IN CLIENT OF CLOUDKIT") when it is awaited from inside one
    /// of its own delegate callbacks, and an ordinary `Task` started there carries that callback's
    /// context with it, through every `Task` it starts in turn. A detached task starts clean, as
    /// Apple's message advises. Every call that can lead back into the delegate goes through here.
    /// (Found on two real phones on 14 Nov 2026: a change arriving from the other phone queued a
    /// send, and the send ran inside the arrival's context.)
    private static func outsideCallbacks(_ work: @escaping @Sendable () async throws -> Void) async throws {
        try await Task.detached(operation: work).value
    }

    /// The app is going to the background: send everything now, inside a background task.
    func appDidEnterBackground() {
        guard isStarted else { return }
        store.applySync { $0.endUndoWindows() }
        let task = BackgroundTask(name: "Send feeds")
        scheduleUploads()
        Task {
            await sendNow()
            task.end()
        }
    }

    func recordToSend(_ recordID: CKRecord.ID) -> CKRecord? {
        let name = recordID.recordName
        if let stored = store.data.events[name] {
            guard stored.needsUpload else { return nil }
            inFlight[name] = stored.localRevision
            return RecordMapping.record(for: stored, zoneID: recordID.zoneID)
        }
        if let key = plainKey(cloudName: name, in: store.data), let stored = store.data.plainRecords[key] {
            guard stored.needsUpload else { return nil }
            inFlight[name] = stored.localRevision
            return RecordMapping.record(for: stored, zoneID: recordID.zoneID)
        }
        return nil
    }

    // MARK: Receiving

    /// A push came in, or the app came to the foreground: fetch now, as the plan says.
    func fetchNow() async {
        guard isStarted else { return }
        if accountAvailable == nil { await refreshAccount() }
        guard accountAvailable == true else {
            problem = Self.notSignedIn
            return
        }
        blocked.removeAll()
        let engines = [privateEngine, sharedEngine].compactMap { $0 }
        do {
            for engine in engines {
                try await Self.outsideCallbacks { try await engine.fetchChanges() }
            }
            lastFetchAt = Date()
            if problem == Self.notSignedIn || problem == Self.offline { problem = nil }
        } catch {
            SyncLog.add("fetch: threw \(String(reflecting: error))")
            report(error, doing: "fetch the other phone's changes")
        }
        scheduleUploads()
    }

    /// Sets the plain message for the parents, and keeps the full error for the Tests screen.
    private func report(_ error: any Error, doing action: String) {
        problem = Self.describe(error, doing: action)
        errorDetail = Self.detail(error, doing: action)
    }

    private static func detail(_ error: any Error, doing action: String) -> String {
        "\(Date().formatted(date: .omitted, time: .standard)), \(action): \(String(reflecting: error))"
    }

    static let notSignedIn = "This phone isn't signed in to iCloud, so feeds don't reach the other phone. They are saved here."
    static let offline = "No internet connection. Feeds are saved on this phone and go to the other phone when it's back."

    /// Plain words for an error, for the banner.
    static func describe(_ error: any Error, doing action: String) -> String {
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated, .accountTemporarilyUnavailable: return notSignedIn
            case .networkUnavailable, .networkFailure: return offline
            default: break
            }
        }
        return "Couldn't \(action): \(error.localizedDescription)"
    }

    func handlePush() async -> UIBackgroundFetchResult {
        start()
        let before = store.data
        await fetchNow()
        return store.data == before ? .noData : .newData
    }

    func handle(_ event: CKSyncEngine.Event, scope: CKDatabase.Scope) async {
        switch event {
        case .stateUpdate(let update):
            let state = try? JSONEncoder().encode(update.stateSerialization)
            store.applySync { $0.syncState[Self.key(scope)] = state }

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                problem = nil
            case .signOut:
                problem = "This phone signed out of iCloud. Feeds stay on this phone, but they don't reach the other phone."
            case .switchAccounts:
                problem = "This phone switched iCloud accounts. Feeds stay on this phone; check the household in Settings."
            @unknown default:
                break
            }
            await refreshAccount()

        case .fetchedDatabaseChanges(let changes):
            for modification in changes.modifications where modification.zoneID.zoneName == Self.zoneName {
                setRole(scope == .private ? .owner : .member(ownerName: modification.zoneID.ownerName))
            }
            for deletion in changes.deletions where deletion.zoneID.zoneName == Self.zoneName {
                let mine = (scope == .private && role == .owner) || (scope == .shared && role != .owner)
                guard mine else { continue }
                // Round 2, S9: keep everything on this phone and say so. Never delete anything here.
                problem = "The shared household is gone from iCloud. Feeds and alerts on this phone are kept."
                setRole(.notSetUp)
            }

        case .fetchedRecordZoneChanges(let changes):
            SyncLog.add("fetched (\(Self.key(scope))): \(changes.modifications.map { "\($0.record.recordType) \($0.record.recordID.recordName)" }), deleted \(changes.deletions.count)")
            store.applySync { data in
                for modification in changes.modifications {
                    Self.receive(modification.record, into: &data)
                }
                for deletion in changes.deletions {
                    if deletion.recordType == "Event" {
                        data.removeEvent(deletion.recordID.recordName)
                    } else if let type = PlainRecordType(rawValue: deletion.recordType) {
                        let name = RecordMapping.localName(cloudName: deletion.recordID.recordName, type: type)
                        data.removePlainRecord("\(type.rawValue)/\(name)")
                    }
                }
            }
            lastFetchAt = Date()
            scheduleUploads()

        case .sentDatabaseChanges(let sent):
            SyncLog.add("sent zones: saved \(sent.savedZones.map(\.zoneID.zoneName)), failed \(sent.failedZoneSaves.map { "\($0.zone.zoneID.zoneName): \(String(reflecting: $0.error))" })")
            for zone in sent.savedZones where zone.zoneID.zoneName == Self.zoneName {
                setRole(.owner)
            }
            for failure in sent.failedZoneSaves {
                problem = "Couldn't make the household in iCloud: \(failure.error.localizedDescription)"
            }

        case .sentRecordZoneChanges(let sent):
            SyncLog.add("sent records: saved \(sent.savedRecords.map { "\($0.recordType) \($0.recordID.recordName)" })")
            store.applySync { data in
                for record in sent.savedRecords {
                    let name = record.recordID.recordName
                    let fields = RecordMapping.systemFields(of: record)
                    let revision = inFlight.removeValue(forKey: name) ?? -1
                    if data.events[name] != nil {
                        data.didUploadEvent(name, sentRevision: revision, systemFields: fields, serverCreatedAt: record.creationDate)
                    } else if let key = plainKey(cloudName: name, in: data) {
                        data.didUploadPlainRecord(key, sentRevision: revision, systemFields: fields)
                    }
                }
            }
            for failure in sent.failedRecordSaves {
                SyncLog.add("sent records: FAILED \(failure.record.recordType) \(failure.record.recordID.recordName), code \(failure.error.code.rawValue): \(String(reflecting: failure.error))")
                handleFailedSave(failure.record, error: failure.error)
            }
            if sent.failedRecordSaves.isEmpty, !sent.savedRecords.isEmpty { clearSendProblem() }
            lastSendAt = Date()
            scheduleUploads()

        default:
            break
        }
    }

    private static func receive(_ record: CKRecord, into data: inout HouseholdData) {
        let fields = RecordMapping.systemFields(of: record)
        if let event = RecordMapping.event(from: record) {
            data.receiveEvent(event, systemFields: fields)
        } else if let plain = RecordMapping.plainRecord(from: record) {
            data.receivePlainRecord(plain, systemFields: fields)
        }
    }

    private func handleFailedSave(_ record: CKRecord, error: CKError) {
        let name = record.recordID.recordName
        inFlight[name] = nil
        switch error.code {
        case .serverRecordChanged:
            // A save clash: merge this phone's changes onto iCloud's copy; they go again if needed.
            if let server = error.serverRecord {
                store.applySync { Self.receive(server, into: &$0) }
            }
        case .zoneNotFound:
            if role == .owner, let privateEngine {
                privateEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: ownZoneID))])
            } else {
                problem = "The shared household is gone from iCloud. Feeds on this phone are kept."
                blocked.insert(name)
            }
        case .unknownItem:
            // iCloud no longer has the version ours was based on: send it as a fresh record.
            store.applySync { data in
                data.events[name]?.systemFields = nil
                if let key = plainKey(cloudName: name, in: data) {
                    data.plainRecords[key]?.systemFields = nil
                }
            }
        case .quotaExceeded:
            // Round 2, S8.
            problem = "The iCloud storage of the parent who shares the household is full. Feeds stay on this phone until there is space."
            blocked.insert(name)
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited,
             .notAuthenticated, .accountTemporarilyUnavailable:
            break // The sync engine retries these by itself.
        default:
            problem = "Couldn't save a change: \(error.localizedDescription)"
            sendProblem = problem
            errorDetail = Self.detail(error, doing: "save \(record.recordType)")
            blocked.insert(name)
        }
    }

    // MARK: Helpers

    private static func key(_ scope: CKDatabase.Scope) -> String { scope == .private ? "private" : "shared" }

    /// The phone's key for the plain record iCloud knows by `cloudName`.
    private func plainKey(cloudName: String, in data: HouseholdData) -> String? {
        data.plainRecords.first { RecordMapping.cloudName(of: $0.value.record) == cloudName }?.key
    }

    private func savedState(for scope: CKDatabase.Scope) -> CKSyncEngine.State.Serialization? {
        guard let data = store.data.syncState[Self.key(scope)] else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    func clearProblem() { problem = nil }
}

/// Hands sync engine calls to `HouseholdSync` on the main actor. One per database.
final class SyncEngineDelegate: CKSyncEngineDelegate {
    let scope: CKDatabase.Scope

    init(scope: CKDatabase.Scope) {
        self.scope = scope
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await AppModel.shared.sync.handle(event, scope: scope)
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await AppModel.shared.sync.recordToSend(recordID)
        }
    }
}

/// Apple's invite sheet reports here.
@MainActor
final class InviteSheetDelegate: NSObject, UICloudSharingControllerDelegate {
    private let report: @MainActor (String) -> Void

    init(report: @escaping @MainActor (String) -> Void) {
        self.report = report
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
        report("The invite couldn't be saved: \(error.localizedDescription)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { "Feeding household" }
}

/// Asks iOS for a little time to finish sending after the app leaves the screen.
@MainActor
final class BackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
