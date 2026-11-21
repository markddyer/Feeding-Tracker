import Foundation

// "Who does what" (`docs/planning/09-who-does-what.md`): each parent's part of the care, as facts.
// One value, `WhoDidIt`, works out who did each entry and who got up at each wake-up, once per
// change of the store (engineering review A4, D5 A). The shared page, the list behind each number,
// "Last night", History's pictures, the editors and the Undo card all read it, so they can never
// disagree. Facts only: no targets, no verdicts. The alerts never read any of it.

// MARK: "Who breastfeeds?"

/// The shared answer to "Who breastfeeds?" (R2). A breastfeed or a pumping session with no stored
/// "done by" counts for this parent. Unanswered (no setting) or `nobody`: for the parent who
/// logged it. Changing it recounts every entry with no stored choice.
public enum Breastfeeder: Hashable, Sendable, Codable {
    case member(MemberID)
    case nobody

    public var member: MemberID? {
        if case .member(let member) = self { return member }
        return nil
    }
}

extension SettingKey {
    /// "Who breastfeeds?" (`Breastfeeder`).
    public static let breastfeeder = "breastfeeder"
}

extension HouseholdData {
    /// Nil until either parent answers.
    public var breastfeeder: Breastfeeder? { setting(Breastfeeder.self, SettingKey.breastfeeder) }

    public mutating func setBreastfeeder(_ answer: Breastfeeder, now: Date) {
        putSetting(answer, key: SettingKey.breastfeeder, now: now)
    }

    /// Sleeps, nappies, medicines and baths of `babyID` logged on both phones (D11 C, D12 A).
    public func careDuplicatePairs(babyID: String) -> [DuplicatePair] {
        duplicateCareEntries(snapshots.filter { $0.event.babyID == babyID }, confirmedDistinct: distinctFeedPairs)
    }

    /// The one answer sheet for `babyID`, from everything this phone holds.
    public func whoDidIt(babyID: String, now: Date) -> WhoDidIt {
        let settings = householdSettings
        return WhoDidIt(snapshots, babyID: babyID, breastfeeder: breastfeeder, confirmedDistinct: distinctFeedPairs,
                        dayHours: settings.dayHours, timeZone: settings.timeZone, now: now)
    }
}

// MARK: What is counted

/// The lines of the shared page. The first six are "Who did what" (DD2; "Feeding time" is the
/// feeds' time); the last three are the night lines (design 1B), counted by the night's evening.
public enum ShareKind: String, CaseIterable, Sendable {
    case feeds, nappies, settled, medicines, baths, pumping
    case gotUpAtNight, nightFeeds, nightNappies

    /// Counted by the night it falls in, named by its evening (design 1A).
    public var isNight: Bool { self == .gotUpAtNight || self == .nightFeeds || self == .nightNappies }
}

/// One counted thing: an entry (with any copy of it from the other phone folded in), or a
/// wake-up (every sleep one ending closed).
public struct ShareItem: Hashable, Sendable, Identifiable {
    /// "<kind>:<first event ID>", unique across the page.
    public var id: String
    public var kind: ShareKind
    /// The entries behind it: the entry and its hidden copy, or the sleeps of a wake-up.
    public var eventIDs: [String]
    /// Who it counts for: who did it, or who got up.
    public var member: MemberID
    /// A parent chose it (true), or the starting rule worked it out (false).
    public var saved: Bool
    /// Its start; a wake-up's moment is its earliest end.
    public var at: Date
    /// The time it adds, for feeds and pumping; nil while running, and for kinds not timed.
    public var seconds: TimeInterval?
    /// The calendar day it counts under, or, for a night line, the night's evening.
    public var day: PlainDate
}

extension EventSnapshot {
    /// Who tapped Finish (TD1, D10 C): the parent in the end time's stamp, but only when the end
    /// was set as it was tapped (the end equals its stamp's time, within a second). A later
    /// correction of the time, or an entry logged afterwards, claims no finisher.
    public var finishedBy: MemberID? {
        guard let end = event.endedAt, let stamp = payload?.stamp(.endedAt),
              abs(stamp.at.timeIntervalSince(end)) <= 1 else { return nil }
        return stamp.by
    }
}

/// Which days the page shows (design 1C): one day, the last days counting today, or all.
public enum ShareRange: Hashable, Sendable {
    case day(PlainDate)
    case lastDays(Int)
    case all

    public func contains(_ date: PlainDate, today: PlainDate) -> Bool {
        switch self {
        case .day(let day): date == day
        case .lastDays(let count): date <= today && today.days(since: date) < count
        case .all: true
        }
    }
}

public struct ShareTally: Hashable, Sendable {
    public var count = 0
    public var seconds: TimeInterval = 0

    public init(count: Int = 0, seconds: TimeInterval = 0) {
        self.count = count
        self.seconds = seconds
    }
}

/// Each parent's count and time per line, for one range.
public struct ShareFacts: Hashable, Sendable {
    public var tallies: [ShareKind: [MemberID: ShareTally]] = [:]

    public func tally(_ kind: ShareKind, _ member: MemberID) -> ShareTally { tallies[kind]?[member] ?? ShareTally() }

    public func total(_ kind: ShareKind) -> ShareTally {
        (tallies[kind] ?? [:]).values.reduce(into: ShareTally()) {
            $0.count += $1.count
            $0.seconds += $1.seconds
        }
    }

    /// The members with anything counted, in ID order.
    public var members: [MemberID] { Set(tallies.values.flatMap(\.keys)).sorted() }

    public var isEmpty: Bool { tallies.values.allSatisfy(\.isEmpty) }
}

/// The night before this morning, for Home's morning line (X3, design 3A): its feeds, nappies and
/// wake-ups in time order, and how long the baby slept in it.
public struct LastNight: Hashable, Sendable {
    /// Named by its evening.
    public var night: PlainDate
    public var items: [ShareItem]
    /// The sleeps that overlap the night hours, cut to them and joined, so no time counts twice.
    public var sleptSeconds: TimeInterval
}

// MARK: The answer sheet

public struct WhoDidIt: Sendable {
    public struct Answer: Hashable, Sendable {
        public var member: MemberID
        /// A parent chose it (true), or it was worked out (false: History draws it dashed, 7A).
        public var saved: Bool

        public init(member: MemberID, saved: Bool) {
            self.member = member
            self.saved = saved
        }
    }

    /// Everything the page counts, oldest first.
    public let items: [ShareItem]
    /// Copies from the other phone, left out of every count (feeds and D12's kinds).
    public let hiddenCopies: Set<String>
    let doneByID: [String: Answer]
    let gotUpBySleep: [String: Answer]
    /// The night before this morning, while the morning line shows (until 12:00).
    let morningNight: PlainDate?
    let today: PlainDate
    /// For the nights' slept time.
    let liveEvents: [Event]
    let babyID: String
    let dayHours: DayHours
    let timeZone: TimeZone
    let now: Date

    /// The morning line shows until this time on the household's wall clock (D6: "until midday").
    public static let lastNightUntil = TimeOfDay(hour: 12)!

    public init(_ snapshots: [EventSnapshot], babyID: String, breastfeeder: Breastfeeder?,
                confirmedDistinct: Set<Set<String>>, dayHours: DayHours, timeZone: TimeZone, now: Date) {
        let live = snapshots.filter {
            $0.event.babyID == babyID && $0.event.deletedAt == nil && $0.event.startedAt <= now && $0.event.kind.countsAsWork
        }
        let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pairs = duplicateFeeds(live.map(\.event), confirmedDistinct: confirmedDistinct)
            + duplicateCareEntries(live, confirmedDistinct: confirmedDistinct)
        let copyOf = Dictionary(pairs.map { ($0.kept, $0.duplicate) }, uniquingKeysWith: { first, _ in first })
        let hidden = Set(pairs.map(\.duplicate))
        today = PlainDate(now, in: timeZone)
        hiddenCopies = hidden

        var doneByID: [String: Answer] = [:]
        var items: [ShareItem] = []
        func night(_ instant: Date) -> PlainDate? {
            if case .night(let evening) = dayHours.period(at: instant, in: timeZone) { return evening }
            return nil
        }

        for entry in live where !hidden.contains(entry.id) {
            let copy = copyOf[entry.id].flatMap { byID[$0] }
            let answer = Self.doneBy(entry, copy: copy, breastfeeder: breastfeeder)
            doneByID[entry.id] = answer
            if let copy { doneByID[copy.id] = answer }
            let event = entry.event
            let ids = [event.id] + (copy.map { [$0.id] } ?? [])
            let calendarDay = PlainDate(event.startedAt, in: timeZone)
            func item(_ kind: ShareKind, day: PlainDate, seconds: TimeInterval? = nil) -> ShareItem {
                ShareItem(id: "\(kind.rawValue):\(event.id)", kind: kind, eventIDs: ids, member: answer.member,
                          saved: answer.saved, at: event.startedAt, seconds: seconds, day: day)
            }
            switch event.kind {
            case .feed:
                let seconds = Self.feedSeconds(entry)
                items.append(item(.feeds, day: calendarDay, seconds: seconds))
                if let evening = night(event.startedAt) { items.append(item(.nightFeeds, day: evening, seconds: seconds)) }
            case .nappy:
                items.append(item(.nappies, day: calendarDay))
                if let evening = night(event.startedAt) { items.append(item(.nightNappies, day: evening)) }
            case .sleep: items.append(item(.settled, day: calendarDay))
            case .medicine: items.append(item(.medicines, day: calendarDay))
            case .bath: items.append(item(.baths, day: calendarDay))
            case .pump:
                items.append(item(.pumping, day: calendarDay,
                                  seconds: event.endedAt.map { max(0, $0.timeIntervalSince(event.startedAt)) }))
            default: break
            }
        }

        // Wake-ups: the sleeps one ending closed (D8 A), each counted once, at its earliest end.
        let feeds = live.map(\.event).filter(\.isLiveFeed)
        var gotUpBySleep: [String: Answer] = [:]
        let ended = live.map(\.event).filter { $0.kind == .sleep && $0.endedAt != nil }
        let wakeUps = Dictionary(grouping: ended) { $0.wakeID ?? $0.endingID ?? $0.id }
        for (key, sleeps) in wakeUps {
            let ordered = sleeps.sorted { ($0.endedAt!, $0.id) < ($1.endedAt!, $1.id) }
            let first = ordered[0]
            let moment = first.endedAt!
            let answer = Self.gotUp(ordered, snapshots: byID, feeds: feeds)
            for sleep in ordered { gotUpBySleep[sleep.id] = answer }
            guard moment <= now, let evening = night(moment) else { continue }
            items.append(ShareItem(id: "\(ShareKind.gotUpAtNight.rawValue):\(key)", kind: .gotUpAtNight,
                                   eventIDs: ordered.map(\.id), member: answer.member, saved: answer.saved,
                                   at: moment, seconds: nil, day: evening))
        }

        self.items = items.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
        self.doneByID = doneByID
        self.gotUpBySleep = gotUpBySleep
        liveEvents = live.map(\.event)
        self.babyID = babyID
        self.dayHours = dayHours
        self.timeZone = timeZone
        self.now = now
        morningNight = Self.morningNight(dayHours: dayHours, timeZone: timeZone, now: now)
    }

    // MARK: Reading

    /// Who did an entry (a copy answers as the entry it was folded into). Nil for a kind that
    /// doesn't count, a deleted entry, or another baby's.
    public func doneBy(_ eventID: String) -> Answer? { doneByID[eventID] }

    /// Who got up when a sleep ended. Nil while it runs.
    public func gotUp(sleep id: String) -> Answer? { gotUpBySleep[id] }

    /// The items behind one number: one line, one parent (or every parent), one range. The page's
    /// numbers are counted from these same items, so a number always equals its list.
    public func entries(_ kind: ShareKind, member: MemberID? = nil, range: ShareRange) -> [ShareItem] {
        items.filter { $0.kind == kind && (member == nil || $0.member == member) && range.contains($0.day, today: today) }
    }

    /// Each parent's counts and time per line.
    public func facts(_ range: ShareRange) -> ShareFacts {
        var facts = ShareFacts()
        for kind in ShareKind.allCases {
            for item in entries(kind, range: range) {
                facts.tallies[kind, default: [:]][item.member, default: ShareTally()].count += 1
                facts.tallies[kind, default: [:]][item.member, default: ShareTally()].seconds += item.seconds ?? 0
            }
        }
        return facts
    }

    /// The night before this morning, from the night's end until 12:00; nil otherwise, with no
    /// night hours, or when nothing was logged in it.
    public func lastNight() -> LastNight? {
        guard let night = morningNight else { return nil }
        let summary = self.night(night)
        return summary.items.isEmpty ? nil : summary
    }

    /// One night, named by its evening: its feeds, nappies and wake-ups in time order, and how
    /// long the baby slept in it (the page's Day view, design 1A).
    public func night(_ evening: PlainDate) -> LastNight {
        let spans = union(sleepSpans(liveEvents, babyID: babyID, now: now).map { ($0.start, $0.end) })
        let slept = spans.reduce(0) { $0 + dayHours.seconds(from: $1.0, to: $1.1, inNight: evening, timeZone: timeZone) }
        return LastNight(night: evening, items: items.filter { $0.kind.isNight && $0.day == evening }, sleptSeconds: slept)
    }

    /// The night named by its evening that `instant` falls in, or nil in the day.
    public func evening(at instant: Date) -> PlainDate? {
        if case .night(let evening) = dayHours.period(at: instant, in: timeZone) { return evening }
        return nil
    }

    /// Who one entry counts for on its own, with no copy from the other phone joined: the Undo
    /// card's picture right after a tap, by the same rule as the page.
    public static func answer(for entry: EventSnapshot, breastfeeder: Breastfeeder?) -> Answer {
        doneBy(entry, copy: nil, breastfeeder: breastfeeder)
    }

    // MARK: Rules

    /// R2's starting rule. A stored choice on either copy wins (the later stamp when both have
    /// one); otherwise a feed with a breast side, or a pumping session, counts for the parent who
    /// breastfeeds, and anything else for the parent who logged the entry shown.
    static func doneBy(_ entry: EventSnapshot, copy: EventSnapshot?, breastfeeder: Breastfeeder?) -> Answer {
        let stored = [entry, copy].compactMap { $0 }.filter { $0.event.doneBy != nil }
            .max { (stampOrOldest($0.payload?.stamp(.doneBy)), $0.id) < (stampOrOldest($1.payload?.stamp(.doneBy)), $1.id) }
        if let member = stored?.event.doneBy { return Answer(member: member, saved: true) }
        let breastWork = entry.event.kind == .pump || !(entry.payload?.feed?.breast.isEmpty ?? true)
        if breastWork, let member = breastfeeder?.member { return Answer(member: member, saved: false) }
        return Answer(member: entry.event.loggedBy, saved: false)
    }

    /// Who got up for one wake-up. A stored "got up" for this ending wins (the later stamp when
    /// sleeps of the wake-up disagree). Otherwise worked out: the logger of a feed that started as
    /// the sleep ended, else the parent in the end's stamp, else the sleep's logger.
    static func gotUp(_ sleeps: [Event], snapshots: [String: EventSnapshot], feeds: [Event]) -> Answer {
        let stamped = sleeps.filter { $0.validGotUp != nil }.max {
            (stampOrOldest(snapshots[$0.id]?.payload?.stamp(.gotUp)), $0.id)
                < (stampOrOldest(snapshots[$1.id]?.payload?.stamp(.gotUp)), $1.id)
        }
        if let member = stamped?.validGotUp { return Answer(member: member, saved: true) }
        let first = sleeps[0]
        let end = first.endedAt!
        if let feed = feeds.first(where: { $0.babyID == first.babyID && abs($0.startedAt.timeIntervalSince(end)) < 1 }) {
            return Answer(member: feed.loggedBy, saved: false)
        }
        if let stamp = snapshots[first.id]?.payload?.stamp(.endedAt) { return Answer(member: stamp.by, saved: false) }
        return Answer(member: first.loggedBy, saved: false)
    }

    /// A missing stamp orders before any real one.
    static func stampOrOldest(_ stamp: FieldStamp?) -> FieldStamp { stamp ?? FieldStamp(at: .distantPast, by: "") }

    /// A finished feed's time: the sum of its breast sides when every side has its seconds,
    /// otherwise start to end (a bottle, a side logged afterwards, or no details). None while it runs.
    static func feedSeconds(_ feed: EventSnapshot) -> TimeInterval? {
        guard let end = feed.event.endedAt else { return nil }
        if let breast = feed.payload?.feed?.breast, !breast.isEmpty, breast.allSatisfy({ $0.durationSeconds != nil }) {
            return TimeInterval(breast.reduce(0) { $0 + max(0, $1.durationSeconds ?? 0) })
        }
        return max(0, end.timeIntervalSince(feed.event.startedAt))
    }

    /// The night before `now` while it is morning (from the day's start to 12:00).
    static func morningNight(dayHours: DayHours, timeZone: TimeZone, now: Date) -> PlainDate? {
        guard dayHours.dayStart != dayHours.nightStart, dayHours.dayStart < lastNightUntil,
              case .day(let today) = dayHours.period(at: now, in: timeZone),
              WallClock.reading(now, in: timeZone).time < lastNightUntil else { return nil }
        return dayHours.nightEnding(on: today)
    }
}

extension DayHours {
    /// The time from `start` to `end` that falls in the night named `night` (by its evening), read
    /// on the household's wall clock. Split at each change of look, as `nightAndDaySeconds`.
    func seconds(from start: Date, to end: Date, inNight night: PlainDate, timeZone: TimeZone) -> TimeInterval {
        var total: TimeInterval = 0
        var from = start
        while from < end {
            var next = nextLookChange(after: from, in: timeZone) ?? end
            if next <= from { next = end }
            let upTo = min(next, end)
            if period(at: from, in: timeZone) == .night(night) { total += upTo.timeIntervalSince(from) }
            from = upTo
        }
        return total
    }
}
