import Foundation

// The baby's firsts (`docs/planning/07-milestones-journal.md`). A first is an `Event` of kind
// `milestone`, so it syncs, merges, undoes and deletes as a feed does. Its words are in the
// encrypted payload; its photos and videos are `Media` records in the photos zone, named here by
// their IDs. None of it touches the alerts: `reconcile` counts feeds only.

/// Which part of a photo shows in its square on the Journal's line (design review D39): the centre
/// of the square, as a fraction of the photo's width (`x`, from the left) and height (`y`, from the
/// top). The middle until a parent drags the photo in Edit. A first's page shows the whole photo
/// (the parents' choice, 19 Nov 2026), so this is for the square only.
public struct MediaCrop: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public static let middle = MediaCrop(x: 0.5, y: 0.5)

    public init(x: Double, y: Double) {
        self.x = x.isFinite ? min(max(x, 0), 1) : 0.5
        self.y = y.isFinite ? min(max(y, 0), 1) : 0.5
    }

    /// The same crop moved as little as needed so a square cut from a `width` × `height` photo
    /// stays inside it. A wide photo can only move sideways, a tall one only up and down.
    public func clamped(width: Double, height: Double) -> MediaCrop {
        guard width > 0, height > 0 else { return .middle }
        let side = min(width, height)
        let halfX = side / width / 2, halfY = side / height / 2
        return MediaCrop(x: min(max(x, halfX), 1 - halfX), y: min(max(y, halfY), 1 - halfY))
    }

    /// Where the photo goes in a square of side `box`: its drawn size (filling the square) and the
    /// offset of its top left corner, so the crop's centre is in the middle of the square.
    public func placement(width: Double, height: Double, box: Double) -> (width: Double, height: Double, x: Double, y: Double) {
        guard width > 0, height > 0, box > 0 else { return (box, box, 0, 0) }
        let scale = max(box / width, box / height)
        let drawnWidth = width * scale, drawnHeight = height * scale
        let crop = clamped(width: width, height: height)
        return (drawnWidth, drawnHeight, box / 2 - crop.x * drawnWidth, box / 2 - crop.y * drawnHeight)
    }

    /// The crop after a drag of `dx`, `dy` points on a square of side `box`, starting from this one:
    /// the photo follows the finger, so the square's centre moves the other way.
    public func dragged(dx: Double, dy: Double, width: Double, height: Double, box: Double) -> MediaCrop {
        let place = placement(width: width, height: height, box: box)
        let start = clamped(width: width, height: height)
        return MediaCrop(x: start.x - dx / place.width, y: start.y - dy / place.height).clamped(width: width, height: height)
    }
}

/// A first's details: what happened, and its photos and videos. The note is the event's own
/// `note`. Each part merges on its own: the title, the media list and the crops by the later
/// change, the removed list by joining both phones' lists (eng D10).
public struct MilestoneDetails: Hashable, Sendable, Codable {
    /// What happened, such as "First smile".
    public var title: String
    /// The IDs of its photos and videos, in order; the first is the cover. Kept free of removed
    /// IDs and repeats, and at most `MilestoneLimits.mediaItems` long (`normalize`).
    public var media: [String]
    /// Every photo or video ever removed from this first, sorted. It only grows, and is joined
    /// with the other phone's on a merge, so an older media list from a phone that was offline can
    /// never name a removed item again. The clean-up deletes only `Media` records on this list.
    public var removedMedia: [String]
    /// Each photo's square on the line, by media ID (D39; one field, so the later change wins
    /// whole: eng2 D5). A photo with none shows its middle. Version 4 of `EventPayload`.
    public var crops: [String: MediaCrop]

    public init(title: String, media: [String] = [], removedMedia: [String] = [], crops: [String: MediaCrop] = [:]) {
        self.title = title
        self.media = media
        self.removedMedia = removedMedia
        self.crops = crops
        normalize()
    }

    /// Sorts the removed list without repeats, and leaves out of the media list every removed ID,
    /// every repeat and anything past the limit; a removed item's crop goes too. Every list shown
    /// or saved goes through this.
    public mutating func normalize() {
        removedMedia = Array(Set(removedMedia)).sorted()
        let removed = Set(removedMedia)
        var seen = Set<String>()
        media = Array(media.filter { !removed.contains($0) && seen.insert($0).inserted }.prefix(MilestoneLimits.mediaItems))
        crops = crops.filter { !removed.contains($0.key) && $0.value != .middle }
    }

    private enum CodingKeys: String, CodingKey {
        case title, media, removedMedia, crops
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        media = try container.decode([String].self, forKey: .media)
        removedMedia = try container.decode([String].self, forKey: .removedMedia)
        crops = try container.decodeIfPresent([String: MediaCrop].self, forKey: .crops) ?? [:]
    }

    /// No crops, no `crops` key: a first nobody cropped is written exactly as version 3 wrote it.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(media, forKey: .media)
        try container.encode(removedMedia, forKey: .removedMedia)
        if !crops.isEmpty { try container.encode(crops, forKey: .crops) }
    }
}

/// How big a first may be (eng D5, outside voice OE9). The character limits are what a parent
/// sees, with a count near each; the byte limits stop text with many code points per character
/// from making a record too big for iCloud (1 MB), so every first can sync.
public enum MilestoneLimits {
    public static let titleCharacters = 80
    public static let noteCharacters = 5_000
    /// In UTF-8 bytes.
    public static let titleBytes = 1_024
    /// In UTF-8 bytes.
    public static let noteBytes = 32 * 1_024
    /// Photos and videos on one first (CEO review, D13).
    public static let mediaItems = 4

    /// `text` cut to the title's limits.
    public static func title(_ text: String) -> String {
        clamp(text, characters: titleCharacters, bytes: titleBytes)
    }

    /// `text` cut to the note's limits.
    public static func note(_ text: String) -> String {
        clamp(text, characters: noteCharacters, bytes: noteBytes)
    }

    /// The longest start of `text` with at most `characters` characters and `bytes` UTF-8 bytes.
    /// It never cuts inside a character.
    static func clamp(_ text: String, characters: Int, bytes: Int) -> String {
        var result = ""
        var count = 0
        var size = 0
        for character in text {
            let characterSize = character.utf8.count
            guard count < characters, size + characterSize <= bytes else { break }
            result.append(character)
            count += 1
            size += characterSize
        }
        return result
    }
}

/// The first's "When" from its photos (design review D17; engineering re-review eng2 D2): the time
/// the earliest picked item was taken, if that is more than 5 minutes before now, on any day; a
/// photo taken just now (or in the app) keeps "now", with no note.
public enum MilestoneWhen {
    public static let justNow: TimeInterval = 5 * 60

    /// The time to use, or nil to keep "now".
    public static func fromPhotos(takenAt: [Date], now: Date) -> Date? {
        guard let earliest = takenAt.min(), now.timeIntervalSince(earliest) > justNow else { return nil }
        return earliest
    }
}

/// Why a first can't have a date (journal plan, "The baby's age").
public enum MilestoneDateProblem: Hashable, Sendable {
    /// The date is before the birth date.
    case beforeBirth(PlainDate)
    /// The time is later than now.
    case inFuture
}

extension HouseholdData {
    // MARK: Reading

    /// The baby's birth date, if the parents gave one.
    public func birthDate(babyID: String) -> PlainDate? {
        PayloadCoder.decode(BabyPayload.self, from: plainRecord(.baby, babyID)?.payload)?.birthDate
    }

    /// The firsts of `babyID` that aren't deleted and that this build can read, oldest first.
    public func milestones(babyID: String) -> [EventSnapshot] {
        snapshots
            .filter { $0.event.kind == .milestone && $0.event.babyID == babyID && $0.event.deletedAt == nil
                && $0.payload?.milestone != nil }
            .sorted { ($0.event.startedAt, $0.event.id) < ($1.event.startedAt, $1.event.id) }
    }

    /// Nil when a first of `babyID` may be dated `date`: not before the birth date, on the
    /// household's calendar, and not later than `now`.
    public func milestoneDateProblem(_ date: Date, babyID: String, now: Date) -> MilestoneDateProblem? {
        if date > now { return .inFuture }
        if let birth = birthDate(babyID: babyID), PlainDate(date, in: householdSettings.timeZone) < birth {
            return .beforeBirth(birth)
        }
        return nil
    }

    /// The earliest first of `babyID` dated before `birthDate`, on the household's calendar. A
    /// birth date is refused while one exists, and the refusal names it.
    /// A first whose delete is still held for Undo counts too: Undo would bring it back before the
    /// birth date (Codex review of T7 and T8).
    public func firstBefore(birthDate: PlainDate, babyID: String) -> EventSnapshot? {
        let timeZone = householdSettings.timeZone
        let undoable = events.values.filter {
            $0.event.kind == .milestone && $0.event.babyID == babyID && $0.heldUndo?.undeletes == true
        }.map(\.snapshot).filter { $0.payload?.milestone != nil }
        return (milestones(babyID: babyID) + undoable)
            .sorted { ($0.event.startedAt, $0.event.id) < ($1.event.startedAt, $1.event.id) }
            .first { PlainDate($0.event.startedAt, in: timeZone) < birthDate }
    }

    // MARK: Changes

    /// Sets or corrects the baby's birth date, on both phones (the Baby record). Refused while a
    /// first is dated before it: that first is returned, so the refusal can name it. Every age is
    /// worked out again from it, as none is stored.
    @discardableResult
    public mutating func setBirthDate(_ birthDate: PlainDate, babyID: String, now: Date) -> EventSnapshot? {
        if let blocking = firstBefore(birthDate: birthDate, babyID: babyID) { return blocking }
        guard let record = plainRecord(.baby, babyID) else { return nil }
        var baby = PayloadCoder.decode(BabyPayload.self, from: record.payload) ?? BabyPayload(name: "Baby")
        guard baby.birthDate != birthDate else { return nil }
        baby.birthDate = birthDate
        var changed = record
        changed.payload = try? PayloadCoder.encode(baby)
        changed.modifiedAt = now
        put(changed)
        return nil
    }

    /// Adds a first at `at`, with its title, note and photos and videos (by ID), cut to the limits.
    /// Nil, and nothing saved, when the title is empty, the date is refused, or it has more than
    /// `MilestoneLimits.mediaItems` photos and videos.
    @discardableResult
    public mutating func addMilestone(id: String = UUID().uuidString, babyID: String, title: String, note: String? = nil,
                                      media: [String] = [], crops: [String: MediaCrop] = [:], at: Date, by member: MemberID,
                                      timeZoneID: String, now: Date) -> String? {
        let title = Self.cleanTitle(title)
        guard !title.isEmpty, Self.fitsTheLimit(media), milestoneDateProblem(at, babyID: babyID, now: now) == nil else {
            return nil
        }
        return add(id: id, kind: .milestone, babyID: babyID, startedAt: at,
                   payload: EventPayload(milestone: MilestoneDetails(title: title, media: media,
                                                                     crops: crops.filter { media.contains($0.key) }),
                                         note: Self.cleanNote(note)),
                   by: member, timeZoneID: timeZoneID, now: now)
    }

    /// Saves what the parent changed in the editor, which opened on `original`. Only what differs
    /// from `original` is applied, onto the first as it is now, so a change the other phone made
    /// while the editor was open is kept:
    /// - only a photo the parent took out joins the removed list;
    /// - a photo the parent only added goes at the end of the list as it is now (keeping an order
    ///   the other phone set); if the parent also moved photos, the parent's order is used, with a
    ///   photo the other phone added after them.
    /// - only a crop the parent moved (or put back in the middle) is changed, so a crop the other
    ///   phone set for another photo stays.
    /// False, and nothing changed, when the title is empty, a changed date is refused, the list
    /// would hold more than `MilestoneLimits.mediaItems` items (never cut silently), or it isn't a
    /// first this build reads.
    @discardableResult
    public mutating func editMilestone(_ id: String, from original: EventSnapshot, title: String, note: String?,
                                       media: [String], crops: [String: MediaCrop]? = nil, at: Date, by member: MemberID,
                                       now: Date) -> Bool {
        // A first deleted meanwhile (on the other phone) isn't changed: its edits would be hidden.
        guard let current = events[id]?.snapshot, current.event.kind == .milestone, current.event.deletedAt == nil,
              var milestone = current.payload?.milestone, let before = original.payload?.milestone else { return false }
        let title = Self.cleanTitle(title)
        let note = Self.cleanNote(note)
        guard !title.isEmpty, Self.fitsTheLimit(media) else { return false }
        let dateChanged = at != original.event.startedAt
        if dateChanged, milestoneDateProblem(at, babyID: current.event.babyID, now: now) != nil { return false }
        let mediaBefore = milestone.media
        var takenOut: [String] = []
        if media != before.media {
            takenOut = before.media.filter { !media.contains($0) }
            let added = media.filter { !before.media.contains($0) }
            let kept = milestone.media.filter { !takenOut.contains($0) }
            let onlyAddedOrTakenOut = before.media.filter { media.contains($0) } + added == media
            let next = onlyAddedOrTakenOut ? kept + added.filter { !kept.contains($0) } : media + kept.filter { !media.contains($0) }
            milestone.removedMedia += takenOut
            let removed = Set(milestone.removedMedia)
            guard Self.fitsTheLimit(next.filter { !removed.contains($0) }) else { return false }
            milestone.media = next
        }
        if title != before.title { milestone.title = title }
        if let crops {
            for item in Set(crops.keys).union(before.crops.keys) where crops[item] != before.crops[item] {
                milestone.crops[item] = crops[item]
            }
        }
        milestone.normalize()
        let removedBefore = Set(current.payload?.milestone?.removedMedia ?? [])
        let saved = edit(id, by: member, now: now) { snapshot in
            snapshot.payload?.milestone = milestone
            if note != original.payload?.note { snapshot.payload?.note = note }
            if dateChanged { snapshot.event.startedAt = at }
        }
        let newlyRemoved = takenOut.filter { !removedBefore.contains($0) }
        if saved, !newlyRemoved.isEmpty {
            let addedHere = milestone.media.filter { !mediaBefore.contains($0) && !before.media.contains($0) }
            hold(id, HeldUndo(undeletes: false, media: mediaBefore, addedLocally: addedHere.filter { media.contains($0) },
                              addedRemovals: newlyRemoved), now: now)
        }
        return saved
    }

    /// Deletes a first: it is hidden, and its photos and videos go on its removed list, so they
    /// are deleted for good once the delete is sent. The delete waits on this phone for the Undo
    /// window first, so Undo brings everything back. Bringing a first back later (`restore`)
    /// brings back its words only. False when it isn't a first this build reads, or is deleted.
    @discardableResult
    public mutating func deleteMilestone(_ id: String, by member: MemberID, now: Date) -> Bool {
        guard let current = events[id]?.snapshot, current.event.kind == .milestone, current.event.deletedAt == nil,
              let details = current.payload?.milestone else { return false }
        let removedBefore = Set(details.removedMedia)
        let deleted = edit(id, by: member, now: now) { snapshot in
            snapshot.event.deletedAt = now
            snapshot.payload?.milestone?.removedMedia += details.media
            snapshot.payload?.milestone?.normalize()
        }
        if deleted {
            hold(id, HeldUndo(undeletes: true, media: details.media,
                              addedRemovals: details.media.filter { !removedBefore.contains($0) }), now: now)
        }
        return deleted
    }

    /// Undo for a first's delete or photos taken out, while it is still held on this phone: the
    /// first shows again with its photos, in their order; a photo the same save added (a replaced
    /// photo's new one) goes onto the removed list, never sent; one the other phone added meanwhile
    /// stays, after them. False once the change has been sent or its Undo window has passed.
    @discardableResult
    public mutating func undoHeld(_ id: String, by member: MemberID, now: Date) -> Bool {
        guard let stored = events[id], let held = stored.heldUndo,
              let deadline = stored.uploadNotBefore, now < deadline else { return false }
        let undone = edit(id, by: member, now: now) { snapshot in
            if held.undeletes { snapshot.event.deletedAt = nil }
            guard var milestone = snapshot.payload?.milestone else { return }
            let addedElsewhere = milestone.media.filter { !held.media.contains($0) && !held.addedLocally.contains($0) }
            milestone.removedMedia.removeAll { held.addedRemovals.contains($0) }
            milestone.removedMedia += held.addedLocally
            milestone.media = held.media + addedElsewhere
            milestone.normalize()
            snapshot.payload?.milestone = milestone
        }
        guard undone else { return false }
        events[id]?.heldUndo = nil
        events[id]?.uploadNotBefore = nil
        return true
    }

    /// Holds a change on this phone for the Undo window. A second change inside the window keeps
    /// the first one's "before", with any photo that arrived from the other phone in between.
    private mutating func hold(_ id: String, _ undo: HeldUndo, now: Date) {
        guard var stored = events[id] else { return }
        if let earlier = stored.heldUndo, let deadline = stored.uploadNotBefore, now < deadline {
            let arrivedBetween = undo.media.filter { !earlier.media.contains($0) && !earlier.addedLocally.contains($0) }
            stored.heldUndo = HeldUndo(undeletes: earlier.undeletes || undo.undeletes, media: earlier.media + arrivedBetween,
                                       addedLocally: earlier.addedLocally + undo.addedLocally,
                                       addedRemovals: earlier.addedRemovals + undo.addedRemovals)
        } else {
            stored.heldUndo = undo
        }
        stored.uploadNotBefore = max(stored.uploadNotBefore ?? now, now.addingTimeInterval(Self.undoWindow))
        events[id] = stored
    }

    /// True when `media` names at most `MilestoneLimits.mediaItems` different items.
    static func fitsTheLimit(_ media: [String]) -> Bool {
        Set(media).count <= MilestoneLimits.mediaItems
    }

    /// A title as it is saved: on one line, trimmed, cut to the limits.
    public static func cleanTitle(_ title: String) -> String {
        let oneLine = String(title.map { $0.isNewline ? " " : $0 })
        return trimmed(MilestoneLimits.title(trimmed(oneLine)))
    }

    /// A note as it is saved: trimmed and cut to the limits; nil when empty.
    public static func cleanNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let clean = trimmed(MilestoneLimits.note(trimmed(note)))
        return clean.isEmpty ? nil : clean
    }

    /// `text` without whitespace or line breaks at either end, taken off a whole character at a
    /// time, so an accent is never left without its letter.
    static func trimmed(_ text: String) -> String {
        guard let first = text.firstIndex(where: { !$0.isWhitespace }),
              let last = text.lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(text[first...last])
    }
}
