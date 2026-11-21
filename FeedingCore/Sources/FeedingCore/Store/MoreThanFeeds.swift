import Foundation

// Logging sleep, nappies, growth and medicine (`docs/planning/06-more-than-feeds.md`). Each is an
// `Event` like a feed, with its own kind, so it syncs, merges and undoes as a feed does. None of
// it touches the alerts: `reconcile` counts feeds only.

extension HouseholdData {
    /// The sleep of `babyID` running now: the one started last, while it has no end. Nil while
    /// awake.
    public func sleepInProgress(babyID: String, now: Date) -> EventSnapshot? {
        guard case .asleep(let id, _) = sleepState(snapshots, babyID: babyID, now: now) else { return nil }
        return events[id]?.snapshot
    }

    /// "Fell asleep", at `startedAt` (now, or earlier when logged late). One sleep runs at a time:
    /// while one runs, this adds nothing and returns the running sleep's ID.
    @discardableResult
    public mutating func startSleep(id: String = UUID().uuidString, babyID: String, startedAt: Date? = nil,
                                    by member: MemberID, timeZoneID: String, now: Date) -> String {
        if let running = sleepInProgress(babyID: babyID, now: now) { return running.id }
        return add(id: id, kind: .sleep, babyID: babyID, startedAt: min(startedAt ?? now, now),
                   payload: EventPayload(), by: member, timeZoneID: timeZoneID, now: now)
    }

    /// "Woke up", at `end` (now, or a few minutes ago when tapped late). Ends every sleep of
    /// `babyID` still running, so a sleep started on each phone ends with one tap. A sleep never
    /// ends before it started. The tap is one wake-up: every sleep it ends gets the same wake-up
    /// ID, with the parent who tapped as "got up" (R3, engineering review D8 A). Returns the IDs it
    /// ended.
    @discardableResult
    public mutating func endSleep(babyID: String, at end: Date? = nil, by member: MemberID, now: Date,
                                  wakeID: String = UUID().uuidString) -> [String] {
        let running = liveSleeps(allEvents, babyID: babyID, now: now).filter { $0.endedAt == nil }
        let wokeAt = min(end ?? now, now)
        var ended: [String] = []
        for sleep in running {
            let done = edit(sleep.id, by: member, now: now) { snapshot in
                snapshot.event.endedAt = max(wokeAt, sleep.startedAt)
                Self.setWakeUp(&snapshot, wakeID, gotUp: member)
            }
            if done { ended.append(sleep.id) }
        }
        return ended
    }

    /// The wake-up ID of sleeps a feed ended (Start feed, or a feed that reached this phone late):
    /// the same on both phones and in every pass, so they are one wake-up.
    public static func feedWakeID(_ feedID: String) -> String { "feed:\(feedID)" }

    /// Gives a sleep's new ending (its end already set) its wake-up ID and who got up for it.
    static func setWakeUp(_ snapshot: inout EventSnapshot, _ wakeID: String, gotUp member: MemberID) {
        snapshot.event.wakeID = wakeID
        snapshot.event.gotUpBy = member
        snapshot.event.gotUpFor = snapshot.event.endingID
    }

    /// A nappy change: wee, poo or both, at `at` (now by default). The colour and consistency come
    /// later, with `edit`.
    @discardableResult
    public mutating func addNappy(id: String = UUID().uuidString, babyID: String, wee: Bool, poo: Bool, at: Date? = nil,
                                  by member: MemberID, timeZoneID: String, now: Date) -> String {
        add(id: id, kind: .nappy, babyID: babyID, startedAt: at ?? now,
            payload: EventPayload(nappy: NappyDetails(wee: wee, poo: poo)), by: member, timeZoneID: timeZoneID, now: now)
    }

    /// A growth entry. Nil, and nothing saved, when it has no measurement.
    @discardableResult
    public mutating func addGrowth(id: String = UUID().uuidString, babyID: String, _ growth: GrowthDetails, at: Date? = nil,
                                   by member: MemberID, timeZoneID: String, now: Date) -> String? {
        guard !growth.isEmpty else { return nil }
        return add(id: id, kind: .growth, babyID: babyID, startedAt: at ?? now, payload: EventPayload(growth: growth),
                   by: member, timeZoneID: timeZoneID, now: now)
    }

    /// A medicine or vitamin given.
    @discardableResult
    public mutating func addMedicine(id: String = UUID().uuidString, babyID: String, _ medicine: MedicineDetails, at: Date? = nil,
                                     by member: MemberID, timeZoneID: String, now: Date) -> String {
        add(id: id, kind: .medicine, babyID: babyID, startedAt: at ?? now, payload: EventPayload(medicine: medicine),
            by: member, timeZoneID: timeZoneID, now: now)
    }
}

// MARK: - A feed during a sleep (the users' choice O, 17 Nov 2026)

extension HouseholdData {
    /// Start feed ends the sleep: the baby woke to feed. Ends every sleep of `babyID` that is
    /// running and started before `start`, at `start`. A sleep that started later (a watch tap
    /// that reached the phone late) is left alone. The alarms don't change: they count feeds only.
    /// The sleeps it ends are one wake-up, with the feed's wake-up ID and the parent who started
    /// the feed as "got up". Returns the IDs it ended.
    @discardableResult
    public mutating func endSleepForFeed(babyID: String, start: Date, feedID: String, by member: MemberID,
                                         now: Date) -> [String] {
        let running = liveSleeps(allEvents, babyID: babyID, now: max(now, start))
            .filter { $0.endedAt == nil && $0.startedAt < start }
        let wake = Self.feedWakeID(feedID)
        return running.filter { sleep in
            edit(sleep.id, by: member, now: now) { snapshot in
                snapshot.event.endedAt = start
                Self.setWakeUp(&snapshot, wake, gotUp: member)
            }
        }.map(\.id)
    }

    /// A feed removed as started by mistake ("Stop · discard"): the sleep its Start feed ended
    /// runs again. The sleep is found by who ended it and when: the same parent, at the moment
    /// the feed was created (`endSleepForFeed` stamps it so). A later correction of the feed's
    /// start, or a Woke up tapped by hand, doesn't match. Only the latest sleep, and only while no
    /// other sleep runs. Returns the IDs it opened again.
    @discardableResult
    public mutating func reopenSleepEnded(byFeed feed: Event, by member: MemberID, now: Date) -> [String] {
        let sleeps = liveSleeps(allEvents, babyID: feed.babyID, now: max(now, feed.createdAt))
        func endedByFeed(_ sleep: Event) -> Bool {
            guard sleep.endedAt != nil, let stamp = events[sleep.id]?.snapshot.payload?.stamp(.endedAt) else { return false }
            // Since wake-up IDs: never a sleep another wake-up or feed ended.
            if let wake = sleep.wakeID, wake != Self.feedWakeID(feed.id) { return false }
            // The end must still be the one the feed's start wrote: an end changed by hand stays.
            return stamp.by == feed.loggedBy && abs(stamp.at.timeIntervalSince(feed.createdAt)) < 1
        }
        guard let last = sleeps.last, endedByFeed(last) else { return [] }
        return sleeps.filter(endedByFeed).filter { sleep in
            edit(sleep.id, by: member, now: now) { $0.event.endedAt = nil }
        }.map(\.id)
    }

    /// The users' choice O for entries that reach this phone late: a sleep still running that
    /// began before a later feed ended when that feed began. Parent A logged Fell asleep with no
    /// signal while Parent B started a feed, or an Undo of Woke up met a feed started since.
    /// Every phone runs this after each change; both write the same end, so they never fight.
    /// Returns the IDs it ended.
    @discardableResult
    public mutating func endSleepsInterruptedByFeeds(by member: MemberID, now: Date) -> [String] {
        let feeds = allEvents.filter { $0.isLiveFeed && $0.startedAt <= now }
        var ended: [String] = []
        for sleep in allEvents where sleep.kind == .sleep && sleep.deletedAt == nil && sleep.endedAt == nil {
            guard let feed = feeds.filter({ $0.babyID == sleep.babyID && $0.startedAt > sleep.startedAt })
                .min(by: { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }) else { continue }
            // The feed's wake-up ID, and its logger as "got up", whichever phone runs this.
            let ended1 = edit(sleep.id, by: member, now: now) { snapshot in
                snapshot.event.endedAt = feed.startedAt
                Self.setWakeUp(&snapshot, Self.feedWakeID(feed.id), gotUp: feed.loggedBy)
            }
            if ended1 { ended.append(sleep.id) }
        }
        return ended
    }

    /// "Stop · discard" for a feed: gone completely while it hasn't been sent, otherwise hidden. A
    /// sleep its start ended runs again. Returns false when the feed is unknown.
    @discardableResult
    public mutating func discardFeed(_ id: String, by member: MemberID, now: Date) -> Bool {
        guard let feed = events[id]?.event else { return false }
        if !undoAdd(id, now: now) {
            guard delete(id, by: member, now: now) else { return false }
        }
        reopenSleepEnded(byFeed: feed, by: member, now: now)
        return true
    }
}

// MARK: - The medicine list (17 Nov 2026)

extension SettingKey {
    /// The household's own short list of medicines and vitamins.
    public static let medicines = "medicines"
}

extension HouseholdData {
    /// The list a new household starts with.
    public static let defaultMedicines = ["Vitamin D"]

    /// The household's medicines and vitamins, in the order the parents chose. Shared by both
    /// phones. The app never shows a "next dose" time: only when each was last given.
    public var medicines: [String] {
        setting([String].self, SettingKey.medicines) ?? Self.defaultMedicines
    }

    /// Saves the list: names trimmed, empty ones and repeats (ignoring case) left out.
    public mutating func setMedicines(_ names: [String], now: Date) {
        var seen = Set<String>()
        let clean = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard clean != medicines else { return }
        putSetting(clean, key: SettingKey.medicines, now: now)
    }

    /// When `name` was last given to `babyID`, up to `now`. Matched ignoring case.
    public func lastGiven(_ name: String, babyID: String, now: Date) -> Date? {
        let key = name.lowercased()
        return snapshots.lazy
            .filter { $0.event.kind == .medicine && $0.event.deletedAt == nil && $0.event.babyID == babyID
                && $0.event.startedAt <= now && $0.payload?.medicine?.name.lowercased() == key }
            .map(\.event.startedAt).max()
    }
}
