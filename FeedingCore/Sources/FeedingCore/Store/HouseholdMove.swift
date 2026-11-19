import Foundation

// The move from Feeding Dev to Feeding, the real app (docs/planning/08-going-live.md, G2): Feeding
// Dev writes the household into one file (`MoveFile`), and the real app on the same phone reads it
// in. The two apps keep their data in different iCloud containers, where each parent has a
// different ID, so every parent's ID is matched on the way in: the parent whose Feeding Dev made the
// file becomes the parent bringing it in, and the other parent becomes the other member of the real
// household, who must have joined it first. Each parent picks their own alarm choices again in the
// real app; those stay on each phone and never move.

/// What the move carries, apart from the photo and video files themselves.
public struct HouseholdMove: Codable, Sendable, Hashable {
    /// A newer build's file is refused, never half read.
    public static let currentVersion = 1

    public var v: Int
    public var madeAt: Date
    /// The parent whose Feeding Dev made the file.
    public var madeBy: MemberID
    /// The baby whose entries move: Feeding Dev's current baby.
    public var babyID: String
    /// Every entry of that baby that isn't deleted.
    public var events: [Event]
    /// The baby, the parents, and the household settings that move.
    public var plainRecords: [PlainRecord]
    /// The photos and videos the file carries, and where each sits in it (`MoveFile`).
    public var media: [MovedMedia]

    public init(madeAt: Date, madeBy: MemberID, babyID: String, events: [Event], plainRecords: [PlainRecord],
                media: [MovedMedia] = []) {
        v = Self.currentVersion
        self.madeAt = madeAt
        self.madeBy = madeBy
        self.babyID = babyID
        self.events = events
        self.plainRecords = plainRecords
        self.media = media
    }

    /// The Setting records that move. The rest stay behind: a pending change, an acknowledgement,
    /// an ask for a night and its answer belong to Feeding Dev's own sync, and the photos share's
    /// link to its own iCloud container. A night taken stays behind too (Codex review of the
    /// move): it could take this phone off duty before the other phone has it; the parents take
    /// the night again in Feeding, which only adds alerting.
    static func moves(settingKey key: String) -> Bool {
        [SettingKey.feedWindow, SettingKey.dayHours, SettingKey.timeZone, SettingKey.rota, SettingKey.medicines,
         SettingKey.photoAllowance].contains(key) || key.hasPrefix("distinct-")
    }

    /// The entries that move: those of the file's baby, never another's.
    public var entries: [Event] { events.filter { $0.babyID == babyID } }

    /// The entries by kind, for the screen that asks before they come in.
    public var counts: [EventKind: Int] {
        entries.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }

    /// The moving firsts, oldest first, with their details.
    private var firsts: [(event: Event, details: MilestoneDetails)] {
        entries.filter { $0.kind == .milestone }.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
            .compactMap { event in PayloadCoder.decode(EventPayload.self, from: event.payload)?.milestone.map { (event, $0) } }
    }

    /// Each photo or video, with the one first that shows it: the oldest, should two name it.
    public var mediaOwners: [String: String] {
        var owners: [String: String] = [:]
        for (event, details) in firsts {
            for id in details.media where owners[id] == nil { owners[id] = event.id }
        }
        return owners
    }

    /// Every photo and video the moving firsts show, in the firsts' order.
    public var mediaIDs: [String] {
        var seen = Set<String>()
        return firsts.flatMap(\.details.media).filter { seen.insert($0).inserted }
    }

    /// The parents' names in Feeding Dev, by their Feeding Dev IDs.
    public var names: [MemberID: String] {
        var names: [MemberID: String] = [:]
        for record in plainRecords where record.type == .member {
            names[MemberID(rawValue: record.name)] = PayloadCoder.decode(MemberPayload.self, from: record.payload)?.displayName
        }
        return names
    }

    /// The Feeding Dev IDs, other than the maker's, that an entry or a setting names. Each needs
    /// the other parent in the real household.
    public var otherParents: Set<MemberID> {
        var ids = Set<MemberID>()
        for event in entries {
            ids.insert(event.loggedBy)
            if let stamps = PayloadCoder.decode(EventPayload.self, from: event.payload)?.stamps {
                ids.formUnion(stamps.values.map(\.by))
            }
        }
        for record in plainRecords where record.type == .member { ids.insert(MemberID(rawValue: record.name)) }
        let settings = settingsOnly
        if let rota = settings.rota { ids.formUnion([rota.firstOnDuty, rota.secondOnDuty]) }
        ids.formUnion(settings.distinctFeeds.map(\.by))
        ids.remove(madeBy)
        return ids
    }

    /// True when an entry's details can't be read by this build: a newer one wrote them, or they
    /// are damaged. Such a file is refused whole, so nothing comes in half understood.
    public var hasUnreadableEntries: Bool {
        entries.contains { $0.payload != nil && PayloadCoder.decode(EventPayload.self, from: $0.payload) == nil }
    }

    /// The moving records in a household of their own, to read them with the usual rules.
    var settingsOnly: HouseholdData {
        var data = HouseholdData()
        for record in plainRecords { data.put(record) }
        return data
    }
}

/// One photo or video in the move file: its file and its thumbnail, as places in the file.
public struct MovedMedia: Codable, Sendable, Hashable {
    public var id: String
    public var file: ByteRange
    public var thumbnail: ByteRange

    public init(id: String, file: ByteRange, thumbnail: ByteRange) {
        self.id = id
        self.file = file
        self.thumbnail = thumbnail
    }
}

/// A run of bytes in the move file, counted from the end of its list of contents.
public struct ByteRange: Codable, Sendable, Hashable {
    public var offset: Int64
    public var length: Int64

    public init(offset: Int64, length: Int64) {
        self.offset = offset
        self.length = length
    }
}

/// Why the move can't come in (yet).
public enum MoveProblem: Error, Hashable, Sendable {
    /// The real app isn't set up: no household, no baby, or this parent isn't known yet.
    case notSetUp
    /// Entries by the other parent are in the file, and they haven't joined the real household.
    case otherParentMissing
    /// The file names the other parent as its maker: it was made on their phone (by the names the
    /// parents gave in each app). Brought in here, each parent's entries would become the other's.
    case madeOnOtherPhone
    /// The file names more than two parents, so whose entries become whose isn't clear.
    case unclearParents
    /// An entry's details can't be read by this build (`hasUnreadableEntries`).
    case unreadableEntries
}

/// What the move brought in.
public struct MoveOutcome: Hashable, Sendable {
    /// New entries, by kind.
    public var added: [EventKind: Int] = [:]
    /// Entries already here, from an earlier move: left as they are.
    public var alreadyHere = 0
    /// Firsts already here that got photos or videos an earlier move couldn't bring.
    public var firstsCompleted = 0
    /// False when an earlier move already brought the settings: they are never brought twice, so
    /// a change made in Feeding since then stays.
    public var settingsBrought = false

    public var addedCount: Int { added.values.reduce(0, +) }
}

/// The note that a move's settings came in, so a later move never brings them again.
public struct MoveReceipt: Hashable, Sendable, Codable {
    public var madeAt: Date
    public var broughtAt: Date
    public var by: MemberID
}

extension SettingKey {
    public static let moveReceipt = "moveReceipt"
}

extension DistinctFeeds {
    func mapped(_ map: (MemberID) -> MemberID) -> DistinctFeeds {
        var copy = self
        copy.by = map(by)
        return copy
    }
}

extension FeedWindowSettings {
    /// Within the limits Settings offers, and opening before it closes: anything else in a file is
    /// left out, not saved where Settings and the alerts would meet it.
    var isSensible: Bool {
        (3600...(5 * 3600)).contains(opensAfter) && ((2 * 3600)...(6 * 3600)).contains(closesAfter)
            && ((10 * 60)...(60 * 60)).contains(backupAfterClose) && opensAfter < closesAfter
    }
}

extension HouseholdData {
    // MARK: Making the move (Feeding Dev)

    /// The move for `babyID`, made by `member`: every entry of that baby that isn't deleted, the
    /// baby, the parents and the settings that move (`HouseholdMove.moves(settingKey:)`). The
    /// photos and videos are added as `MoveFile` writes them.
    public func move(babyID: String, by member: MemberID, now: Date) -> HouseholdMove {
        let events = allEvents.filter { $0.babyID == babyID && $0.deletedAt == nil }
            .sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
        let records = plainRecords.values.map(\.record).filter { record in
            switch record.type {
            case .baby: return record.name == babyID
            case .member: return true
            case .setting: return HouseholdMove.moves(settingKey: record.name)
            }
        }
        .sorted { $0.key < $1.key }
        return HouseholdMove(madeAt: now, madeBy: member, babyID: babyID, events: events, plainRecords: records)
    }

    /// The other member of this household, seen from `me`: the first other Member record.
    public func otherMember(than me: MemberID) -> MemberID? {
        plainRecords(of: .member).map { MemberID(rawValue: $0.name) }.first { $0 != me }
    }

    private func displayName(_ member: MemberID?) -> String? {
        member.flatMap { PayloadCoder.decode(MemberPayload.self, from: plainRecord(.member, $0.rawValue)?.payload)?.displayName }
    }

    // MARK: Bringing it in (Feeding)

    /// Checks that `move` can come in now: the real app is set up, the file is readable and names
    /// at most the two parents, it wasn't made on the other parent's phone, and the other parent
    /// has joined when the file names them.
    public func moveProblem(_ move: HouseholdMove, me: MemberID?) -> MoveProblem? {
        guard let me, currentBaby != nil, plainRecord(.member, me.rawValue) != nil else { return .notSetUp }
        if move.hasUnreadableEntries { return .unreadableEntries }
        let others = move.otherParents
        if others.count > 1 { return .unclearParents }
        let simple = { (name: String?) in name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let maker = simple(move.names[move.madeBy])
        let other = otherMember(than: me)
        if let maker, !maker.isEmpty, maker == simple(displayName(other)), maker != simple(displayName(me)) {
            return .madeOnOtherPhone
        }
        if !others.isEmpty, other == nil { return .otherParentMissing }
        return nil
    }

    /// Brings `move` in, on the phone of `me`, the parent whose Feeding Dev made it. Each entry
    /// comes in as new, to be sent to iCloud, with every parent's ID matched and this household's
    /// baby. An entry already here (an earlier move) is left as it is, except that a first gets the
    /// photos and videos an earlier move couldn't bring. A first keeps only the photos and videos
    /// in `carried` (those whose files are here now) that it is the owner of (`mediaOwners`).
    ///
    /// The first move also brings the baby's name and birth date, the parents' colours, the
    /// medicines list, the photo allowance, the night rota and the feeds marked as two; never a
    /// later one, so a change made in Feeding since stays. The feed window's times (never its
    /// Alerts switch), the day and night hours and the time zone come through
    /// `updateHouseholdSettings`, and the rota is always a change for the other phone to confirm,
    /// so this phone alerts as if on duty until the other phone has them (the acknowledgement
    /// rule). Nothing changes when there is a problem.
    @discardableResult
    public mutating func bringIn(_ move: HouseholdMove, me: MemberID, carried: Set<String>, now: Date) throws(MoveProblem) -> MoveOutcome {
        if let problem = moveProblem(move, me: me) { throw problem }
        guard let baby = currentBaby else { throw .notSetUp }
        let other = otherMember(than: me)
        let map: (MemberID) -> MemberID = { $0 == move.madeBy ? me : (other ?? $0) }
        let owners = move.mediaOwners
        var outcome = MoveOutcome()

        for original in move.entries {
            var payload = PayloadCoder.decode(EventPayload.self, from: original.payload)
            // A first's photos: those here now, that it owns, and nothing removed in this container.
            let keep = { (id: String) in carried.contains(id) && owners[id] == original.id }
            if let existing = events[original.id] {
                outcome.alreadyHere += 1
                if let details = payload?.milestone, completeFirst(existing, with: details, keep: keep, me: me, now: now) {
                    outcome.firstsCompleted += 1
                }
                continue
            }
            var event = original
            event.babyID = baby.name
            event.loggedBy = map(original.loggedBy)
            // iCloud stamps its own time when this container first gets the record. Feeding Dev's
            // cap on a start from a phone whose clock ran fast is kept in the start itself, so the
            // alerts plan from the same moment in both apps (Codex review of the move).
            if event.kind == .feed, let server = original.serverCreatedAt {
                event.startedAt = min(original.startedAt, server.addingTimeInterval(Event.serverClockAllowance))
            }
            event.serverCreatedAt = nil
            if let stamps = payload?.stamps {
                payload?.stamps = stamps.mapValues { FieldStamp(at: $0.at, by: map($0.by)) }
            }
            if let first = payload?.milestone {
                var moved = first
                moved.media = first.media.filter(keep)
                moved.crops = first.crops.filter { keep($0.key) }
                moved.removedMedia = []
                payload?.milestone = moved
                // What the move itself changed is its own change.
                let stamp = FieldStamp(at: now, by: me)
                if moved.media != first.media { payload?.setStamp(.media, stamp) }
                if moved.crops != first.crops { payload?.setStamp(.crops, stamp) }
                if moved.removedMedia != first.removedMedia { payload?.setStamp(.removedMedia, stamp) }
            }
            if let payload { event.payload = try? PayloadCoder.encode(payload) }
            events[event.id] = StoredEvent(event: event, changedFields: EventField.fields(for: event.kind), needsUpload: true,
                                           uploadNotBefore: nil, systemFields: nil, localRevision: 1)
            outcome.added[event.kind, default: 0] += 1
        }

        guard setting(MoveReceipt.self, SettingKey.moveReceipt) == nil else { return outcome }
        outcome.settingsBrought = true
        putSetting(MoveReceipt(madeAt: move.madeAt, broughtAt: now, by: me), key: SettingKey.moveReceipt, now: now)
        let dev = move.settingsOnly
        if let details = dev.plainRecord(.baby, move.babyID)?.payload,
           PayloadCoder.decode(BabyPayload.self, from: details) != nil,
           details != baby.payload {
            var updated = baby
            updated.payload = details
            updated.modifiedAt = now
            put(updated)
        }
        for record in dev.plainRecords(of: .member) {
            if let colour = PayloadCoder.decode(MemberPayload.self, from: record.payload)?.colour {
                setColour(colour, of: map(MemberID(rawValue: record.name)), now: now)
            }
        }
        let has: (String) -> Bool = { dev.plainRecord(.setting, $0) != nil }
        let settings = dev.householdSettings
        updateHouseholdSettings(by: me, now: now) { current in
            // The times only: the move never turns the alerts off (Codex review of the move).
            if has(SettingKey.feedWindow), settings.window.isSensible {
                current.window.opensAfter = settings.window.opensAfter
                current.window.closesAfter = settings.window.closesAfter
                current.window.backupAfterClose = settings.window.backupAfterClose
            }
            if has(SettingKey.dayHours) { current.dayHours = settings.dayHours }
            if has(SettingKey.timeZone), TimeZone(identifier: settings.timeZoneID) != nil { current.timeZoneID = settings.timeZoneID }
        }
        if let rota = dev.rota {
            let mapped = Rota(startDate: rota.startDate, firstOnDuty: map(rota.firstOnDuty), secondOnDuty: map(rota.secondOnDuty))
            if mapped != self.rota {
                putSetting(mapped, key: SettingKey.rota, now: now)
                addPendingChange(previousSettings: nil, by: me, now: now)
            }
        }
        if has(SettingKey.medicines) { setMedicines(dev.medicines, now: now) }
        if has(SettingKey.photoAllowance) { setPhotoAllowance(dev.photoAllowance, now: now) }
        // A pair already marked here stays as it is.
        for pair in dev.distinctFeeds where pair.ids.count == 2 {
            let key = SettingKey.distinct(pair.ids[0], pair.ids[1])
            guard plainRecord(.setting, key) == nil else { continue }
            putSetting(pair.mapped(map), key: key, now: now)
        }
        return outcome
    }

    /// Gives a first already here the photos and videos of `details` it lacks, that `keep` allows
    /// and that weren't removed here, after those it has, up to the limit. True if it changed.
    private mutating func completeFirst(_ existing: StoredEvent, with details: MilestoneDetails, keep: (String) -> Bool,
                                        me: MemberID, now: Date) -> Bool {
        guard existing.event.kind == .milestone, existing.event.deletedAt == nil,
              let here = existing.snapshot.payload?.milestone else { return false }
        let missing = details.media.filter { keep($0) && !here.media.contains($0) && !here.removedMedia.contains($0) }
        let media = Array((here.media + missing).prefix(MilestoneLimits.mediaItems))
        guard media != here.media else { return false }
        return edit(existing.event.id, by: me, now: now) { snapshot in
            snapshot.payload?.milestone?.media = media
            for id in missing where media.contains(id) {
                if let crop = details.crops[id] { snapshot.payload?.milestone?.crops[id] = crop }
            }
        }
    }

    /// Every pair marked as two feeds, as stored.
    var distinctFeeds: [DistinctFeeds] {
        plainRecords(of: .setting).filter { $0.name.hasPrefix("distinct-") }.compactMap {
            PayloadCoder.decode(SettingPayload<DistinctFeeds>.self, from: $0.payload)?.value
        }
    }
}
