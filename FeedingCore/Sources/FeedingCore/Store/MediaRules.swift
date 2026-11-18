import Foundation

// The rules for the firsts' photos and videos (`docs/planning/07-milestones-journal.md`), with no
// CloudKit or file types, so they are tested on Linux too. `MediaSync` and `MediaStore` in the app
// ask these rules and do what they say.
//
//   UPLOAD (eng D3, D9, D11)
//   item saved on phone ──> an entry waiting to send, or an engine fetch running? ──yes──> wait
//         │no                                   (`TransferGate.mayStart`)
//         ▼
//   one all-or-nothing save: Media record + tally entry (`MediaTally.decide`)
//         │ tally changed since read ──> read it again, decide again (the limit is checked again)
//         │ over the limit ──> pause: the item stays on this phone
//         ▼
//   saved
//
//   IN FLIGHT, UPLOAD OR DOWNLOAD (`TransferGate.stopsTransferInFlight`)
//   an entry has waited 5 s to send ──> stop the transfer; send it again from the start later
//   an engine fetch starts (push, opening, joining) ──> stop a download; start it again after

// MARK: - The household photo allowance (CEO review D14, D20; eng D2, D11)

extension SettingKey {
    /// The household photo allowance, in bytes. One shared setting; either parent can raise it.
    public static let photoAllowance = "photoAllowance"
}

extension HouseholdData {
    /// The allowance a household starts with (D14): 1 GB, as iPhone counts storage.
    public static let defaultPhotoAllowance: Int64 = 1_000_000_000

    public var photoAllowance: Int64 {
        setting(Int64.self, SettingKey.photoAllowance) ?? Self.defaultPhotoAllowance
    }

    /// Saves a new allowance. Nothing below 1 byte.
    public mutating func setPhotoAllowance(_ bytes: Int64, now: Date) {
        guard bytes > 0, bytes != photoAllowance else { return }
        putSetting(bytes, key: SettingKey.photoAllowance, now: now)
    }

    /// The photos and videos the live firsts name: the ones to keep, download and export. A
    /// removed item, or one of a deleted first, is not among them.
    public var mediaInUse: Set<String> {
        Set(snapshots.lazy.filter { $0.event.kind == .milestone && $0.event.deletedAt == nil }
            .flatMap { $0.payload?.milestone?.media ?? [] })
    }
}

/// How full the allowance is. The words come from the app.
public enum AllowanceLevel: Hashable, Sendable {
    case fine
    /// 80% or more used: both phones say so.
    case nearlyFull
    /// All used: new uploads pause, and the firsts' words still sync.
    case full

    public init(used: Int64, limit: Int64) {
        if used >= limit {
            self = .full
        } else if used * 5 >= limit * 4 {
            self = .nearlyFull
        } else {
            self = .fine
        }
    }
}

/// The tally record in the photos zone (`MediaTally` in `schema.ckdb`): each item's size, by
/// media ID; the bytes used are their sum. An item's entry is saved in the same all-or-nothing
/// save as its `Media` record, and only if nobody changed the tally since it was read (eng D11),
/// so the count always matches the records and the limit holds when both phones upload at once.
public struct MediaTally: VersionedPayload, Hashable {
    public static let currentVersion = 1

    public var v: Int
    /// Bytes, by media ID.
    public var items: [String: Int64]

    public init(items: [String: Int64] = [:]) {
        v = Self.currentVersion
        self.items = items
    }

    public var bytesUsed: Int64 { items.values.reduce(0, +) }

    /// The tally's largest encoded size, so its record stays under iCloud's 1 MB with room to
    /// spare (about 50 bytes an item: about 18,000 items). Past it, uploads pause as if the
    /// allowance were full.
    public static let mostBytes = 900_000

    /// What to do with an item about to be saved, against the tally as just read.
    public enum Decision: Hashable, Sendable {
        /// Save the `Media` record together with this tally, only if the tally is unchanged.
        case save(MediaTally)
        /// The tally already lists the item: an earlier save went through (its answer was lost).
        case alreadySaved
        /// It doesn't fit under the limit: pause, and keep the item on this phone.
        case overLimit
    }

    /// The decision for item `id` of `bytes` under `limit`. After a clash, read the tally again
    /// and decide again, so the limit is checked against what the other phone saved meanwhile.
    public func decide(adding id: String, bytes: Int64, limit: Int64) -> Decision {
        if items[id] != nil { return .alreadySaved }
        guard bytesUsed + bytes <= limit else { return .overLimit }
        var next = self
        next.items[id] = bytes
        guard let encoded = try? PayloadCoder.encode(next), encoded.count <= Self.mostBytes else { return .overLimit }
        return .save(next)
    }

    /// The tally without item `id`, saved in the same all-or-nothing save as the deletion of its
    /// `Media` record.
    public func removing(_ id: String) -> MediaTally {
        var next = self
        next.items[id] = nil
        return next
    }
}

// MARK: - Space kept free for feeds (CEO review D19, outside voice OE8)

public enum SpaceRule {
    /// Free space always kept, so feeds can still be saved: the plan's 500 MB, in bytes as iPhone
    /// counts them.
    public static let reserveBytes: Int64 = 500_000_000

    /// True when `needed` bytes can be written and the reserve still kept. Below it, the app says
    /// "Not enough space on this iPhone" and waits.
    public static func fits(_ needed: Int64, free: Int64) -> Bool {
        free - needed >= reserveBytes
    }

    /// An export's check: the items it still has to download and the packed file, with the
    /// reserve kept. Its folder is made of copies that share storage with the originals
    /// (clones), so it adds almost nothing.
    public static func exportFits(toDownload: Int64, packedFile: Int64, free: Int64) -> Bool {
        fits(toDownload + packedFile, free: free)
    }
}

// MARK: - Feeds first (eng D3, D9)

/// Whether a photo or video transfer may start, or must stop, at a moment. See the diagram at
/// the top of this file.
public struct TransferGate: Hashable, Sendable {
    /// How long an entry may wait to send behind a transfer in flight.
    public static let longestWaitBehindATransfer: TimeInterval = 5

    /// A sync engine fetch is running (after a push, on opening, or on joining).
    public var engineFetchRunning: Bool
    /// How long the entry that has waited longest to send has been ready to go (past its Undo
    /// window), measured on a clock that setting the time can't move (the phone's time since it
    /// started); nil when nothing waits.
    public var entryWaitingFor: TimeInterval?

    public init(engineFetchRunning: Bool, entryWaitingFor: TimeInterval?) {
        self.engineFetchRunning = engineFetchRunning
        self.entryWaitingFor = entryWaitingFor
    }

    /// A transfer, up or down, starts only while nothing waits to send and no fetch runs: photos
    /// never go ahead of entries.
    public var mayStart: Bool { !engineFetchRunning && entryWaitingFor == nil }

    /// True when the transfer in flight must stop now, to start again from the beginning later:
    /// an entry has waited 5 seconds to send, or (for a download) an engine fetch has started.
    public func stopsTransferInFlight(isDownload: Bool) -> Bool {
        if isDownload && engineFetchRunning { return true }
        guard let waited = entryWaitingFor else { return false }
        return waited >= Self.longestWaitBehindATransfer
    }
}

// MARK: - The clean-up (journal plan, "Record shape"; eng D10)

/// A `Media` record as the clean-up sees it.
public struct MediaRecordFacts: Hashable, Sendable {
    public var id: String
    /// The first it belongs to.
    public var eventID: String
    /// The iCloud user record name of the parent whose account saved it.
    public var creator: String

    public init(id: String, eventID: String, creator: String) {
        self.id = id
        self.eventID = eventID
        self.creator = creator
    }
}

public enum CleanUpDecision: Hashable, Sendable {
    /// Not removed, or its first isn't known here yet: keep it.
    case keep
    /// Removed, but another phone deletes it: the phone of the parent who saved it.
    case notThisPhone
    /// Removed; ask again at this time, then check once more just before deleting.
    case waitUntil(Date)
    /// Delete the record and its tally entry, in one all-or-nothing save.
    case delete
}

public enum MediaCleanUp {
    /// After a removal reaches this phone, how long before its item is deleted for good: the
    /// 10-second Undo window plus one minute.
    public static let delayAfterRemoval: TimeInterval = HouseholdData.undoWindow + 60
    /// How long the owner's phone waits before deleting the removed items of a parent who left.
    public static let delayAfterLeaving: TimeInterval = 30 * 24 * 3600

    /// Whether this phone deletes `item` now. Only an item on its first's removed list is ever
    /// deleted (a first's delete puts all its items there), so an item that arrives before its
    /// first is never treated as unused; and only once iCloud has that removal, so this phone's
    /// own removal can't be deleted while Undo can still take it back, whatever the clock says.
    /// The parent who saved it deletes it; if that parent has left the household (`leftAt`, by
    /// iCloud user record name), the owner's phone does, 30 days after they left.
    public static func decide(_ item: MediaRecordFacts, first stored: StoredEvent?, me: String, isOwner: Bool,
                              leftAt: [String: Date], now: Date) -> CleanUpDecision {
        guard let stored, !stored.changedFields.contains(.removedMedia) else { return .keep }
        let first = stored.snapshot
        guard first.event.kind == .milestone, let details = first.payload?.milestone,
              details.removedMedia.contains(item.id) else { return .keep }
        var deleteAfter = (first.payload?.stamp(.removedMedia)?.at ?? first.event.modifiedAt).addingTimeInterval(delayAfterRemoval)
        if item.creator != me {
            guard isOwner, let left = leftAt[item.creator] else { return .notThisPhone }
            deleteAfter = max(deleteAfter, left.addingTimeInterval(delayAfterLeaving))
        }
        return now >= deleteAfter ? .delete : .waitUntil(deleteAfter)
    }
}

// MARK: - The photos share's members (outside review O4, outside voice OE7)

/// What the owner's phone changes on the photos share so it has exactly the household share's
/// parents. Run on each launch and sync, and when the invite sheet says the share changed; a
/// change that didn't finish shows up again the next time.
public struct PhotosShareChanges: Hashable, Sendable {
    public var add: Set<String>
    public var remove: Set<String>

    /// By iCloud user record name. The owner is never added or removed.
    public init(household: Set<String>, photos: Set<String>, owner: String) {
        add = household.subtracting(photos).subtracting([owner])
        remove = photos.subtracting(household).subtracting([owner])
    }

    public var isEmpty: Bool { add.isEmpty && remove.isEmpty }
}

// MARK: - Telling the other phone of a new first (X1, D8; design review D19)

/// How a new first logged on the other phone is shown. Never an alarm, never time-sensitive,
/// never with sound.
public enum NewFirstNotice: Hashable, Sendable {
    /// By day: shown as it arrives (iOS's `.active` level), with no sound.
    case shown
    /// In the night hours: straight to the list, without lighting the screen (`.passive`).
    case listOnly
}

public enum NewFirstRule {
    /// Only a first iCloud saved in the last 24 hours.
    public static let newFor: TimeInterval = 24 * 3600
    /// How far this phone's clock may be behind iCloud's for a first to still count as new. A
    /// clock set back further makes every first look new, so none is shown.
    public static let slowClockAllowance: TimeInterval = 10 * 60

    /// The notice for `first`, or nil for none. Only a first this phone didn't hold before, from
    /// the other parent, not deleted, saved by iCloud (`serverCreatedAt`, not anyone's clock or the
    /// first's own date) in the last 24 hours, and not fetched in the first fetch after setting up
    /// or reinstalling. Not for edits, Undo or restores: those change a first the phone held.
    public static func notice(for first: Event, heldBefore: Bool, isInitialFetch: Bool, me: MemberID,
                              wanted: Bool, dayHours: DayHours, timeZone: TimeZone, now: Date) -> NewFirstNotice? {
        guard wanted, first.kind == .milestone, !heldBefore, !isInitialFetch, first.loggedBy != me,
              first.deletedAt == nil, let saved = first.serverCreatedAt,
              (-slowClockAllowance..<newFor).contains(now.timeIntervalSince(saved)) else { return nil }
        if case .night = dayHours.period(at: now, in: timeZone) { return .listOnly }
        return .shown
    }
}
