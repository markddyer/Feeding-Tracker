import CloudKit
import FeedingCore
import Foundation
import Observation
import UIKit

// The firsts' photos and videos in iCloud (`docs/planning/07-milestones-journal.md`, task T6).
// They live in a zone of their own (`AppConfig.photosZoneName`), which no sync engine ever fetches,
// and move with this class's own requests, one at a time, always behind the feeds.
//
//   EACH RUN (on opening, after the household syncs, when an item is added; never in the background)
//   the photos share ──> owner: zone, share, the other parent, the link in a household setting
//         │                member: accept the link by itself
//         ▼ ready
//   fetch the zone's changes (thumbnails and small fields only, `desiredKeys`); a record that
//   failed is fetched again on its own
//         ▼
//   uploads ──> read the tally ──> decide (`MediaTally.decide`) ──> one all-or-nothing save:
//         │      ▲                                                 Media record + tally
//         │      └──── tally changed since read (a clash) ◄────────┘
//         ▼
//   downloads of full files (the live firsts' items not on this phone; space reserve first)
//         ▼
//   clean-up (`MediaCleanUp.decide`, checked again just before): delete a removed item and its
//   tally entry in one save; then this phone's files no first needs any more
//
//   Every iCloud request goes through `transfer`: it starts only through `TransferGate.mayStart`
//   (no entry waiting to send, no engine fetch running), and is stopped by
//   `TransferGate.stopsTransferInFlight`: an entry that has waited 5 seconds, or (for a download)
//   an engine fetch starting, which also stops it at once (eng D3, D9). A stopped or backed-off
//   run ends; the next one starts from the beginning.

/// A photo or video waiting to go to iCloud, kept between launches.
struct MediaUpload: Codable, Hashable, Sendable {
    var id: String
    var eventID: String
    var byteSize: Int64
    /// The item's details, encoded by FeedingCore; encrypted by CloudKit.
    var payload: Data?
    var queuedAt: Date
    /// Why it isn't going now; nil while it waits its turn.
    var pause: MediaPause?
    /// The iCloud account and household it belongs to ("account|household owner"): it is sent
    /// only there. Nil until the first run that knows both; then it is bound to them.
    var binding: String?
}

/// Why an item isn't going to iCloud now. The words come from the app's screens (task T8).
enum MediaPause: String, Codable, Sendable {
    /// The household photo allowance is used up.
    case allowanceFull
    /// The household owner's iCloud storage is full.
    case iCloudFull
    /// The photos share isn't there yet on this phone.
    case notSharedYet
    /// iCloud refused it for a reason a retry won't fix; tried again on the next launch.
    case refused
}

/// What a CloudKit error means for a photo or video transfer (the journal plan's error map).
enum MediaFailure: Equatable, Sendable {
    /// Network trouble or a busy server: try again later, after `after` seconds if iCloud said.
    case retryLater(after: TimeInterval?)
    /// The tally changed since it was read: read it again and decide again (eng D11).
    case clash
    /// The household owner's iCloud is full: photos pause; feeds keep going.
    case iCloudFull
    /// The photos zone isn't there: the owner makes it again; the other phone waits for the share.
    case zoneMissing
    /// This phone can't use the photos zone yet: not accepted, or removed.
    case notSharedYet
    /// iCloud doesn't have the record (not uploaded yet, or gone).
    case missing
    /// The zone's change token is too old: fetch everything again.
    case tokenExpired
    /// Stopped by this app (the 5-second rule, a fetch starting, or the app leaving the screen).
    case stopped
    /// Anything else: kept, and tried again on the next launch.
    case refused

    init(_ error: any Error) {
        if error is CancellationError || error is MediaRunStop {
            self = .stopped
            return
        }
        guard let error = error as? CKError else {
            self = .refused
            return
        }
        if error.code == .partialFailure, let inner = error.partialErrorsByItemID?.values.compactMap({ $0 as? CKError })
            .first(where: { $0.code != .batchRequestFailed }) {
            self.init(inner)
            return
        }
        switch error.code {
        case .serverRecordChanged: self = .clash
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .notAuthenticated, .accountTemporarilyUnavailable, .serverResponseLost:
            self = .retryLater(after: error.retryAfterSeconds)
        case .quotaExceeded: self = .iCloudFull
        case .zoneNotFound, .userDeletedZone: self = .zoneMissing
        case .permissionFailure, .participantMayNeedVerification: self = .notSharedYet
        case .unknownItem: self = .missing
        case .changeTokenExpired: self = .tokenExpired
        case .operationCancelled: self = .stopped
        default: self = .refused
        }
    }
}

/// Ends a run quietly: the feeds need the way, the app left the screen, or iCloud asked to wait.
struct MediaRunStop: Error {}

/// The tally in iCloud can't be read (a newer build wrote it, or it is damaged). Nothing is saved
/// over it.
struct UnreadableTally: Error {}

/// Set when a request is stopped, so an answer that arrives anyway is not used.
@MainActor
final class StopFlag {
    var stopped = false
}

/// The photos zone this phone uses, and the database it is in.
struct PhotosZone {
    let id: CKRecordZone.ID
    let database: CKDatabase
    let isOwner: Bool
}

@MainActor
@Observable
final class MediaSync {
    /// Where the photos share stands on this phone, for Settings (task T8).
    enum ShareState: Equatable {
        case off
        case settingUp
        /// Not working yet, with the reason in plain words.
        case waiting(String)
        case ready
    }

    private(set) var shareState: ShareState = .off
    /// The tally as last read: the household's photo use.
    private(set) var tally: MediaTally?
    private(set) var uploads: [MediaUpload]

    /// The item's wait, if it is marked "Only on this iPhone" now (`OnlyHereRule`).
    func onlyHere(_ id: String, now: Date) -> MediaUpload? {
        guard let upload = uploads.first(where: { $0.id == id }),
              OnlyHereRule.isOnlyHere(queuedAt: upload.queuedAt, stopped: upload.pause != nil, now: now) else { return nil }
        return upload
    }

    /// When the next "Only on this iPhone" mark appears by itself, for the screens to look again.
    func nextOnlyHereChange(now: Date) -> Date? {
        OnlyHereRule.nextChange(queuedAt: uploads.filter { $0.pause == nil }.map(\.queuedAt), now: now)
    }
    /// The owner's phone is removing a parent who left from the photos share (outside voice OE7).
    private(set) var removingAccess = false
    /// The owner's phone couldn't add the other parent to the photos share yet: this phone's own
    /// photos still go; the other phone can't get them until it is added ("Photos sharing:
    /// waiting", task T8; the fallback is the link in Messages).
    private(set) var otherParentWaiting = false
    /// Goes up for an item whenever its file or thumbnail arrives on this phone or goes, so the
    /// screens show it; only that item's picture loads again.
    private(set) var fileVersions: [String: Int] = [:]
    /// Items an editor has made and not saved yet: never cleaned away (Codex review of T7 and T8).
    @ObservationIgnored private var drafts: Set<String> = []
    /// A first a parent opened from its notice: its photos come first (still behind the feeds).
    @ObservationIgnored private var preferredFirst: String?
    /// The account and household an item saved now belongs to; nil until both are known.
    func currentBinding() -> String? {
        guard let zone = photosZone, let me = household.memberID?.rawValue else { return nil }
        return Self.binding(me: me, zone: zone)
    }

    /// Photo or video, by item, once known (`kind(of:)`).
    @ObservationIgnored private var kinds: [String: MediaKind] = [:]
    /// An export is fetching what it needs: the photo run waits, so the two never transfer at once.
    @ObservationIgnored private var exporting = false

    private let store: HouseholdStore
    private let household: HouseholdSync
    private let files: MediaFiles?
    private let defaults: UserDefaults
    /// The upload queue's own file (task T17): written at once and checked, as Save counts on it.
    private let queueFile: URL?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private var enginesFetching = 0
    @ObservationIgnored private var entriesWaitingSince: ContinuousClock.Instant?
    /// iCloud asked to wait until then: no run starts before it.
    @ObservationIgnored private var backOffUntil: ContinuousClock.Instant?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var cleanUpTask: Task<Void, Never>?
    /// The request in flight, so a fetch starting can stop a download at once.
    @ObservationIgnored private var inFlight: (id: UUID, isDownload: Bool, cancel: () -> Void)?

    init(store: HouseholdStore, household: HouseholdSync, files: MediaFiles?, defaults: UserDefaults, queueFile: URL?) {
        self.store = store
        self.household = household
        self.files = files
        self.defaults = defaults
        self.queueFile = queueFile
        if let queueFile, let saved = try? Data(contentsOf: queueFile),
           let loaded = try? JSONDecoder().decode([MediaUpload].self, from: saved) {
            uploads = loaded
        } else {
            // Builds before 19 Nov 2026 kept the queue in the app's settings, which reach the disk
            // a moment later (Codex review of the crop and safety work): read once, then the file.
            uploads = defaults.data(forKey: Keys.uploads).flatMap { try? JSONDecoder().decode([MediaUpload].self, from: $0) } ?? []
        }
        // A refusal is tried again once per launch.
        for index in uploads.indices where uploads[index].pause == .refused { uploads[index].pause = nil }
    }

    // MARK: Calls from the rest of the app

    /// Queues an item whose file and thumbnail `MediaStore` has put in `MediaFiles`. False, and
    /// nothing queued, when the queue couldn't be written to this phone: Save then stops before
    /// the first is saved, so a first never names a photo that isn't queued (task T17).
    @discardableResult
    func add(_ upload: MediaUpload) -> Bool {
        guard !uploads.contains(where: { $0.id == upload.id }) else { return true }
        var upload = upload
        if upload.binding == nil, let zone = photosZone, let me = household.memberID?.rawValue {
            upload.binding = Self.binding(me: me, zone: zone)
        }
        uploads.append(upload)
        guard saveUploads() else {
            uploads.removeAll { $0.id == upload.id }
            return false
        }
        kick()
        return true
    }

    /// Forgets an item that was never sent (its first's add was undone): off the queue, and its
    /// files gone from this phone.
    func forget(_ id: String) {
        uploads.removeAll { $0.id == id }
        saveUploads()
        files?.remove(id)
        drafts.remove(id)
        changed(id)
    }

    /// Queues several items in one write (a first's Save), all or none. False, and none queued,
    /// when the queue couldn't be written to this phone (Codex review of step 2).
    @discardableResult
    func add(_ batch: [MediaUpload]) -> Bool {
        let new = batch.filter { item in !uploads.contains { $0.id == item.id } }
        guard !new.isEmpty else { return true }
        let before = uploads
        for var upload in new {
            if upload.binding == nil, let zone = photosZone, let me = household.memberID?.rawValue {
                upload.binding = Self.binding(me: me, zone: zone)
            }
            uploads.append(upload)
        }
        guard saveUploads() else {
            uploads = before
            return false
        }
        kick()
        return true
    }

    /// Takes an item off the queue only (its first couldn't be saved), keeping its files.
    func unqueue(_ id: String) {
        unqueue([id])
    }

    /// Takes several items off the queue in one write.
    func unqueue(_ ids: [String]) {
        guard uploads.contains(where: { ids.contains($0.id) }) else { return }
        uploads.removeAll { ids.contains($0.id) }
        saveUploads()
    }

    /// Forgets every item queued for a first whose add was undone, its files with them: also those
    /// a later edit inside the Undo window added (Codex review of step 2).
    func forgetUploads(ofFirst eventID: String) {
        for upload in uploads where upload.eventID == eventID { forget(upload.id) }
    }

    /// The editor made an item's files: kept while the editor is open.
    func holdDraft(_ id: String) {
        drafts.insert(id)
        changed(id)
    }

    // MARK: The export (task T10)

    /// The sizes of the items in iCloud, read once, for the export's space check.
    func byteSizes() -> [String: Int64] { savedIndex.mapValues(\.byteSize) }

    /// For "Export the journal": fetches each item not on this phone yet, one at a time, behind
    /// the feeds (the same gate and stops as every transfer; one stopped for the feeds is tried
    /// again, as is one iCloud asks to wait for, up to `deadline`). The photo run waits meanwhile;
    /// one export's fetch at a time, the one before drained first. This also runs with the app in
    /// the background, under the export's own background task. Returns the IDs not fetched.
    func fetchForExport(_ ids: [String], deadline: ContinuousClock.Instant = .now + .seconds(600),
                        progress: @MainActor (Int) -> Void) async -> Set<String> {
        guard let files else { return Set(ids) }
        // A cancelled export before this one is still unwinding: wait for it (Codex review of T10).
        while exporting {
            if Task.isCancelled { return Set(ids) }
            try? await Task.sleep(for: .milliseconds(100))
        }
        exporting = true
        running?.cancel()
        inFlight?.cancel()
        await running?.value
        defer {
            exporting = false
            kick()
        }
        var missing = Set<String>()
        for (index, id) in ids.enumerated() {
            if Task.isCancelled || ContinuousClock.now >= deadline {
                missing.formUnion(ids[index...].filter { !files.hasFile($0) })
                break
            }
            if !files.hasFile(id), !(await fetchOneForExport(id, files: files, deadline: deadline)) { missing.insert(id) }
            progress(index + 1)
        }
        return missing
    }

    /// A single photo for Share, by the same careful way. True once it is on this phone.
    func fetchForShare(_ id: String) async -> Bool {
        await fetchForExport([id], deadline: .now + .seconds(120)) { _ in }.isEmpty
    }

    private func fetchOneForExport(_ id: String, files: MediaFiles, deadline: ContinuousClock.Instant) async -> Bool {
        // The photo index can lag behind a first (a new phone): the record is asked for by its ID.
        guard let zone = photosZone else { return false }
        if let size = savedIndex[id]?.byteSize, !SpaceRule.fits(size, free: files.freeSpace()) { return false }
        let recordID = CKRecord.ID(recordName: id, zoneID: zone.id)
        let database = zone.database
        var attempts = 0
        while attempts < 8, ContinuousClock.now < deadline, !Task.isCancelled {
            attempts += 1
            let failure: MediaFailure
            do {
                let results = try await transfer(isDownload: true) {
                    try await database.configuredWith(configuration: Self.lowPriority) { database in
                        try await database.records(for: [recordID], desiredKeys: ["file"])
                    }
                }
                switch results[recordID] {
                case .success(let record):
                    guard let file = RecordMapping.fileURL(of: record) else { return false }
                    let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    guard SpaceRule.fits(size, free: files.freeSpace()) else { return false }
                    try await Task.detached { try files.keepFile(from: file, for: id) }.value
                    changed(id)
                    return true
                case .failure(let error):
                    failure = MediaFailure(error)
                case nil:
                    return false
                }
            } catch {
                failure = MediaFailure(error)
            }
            switch failure {
            case .stopped:
                // Stopped for the feeds: tried again once they are done (not counted).
                attempts -= 1
                try? await Task.sleep(for: .seconds(1))
            case .retryLater(let after):
                // iCloud's own wait, when it gives one.
                try? await Task.sleep(for: .seconds(min(max(after ?? 3, 1), 60)))
            default:
                SyncLog.add("media: export couldn't fetch \(id): \(failure)")
                return false
            }
        }
        return false
    }

    /// A first opened from its notice: its photos and videos move to the front of the downloads.
    func preferFirst(_ eventID: String) {
        preferredFirst = eventID
        kick()
    }

    /// The editor saved, or let go of, the item.
    func releaseDraft(_ id: String) { drafts.remove(id) }

    private func changed(_ id: String) { fileVersions[id, default: 0] += 1 }

    /// An item's file or thumbnail was made on this phone (a video's still, then its copy): the
    /// screens show it.
    func noteFileChanged(_ id: String) { changed(id) }

    /// Starts a run unless one is going; a call during a run starts one more after it. Only while
    /// the app is open (a push that wakes it in the background is for the feeds alone), and not
    /// while iCloud has asked to wait.
    func kick() {
        guard AppConfig.photosEnabled, UIApplication.shared.applicationState != .background, !exporting else { return }
        if let backOffUntil, ContinuousClock.now < backOffUntil {
            if retryTask == nil || retryTask?.isCancelled == true { wake(at: backOffUntil) }
            return
        }
        if running != nil {
            runAgain = true
            return
        }
        running = Task { [weak self] in
            guard let self else { return }
            repeat {
                runAgain = false
                await run()
            } while runAgain && !Task.isCancelled && !isBackingOff
            running = nil
            // A kick that came while a stopped run was ending starts a fresh one.
            if runAgain {
                runAgain = false
                kick()
            }
        }
    }

    /// The app left the screen: transfers stop, and start again from the beginning next time.
    /// The run is kept until it has ended, so two never overlap.
    func stop() {
        running?.cancel()
        inFlight?.cancel()
        runAgain = false
        retryTask?.cancel()
        cleanUpTask?.cancel()
    }

    /// A sync engine fetch started or ended (`CKSyncEngine`'s will and did fetch events, and the
    /// whole of `HouseholdSync.fetchNow`). A fetch starting stops a download at once (eng D9).
    func engineFetch(started: Bool) {
        enginesFetching = max(0, enginesFetching + (started ? 1 : -1))
        if started, let inFlight, inFlight.isDownload {
            SyncLog.add("media: download stopped for a fetch")
            inFlight.cancel()
        }
        if !started && enginesFetching == 0 { kick() }
    }

    // MARK: The run

    private func run() async {
        // Only with this launch's own check of the iCloud account, not the one remembered.
        guard household.accountAvailable == true, let zone = photosZone, let me = household.memberID?.rawValue else {
            shareState = .off
            return
        }
        startAgainIfTheAccountChanged(me: me, zone: zone)
        bindUnboundUploads(to: Self.binding(me: me, zone: zone))
        do {
            try await keepShareInStep(zone)
            guard shareState == .ready, let files else { return }
            try await fetchChanges(zone, files: files)
            try await fetchAgainWhatFailed(zone, files: files)
            // Deletions first: they can free space that a waiting upload needs.
            try await cleanUp(zone, files: files, me: me)
            try await sendUploads(zone, files: files, binding: Self.binding(me: me, zone: zone))
            try await downloadFiles(zone, files: files)
            removeFilesNoFirstNeeds(files)
        } catch {
            note(error, zone: zone)
        }
    }

    nonisolated static func binding(me: String, zone: PhotosZone) -> String { "\(me)|\(zone.id.ownerName)" }

    private func bindUnboundUploads(to binding: String) {
        guard uploads.contains(where: { $0.binding == nil }) else { return }
        for index in uploads.indices where uploads[index].binding == nil { uploads[index].binding = binding }
        saveUploads()
    }

    /// The photos zone and the database it is in, from this phone's role.
    private var photosZone: PhotosZone? {
        guard AppConfig.photosEnabled else { return nil }
        switch household.role {
        case .owner:
            return PhotosZone(id: CKRecordZone.ID(zoneName: AppConfig.photosZoneName, ownerName: CKCurrentUserDefaultName),
                              database: household.container.privateCloudDatabase, isOwner: true)
        case .member(let owner):
            return PhotosZone(id: CKRecordZone.ID(zoneName: AppConfig.photosZoneName, ownerName: owner),
                              database: household.container.sharedCloudDatabase, isOwner: false)
        case .notSetUp:
            return nil
        }
    }

    /// What this phone knows of the photos zone belongs to one iCloud account and one household.
    /// Another account or household starts it again; queued items stay for their own account.
    private func startAgainIfTheAccountChanged(me: String, zone: PhotosZone) {
        let key = Self.binding(me: me, zone: zone)
        let saved = defaults.string(forKey: Keys.account)
        guard saved != key else { return }
        if saved != nil { SyncLog.add("media: another iCloud account or household; photos start again") }
        for name in [Keys.index, Keys.token, Keys.zoneMade, Keys.acceptedLink, Keys.leftAt, Keys.refetch] {
            defaults.removeObject(forKey: name)
        }
        tally = nil
        defaults.set(key, forKey: Keys.account)
    }

    // MARK: The photos share (journal plan, "Who creates it"; outside review O4)

    private func keepShareInStep(_ zone: PhotosZone) async throws {
        if shareState == .off { shareState = .settingUp }
        if zone.isOwner {
            try await keepShareInStepAsOwner(zone)
        } else {
            try await acceptShareAsMember()
        }
    }

    /// The owner's phone: the zone, its share, the household's other parents on it and no one
    /// else, and its link in a household setting for the other phone.
    private func keepShareInStepAsOwner(_ zone: PhotosZone) async throws {
        let database = zone.database
        if !defaults.bool(forKey: Keys.zoneMade) {
            let result = try await transfer(isDownload: false) {
                try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zone.id)], deleting: [])
            }
            if case .failure(let error) = result.saveResults[zone.id] { throw error }
            defaults.set(true, forKey: Keys.zoneMade)
            SyncLog.add("media: photos zone made")
        }
        let share = try await photosShare(zone)
        // Only a share that is confirmed missing counts as "no other parent"; any other error
        // stops here, so a passing iCloud hiccup never takes a parent off the photos share.
        let householdShareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare,
                                           zoneID: CKRecordZone.ID(zoneName: HouseholdSync.zoneName, ownerName: CKCurrentUserDefaultName))
        let householdShare: CKShare?
        do {
            householdShare = try await transfer(isDownload: false) { try await database.record(for: householdShareID) } as? CKShare
        } catch where MediaFailure(error) == .missing {
            householdShare = nil
        }
        let owner = share.owner.userIdentity.userRecordID?.recordName ?? CKCurrentUserDefaultName
        let changes = PhotosShareChanges(household: Self.parentIDs(householdShare), photos: Self.parentIDs(share), owner: owner)
        var changed = share.recordChangeTag == nil
        var notFound: [String] = []
        let container = household.container
        for id in changes.add.sorted() {
            do {
                let participant = try await transfer(isDownload: false) {
                    try await container.shareParticipant(forUserRecordID: CKRecord.ID(recordName: id))
                }
                participant.permission = .readWrite
                share.addParticipant(participant)
                changed = true
            } catch where MediaFailure(error) == .stopped {
                throw error
            } catch {
                notFound.append(id)
                SyncLog.add("media: couldn't find the other parent for the photos share: \(String(reflecting: error))")
            }
        }
        removingAccess = !changes.remove.isEmpty
        var leftAt = savedLeftAt
        // A parent back in the household has no leaving date; one leaving gets it before the
        // share is saved, so a lost answer from iCloud can't lose it.
        for id in Self.parentIDs(householdShare) { leftAt[id] = nil }
        for id in changes.remove.sorted() {
            if let participant = share.participants.first(where: { $0.userIdentity.userRecordID?.recordName == id }) {
                share.removeParticipant(participant)
                changed = true
            }
            leftAt[id] = leftAt[id] ?? Date()
        }
        savedLeftAt = leftAt
        var link = share.url
        if changed {
            let toSave = share
            let result = try await transfer(isDownload: false) {
                try await database.modifyRecords(saving: [toSave], deleting: [], savePolicy: .changedKeys)
            }
            switch result.saveResults[share.recordID] {
            case .failure(let error): throw error
            case .success(let saved): link = (saved as? CKShare)?.url ?? link
            case nil: throw CKError(.internalError)
            }
            SyncLog.add("media: photos share saved (added \(changes.add.count - notFound.count), removed \(changes.remove.count))")
        }
        removingAccess = false
        if let url = link?.absoluteString, store.data.photosShareURL != url {
            store.change { $0.setPhotosShareURL(url, now: Date()) }
            SyncLog.add("media: photos share link written for the other phone")
        }
        otherParentWaiting = !notFound.isEmpty
        if otherParentWaiting { later(300) }
        shareState = .ready
    }

    /// The photos zone's one share: fetched if it exists, made if not. Like the household share,
    /// no access by link alone.
    private func photosShare(_ zone: PhotosZone) async throws -> CKShare {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone.id)
        let database = zone.database
        do {
            if let existing = try await transfer(isDownload: false, { try await database.record(for: shareID) }) as? CKShare {
                return existing
            }
        } catch where MediaFailure(error) == .missing {
            // Not made yet.
        }
        let share = CKShare(recordZoneID: zone.id)
        share[CKShare.SystemFieldKey.title] = "Little Log photos"
        share.publicPermission = .none
        return share
    }

    /// The other parent's phone: accepts the link the owner's phone wrote, by itself.
    private func acceptShareAsMember() async throws {
        guard let link = store.data.photosShareURL, let url = URL(string: link) else {
            shareState = .waiting("The other phone hasn't shared photos yet.")
            return
        }
        if defaults.string(forKey: Keys.acceptedLink) != link {
            let container = household.container
            let metadata = try await transfer(isDownload: false) { try await container.shareMetadata(for: url) }
            if metadata.participantStatus != .accepted {
                _ = try await transfer(isDownload: false) { try await container.accept(metadata) }
            }
            defaults.set(link, forKey: Keys.acceptedLink)
            SyncLog.add("media: photos share accepted")
        }
        shareState = .ready
    }

    /// The iCloud user record names of a share's parents other than its owner.
    nonisolated static func parentIDs(_ share: CKShare?) -> Set<String> {
        Set(share?.participants.filter { $0.role != .owner && $0.acceptanceStatus != .removed }
            .compactMap { $0.userIdentity.userRecordID?.recordName } ?? [])
    }

    // MARK: Fetching the zone's changes

    /// What this phone knows of each `Media` record in iCloud, for downloads and the clean-up.
    struct IndexEntry: Codable, Hashable, Sendable {
        var eventID: String
        var creator: String
        var byteSize: Int64
        /// Photo or video, from the record's details; nil from an index saved before 19 Nov 2026.
        var kind: MediaKind?
    }

    /// Whether an item is a photo or a video, when this phone knows: from its queue entry or the
    /// photo index.
    func kind(of id: String) -> MediaKind? {
        if let known = kinds[id] { return known }
        var kind: MediaKind?
        if let upload = uploads.first(where: { $0.id == id }),
           let details = PayloadCoder.decode(MediaDetails.self, from: upload.payload) {
            kind = details.kind
        } else if let indexed = savedIndex[id]?.kind {
            kind = indexed
        } else if let isVideo = files?.isVideoFile(id) {
            kind = isVideo ? .video : .photo
        }
        // Remembered once known, so the screens never read the index or a file again for it.
        if let kind { kinds[id] = kind }
        return kind
    }

    /// Room a page of thumbnails may need: 20 thumbnails of up to a megabyte, copied once.
    private static let thumbnailPageBytes: Int64 = 40_000_000

    private func fetchChanges(_ zone: PhotosZone, files: MediaFiles) async throws {
        var index = savedIndex
        var token = savedToken
        var refetch = savedRefetch
        var moreComing = true
        let database = zone.database
        while moreComing {
            try needSpace(Self.thumbnailPageBytes, files: files)
            let since = token
            let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                          deletions: [CKDatabase.RecordZoneChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool)
            do {
                changes = try await transfer(isDownload: true) {
                    try await database.configuredWith(configuration: Self.lowPriority) { database in
                        try await database.recordZoneChanges(inZoneWith: zone.id, since: since,
                                                             desiredKeys: RecordMapping.mediaThumbnailKeys, resultsLimit: 20)
                    }
                }
            } catch where MediaFailure(error) == .tokenExpired {
                // Everything is fetched again, and the list of what is in iCloud is made afresh.
                SyncLog.add("media: change token expired; fetching the photos zone again")
                token = nil
                index = [:]
                continue
            }
            for (recordID, result) in changes.modificationResultsByID {
                switch result {
                case .success(let modification):
                    if await take(modification.record, into: &index, files: files) {
                        refetch.remove(recordID.recordName)
                    } else {
                        refetch.insert(recordID.recordName)
                    }
                case .failure:
                    refetch.insert(recordID.recordName)
                }
            }
            for deletion in changes.deletions where deletion.recordType == RecordMapping.mediaType {
                index[deletion.recordID.recordName] = nil
                refetch.remove(deletion.recordID.recordName)
            }
            token = changes.changeToken
            moreComing = changes.moreComing
            savedIndex = index
            savedToken = token
            savedRefetch = refetch
        }
    }

    /// Records a page couldn't give, or whose thumbnail couldn't be kept, fetched on their own.
    private func fetchAgainWhatFailed(_ zone: PhotosZone, files: MediaFiles) async throws {
        var refetch = savedRefetch
        guard !refetch.isEmpty else { return }
        var index = savedIndex
        let database = zone.database
        for name in refetch.sorted() {
            try needSpace(Self.thumbnailPageBytes, files: files)
            let recordID = CKRecord.ID(recordName: name, zoneID: zone.id)
            let results = try await transfer(isDownload: true) {
                try await database.configuredWith(configuration: Self.lowPriority) { database in
                    try await database.records(for: [recordID], desiredKeys: RecordMapping.mediaThumbnailKeys)
                }
            }
            switch results[recordID] {
            case .success(let record):
                if await take(record, into: &index, files: files) { refetch.remove(name) }
            case .failure(let error) where MediaFailure(error) == .missing:
                refetch.remove(name)
                index[name] = nil
            case .failure(let error):
                switch MediaFailure(error) {
                case .retryLater, .notSharedYet, .zoneMissing, .stopped: throw error
                default: break
                }
            case nil:
                break
            }
            savedIndex = index
            savedRefetch = refetch
        }
    }

    /// Notes a `Media` record (and keeps its thumbnail) or the tally. False if the thumbnail
    /// couldn't be kept, so the record is fetched again.
    private func take(_ record: CKRecord, into index: inout [String: IndexEntry], files: MediaFiles) async -> Bool {
        if let media = RecordMapping.media(from: record) {
            let kind = PayloadCoder.decode(MediaDetails.self, from: media.payload)?.kind
            index[media.id] = IndexEntry(eventID: media.eventID, creator: record.creatorUserRecordID?.recordName ?? "",
                                         byteSize: media.byteSize, kind: kind)
            // Learnt here: the screens show a play mark at once (Codex review of step 2).
            if let kind, kinds[media.id] != kind {
                kinds[media.id] = kind
                changed(media.id)
            }
            if !files.hasThumbnail(media.id), let thumbnail = RecordMapping.thumbnailURL(of: record) {
                let id = media.id
                do {
                    try await Task.detached { try files.keepThumbnail(from: thumbnail, for: id) }.value
                    changed(id)
                    try Task.checkCancellation()
                } catch {
                    SyncLog.add("media: couldn't keep the thumbnail of \(id): \(String(reflecting: error))")
                    return false
                }
            }
        } else if let payload = RecordMapping.tallyPayload(from: record) {
            tally = PayloadCoder.decode(MediaTally.self, from: payload) ?? tally
        }
        return true
    }

    // MARK: Uploads (eng D11)

    /// Whether a queued item may go now: its first is here, past any Undo (its add, or a held
    /// change), and names it. One taken out is dropped. One whose first isn't here waits, as the
    /// household file may be filling again from iCloud; after a day with the file whole, it was an
    /// add that was undone, and it is dropped.
    /// This is also what keeps a photo safe if the app stops between Save's two writes (task T17):
    /// the queue is written before the first, so a queued photo with no first yet waits, and a
    /// first never names a photo that isn't queued.
    enum Readiness { case ready, wait, drop }

    private func readiness(_ item: MediaUpload, now: Date = Date()) -> Readiness {
        Self.readiness(item, stored: store.data.events[item.eventID], waitingForICloud: store.data.isWaitingForICloud(now: now),
                       now: now)
    }

    nonisolated static func readiness(_ item: MediaUpload, stored: StoredEvent?, waitingForICloud: Bool, now: Date) -> Readiness {
        guard let stored, let first = stored.snapshot.payload?.milestone else {
            let undone = !waitingForICloud && now.timeIntervalSince(item.queuedAt) > 86_400
            return undone ? .drop : .wait
        }
        if let until = stored.uploadNotBefore, until > now { return .wait }
        if first.removedMedia.contains(item.id) { return .drop }
        if first.media.contains(item.id) { return .ready }
        // An edit that never reached the file (the app stopped between Save's two writes): a day
        // later, with the file whole, it isn't coming.
        let stale = !waitingForICloud && now.timeIntervalSince(item.queuedAt) > 86_400
        return stale ? .drop : .wait
    }

    private func sendUploads(_ zone: PhotosZone, files: MediaFiles, binding: String) async throws {
        let limit = store.data.photoAllowance
        for item in uploads where item.pause != .refused && item.binding == binding {
            switch readiness(item) {
            case .wait:
                continue
            case .drop:
                SyncLog.add("media: \(item.id) was taken out of its first; not sent")
                finishUpload(item.id)
                continue
            case .ready:
                break
            }
            guard files.hasFile(item.id), files.hasThumbnail(item.id) else {
                SyncLog.add("media: \(item.id) has no file on this phone; not sent")
                setPause(.refused, for: item.id)
                continue
            }
            do {
                try await upload(item, zone: zone, files: files, limit: limit)
            } catch {
                switch MediaFailure(error) {
                case .retryLater, .stopped:
                    throw error
                case .iCloudFull:
                    setPause(.iCloudFull, for: item.id)
                    throw MediaRunStop()
                case .zoneMissing, .notSharedYet:
                    setPause(.notSharedYet, for: item.id)
                    throw error
                case .clash, .missing, .tokenExpired, .refused:
                    SyncLog.add("media: \(item.id) refused: \(String(reflecting: error))")
                    setPause(.refused, for: item.id)
                }
            }
        }
    }

    /// One item: read the tally, decide, save the record and the tally together; after a clash,
    /// read and decide again (eng D11). Five clashes in a row: try again later, still queued.
    private func upload(_ item: MediaUpload, zone: PhotosZone, files: MediaFiles, limit: Int64) async throws {
        for _ in 0..<5 {
            let (current, systemFields) = try await readTally(zone)
            tally = current
            // Checked again after the wait for the tally: Undo or a removal may have come.
            guard readiness(item) == .ready else { return }
            switch current.decide(adding: item.id, bytes: item.byteSize, limit: limit) {
            case .alreadySaved:
                finishUpload(item.id)
                return
            case .overLimit:
                setPause(.allowanceFull, for: item.id)
                return
            case .save(let next):
                let media = RecordMapping.record(
                    for: RecordMapping.MediaFields(id: item.id, eventID: item.eventID, byteSize: item.byteSize, payload: item.payload),
                    file: files.fileURL(item.id), thumbnail: files.thumbnailURL(item.id), zoneID: zone.id)
                let tallyRecord = RecordMapping.tallyRecord(payload: try PayloadCoder.encode(next), systemFields: systemFields,
                                                            zoneID: zone.id)
                do {
                    try await saveTogether([media, tallyRecord], deleting: [], in: zone.database)
                    tally = next
                    finishUpload(item.id)
                    SyncLog.add("media: sent \(item.id)")
                    return
                } catch where [.clash, .missing].contains(MediaFailure(error)) {
                    continue
                }
            }
        }
        throw CKError(.zoneBusy)
    }

    /// The tally and its version tag, or an empty one if it isn't made yet. A tally that can't be
    /// read is never saved over (`UnreadableTally`).
    private func readTally(_ zone: PhotosZone) async throws -> (MediaTally, Data?) {
        let id = CKRecord.ID(recordName: RecordMapping.mediaTallyName, zoneID: zone.id)
        let database = zone.database
        let results = try await transfer(isDownload: false) {
            try await database.configuredWith(configuration: Self.lowPriority) { database in
                try await database.records(for: [id], desiredKeys: ["payload"])
            }
        }
        switch results[id] {
        case .success(let record):
            guard let payload = RecordMapping.tallyPayload(from: record),
                  let tally = PayloadCoder.decode(MediaTally.self, from: payload) else { throw UnreadableTally() }
            return (tally, RecordMapping.systemFields(of: record))
        case .failure(let error) where MediaFailure(error) == .missing:
            return (MediaTally(), nil)
        case .failure(let error):
            throw error
        case nil:
            throw CKError(.internalError)
        }
    }

    /// One all-or-nothing save in the photos zone, only over versions unchanged since read. Every
    /// record must come back saved, and every deletion done.
    private func saveTogether(_ records: [CKRecord], deleting: [CKRecord.ID], in database: CKDatabase) async throws {
        let result = try await transfer(isDownload: false) {
            try await database.configuredWith(configuration: Self.lowPriority) { database in
                try await database.modifyRecords(saving: records, deleting: deleting, savePolicy: .ifServerRecordUnchanged,
                                                 atomically: true)
            }
        }
        for record in records {
            switch result.saveResults[record.recordID] {
            case .success: continue
            case .failure(let error): throw error
            case nil: throw CKError(.internalError)
            }
        }
        for id in deleting {
            switch result.deleteResults[id] {
            case .success: continue
            case .failure(let error): throw error
            case nil: throw CKError(.internalError)
            }
        }
    }

    private func finishUpload(_ id: String) {
        uploads.removeAll { $0.id == id }
        saveUploads()
    }

    private func setPause(_ pause: MediaPause, for id: String) {
        guard let index = uploads.firstIndex(where: { $0.id == id }), uploads[index].pause != pause else { return }
        uploads[index].pause = pause
        saveUploads()
    }

    // MARK: Downloads (eng D7, D9; CEO review D19)

    private func downloadFiles(_ zone: PhotosZone, files: MediaFiles) async throws {
        let index = savedIndex
        let database = zone.database
        var tried = Set<String>()
        // Chosen again before each one, so a first opened from its notice meanwhile comes next
        // (design review D18); feeds are still first, as no transfer runs while the household's
        // sync has work.
        while let id = nextDownload(index: index, files: files, excluding: tried) {
            tried.insert(id)
            guard let entry = index[id] else { continue }
            try needSpace(entry.byteSize, files: files)
            let recordID = CKRecord.ID(recordName: id, zoneID: zone.id)
            let results = try await transfer(isDownload: true) {
                try await database.configuredWith(configuration: Self.lowPriority) { database in
                    try await database.records(for: [recordID], desiredKeys: ["file"])
                }
            }
            switch results[recordID] {
            case .success(let record):
                guard let file = RecordMapping.fileURL(of: record) else {
                    SyncLog.add("media: \(id) came without its file")
                    continue
                }
                try await Task.detached { try files.keepFile(from: file, for: id) }.value
                changed(id)
                try Task.checkCancellation()
                SyncLog.add("media: fetched \(id)")
            case .failure(let error):
                switch MediaFailure(error) {
                case .missing: SyncLog.add("media: \(id) isn't in iCloud yet") // the other phone hasn't sent it (O5)
                case .retryLater, .stopped, .zoneMissing, .notSharedYet: throw error
                default: SyncLog.add("media: couldn't fetch \(id): \(String(reflecting: error))")
                }
            case nil:
                continue
            }
        }
    }

    /// The next full file to fetch: a first opened from its notice first, then in ID order.
    private func nextDownload(index: [String: IndexEntry], files: MediaFiles, excluding tried: Set<String>) -> String? {
        let front = Set(preferredFirst.flatMap { store.data.events[$0]?.snapshot.payload?.milestone?.media } ?? [])
        return store.data.mediaInUse
            .filter { !tried.contains($0) && !files.hasFile($0) && index[$0] != nil }
            .min { (front.contains($0) ? 0 : 1, $0) < (front.contains($1) ? 0 : 1, $1) }
    }

    /// Stops the run when keeping `bytes` more would eat into the space kept free for feeds (D19).
    private func needSpace(_ bytes: Int64, files: MediaFiles) throws {
        guard SpaceRule.fits(bytes, free: files.freeSpace()) else {
            SyncLog.add("media: not enough space on this iPhone; photos wait")
            throw MediaRunStop()
        }
    }

    // MARK: The clean-up (journal plan, "Record shape"; eng D10, D11)

    private func cleanUp(_ zone: PhotosZone, files: MediaFiles, me: String) async throws {
        var index = savedIndex
        var earliest: Date?
        func decision(_ id: String, _ entry: IndexEntry) -> CleanUpDecision {
            // In the owner's own database, the owner's records name their maker as the current user.
            let creator = entry.creator == CKCurrentUserDefaultName ? me : entry.creator
            return MediaCleanUp.decide(MediaRecordFacts(id: id, eventID: entry.eventID, creator: creator),
                                       first: store.data.events[entry.eventID], me: me, isOwner: zone.isOwner,
                                       leftAt: savedLeftAt, now: Date())
        }
        for (id, entry) in index.sorted(by: { $0.key < $1.key }) {
            switch decision(id, entry) {
            case .waitUntil(let date):
                earliest = min(earliest ?? date, date)
                continue
            case .delete:
                break
            case .keep, .notThisPhone:
                continue
            }
            let recordID = CKRecord.ID(recordName: id, zoneID: zone.id)
            var done = false
            for _ in 0..<5 where !done {
                let (current, systemFields) = try await readTally(zone)
                // Checked again after the wait for the tally: Undo or a restore may have come.
                guard decision(id, entry) == .delete else { break }
                let tallyRecord = RecordMapping.tallyRecord(payload: try PayloadCoder.encode(current.removing(id)),
                                                            systemFields: systemFields, zoneID: zone.id)
                do {
                    try await saveTogether([tallyRecord], deleting: [recordID], in: zone.database)
                } catch where MediaFailure(error) == .clash {
                    continue
                } catch where MediaFailure(error) == .missing {
                    // The record is already gone: take its entry off the tally on its own.
                    try await saveTogether([tallyRecord], deleting: [], in: zone.database)
                }
                tally = current.removing(id)
                index[id] = nil
                savedIndex = index
                files.remove(id)
                SyncLog.add("media: deleted \(id) for good")
                done = true
            }
            // Still due after five clashes in a row: asked again in a minute.
            if !done, decision(id, entry) == .delete { earliest = min(earliest ?? Date(), Date().addingTimeInterval(60)) }
        }
        if let earliest {
            // Ask again when the first removal's wait is over.
            later(earliest.timeIntervalSinceNow)
        }
    }

    /// This phone's files that no first needs: not named by a live first or an Undo, not waiting
    /// to go, and either gone from iCloud or on their first's removed list. An item that arrived
    /// before its first is kept.
    private func removeFilesNoFirstNeeds(_ files: MediaFiles) {
        let inUse = store.data.mediaInUse
        let queued = Set(uploads.map(\.id)).union(drafts)
        let index = savedIndex
        for id in files.storedIDs() where !inUse.contains(id) && !queued.contains(id) {
            guard let entry = index[id] else {
                files.remove(id)
                continue
            }
            if store.data.events[entry.eventID]?.snapshot.payload?.milestone?.removedMedia.contains(id) == true {
                files.remove(id)
            }
        }
    }

    // MARK: Feeds first (eng D3, D9)

    /// The gate as things stand now. The wait of an entry is measured on a clock that setting the
    /// time can't move.
    private var gate: TransferGate {
        let clock = ContinuousClock()
        if household.hasEntriesWaitingToSend {
            if entriesWaitingSince == nil { entriesWaitingSince = clock.now }
        } else {
            entriesWaitingSince = nil
        }
        let waited = entriesWaitingSince.map { since -> TimeInterval in
            let elapsed = clock.now - since
            return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        }
        return TransferGate(engineFetchRunning: enginesFetching > 0, entryWaitingFor: waited)
    }

    /// Runs one iCloud request: only if the gate lets it start, checked again just before it is
    /// sent, and stopped when the gate says so. A stopped request ends the run (`MediaRunStop`).
    private func transfer<T: Sendable>(isDownload: Bool, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        guard !Task.isCancelled, gate.mayStart else { throw MediaRunStop() }
        let flag = StopFlag()
        let task = Task { [weak self] in
            guard let self, self.gate.mayStart else { throw MediaRunStop() }
            return try await work()
        }
        let handle = UUID()
        inFlight = (handle, isDownload, {
            flag.stopped = true
            task.cancel()
        })
        let watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                if self.gate.stopsTransferInFlight(isDownload: isDownload) {
                    SyncLog.add("media: transfer stopped for the feeds")
                    flag.stopped = true
                    task.cancel()
                    return
                }
            }
        }
        defer {
            watcher.cancel()
            // Only this transfer's own handle: another may have started meanwhile (Codex review of T10).
            if inFlight?.id == handle { inFlight = nil }
        }
        let value: T
        do {
            value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch where MediaFailure(error) == .stopped {
            throw MediaRunStop()
        }
        // An answer that came after the stop is not used: the run starts again from the beginning.
        if flag.stopped || Task.isCancelled { throw MediaRunStop() }
        return value
    }

    private static var lowPriority: CKOperation.Configuration {
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .utility
        return configuration
    }

    /// iCloud asked to wait: no run starts before then, whatever asks for one.
    private func retry(after seconds: TimeInterval?) {
        let until = ContinuousClock.now + .seconds(max(seconds ?? 30, 5))
        backOffUntil = until
        wake(at: until)
    }

    private var isBackingOff: Bool { backOffUntil.map { ContinuousClock.now < $0 } ?? false }

    /// A run starts at `instant` (just after it, so the wait is over).
    private func wake(at instant: ContinuousClock.Instant) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(until: instant + .milliseconds(100), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.retryTask = nil
            self?.kick()
        }
    }

    /// Asks for a run after `seconds`, without the back-off: for work that is due later.
    private func later(_ seconds: TimeInterval) {
        cleanUpTask?.cancel()
        cleanUpTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(seconds, 5)))
            guard !Task.isCancelled else { return }
            self?.kick()
        }
    }

    private func note(_ error: any Error, zone: PhotosZone) {
        let failure = MediaFailure(error)
        if failure != .stopped { SyncLog.add("media: run stopped: \(String(reflecting: error))") }
        switch failure {
        case .retryLater(let after):
            retry(after: after)
        case .stopped:
            break
        case .notSharedYet, .zoneMissing:
            // The owner makes the zone again; the other phone accepts the link again, as a share
            // made again keeps its link.
            if zone.isOwner {
                defaults.set(false, forKey: Keys.zoneMade)
            } else {
                defaults.removeObject(forKey: Keys.acceptedLink)
            }
            tally = nil
            shareState = .waiting("Photos sharing isn't ready on this phone yet.")
            retry(after: 300)
        case .iCloudFull:
            shareState = .waiting("The iCloud storage of the parent who shares the household is full.")
        default:
            shareState = .waiting("Photos sharing isn't working: \(error.localizedDescription)")
        }
    }

    // MARK: Saved between launches

    private enum Keys {
        static let uploads = "mediaUploads"
        static let index = "mediaIndex"
        static let token = "photosZoneToken"
        static let zoneMade = "photosZoneMade"
        static let acceptedLink = "photosShareAccepted"
        static let leftAt = "photosLeftAt"
        static let refetch = "mediaRefetch"
        static let account = "mediaAccount"
    }

    @discardableResult
    private func saveUploads() -> Bool {
        guard let encoded = try? JSONEncoder().encode(uploads) else { return false }
        guard let queueFile else {
            defaults.set(encoded, forKey: Keys.uploads)
            return true
        }
        do {
            try encoded.write(to: queueFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            SyncLog.add("media: couldn't save the queue: \(type(of: error))")
            return false
        }
        if defaults.object(forKey: Keys.uploads) != nil { defaults.removeObject(forKey: Keys.uploads) }
        return true
    }

    private var savedIndex: [String: IndexEntry] {
        get { defaults.data(forKey: Keys.index).flatMap { try? JSONDecoder().decode([String: IndexEntry].self, from: $0) } ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.index) }
    }

    private var savedRefetch: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.refetch) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Keys.refetch) }
    }

    private var savedToken: CKServerChangeToken? {
        get {
            defaults.data(forKey: Keys.token).flatMap {
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
            }
        }
        set {
            defaults.set(newValue.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) },
                         forKey: Keys.token)
        }
    }

    /// When each parent who left the household was removed from the photos share, by iCloud user
    /// record name (owner's phone only): their removed items are deleted 30 days after.
    private var savedLeftAt: [String: Date] {
        get { defaults.data(forKey: Keys.leftAt).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.leftAt) }
    }
}
