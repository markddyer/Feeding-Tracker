import Foundation
import FeedingCore

// The facts sheet behind the AI insights (`docs/planning/12-ai-insights-gauntlet.md`, step 1,
// task AI2). Code works out every number from the log; the AI never does (A1). The AI is sent
// this sheet as it is (R2): the logged numbers and times, for last night, yesterday and the 4
// weeks before, so it can look for patterns. It never holds text: no names, notes, medicine names
// or titles of firsts, and no medicine at all (A6, D6, R3). Nothing in it is a `String`, so free
// text can't be added by mistake. It is built from the same counting code as Graphs, with its
// own windows, so the time of the first opening never changes it (O5).

/// The kinds of entry the sheet speaks of. A closed list (finding 9). Medicines are not in it (D6).
public enum InsightKind: String, Hashable, Sendable, Codable, CaseIterable {
    case feed, pump, sleep, nappy, bath, weight, first
}

/// Poos by colour, from the colours this app offers. A colour it doesn't know (from a newer
/// build) counts as `other`; a poo logged with no colour counts in `notGiven`.
public struct PooColours: Hashable, Sendable, Codable {
    public var brown = 0
    public var yellow = 0
    public var green = 0
    public var pale = 0
    public var other = 0
    public var notGiven = 0

    public init() {}

    mutating func add(_ colour: PooColour?) {
        switch colour {
        case nil: notGiven += 1
        case .brown?: brown += 1
        case .yellow?: yellow += 1
        case .green?: green += 1
        case .pale?: pale += 1
        default: other += 1
        }
    }
}

/// A stretch of time, such as a sleep or a time with nothing logged.
public struct Stretch: Hashable, Sendable, Codable {
    public var from: Date
    public var to: Date

    public init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }

    public var seconds: TimeInterval { to.timeIntervalSince(from) }
}

/// One calendar day, midnight to midnight in the household's time zone.
public struct DayFacts: Hashable, Sendable, Codable, Identifiable {
    public var date: PlainDate
    public var feeds = 0
    /// Feeds with at least one breast segment. Their milk is never added up (A3).
    public var breastFeeds = 0
    /// Feeds with at least one bottle.
    public var bottleFeeds = 0
    public var leftBreastSeconds = 0
    public var rightBreastSeconds = 0
    public var formulaML = 0
    public var expressedML = 0
    /// Bottles logged with no amount: the day's bottle total leaves them out (O6).
    public var bottlesWithoutAmount = 0
    /// Feeds whose details this build can't read: they count in `feeds` only.
    public var feedsWithUnreadDetails = 0
    /// From each feed's start to the next feed's start, kept under the day the next feed started.
    public var feedGaps: [TimeInterval] = []
    public var pumpSessions = 0
    public var pumpedML = 0
    /// Pumping sessions with a side's amount missing, or details this build can't read.
    public var pumpsWithoutAmount = 0
    public var sleepSeconds: TimeInterval = 0
    /// The part of `sleepSeconds` in the rota's night hours, and the rest.
    public var nightSleepSeconds: TimeInterval = 0
    public var daySleepSeconds: TimeInterval = 0
    public var wees = 0
    public var poos = 0
    public var pooColours = PooColours()
    /// Nappies whose details this build can't read: neither a wee nor a poo is counted for them.
    public var nappiesWithUnreadDetails = 0
    /// When each bath started.
    public var baths: [Date] = []
    /// Firsts added to the journal for this day (never their titles).
    public var firstsAdded = 0
    /// Weights logged on this day (the weights themselves are in `InsightFacts.weights`).
    public var weightsLogged = 0
    /// The kinds logged on this day for the first time ever.
    public var firstEver: [InsightKind] = []
    /// The longest time in the day with nothing logged and no sleep: a forgotten entry looks like
    /// this, so a fall across such a day is left out (R6).
    public var longestEmptyStretch: Stretch?

    public init(date: PlainDate) {
        self.date = date
    }

    public var id: PlainDate { date }
}

/// One of the rota's nights, named by its evening (21:00 to 07:00 by default).
public struct NightFacts: Hashable, Sendable, Codable, Identifiable {
    public var evening: PlainDate
    public var start: Date
    public var end: Date
    public var feeds = 0
    /// From each feed's start to the next feed's start, both in the night.
    public var feedGaps: [TimeInterval] = []
    public var wees = 0
    public var poos = 0
    /// Time asleep in the night's hours.
    public var sleptSeconds: TimeInterval = 0
    /// The longest sleep in the night's hours (a sleep is cut at the night's start and end).
    public var longestSleep: Stretch?
    /// When that sleep really began, before the night's start if it began in the evening: the
    /// "comes after" pattern pairs it with the evening's bath (O7).
    public var longestSleepBegan: Date?
    /// Times the baby woke and a sleep was ended in the night (one per ending, "who does what").
    public var wakeUps = 0
    /// The longest time in the night with nothing logged and no sleep.
    public var longestEmptyStretch: Stretch?

    public init(evening: PlainDate, start: Date, end: Date) {
        self.evening = evening
        self.start = start
        self.end = end
    }

    public var id: PlainDate { evening }
}

/// Today so far, for Ask (step 3 D3 A): today's counts until now, and the times of the last feed,
/// nappy, sleep and bath (from the week Ask sends). Numbers and times only.
public struct TodaySoFar: Hashable, Sendable, Codable {
    public var day: DayFacts
    public var lastFeed: Date?
    public var lastNappy: Date?
    public var lastSleepStart: Date?
    /// Nil while the last sleep is still going.
    public var lastSleepEnd: Date?
    public var lastBath: Date?
    public var asOf: Date

    public init(day: DayFacts, lastFeed: Date?, lastNappy: Date?, lastSleepStart: Date?, lastSleepEnd: Date?,
                lastBath: Date?, asOf: Date) {
        self.day = day
        self.lastFeed = lastFeed
        self.lastNappy = lastNappy
        self.lastSleepStart = lastSleepStart
        self.lastSleepEnd = lastSleepEnd
        self.lastBath = lastBath
        self.asOf = asOf
    }
}

/// A weight, as logged.
public struct WeightFact: Hashable, Sendable, Codable {
    public var at: Date
    public var grams: Int

    public init(at: Date, grams: Int) {
        self.at = at
        self.grams = grams
    }
}

/// Everything the AI insights may say about the log, worked out by code.
public struct InsightFacts: Hashable, Sendable, Codable {
    /// How many whole days and nights back the sheet looks, ending yesterday and last night.
    public static let daysBack = 28

    /// Whole days since the birth date; nil with no birth date, or one after today.
    public var ageInDays: Int?
    /// The calendar day before today; nil when nothing was logged by then.
    public var yesterday: DayFacts?
    /// The rota's night that ended last, before now; nil with no night hours, or before anything
    /// was logged.
    public var lastNight: NightFacts?
    /// Up to 28 whole days ending yesterday, oldest first, from the first day anything was logged.
    /// Today's unfinished day is never in it (O5).
    public var days: [DayFacts] = []
    /// Up to 28 nights ending last night, oldest first, from the first night anything was logged.
    public var nights: [NightFacts] = []
    /// Every weight logged up to now, oldest first.
    public var weights: [WeightFact] = []
    /// Changes when any fact changes and never otherwise, the same on both phones for the same
    /// log (O4): a card made from an older revision is made again.
    public var revision: UInt64 = 0

    public init() {}
}

// MARK: Building it

extension InsightFacts {
    /// The facts for `babyID` at `now`. Copies logged on both phones count once, as on every
    /// screen. `now` only chooses which day and which night are the last whole ones, so two
    /// openings on the same morning give the same sheet for the same log.
    public init(_ snapshots: [EventSnapshot], babyID: String, birthDate: PlainDate?, dayHours: DayHours,
                timeZone: TimeZone, breastfeeder: Breastfeeder?, confirmedDistinct: Set<Set<String>>, now: Date) {
        self.init()
        let today = PlainDate(now, in: timeZone)
        let yesterdayDate = today.adding(days: -1)
        // Just before today began: the end of the last whole day.
        let endOfYesterday = today.firstMoment(in: timeZone).addingTimeInterval(-0.001)
        if let birthDate {
            let days = today.days(since: birthDate)
            ageInDays = days >= 0 ? days : nil
        }

        // Only the 4 weeks, with 2 days before them for the first gap between feeds, are counted, so
        // a year of entries costs no more than a month (O9).
        let from = yesterdayDate.adding(days: -Self.daysBack - 2).firstMoment(in: timeZone)
        let (all, live) = Self.entries(snapshots, babyID: babyID, from: from, confirmedDistinct: confirmedDistinct, now: now)

        let past = live.filter { $0.event.startedAt <= endOfYesterday }
        // The first day of each kind, and of anything, from the whole log.
        let firstDays = Self.firstDays(all.filter { $0.event.startedAt <= endOfYesterday }, timeZone: timeZone)
        if let first = firstDays.values.min(), first <= yesterdayDate {
            days = Self.days(past, babyID: babyID, from: max(first, yesterdayDate.adding(days: 1 - Self.daysBack)),
                             to: yesterdayDate, firstDays: firstDays, dayHours: dayHours, timeZone: timeZone,
                             endOfYesterday: endOfYesterday)
            yesterday = days.last { $0.date == yesterdayDate }
        }

        if let last = Self.lastNightEvening(now: now, dayHours: dayHours, timeZone: timeZone),
           let firstStart = all.map(\.event.startedAt).min() {
            let who = WhoDidIt(live, babyID: babyID, breastfeeder: breastfeeder, confirmedDistinct: confirmedDistinct,
                               dayHours: dayHours, timeZone: timeZone, now: now)
            nights = (0..<Self.daysBack).reversed().compactMap { back -> NightFacts? in
                let evening = last.adding(days: -back)
                guard let window = Self.nightWindow(evening, dayHours: dayHours, timeZone: timeZone),
                      window.end > firstStart else { return nil }
                return Self.night(evening, window: window, live: live, babyID: babyID, who: who)
            }
            lastNight = nights.last { $0.evening == last }
        }

        weights = FeedingCore.weights(all, babyID: babyID).map { WeightFact(at: $0.at, grams: $0.grams) }
        revision = Self.revision(of: self)
    }

    /// The baby's entries up to `now` (`all`; entries after now, from a clock set back, are left
    /// out), and those from `from` with copies logged on both phones counted once, as on every
    /// screen (`live`). Medicines never reach the sheet (D6).
    static func entries(_ snapshots: [EventSnapshot], babyID: String, from: Date, confirmedDistinct: Set<Set<String>>,
                        now: Date) -> (all: [EventSnapshot], live: [EventSnapshot]) {
        let all = snapshots.filter {
            $0.event.babyID == babyID && $0.event.deletedAt == nil && $0.event.kind != .medicine && $0.event.startedAt <= now
        }
        let recent = all.filter { $0.event.startedAt >= from }
        let pairs = duplicateFeeds(recent.map(\.event), confirmedDistinct: confirmedDistinct)
            + duplicateCareEntries(recent, confirmedDistinct: confirmedDistinct)
        let hidden = Set(pairs.map(\.duplicate))
        return (all, recent.filter { !hidden.contains($0.id) })
    }

    // MARK: Today so far (Ask, step 3 D3 A)

    /// Today's counts so far and the times of the last feed, nappy, sleep and bath, for Ask: the
    /// same counting as the sheet's days, with "now" in place of the end of yesterday. Numbers and
    /// times only: no notes, no medicines.
    public static func todaySoFar(_ snapshots: [EventSnapshot], babyID: String, dayHours: DayHours, timeZone: TimeZone,
                                  confirmedDistinct: Set<Set<String>>, now: Date) -> TodaySoFar {
        let today = PlainDate(now, in: timeZone)
        // Two days back, for the first gap between feeds and a sleep that began before midnight;
        // the last of each kind is looked for over the week Ask sends.
        let from = today.adding(days: -InsightQuestions.daysSent).firstMoment(in: timeZone)
        let (_, live) = entries(snapshots, babyID: babyID, from: from, confirmedDistinct: confirmedDistinct, now: now)
        let day = days(live, babyID: babyID, from: today, to: today, firstDays: [:], dayHours: dayHours,
                       timeZone: timeZone, endOfYesterday: now).first ?? DayFacts(date: today)
        func last(_ kind: EventKind) -> EventSnapshot? {
            live.filter { $0.event.kind == kind }.max { $0.event.startedAt < $1.event.startedAt }
        }
        let sleep = last(.sleep)
        return TodaySoFar(day: day, lastFeed: last(.feed)?.event.startedAt, lastNappy: last(.nappy)?.event.startedAt,
                          lastSleepStart: sleep?.event.startedAt, lastSleepEnd: sleep?.event.endedAt,
                          lastBath: last(.bath)?.event.startedAt, asOf: now)
    }

    // MARK: Days

    private static func days(_ past: [EventSnapshot], babyID: String, from start: PlainDate, to end: PlainDate,
                             firstDays: [InsightKind: PlainDate], dayHours: DayHours, timeZone: TimeZone,
                             endOfYesterday: Date) -> [DayFacts] {
        let count = end.days(since: start) + 1
        guard count > 0 else { return [] }
        // The same counting as Graphs, with "now" just before today began, so today never counts.
        let graph = Dictionary(graphDays(past, babyID: babyID, timeZone: timeZone, range: .fourWeeks, now: endOfYesterday)
            .map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let rhythm = Dictionary(rhythmDays(past, babyID: babyID, timeZone: timeZone, dayHours: dayHours, range: .fourWeeks,
                                           now: endOfYesterday).map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let sleeps = sleepStretches(past.map(\.event), babyID: babyID, now: endOfYesterday)

        return (0..<count).map { offset in
            let date = start.adding(days: offset)
            let dayStart = date.firstMoment(in: timeZone)
            let dayEnd = date.adding(days: 1).firstMoment(in: timeZone)
            var day = DayFacts(date: date)
            if let g = graph[date] {
                day.feeds = g.feeds
                day.formulaML = g.formulaML
                day.expressedML = g.expressedML
                day.leftBreastSeconds = g.leftSeconds
                day.rightBreastSeconds = g.rightSeconds
                day.pumpSessions = g.pumpSessions
                day.pumpedML = g.pumpedML
                day.feedGaps = g.gaps
            }
            if let r = rhythm[date] {
                day.nightSleepSeconds = r.nightSleepSeconds
                day.daySleepSeconds = r.daySleepSeconds
                day.sleepSeconds = r.sleepSeconds
            }
            let entries = past.filter { $0.event.startedAt >= dayStart && $0.event.startedAt < dayEnd }
            for entry in entries {
                switch entry.event.kind {
                case .feed:
                    guard let payload = entry.payload else { day.feedsWithUnreadDetails += 1; continue }
                    let feed = payload.feed ?? FeedDetails()
                    if !feed.breast.isEmpty { day.breastFeeds += 1 }
                    if !feed.bottles.isEmpty { day.bottleFeeds += 1 }
                    day.bottlesWithoutAmount += feed.bottles.filter { $0.ml == nil }.count
                case .pump:
                    if Self.pumpMissesAmount(entry.payload) { day.pumpsWithoutAmount += 1 }
                case .nappy:
                    guard let nappy = entry.payload?.nappy else { day.nappiesWithUnreadDetails += 1; continue }
                    if nappy.wee { day.wees += 1 }
                    if nappy.poo {
                        day.poos += 1
                        day.pooColours.add(nappy.colour)
                    }
                case .bath:
                    day.baths.append(entry.event.startedAt)
                case .milestone:
                    day.firstsAdded += 1
                case .growth:
                    if entry.payload?.growth?.weightGrams != nil { day.weightsLogged += 1 }
                default:
                    break
                }
            }
            day.baths.sort()
            day.firstEver = InsightKind.allCases.filter { firstDays[$0] == date }
            day.longestEmptyStretch = Self.longestEmptyStretch(from: dayStart, to: min(dayEnd, endOfYesterday),
                                                               busy: Self.busy(entries, sleeps: sleeps))
            return day
        }
    }

    /// A side's amount is missing, or the details can't be read (O6).
    private static func pumpMissesAmount(_ payload: EventPayload?) -> Bool {
        guard let pump = payload?.pump else { return true }
        switch pump.side {
        case .left: return pump.leftML == nil
        case .right: return pump.rightML == nil
        case .both: return pump.leftML == nil || pump.rightML == nil
        }
    }

    /// The first day each kind was ever logged, in the household's time zone.
    private static func firstDays(_ entries: [EventSnapshot], timeZone: TimeZone) -> [InsightKind: PlainDate] {
        var first: [InsightKind: PlainDate] = [:]
        for entry in entries {
            guard let kind = insightKind(entry) else { continue }
            let day = PlainDate(entry.event.startedAt, in: timeZone)
            if first[kind].map({ day < $0 }) ?? true { first[kind] = day }
        }
        return first
    }

    private static func insightKind(_ entry: EventSnapshot) -> InsightKind? {
        switch entry.event.kind {
        case .feed: .feed
        case .pump: .pump
        case .sleep: .sleep
        case .nappy: .nappy
        case .bath: .bath
        case .growth: entry.payload?.growth?.weightGrams == nil ? nil : .weight
        case .milestone: .first
        default: nil
        }
    }

    // MARK: Nights

    /// The rota's night that ended last, before `now`. Nil with no night hours.
    static func lastNightEvening(now: Date, dayHours: DayHours, timeZone: TimeZone) -> PlainDate? {
        guard dayHours.dayStart != dayHours.nightStart else { return nil }
        var candidate: PlainDate
        if case .night(let current) = dayHours.period(at: now, in: timeZone) {
            candidate = current.adding(days: -1)
        } else {
            candidate = dayHours.nightEnding(on: PlainDate(now, in: timeZone))
        }
        for _ in 0..<3 {
            if let window = nightWindow(candidate, dayHours: dayHours, timeZone: timeZone), window.end <= now { return candidate }
            candidate = candidate.adding(days: -1)
        }
        return nil
    }

    /// From the start to the end of the night named `evening`, on the household's wall clock, clock
    /// changes included. Nil with no night hours.
    public static func nightWindow(_ evening: PlainDate, dayHours: DayHours, timeZone: TimeZone) -> (start: Date, end: Date)? {
        var from = evening.firstMoment(in: timeZone)
        if dayHours.period(at: from, in: timeZone) == .night(evening) {
            return dayHours.nextLookChange(after: from, in: timeZone).map { (from, $0) }
        }
        for _ in 0..<4 {
            guard let change = dayHours.nextLookChange(after: from, in: timeZone) else { return nil }
            if dayHours.period(at: change, in: timeZone) == .night(evening) {
                return dayHours.nextLookChange(after: change, in: timeZone).map { (change, $0) }
            }
            from = change
        }
        return nil
    }

    private static func night(_ evening: PlainDate, window: (start: Date, end: Date), live: [EventSnapshot],
                              babyID: String, who: WhoDidIt) -> NightFacts {
        var night = NightFacts(evening: evening, start: window.start, end: window.end)
        let entries = live.filter { $0.event.startedAt >= window.start && $0.event.startedAt < window.end }
        let feedStarts = entries.filter { $0.event.kind == .feed }.map(\.event.startedAt).sorted()
        night.feeds = feedStarts.count
        night.feedGaps = zip(feedStarts, feedStarts.dropFirst()).map { $1.timeIntervalSince($0) }
        for entry in entries where entry.event.kind == .nappy {
            guard let nappy = entry.payload?.nappy else { continue }
            if nappy.wee { night.wees += 1 }
            if nappy.poo { night.poos += 1 }
        }
        // Sleeps cut at the night's end, so a sleep still running when the card is made, or one that
        // runs on into the morning, counts the same at every opening.
        let whole = sleepStretches(live.map(\.event), babyID: babyID, now: window.end)
        let sleeps = whole.compactMap { stretch -> Stretch? in
            let from = max(stretch.start, window.start)
            let to = min(stretch.end, window.end)
            return to > from ? Stretch(from: from, to: to) : nil
        }
        night.sleptSeconds = sleeps.reduce(0) { $0 + $1.seconds }
        night.longestSleep = sleeps.max { ($0.seconds, $1.from) < ($1.seconds, $0.from) }
        night.longestSleepBegan = night.longestSleep.flatMap { longest in
            whole.first { $0.start <= longest.from && $0.end >= longest.to }?.start
        }
        night.wakeUps = who.entries(.gotUpAtNight, range: .day(evening)).count
        night.longestEmptyStretch = longestEmptyStretch(from: window.start, to: window.end,
                                                        busy: busy(entries, sleeps: sleeps.map { (start: $0.from, end: $0.to) }))
        return night
    }

    // MARK: Nothing logged

    /// The times something was logged or the baby slept: each entry from its start to its end (or
    /// just its start), and each sleep. Firsts are left out: they are added later about a moment.
    private static func busy(_ entries: [EventSnapshot], sleeps: [(start: Date, end: Date)]) -> [(Date, Date)] {
        entries.filter { $0.event.kind != .milestone }
            .map { ($0.event.startedAt, max($0.event.startedAt, $0.event.endedAt ?? $0.event.startedAt)) }
            + sleeps.map { ($0.start, $0.end) }
    }

    /// The longest stretch from `start` to `end` that no busy time touches; the earliest of equals.
    static func longestEmptyStretch(from start: Date, to end: Date, busy: [(Date, Date)]) -> Stretch? {
        guard end > start else { return nil }
        var cursor = start
        var best: Stretch?
        func consider(_ from: Date, _ to: Date) {
            guard to > from else { return }
            if best.map({ to.timeIntervalSince(from) > $0.seconds }) ?? true { best = Stretch(from: from, to: to) }
        }
        for (from, to) in busy.sorted(by: { $0.0 < $1.0 }) where to >= start && from <= end {
            consider(cursor, max(from, start))
            cursor = max(cursor, min(to, end))
        }
        consider(cursor, end)
        return best
    }

    // MARK: Revision

    /// A number that changes when any fact changes: FNV-1a over the sheet's JSON with sorted keys.
    /// The sheet has no dictionaries or sets, so its JSON is the same for the same facts.
    static func revision(of facts: InsightFacts) -> UInt64 {
        var copy = facts
        copy.revision = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(copy)) ?? Data()
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

extension HouseholdData {
    /// The facts sheet for `babyID`, from everything this phone holds.
    public func insightFacts(babyID: String, now: Date) -> InsightFacts {
        let settings = householdSettings
        return InsightFacts(snapshots, babyID: babyID, birthDate: birthDate(babyID: babyID), dayHours: settings.dayHours,
                            timeZone: settings.timeZone, breastfeeder: breastfeeder, confirmedDistinct: distinctFeedPairs,
                            now: now)
    }

    /// Today so far, for Ask (step 3 D3 A).
    public func todaySoFar(babyID: String, now: Date) -> TodaySoFar {
        let settings = householdSettings
        return InsightFacts.todaySoFar(snapshots, babyID: babyID, dayHours: settings.dayHours, timeZone: settings.timeZone,
                                       confirmedDistinct: distinctFeedPairs, now: now)
    }
}
