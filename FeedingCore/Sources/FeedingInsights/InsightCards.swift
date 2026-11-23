import Foundation
import FeedingCore

// The shared AI cards (step 2 of `docs/planning/12-ai-insights-gauntlet.md`, task AI7): the morning
// card (last night and yesterday, D13, D14) and "This week" (last Monday to Sunday, step 2 D5).
// Every rule lives here, tested on Linux (step 2 D1): what is sent (O8), the form the AI fills (a
// form of choices only, built for each card: D3, D9), when a card is due or made again (D4, with
// O4), the two-yes gate (D12, S8, O2), the pause after "this was wrong" (A7), the two stored
// records (D8) and the check before saving (D10). The app only turns the form into Apple's and
// makes the call (`App/Insights/InsightEngine.swift`).

// MARK: - Which card, and which days

public enum CardKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// Last night and yesterday, made at the first open after the night ends.
    case morning
    /// Last Monday to Sunday, made at the first open from Monday morning.
    case week

    var settingKey: String { "insightCard-\(rawValue)" }
}

/// The days and nights a card covers, named outright, so a stored card never drifts to another
/// day (O3).
public struct CardPeriod: Hashable, Sendable, Codable {
    public var kind: CardKind
    public var days: DateSpan
    /// The nights, by their evenings.
    public var nights: DateSpan?

    public init(kind: CardKind, days: DateSpan, nights: DateSpan?) {
        self.kind = kind
        self.days = days
        self.nights = nights
    }

    var lastDate: PlainDate { max(days.last, nights?.last ?? days.last) }

    func isNewer(than other: CardPeriod) -> Bool { lastDate > other.lastDate }
}

// MARK: - What is sent (O8)

/// One NHS passage offered for a card, with its checked summaries: the AI may pick one by ID.
public struct OfferedPassage: Hashable, Sendable, Codable {
    public var id: String
    public var page: String
    public var summaries: [OfferedSummary]
}

public struct OfferedSummary: Hashable, Sendable, Codable {
    public var id: String
    public var words: String
}

/// Exactly what leaves the phone for a card, and what "What the AI sees" shows: the facts sheet's
/// numbers and times for 4 weeks, the age in whole weeks (never the birth date, A6), the weights
/// of those weeks and the one before them (R2), and the passages offered. No text from the log,
/// no names and no medicines: nothing in it is free text (A6, D6).
public struct CardRequest: Hashable, Sendable, Codable {
    public var period: CardPeriod
    public var ageInWeeks: Int?
    public var days: [DayFacts]
    public var nights: [NightFacts]
    public var weights: [WeightFact]
    public var passages: [OfferedPassage]
}

// MARK: - The form the AI fills (D3, D9)

/// The AI's form, as plain data, built for each card: the app turns it into Apple's run-time form.
/// On a card every value is a choice from a list: the AI writes no words. Ask's form alone has
/// `text`, for its up to 2 checked sentences (step 3 D2 B).
public indirect enum FormNode: Hashable, Sendable {
    case object(name: String, fields: [FormField])
    case list(of: FormNode, maximum: Int)
    case oneOf([String])
    case yesNo
    case text(maximumLength: Int)
}

public struct FormField: Hashable, Sendable {
    public var name: String
    public var about: String
    public var node: FormNode

    public init(name: String, about: String, node: FormNode) {
        self.name = name
        self.about = about
        self.node = node
    }
}

/// One card's form: its facts, patterns and passages, each limited to what this card may name.
public struct CardForm: Hashable, Sendable {
    public var root: FormNode

    public init(root: FormNode) {
        self.root = root
    }
}

// MARK: - The stored card (D8)

/// A shared card, kept as a household setting (encrypted in iCloud), one record per kind: the AI's
/// choices, what was offered, and the entries it saw. Each phone checks it against its own log
/// before showing it (S5, O3).
public struct StoredCard: Hashable, Sendable, Codable {
    public var period: CardPeriod
    public var choices: CardChoices
    /// The passages chosen by code for this card (O6).
    public var offered: [String]
    /// The entries for its days it saw, by ID, with their change time (O4).
    public var seen: [String: Date]
    /// How many cards were made for this period (S3: at most 3).
    public var made: Int
    public var madeAt: Date

    public init(period: CardPeriod, choices: CardChoices, offered: [String], seen: [String: Date], made: Int,
                madeAt: Date) {
        self.period = period
        self.choices = choices
        self.offered = offered
        self.seen = seen
        self.made = made
        self.madeAt = madeAt
    }
}

// MARK: - Each parent's yes (D12) and "this was wrong" (A7)

/// A parent's yes to sending the facts to Anthropic, given on their own phone. `yes` false is
/// "off": either parent turning it off stops it for both.
public struct InsightYes: Hashable, Sendable, Codable {
    public var yes: Bool
    /// The version of what they agreed to: a new version asks again.
    public var version: Int
    public var at: Date

    public init(yes: Bool, version: Int, at: Date) {
        self.yes = yes
        self.version = version
        self.at = at
    }
}

/// The "this was wrong" reports, one list for the household, and when a parent last switched
/// the AI back on after a pause.
public struct WrongReports: Hashable, Sendable, Codable {
    public var dates: [Date] = []
    public var resumedAt: Date?

    public init(dates: [Date] = [], resumedAt: Date? = nil) {
        self.dates = dates
        self.resumedAt = resumedAt
    }
}

/// Why no AI card is made or shown.
public enum CardClosed: Hashable, Sendable {
    /// Not every parent has said yes (or the version changed).
    case waitingForYes
    /// A parent turned it off.
    case turnedOff
    /// Two "this was wrong" reports in 30 days (A7).
    case paused
    /// The household's members aren't known yet on this phone (after a launch, a sign-out or an
    /// account switch): a stored card may show, nothing is sent (O2).
    case notChecked
    /// A card is due but can't be made now: the 10-minute wait or this phone's calls for the
    /// period are used up (S14, D10).
    case later
}

/// What a screen shows for one kind of card (AI11).
public enum CardOnScreen: Hashable, Sendable {
    /// No card yet (no night, or under 3 days logged in the week), or the AI isn't on (no yes from
    /// both, or turned off): nothing new on screen.
    case nothing
    /// The shared card, checked against this phone's log; `period` is the card's own.
    case card(CheckedCard, period: CardPeriod)
    /// The AI is on but no card for now can be shown: being made, or the facts only. `plain` is
    /// the morning's facts-only card.
    case noCard(CardPeriod, plain: PlainCard?)
    /// Paused after two "this was wrong" reports (A7): the facts only.
    case paused(CardPeriod, plain: PlainCard?)
}

/// The morning card with no AI (S12): the app's fixed facts and the passages offered.
public struct PlainCard: Hashable, Sendable {
    public let period: CardPeriod
    public let lines: [String]
    /// The fact behind each line, in order.
    public let refs: [FactRef]
    public let passages: [Passage]
}

extension FactScope {
    /// The day or night (by its evening) a fact is about; nil for the latest weight.
    public var date: PlainDate? {
        switch self {
        case .day(let date), .night(let date): date
        case .yesterday, .lastNight, .latest: nil
        }
    }

    public var isNight: Bool {
        switch self {
        case .night, .lastNight: true
        case .day, .yesterday, .latest: false
        }
    }
}

extension Measure {
    /// The graph page a fact or pattern about this measure opens (AI11, `10-graph-pages.md`);
    /// nil when no graph shows it.
    public var graph: GraphKind? {
        switch self {
        case .feeds, .breastFeeds, .bottleFeeds: .feeds
        case .bottleML: .bottles
        case .pumpSessions, .pumpedML: .pumped
        case .sleep, .daySleep, .nightSleep, .slept, .longestSleep, .longestSleepStart, .wakeUps: .asleep
        case .wees, .poos: .nappies
        case .longestGap, .shortestGap: .gaps
        case .weight, .weightChange: .weight
        case .baths: nil
        }
    }
}

/// What the app does for one kind of card now.
public enum CardPlan: Hashable, Sendable {
    /// Nothing to show (no night or week yet).
    case none
    /// No AI: the facts-only card. A stored card comes along only when it may still be shown.
    case closed(CardClosed, StoredCard?)
    case show(StoredCard)
    /// Make a card (the first for its period, or again for entries the stored one didn't see),
    /// showing `showing` meanwhile.
    case make(CardJob, showing: StoredCard?)
}

/// A card to make: the request sent, its form, and what to store with the answer.
public struct CardJob: Hashable, Sendable {
    public var request: CardRequest
    public var form: CardForm
    public var offered: [String]
    public var seen: [String: Date]
    /// What `made` will be once this card is stored.
    public var made: Int
}

/// This phone's own count of calls for a period (D10): kept on the phone, never synced.
public struct LocalCardTries: Hashable, Sendable, Codable {
    public var period: CardPeriod?
    public var calls: Int
    public var lastTry: Date?

    public init(period: CardPeriod? = nil, calls: Int = 0, lastTry: Date? = nil) {
        self.period = period
        self.calls = calls
        self.lastTry = lastTry
    }

    /// One more call for `period`, failed or not.
    public mutating func record(_ period: CardPeriod, at now: Date) {
        if self.period != period { self = LocalCardTries(period: period) }
        calls += 1
        lastTry = now
    }
}

// MARK: - The rules

public enum InsightCards {
    /// The version of what the parents agree to: raising it asks both again.
    public static let consentVersion = 1
    /// S3 (step 2 D4 A): at most 3 cards for a period, and not within 10 minutes of the last.
    public static let maxCards = 3
    public static let wait: TimeInterval = 10 * 60
    /// D10 B: at most 6 calls a period on each phone, failed calls included.
    public static let maxCalls = 6
    /// A7: two "this was wrong" reports within 30 days pause the AI for both phones.
    public static let pauseAfterReports = 2
    public static let reportWindow: TimeInterval = 30 * 24 * 3600
    /// A card's limits (the plan: up to 6 facts, 3 patterns, 1 or 2 passages).
    public static let maxPassages = 2

    // MARK: Periods

    /// The morning card's period: last night and yesterday, once the night has ended.
    public static func morningPeriod(_ facts: InsightFacts) -> CardPeriod? {
        guard let night = facts.lastNight else { return nil }
        let day = facts.yesterday?.date ?? night.evening
        return CardPeriod(kind: .morning, days: DateSpan(day, day), nights: DateSpan(night.evening, night.evening))
    }

    /// "This week": the last whole Monday to Sunday, from Monday's rota morning (step 2 D5).
    public static func weekPeriod(now: Date, dayHours: DayHours, timeZone: TimeZone) -> CardPeriod {
        let today = PlainDate(now, in: timeZone)
        let morning = InsightFacts.nightWindow(today.adding(days: -1), dayHours: dayHours, timeZone: timeZone)?.end
        let reference = (morning.map { now >= $0 } ?? true) ? today : today.adding(days: -1)
        let lastDay = reference.adding(days: -1)
        let sunday = lastDay.adding(days: -(lastDay.weekday % 7))
        let monday = sunday.adding(days: -6)
        return CardPeriod(kind: .week, days: DateSpan(monday, sunday), nights: DateSpan(monday, sunday))
    }

    static func period(_ kind: CardKind, facts: InsightFacts, now: Date, dayHours: DayHours,
                       timeZone: TimeZone) -> CardPeriod? {
        switch kind {
        case .morning:
            return morningPeriod(facts)
        case .week:
            let week = weekPeriod(now: now, dayHours: dayHours, timeZone: timeZone)
            let logged = facts.days.filter { week.days.dates.contains($0.date) }.count
            return logged >= 3 ? week : nil
        }
    }

    // MARK: The entries a card saw (O4)

    /// The entries for a period's days and nights, by ID, with their change time: deleted entries
    /// too, so a deletion counts as a change. Medicines aren't on a card's facts.
    static func seen(_ period: CardPeriod, snapshots: [EventSnapshot], babyID: String, dayHours: DayHours,
                     timeZone: TimeZone) -> [String: Date] {
        let window = window(period, dayHours: dayHours, timeZone: timeZone)
        var seen: [String: Date] = [:]
        for snapshot in snapshots where snapshot.event.babyID == babyID && snapshot.event.kind != .medicine {
            if window.contains(snapshot.event.startedAt) { seen[snapshot.event.id] = snapshot.event.modifiedAt }
        }
        return seen
    }

    /// The time a card's days and nights cover: from the first moment of its first day or night to
    /// the end of its last day, or of its last night if later. The card's medicine chips (R3) are
    /// the medicines given in it.
    public static func window(_ period: CardPeriod, dayHours: DayHours, timeZone: TimeZone) -> Range<Date> {
        let start = min(period.days.first, period.nights?.first ?? period.days.first).firstMoment(in: timeZone)
        var end = period.days.last.adding(days: 1).firstMoment(in: timeZone)
        if let lastNight = period.nights?.last,
           let window = InsightFacts.nightWindow(lastNight, dayHours: dayHours, timeZone: timeZone) {
            end = max(end, window.end)
        }
        return start..<max(start, end)
    }

    // MARK: Showing a card (AI11)

    /// What a screen shows for `kind` now, from one facts sheet. The engine's state ("Making…", or
    /// why none was made) is the app's to add.
    public static func onScreen(_ kind: CardKind, data: HouseholdData, babyID: String, me: MemberID?,
                                now: Date) -> CardOnScreen {
        // The gate first: with the AI not on (most of the time, for most households) Home doesn't
        // build the facts sheet at all.
        let shown = gate(data, me: me, participants: nil, now: now).show
        if shown == .waitingForYes || shown == .turnedOff { return .nothing }
        let settings = data.householdSettings
        let facts = data.insightFacts(babyID: babyID, now: now)
        guard let period = period(kind, facts: facts, now: now, dayHours: settings.dayHours,
                                  timeZone: settings.timeZone) else { return .nothing }
        if shown == .paused { return .paused(period, plain: plainCard(period, facts: facts, data: data)) }
        if let stored = data.insightCard(kind), isCurrent(stored, for: period),
           let checked = show(stored, facts: facts, data: data) {
            return .card(checked, period: stored.period)
        }
        return .noCard(period, plain: plainCard(period, facts: facts, data: data))
    }

    /// The days and nights a card of `kind` would cover now; nil when there is none yet.
    public static func currentPeriod(_ kind: CardKind, data: HouseholdData, babyID: String, now: Date) -> CardPeriod? {
        let settings = data.householdSettings
        return period(kind, facts: data.insightFacts(babyID: babyID, now: now), now: now, dayHours: settings.dayHours,
                      timeZone: settings.timeZone)
    }

    /// The morning's card with no AI (S12, "Facts only today"): fixed facts the app writes, with
    /// the same wording as a card, and the NHS passages the chooser offers, without summaries. Nil
    /// before the first night, or when none of its facts is on the sheet. "This week" has none: its
    /// facts are the graphs.
    public static func plainCard(_ data: HouseholdData, babyID: String, now: Date) -> PlainCard? {
        let facts = data.insightFacts(babyID: babyID, now: now)
        guard let period = morningPeriod(facts) else { return nil }
        return plainCard(period, facts: facts, data: data)
    }

    static func plainCard(_ period: CardPeriod, facts: InsightFacts, data: HouseholdData) -> PlainCard? {
        guard period.kind == .morning else { return nil }
        let settings = data.householdSettings
        var refs: [FactRef] = []
        if let night = period.nights?.last {
            refs += [FactRef(.night(night), .feeds), FactRef(.night(night), .longestSleep)]
        }
        let day = period.days.last
        refs += [FactRef(.day(day), .feeds), FactRef(.day(day), .wees), FactRef(.day(day), .poos)]
        var lines: [String] = []
        var kept: [FactRef] = []
        for ref in refs {
            guard let line = CardWording.fact(ref, facts: facts, timeZone: settings.timeZone) else { continue }
            lines.append(line)
            kept.append(ref)
        }
        guard !lines.isEmpty else { return nil }
        let passages = request(period, facts: facts, data: data).1.compactMap(NHSPassages.passage)
        return PlainCard(period: period, lines: lines, refs: kept, passages: passages)
    }

    /// Whether `now` holds an entry `before` didn't, or a later change to one it did: an entry
    /// moved out of the period counts by its change time.
    static func hasNewer(_ now: [String: Date], than before: [String: Date], snapshots: [EventSnapshot]) -> Bool {
        for (id, changed) in now where before[id].map({ changed > $0 }) ?? true { return true }
        let changes = Dictionary(snapshots.map { ($0.event.id, $0.event.modifiedAt) }, uniquingKeysWith: max)
        for (id, saw) in before where now[id] == nil {
            if let changed = changes[id], changed > saw { return true }
        }
        return false
    }

    /// Whether `first` saw an entry `second` didn't, or a later change to one: then `second` was
    /// made from fewer entries and isn't saved over it (D10).
    static func sawMore(_ first: [String: Date], than second: [String: Date]) -> Bool {
        first.contains { id, changed in second[id].map { changed > $0 } ?? true }
    }

    // MARK: The gate (D12, S8, O2, A7)

    /// Whether a card may be shown, and whether one may be made now. `participants` are the
    /// household share's participants as read from iCloud on this phone, nil until read (and
    /// again after a sign-out, an account switch or a share change); `me` is this phone's iCloud
    /// user.
    public static func gate(_ data: HouseholdData, me: MemberID?, participants: Set<MemberID>?,
                            now: Date) -> (show: CardClosed?, make: CardClosed?) {
        let yeses = data.insightYeses
        if isPaused(data.wrongReports, now: now) { return (.paused, .paused) }
        if yeses.values.contains(where: { !$0.yes }) { return (.turnedOff, .turnedOff) }
        let current = yeses.filter { $0.value.yes && $0.value.version == consentVersion }
        guard let participants else {
            return (current.count >= 2 ? nil : .waitingForYes, .notChecked)
        }
        if let off = participants.first(where: { yeses[$0]?.yes == false }) { _ = off; return (.turnedOff, .turnedOff) }
        guard participants.count >= 2, participants.allSatisfy({ current[$0] != nil }) else {
            return (.waitingForYes, .waitingForYes)
        }
        guard let me, participants.contains(me) else { return (nil, .notChecked) }
        return (nil, nil)
    }

    static func isPaused(_ reports: WrongReports, now: Date) -> Bool {
        wrongCount(reports, now: now) >= pauseAfterReports
    }

    /// The "this was wrong" reports that count towards a pause now: those in the last 30 days and
    /// since the AI was last switched back on. Settings shows this number.
    public static func wrongCount(_ reports: WrongReports, now: Date) -> Int {
        let since = max(reports.resumedAt ?? .distantPast, now.addingTimeInterval(-reportWindow))
        return reports.dates.filter { $0 > since && $0 <= now }.count
    }

    // MARK: The plan

    /// What to do for `kind` now. `tries` is this phone's own count of calls (D10).
    public static func plan(_ kind: CardKind, data: HouseholdData, babyID: String, me: MemberID?,
                            participants: Set<MemberID>?, tries: LocalCardTries, now: Date) -> CardPlan {
        let settings = data.householdSettings
        let facts = data.insightFacts(babyID: babyID, now: now)
        guard let period = period(kind, facts: facts, now: now, dayHours: settings.dayHours,
                                  timeZone: settings.timeZone) else { return .none }
        let gate = gate(data, me: me, participants: participants, now: now)
        let stored = data.insightCard(kind)
        if let closed = gate.show { return .closed(closed, nil) }
        if let closed = gate.make {
            if let stored { return .closed(closed, stored) }
            return .closed(closed, nil)
        }

        let snapshots = data.snapshots
        let seenNow = seen(period, snapshots: snapshots, babyID: babyID, dayHours: settings.dayHours,
                           timeZone: settings.timeZone)
        var made = 1
        if let stored {
            if stored.period.isNewer(than: period) { return .show(stored) }
            if stored.period == period {
                guard hasNewer(seenNow, than: stored.seen, snapshots: snapshots), stored.made < maxCards,
                      now >= stored.madeAt.addingTimeInterval(wait) else { return .show(stored) }
                made = stored.made + 1
            }
        }
        let samePeriod = stored.flatMap { $0.period == period ? $0 : nil }
        let calls = tries.period == period ? tries.calls : 0
        if calls >= maxCalls || (tries.period == period && tries.lastTry.map { now < $0.addingTimeInterval(wait) } ?? false) {
            return samePeriod.map { .show($0) } ?? .closed(.later, nil)
        }
        let (request, offered) = self.request(period, facts: facts, data: data)
        let job = CardJob(request: request, form: form(for: request, facts: facts), offered: offered, seen: seenNow,
                          made: made)
        return .make(job, showing: samePeriod)
    }

    // MARK: The request (O8)

    /// What a card of `kind` would send now, whatever the gate says: Settings' "What the AI sees"
    /// (A8, O8) shows it, and `plan` sends the same request. Nil when there is no card to make
    /// (no night or week yet).
    public static func preview(_ kind: CardKind, data: HouseholdData, babyID: String, now: Date) -> CardRequest? {
        let settings = data.householdSettings
        let facts = data.insightFacts(babyID: babyID, now: now)
        guard let period = period(kind, facts: facts, now: now, dayHours: settings.dayHours,
                                  timeZone: settings.timeZone) else { return nil }
        return request(period, facts: facts, data: data).0
    }

    /// Whether `stored` is the card for `period` (or a later one), so it is shown rather than made.
    public static func isCurrent(_ stored: StoredCard, for period: CardPeriod) -> Bool {
        stored.period == period || stored.period.isNewer(than: period)
    }

    /// The request for `period` from the household's facts and ticks: the one way `plan` and
    /// `preview` build it.
    static func request(_ period: CardPeriod, facts: InsightFacts, data: HouseholdData) -> (CardRequest, [String]) {
        let breastfeeds = facts.days.contains { $0.breastFeeds > 0 }
        let bottleFeeds = facts.days.contains { $0.bottleFeeds > 0 }
        return request(period, facts: facts, checks: data.passageChecks, breastfeeds: breastfeeds,
                       bottleFeeds: bottleFeeds, timeZone: data.householdSettings.timeZone)
    }

    /// What is sent for a card, and the passages offered with it.
    public static func request(_ period: CardPeriod, facts: InsightFacts, checks: PassageChecks, breastfeeds: Bool,
                               bottleFeeds: Bool, timeZone: TimeZone) -> (CardRequest, [String]) {
        var kinds = facts.kindsLogged
        if period.kind == .week {
            kinds = []
            for day in facts.days where period.days.dates.contains(day.date) {
                if day.feeds > 0 { kinds.insert(.feed) }
                if day.pumpSessions > 0 { kinds.insert(.pump) }
                if day.sleepSeconds > 0 { kinds.insert(.sleep) }
                if day.wees + day.poos + day.nappiesWithUnreadDetails > 0 { kinds.insert(.nappy) }
                if !day.baths.isEmpty { kinds.insert(.bath) }
                if day.weightsLogged > 0 { kinds.insert(.weight) }
            }
        }
        var passages: [Passage] = []
        if let today = facts.today {
            passages = NHSPassages.choose(kinds: kinds, ageInDays: facts.ageInDays, breastfeeds: breastfeeds,
                                          bottleFeeds: bottleFeeds, checks: checks, today: today, limit: maxPassages)
        }
        let offered = passages.map { passage in
            OfferedPassage(id: passage.id, page: passage.page,
                           summaries: facts.today.map { today in
                               NHSPassages.checkedSummaries(of: passage, checks: checks, today: today)
                                   .map { OfferedSummary(id: $0.id, words: $0.words) }
                           } ?? [])
        }
        // The weights of the sheet's 4 weeks, and the one before them for the change (R2).
        var weights = facts.weights
        if let first = facts.days.first?.date.firstMoment(in: timeZone) {
            let before = weights.lastIndex { $0.at < first }
            weights = weights.enumerated().filter { index, weight in weight.at >= first || index == before }.map(\.element)
        }
        let request = CardRequest(period: period, ageInWeeks: facts.ageInDays.map { $0 / 7 }, days: facts.days,
                                  nights: facts.nights, weights: weights, passages: offered)
        return (request, passages.map(\.id))
    }

    /// The text sent: the instructions, then the request as JSON with times in the household's
    /// time zone. "What the AI sees" shows the same.
    public static func prompt(_ request: CardRequest, timeZone: TimeZone) -> String {
        instructions(for: request.period.kind) + "\n\nTHE LOG (JSON):\n" + json(request, timeZone: timeZone)
    }

    /// The same text spaced out for reading, for "What the AI sees": the same instructions and
    /// the same log, value for value; only the spaces and line breaks between them differ.
    public static func readablePrompt(_ request: CardRequest, timeZone: TimeZone) -> String {
        instructions(for: request.period.kind) + "\n\nTHE LOG (JSON):\n" + json(request, timeZone: timeZone, readable: true)
    }

    /// The log as JSON. It is sent with no spaces or line breaks: 29% fewer tokens than spaced out
    /// (AI13 measured about 26,000 tokens a card spaced out; Parent A's D1 A, 23 Nov 2026).
    public static func json(_ request: CardRequest, timeZone: TimeZone, readable: Bool = false) -> String {
        encode(request, timeZone: timeZone, readable: readable)
    }

    /// A request as JSON, times in the household's time zone: the cards' and Ask's (step 3).
    static func encode<Request: Encodable>(_ request: Request, timeZone: TimeZone, readable: Bool = false) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = readable ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        let data = (try? encoder.encode(request)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func instructions(for kind: CardKind) -> String {
        let span = kind == .morning
            ? "last night and yesterday (the days and nights named in \"period\")"
            : "last week, Monday to Sunday (the days and nights named in \"period\")"
        return """
        You help two parents look back at their own log of their baby's care. The log below holds \
        numbers and times only: feeds, sleep, nappies, baths, pumping and weights, by day and by night \
        (a night is named by its evening), for up to 4 weeks, and the baby's age in weeks.

        Fill in the form by choosing. You write no words of your own: the app writes every sentence \
        from your choices.
        - facts: choose up to 6 facts about \(span) that these parents would find most interesting or \
        useful, in the order to show them.
        - patterns: choose up to 3 patterns across the 4 weeks that stand out, falls included, in the \
        form's shapes. Each is checked against the log, and one that doesn't hold is turned down.
        - passages: for each NHS passage offered, choose the summary that fits best, or "none".

        Never judge the baby's health, compare the baby with others, or choose something to alarm \
        or reassure. When in doubt, choose fewer.
        """
    }

    // MARK: The form (D3, D9)

    /// The form for a card: facts only for its own days and nights (and the latest weight),
    /// patterns over the sheet's days, and only the passages and summaries offered.
    public static func form(for request: CardRequest, facts: InsightFacts) -> CardForm {
        var scopes = request.period.days.dates.map { "day:\($0)" }
        scopes += (request.period.nights?.dates ?? []).map { "night:\($0)" }
        if !request.weights.isEmpty { scopes.append("latest") }
        let measures = Measure.allCases.map(\.rawValue)
        let patternMeasures = Measure.allCases.filter { ![.time, .grams, .gramsChange].contains($0.unit) }.map(\.rawValue)
        let dates = Array(Set(facts.days.map(\.date) + facts.nights.map(\.evening))).sorted().map(\.description)
        let passageIDs = request.passages.map(\.id)
        let summaryIDs = request.passages.flatMap { $0.summaries.map(\.id) } + ["none"]

        let fact = FormNode.object(name: "Fact", fields: [
            FormField(name: "scope", about: "A day (day:DATE) or night (night:EVENING) of this card, or latest for the weight",
                      node: .oneOf(scopes)),
            FormField(name: "measure", about: "What the fact counts", node: .oneOf(measures)),
        ])
        let pattern = FormNode.object(name: "Pattern", fields: [
            FormField(name: "shape", about: "The pattern's shape", node: .oneOf(PatternShape.allCases.map(\.rawValue))),
            FormField(name: "measure", about: "What it is about", node: .oneOf(patternMeasures)),
            FormField(name: "nights", about: "Nights rather than days", node: .yesNo),
            FormField(name: "recentFirst", about: "First day or night of the recent stretch", node: .oneOf(dates)),
            FormField(name: "recentLast", about: "Last day or night of the recent stretch", node: .oneOf(dates)),
            FormField(name: "earlierFirst", about: "First of the stretch compared with, or none",
                      node: .oneOf(dates + ["none"])),
            FormField(name: "earlierLast", about: "Last of the stretch compared with, or none",
                      node: .oneOf(dates + ["none"])),
        ])
        var fields = [
            FormField(name: "facts", about: "Up to 6 facts, in order", node: .list(of: fact, maximum: AnswerCheck.maxFacts)),
            FormField(name: "patterns", about: "Up to 3 patterns", node: .list(of: pattern, maximum: AnswerCheck.maxPatterns)),
        ]
        if !passageIDs.isEmpty {
            let passage = FormNode.object(name: "PassagePick", fields: [
                FormField(name: "passage", about: "An offered NHS passage", node: .oneOf(passageIDs)),
                FormField(name: "summary", about: "One of its summaries, or none", node: .oneOf(summaryIDs)),
            ])
            fields.append(FormField(name: "passages", about: "A summary for each offered passage",
                                    node: .list(of: passage, maximum: passageIDs.count)))
        }
        return CardForm(root: .object(name: "Card", fields: fields))
    }

    // MARK: Reading the answer

    private struct WireCard: Decodable {
        var facts: [WireFact]
        var patterns: [WirePattern]
        var passages: [WirePassage]?
    }

    private struct WireFact: Decodable {
        var scope: String
        var measure: String
    }

    private struct WirePattern: Decodable {
        var shape: String
        var measure: String
        var nights: Bool
        var recentFirst: String
        var recentLast: String
        var earlierFirst: String
        var earlierLast: String
    }

    private struct WirePassage: Decodable {
        var passage: String
        var summary: String
    }

    /// The AI's choices from its answer (JSON fitting the form), with every day and night named
    /// outright; nil when anything in it isn't on the form's lists, so it is asked again.
    public static func read(_ json: Data) -> CardChoices? {
        guard let wire = try? JSONDecoder().decode(WireCard.self, from: json) else { return nil }
        var facts: [FactRef] = []
        for item in wire.facts {
            guard let measure = Measure(rawValue: item.measure), let scope = scope(item.scope) else { return nil }
            facts.append(FactRef(scope, measure))
        }
        var patterns: [PatternChoice] = []
        for item in wire.patterns {
            guard let shape = PatternShape(rawValue: item.shape), let measure = Measure(rawValue: item.measure),
                  let recentFirst = PlainDate(item.recentFirst), let recentLast = PlainDate(item.recentLast) else { return nil }
            var earlier: DateSpan?
            if item.earlierFirst != "none" || item.earlierLast != "none" {
                guard let first = PlainDate(item.earlierFirst), let last = PlainDate(item.earlierLast) else { return nil }
                earlier = DateSpan(first, last)
            }
            patterns.append(PatternChoice(shape, measure, nights: item.nights, recent: DateSpan(recentFirst, recentLast),
                                          earlier: earlier))
        }
        let passages = (wire.passages ?? []).map { PassageChoice($0.passage, summary: $0.summary == "none" ? nil : $0.summary) }
        return CardChoices(facts: facts, patterns: patterns, passages: passages)
    }

    static func scope(_ text: String) -> FactScope? {
        if text == "latest" { return .latest }
        if text.hasPrefix("day:"), let date = PlainDate(String(text.dropFirst(4))) { return .day(date) }
        if text.hasPrefix("night:"), let date = PlainDate(String(text.dropFirst(6))) { return .night(date) }
        return nil
    }

    // MARK: Checking, storing and showing

    /// A card made from `choices` for `job`, checked, ready to store.
    /// `leaveOut` false (the first try): any pick that fails the check turns the card down, so the
    /// AI chooses again. `leaveOut` true (the last try, AI13 D3 A): a pick that fails is left out on
    /// its own, as when a stored card is shown again, and the card is stored with only what passed;
    /// it is turned down only when nothing is left. Nothing that fails the check is ever shown.
    public static func accept(_ choices: CardChoices, job: CardJob, data: HouseholdData, babyID: String,
                              now: Date, leaveOut: Bool = false) -> (AnswerVerdict, StoredCard?) {
        // A fact only about this card's own days and nights, or the latest weight: the form says so,
        // and the checker holds it even if an answer doesn't keep to the form.
        var choices = choices
        let outside = choices.facts.filter { !covers(job.request.period, $0.scope) }
        if !outside.isEmpty {
            guard leaveOut else {
                return (.rejected(outside.map { _ in Rejection(part: "fact", reason: .unknownFact) }, needsHelpNow: false), nil)
            }
            choices.facts.removeAll { !covers(job.request.period, $0.scope) }
        }
        let settings = data.householdSettings
        let facts = data.insightFacts(babyID: babyID, now: now)
        let verdict = AnswerCheck.accept(choices, offered: job.offered, facts: facts, checks: data.passageChecks,
                                         timeZone: settings.timeZone, leaveOut: leaveOut)
        guard case .accepted(let checked) = verdict else { return (verdict, nil) }
        if leaveOut {
            choices = CardChoices(facts: checked.factRefs, patterns: checked.patternChoices,
                                  passages: checked.passages.map { PassageChoice($0.passage.id, summary: $0.summary?.id) })
        }
        let card = StoredCard(period: job.request.period, choices: choices, offered: job.offered, seen: job.seen,
                              made: job.made, madeAt: now)
        return (verdict, card)
    }

    // MARK: Trying again (AI3)

    /// Added to the second try when the first answer couldn't be read.
    public static let unreadableNote = "\n\nYOUR LAST ANSWER COULDN'T BE READ: choose only from the form's lists."

    /// Added to the second try when the first was turned down: each pick and why, in plain words
    /// (AI13 D3 A; the first run named only code words such as "emptyStretch").
    public static func retryNote(_ problems: [Rejection]) -> String {
        "\n\nYOUR LAST CHOICES WERE TURNED DOWN, so choose again. Change or leave out these: "
            + problems.map { "\($0.part) (\(why($0.reason)))" }.joined(separator: "; ")
            + ". A pick that still doesn't pass is left out of the card."
    }

    static func why(_ reason: Rejection.Reason) -> String {
        switch reason {
        case .unknownFact: "the log has no value for that measure on that day or night"
        case .patternSpan: "its days aren't all in the log, or don't fit the pattern's shape"
        case .patternUntrue: "the log's numbers don't bear it out"
        case .incompleteDays: "some of its days have entries with no amount or unread details, so their totals aren't known"
        case .emptyStretch: "it is a fall across a day or night with a long stretch with nothing logged, which may be entries not made"
        case .readsTheSame: "its numbers read the same once written, so the change can't be seen"
        case .unknownPassage: "that passage isn't offered with this card, or can't be shown with the other one"
        case .unknownSummary: "that summary isn't one offered for its passage"
        case .tooMany: "too many picks, none at all, or the same pick twice"
        case .tooLong, .number, .dateOrTime, .banned, .unknownPlaceholder: "it isn't allowed on a card"
        }
    }

    /// A stored card as this phone shows it: checked against this phone's log, leaving out a fact
    /// or pattern that no longer holds (R5, O3); nil when nothing is left.
    public static func show(_ card: StoredCard, data: HouseholdData, babyID: String, now: Date) -> CheckedCard? {
        show(card, facts: data.insightFacts(babyID: babyID, now: now), data: data)
    }

    static func show(_ card: StoredCard, facts: InsightFacts, data: HouseholdData) -> CheckedCard? {
        let settings = data.householdSettings
        var choices = card.choices
        choices.facts = choices.facts.filter { covers(card.period, $0.scope) }
        let verdict = AnswerCheck.accept(choices, offered: card.offered, facts: facts, checks: data.passageChecks,
                                         timeZone: settings.timeZone, leaveOut: true)
        if case .accepted(let checked) = verdict { return checked }
        return nil
    }

    /// Whether a fact's scope is one of the period's own days or nights, or the latest weight.
    static func covers(_ period: CardPeriod, _ scope: FactScope) -> Bool {
        switch scope {
        case .latest: true
        case .day(let date): period.days.dates.contains(date)
        case .night(let evening): period.nights?.dates.contains(evening) ?? false
        case .yesterday, .lastNight: false
        }
    }
}

// MARK: - Kept in the household

extension HouseholdData {
    /// Each member's yes, by member.
    public var insightYeses: [MemberID: InsightYes] {
        var yeses: [MemberID: InsightYes] = [:]
        for record in plainRecords(of: .setting) where record.name.hasPrefix(InsightCards.yesPrefix) {
            let member = MemberID(rawValue: String(record.name.dropFirst(InsightCards.yesPrefix.count)))
            if let yes = setting(InsightYes.self, record.name) { yeses[member] = yes }
        }
        return yeses
    }

    /// A parent's yes, or their "off" (`yes` false), given on their own phone.
    public mutating func setInsightYes(_ yes: Bool, member: MemberID, now: Date) {
        putSetting(InsightYes(yes: yes, version: InsightCards.consentVersion, at: now),
                   key: InsightCards.yesPrefix + member.rawValue, now: now)
    }

    /// Every "this was wrong" report the household holds. Each report is a Setting record of its
    /// own ("insightWrong-<id>"), so two reports made on both phones before either syncs both
    /// count (step 3 X9): one shared list would keep only the later phone's copy. The shared list
    /// ("insightWrong") is still written for older builds, and read and joined here.
    public var wrongReports: WrongReports {
        var reports = setting(WrongReports.self, InsightCards.wrongKey) ?? WrongReports()
        for record in plainRecords(of: .setting) where record.name.hasPrefix(InsightCards.wrongReportPrefix) {
            guard let date = PayloadCoder.decode(SettingPayload<Date>.self, from: record.payload)?.value,
                  !reports.dates.contains(date) else { continue }
            reports.dates.append(date)
        }
        if let resumed = setting(Date.self, InsightCards.wrongResumedKey) {
            reports.resumedAt = max(reports.resumedAt ?? resumed, resumed)
        }
        reports.dates.sort()
        return reports
    }

    /// "This was wrong": kept for 30 days; two in that time pause the AI (A7).
    public mutating func reportWrongCard(now: Date, id: String = UUID().uuidString) {
        putSetting(now, key: InsightCards.wrongReportPrefix + id, now: now)
        var shared = setting(WrongReports.self, InsightCards.wrongKey) ?? WrongReports()
        shared.dates = shared.dates.filter { $0 > now.addingTimeInterval(-InsightCards.reportWindow) } + [now]
        putSetting(shared, key: InsightCards.wrongKey, now: now)
    }

    /// A parent switches the AI back on after a pause. The later switch wins, whichever phone.
    public mutating func resumeInsights(now: Date) {
        putSetting(now, key: InsightCards.wrongResumedKey, now: now)
        var shared = setting(WrongReports.self, InsightCards.wrongKey) ?? WrongReports()
        shared.resumedAt = now
        putSetting(shared, key: InsightCards.wrongKey, now: now)
    }

    /// The stored card of a kind, if any.
    public func insightCard(_ kind: CardKind) -> StoredCard? {
        setting(StoredCard.self, kind.settingKey)
    }

    /// Stores a card unless the one held now is for a later period, or saw entries this one
    /// didn't (D8, D10). Returns whether it was stored.
    @discardableResult
    public mutating func storeInsightCard(_ card: StoredCard, now: Date) -> Bool {
        if let current = insightCard(card.period.kind) {
            if current.period.isNewer(than: card.period) { return false }
            if current.period == card.period, InsightCards.sawMore(current.seen, than: card.seen) { return false }
        }
        putSetting(card, key: card.period.kind.settingKey, now: now)
        return true
    }
}

extension InsightCards {
    static let yesPrefix = "insightYes-"
    static let wrongKey = "insightWrong"
    /// One record per report (X9); the hyphen keeps it apart from `wrongKey` itself.
    static let wrongReportPrefix = "insightWrong-"
    static let wrongResumedKey = "insightWrongResumedAt"
}
