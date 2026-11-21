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
    /// When a fetch from the household's database last finished, not when a batch arrived: the
    /// "who did what" page's "Checked with iCloud" (design 1D; Codex review of the plan, 9).
    private(set) var lastCompletedFetchAt: Date?
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
    /// The owner's iCloud name from an invite being accepted, until the role is known.
    @ObservationIgnored private var joiningOwner: String?
    /// The owner names of every photos zone the databases have reported, kept on this phone.
    @ObservationIgnored private var photosZoneOwners: Set<String> = []
    /// Called when an engine fetch starts (true) and ends (false), so photo transfers make way.
    @ObservationIgnored var onEngineFetch: (@MainActor (Bool) -> Void)?
    /// Called when the engines have sent changes, or the shares changed, so photos may go on.
    @ObservationIgnored var onSent: (@MainActor () -> Void)?
    /// True once this launch has listed the shared database's zones (`learnSharedPhotosZones`).
    @ObservationIgnored private var sharedZonesListed = false
    @ObservationIgnored private var sharedZonesTask: Task<Void, Never>?

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
        photosZoneOwners = Set(defaults.stringArray(forKey: "photosZoneOwners") ?? [])
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

    /// The database that holds the household: this phone's own when it made it, the shared one
    /// when it joined.
    private var householdScope: CKDatabase.Scope? {
        switch role {
        case .owner: .private
        case .member: .shared
        case .notSetUp: nil
        }
    }

    /// The parent who made the household: the "who did what" page puts them on the left on both
    /// phones (design 2C). Their member ID is their iCloud user record name, which is the shared
    /// zone's owner name on the other phone.
    var householdOwner: MemberID? {
        switch role {
        case .owner: memberID
        case .member(let owner): MemberID(rawValue: owner)
        case .notSetUp: nil
        }
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
        share[CKShare.SystemFieldKey.title] = "Little Log household"
        share.publicPermission = .none
        guard let saved = try await database.save(share) as? CKShare else { throw CKError(.internalError) }
        return saved
    }

    private func presentInviteSheet(_ share: CKShare) {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        let delegate = InviteSheetDelegate(report: { [weak self] message in self?.problem = message },
                                           sharesChanged: { [weak self] in self?.onSent?() })
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
        // The role is learnt from the join fetch, so the owner's name comes from the invite.
        joiningOwner = metadata.share.recordID.zoneID.ownerName
        do {
            _ = try await container.accept(metadata)
            let options = fetchOptions(for: .shared)
            try await Self.outsideCallbacks { try await sharedEngine.fetchChanges(options) }
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

    /// True while an entry is ready to send and not blocked: photo transfers wait behind it
    /// (journal plan, "Photos never get in the way of feeds").
    var hasEntriesWaitingToSend: Bool {
        let now = Date()
        return store.data.eventsToUpload(now: now).contains { !blocked.contains($0.event.id) }
            || store.data.plainRecordsToUpload().contains { !blocked.contains(RecordMapping.cloudName(of: $0.record)) }
    }

    /// Queues everything that is waiting and past its undo window, then sends it. True when it
    /// started a send.
    @discardableResult
    func scheduleUploads() -> Bool {
        guard let target = writeTarget else { return false }
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
                // A record queued before its hold was skipped while held: send it now, even
                // though it is already queued, unless this already started a send (Codex review).
                if self?.scheduleUploads() == false { await self?.sendNow() }
            }
        }
        return !new.isEmpty
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

    /// False while a held first's change is on its way to iCloud: Undo can no longer take it
    /// back (Codex review of T5 and T6). The Undo bar asks this with `undoHeld`'s own deadline.
    func mayUndo(_ id: String) -> Bool { inFlight[id] == nil }

    /// What to do with an entry on a sync engine's list of records to send.
    enum SendDecision: Equatable {
        /// Send the record now.
        case send
        /// Not yet (held for Undo): the entry stays on the list, and is queued again when the
        /// hold ends.
        case hold
        /// Nothing to send (already sent, or replaced by the other phone's copy, or gone): the
        /// entry comes off the list, as Apple asks. Left on, it stayed there for good, and every
        /// send asked about it again (found on the owner's phone, 18 Nov 2026).
        case drop
    }

    nonisolated static func sendDecision(needsUpload: Bool, uploadNotBefore: Date?, now: Date) -> SendDecision {
        guard needsUpload else { return .drop }
        if let until = uploadNotBefore, until > now { return .hold }
        return .send
    }

    /// The record to send for an entry on the engine's list, and whether the entry stays on it.
    func recordToSend(_ recordID: CKRecord.ID) -> (record: CKRecord?, keepOnList: Bool) {
        let answer = recordOrDecision(recordID)
        if !answer.keepOnList { SyncLog.add("send: nothing to send for \(recordID.recordName); taken off the list") }
        return answer
    }

    private func recordOrDecision(_ recordID: CKRecord.ID) -> (record: CKRecord?, keepOnList: Bool) {
        let name = recordID.recordName
        if let stored = store.data.events[name] {
            // The same rule as `eventsToUpload` (`HouseholdData.mayUpload`): a change queued earlier
            // never carries a held delete out before its Undo window ends (outside voice OE4).
            switch Self.sendDecision(needsUpload: stored.needsUpload, uploadNotBefore: stored.uploadNotBefore, now: Date()) {
            case .drop: return (nil, false)
            case .hold: return (nil, true)
            case .send: break
            }
            // From here until iCloud answers, its Undo is closed (`mayUndo`), whatever the clock
            // does next; iCloud's answer ends it for good (`didUploadEvent`).
            inFlight[name] = stored.localRevision
            return (RecordMapping.record(for: stored, zoneID: recordID.zoneID), true)
        }
        if let key = plainKey(cloudName: name, in: store.data), let stored = store.data.plainRecords[key] {
            guard Self.sendDecision(needsUpload: stored.needsUpload, uploadNotBefore: nil, now: Date()) == .send else {
                return (nil, false)
            }
            inFlight[name] = stored.localRevision
            return (RecordMapping.record(for: stored, zoneID: recordID.zoneID), true)
        }
        return (nil, false)
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
        let engines: [(CKSyncEngine, CKDatabase.Scope)] = [(privateEngine, .private), (sharedEngine, .shared)]
            .compactMap { engine, scope in engine.map { ($0, scope) } }
        // Photos wait from the first engine's fetch to the last one's end, not just during each.
        onEngineFetch?(true)
        defer { onEngineFetch?(false) }
        do {
            for (engine, scope) in engines {
                // The private engine (the owner's feeds) never waits for this; the shared one
                // lists its zones first only while no owner is known (after a reinstall).
                if scope == .shared { await learnSharedPhotosZones() }
                let options = fetchOptions(for: scope)
                try await Self.outsideCallbacks { try await engine.fetchChanges(options) }
            }
            lastFetchAt = Date()
            if store.data.waitingForICloudSince != nil, !store.data.events.isEmpty,
               store.data.hasFeedsBack(plannedFrom: defaults.plannedFeedStarts, now: Date()) {
                // Every engine has fetched, and the feeds the alerts were planned from are back:
                // the alerts are planned normally again (CEO review D18). An empty fetch (a share
                // that has gone), or one without those feeds, leaves the phone waiting, for a day
                // at most.
                store.applySync { $0.waitingForICloudSince = nil }
                SyncLog.add("file: filled again from iCloud")
            }
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
        case .willFetchChanges:
            onEngineFetch?(true)

        case .didFetchChanges:
            onEngineFetch?(false)
            if scope == householdScope { lastCompletedFetchAt = Date() }
            await fetchMissingWhoValues()

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
            let photosOwners = changes.modifications.map(\.zoneID).filter { $0.zoneName == AppConfig.photosZoneName }.map(\.ownerName)
            if !photosOwners.isEmpty, !photosZoneOwners.isSuperset(of: photosOwners) {
                photosZoneOwners.formUnion(photosOwners)
                defaults.set(photosZoneOwners.sorted(), forKey: "photosZoneOwners")
            }
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
                    } else {
                        // A kind of record a newer build wrote: its kept copy goes too (step 0).
                        data.removePlainRecord("\(deletion.recordType)/\(deletion.recordID.recordName)")
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
            onSent?()

        default:
            break
        }
    }

    /// Set once this launch has looked for "who does what" values to fetch again.
    private var checkedMissingWhoValues = false

    /// Once per launch, after a fetch: the entries whose "done by" or "got up" an older build
    /// dropped from this phone's file are fetched again by name from the household zone, and
    /// received as any fetched record is, so a waiting local change still merges (engineering
    /// review of "who does what", E3, D9 A). The sync engines are never reset. An entry iCloud has
    /// no value for either is noted as checked and never fetched again.
    private func fetchMissingWhoValues() async {
        guard !checkedMissingWhoValues, let target = writeTarget else { return }
        checkedMissingWhoValues = true
        let ids = store.data.entriesMissingWhoValues
        guard !ids.isEmpty else { return }
        let database = switch role {
        case .owner: container.privateCloudDatabase
        default: container.sharedCloudDatabase
        }
        do {
            let results = try await database.records(for: ids.map { CKRecord.ID(recordName: $0, zoneID: target.zoneID) })
            var answered: [String] = []
            store.applySync { data in
                for (recordID, result) in results {
                    switch result {
                    case .success(let record):
                        Self.receive(record, into: &data)
                        answered.append(recordID.recordName)
                    case .failure(let error as CKError) where error.code == .unknownItem:
                        answered.append(recordID.recordName)
                    case .failure:
                        break // tried again at the next launch
                    }
                }
                data.noteWhoValuesFetched(answered)
            }
            SyncLog.add("who: fetched \(answered.count) of \(ids.count) entries missing a value; checked and still missing \(store.data.whoValuesChecked.count)")
            scheduleUploads()
        } catch {
            SyncLog.add("who: fetching entries missing a value failed: \(String(reflecting: error))")
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

    // MARK: What a fetch leaves out

    /// The options for the fetches this class starts: a push or coming to the foreground
    /// (`fetchNow`) and joining (`accept`). The engines' own fetches go through
    /// `fetchScope(restricting:for:)`. So no fetch, including one added later, includes the photos
    /// zone (eng D8, OE1a, 18 Nov 2026).
    func fetchOptions(for scope: CKDatabase.Scope) -> CKSyncEngine.FetchChangesOptions {
        CKSyncEngine.FetchChangesOptions(scope: fetchScope(restricting: .all, for: scope))
    }

    /// After a reinstall, before the role is known, the shared database's photos zones aren't
    /// known either, so a first fetch could include one. The zone list (no records) names them;
    /// asked once a launch, only while no owner is known (Codex review of T5 and T6).
    func learnSharedPhotosZones() async {
        guard !sharedZonesListed, joiningOwner == nil, photosZoneOwners.isEmpty else { return }
        if case .member = role { return }
        // One listing at a time: a second fetch waits for the one already asking.
        if let sharedZonesTask {
            await sharedZonesTask.value
            return
        }
        let database = container.sharedCloudDatabase
        let task = Task { [weak self] in
            let zones = try? await database.allRecordZones()
            guard let self else { return }
            sharedZonesTask = nil
            guard let zones else { return }
            sharedZonesListed = true
            let owners = zones.map(\.zoneID).filter { $0.zoneName == AppConfig.photosZoneName }.map(\.ownerName)
            guard !owners.isEmpty else { return }
            photosZoneOwners.formUnion(owners)
            defaults.set(photosZoneOwners.sorted(), forKey: "photosZoneOwners")
        }
        sharedZonesTask = task
        await task.value
    }

    /// `given` with the photos zones left out, for the engine of `scope`.
    func fetchScope(restricting given: CKSyncEngine.FetchChangesOptions.Scope,
                    for scope: CKDatabase.Scope) -> CKSyncEngine.FetchChangesOptions.Scope {
        Self.restricted(given, leavingOut: Self.photosZoneIDs(for: scope, role: role, joiningOwner: joiningOwner,
                                                              knownOwners: photosZoneOwners))
    }

    /// The photos zones a fetch by the engine of `scope` leaves out, by full ID: the owner's own
    /// (private database), and the one under the household owner's name (shared database), as
    /// `writeTarget` names the household zone. The owner's name comes from the role, from the
    /// invite while joining, and from every photos zone this phone has been told about, so the
    /// zone stays out even if the role is lost. It changes nothing until the journal makes a
    /// photos zone.
    static func photosZoneIDs(for scope: CKDatabase.Scope, role: Role, joiningOwner: String? = nil,
                              knownOwners: Set<String> = []) -> [CKRecordZone.ID] {
        var owners = knownOwners
        switch scope {
        case .private:
            owners.insert(CKCurrentUserDefaultName)
        case .shared:
            if case .member(let name) = role { owners.insert(name) }
            if let joiningOwner { owners.insert(joiningOwner) }
        default:
            break
        }
        return owners.sorted().map { CKRecordZone.ID(zoneName: AppConfig.photosZoneName, ownerName: $0) }
    }

    /// `scope` with `photos` left out. An explicit fetch's own exclusions are kept.
    static func restricted(_ scope: CKSyncEngine.FetchChangesOptions.Scope,
                           leavingOut photos: [CKRecordZone.ID]) -> CKSyncEngine.FetchChangesOptions.Scope {
        switch scope {
        case .all:
            return .allExcluding(photos)
        case .allExcluding(let excluded):
            return .allExcluding(excluded + photos.filter { !excluded.contains($0) })
        case .zoneIDs(let zones):
            return .zoneIDs(zones.filter { !photos.contains($0) })
        @unknown default:
            return .allExcluding(photos)
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

    /// Every fetch, the automatic ones too, leaves out the photos zone (eng D8).
    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        if scope == .shared { await AppModel.shared.sync.learnSharedPhotosZones() }
        var options = context.options
        options.scope = await AppModel.shared.sync.fetchScope(restricting: context.options.scope, for: scope)
        return options
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            let answer = await AppModel.shared.sync.recordToSend(recordID)
            if !answer.keepOnList {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
            return answer.record
        }
    }
}

/// Apple's invite sheet reports here.
@MainActor
final class InviteSheetDelegate: NSObject, UICloudSharingControllerDelegate {
    private let report: @MainActor (String) -> Void
    /// The sheet changed who is in the household: the photos share follows at once (outside voice
    /// OE7), as the sheet can remove a parent without telling the app otherwise.
    private let sharesChanged: @MainActor () -> Void

    init(report: @escaping @MainActor (String) -> Void, sharesChanged: @escaping @MainActor () -> Void) {
        self.report = report
        self.sharesChanged = sharesChanged
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
        report("The invite couldn't be saved: \(error.localizedDescription)")
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { sharesChanged() }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { sharesChanged() }

    func itemTitle(for csc: UICloudSharingController) -> String? { "Little Log household" }
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
