import Foundation
import Testing
import FeedingCore
@testable import FeedingInsights

// The shared AI cards (task AI7; step 2 D3 to D10 and Codex's O1 to O8 in
// `docs/planning/12-ai-insights-gauntlet.md`). No model runs here: fixed choices stand in for it.

/// A household holding `entries`, each added at its own start time unless `changedAt` says so.
func household(_ entries: [EventSnapshot], changedAt: [String: Date] = [:]) -> HouseholdData {
    var data = HouseholdData()
    for snapshot in entries {
        let event = snapshot.event
        data.add(id: event.id, kind: event.kind, babyID: event.babyID, startedAt: event.startedAt, endedAt: event.endedAt,
                 payload: snapshot.payload ?? EventPayload(), by: parentA, timeZoneID: event.timeZoneID,
                 now: changedAt[event.id] ?? event.startedAt)
    }
    return data
}

/// Days of steady feeds, `perDay[i]` on the `i`-th day from `first`, each with a wet nappy, and a
/// sleep each night from 22:00 to 05:00.
func loggedDays(from first: PlainDate, feeds perDay: [Int]) -> [EventSnapshot] {
    perDay.enumerated().flatMap { offset, count -> [EventSnapshot] in
        let day = first.adding(days: offset)
        let start = at(day.year, day.month, day.day, 22)
        return steadyDay(day.year, day.month, day.day, feeds: count)
            + [entry(.sleep, start, end: start.addingTimeInterval(.hours(7)))]
    }
}

@Suite("Cards: the app writes every sentence (D9, O1)")
struct CardWordingTests {
    let now = at(2026, 11, 22, 10)
    var sheet: InsightFacts {
        facts(loggedDays(from: date("2026-11-09"), feeds: [8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 10, 11]), now: now)
    }

    @Test func aNumberAlwaysSitsBesideWhatItCounts() {
        let card = AnswerCheck.accept(CardChoices(facts: [FactRef(.day(date("2026-11-21")), .feeds),
                                                          FactRef(.day(date("2026-11-21")), .wees)]),
                                      offered: [], facts: sheet, checks: [:], timeZone: london)
        guard case .accepted(let checked) = card else { Issue.record("turned down"); return }
        #expect(checked.lines == ["11 feeds logged yesterday.", "11 wet nappies logged yesterday."])
        // The AI chooses a measure, never the words: a wee count can only be called wet nappies.
        #expect(checked.lines.allSatisfy { $0.contains("logged") })
    }

    @Test func everyMeasureHasWordingWhereItApplies() {
        let day = date("2026-11-21")
        for measure in Measure.allCases {
            let dayFact = CardWording.fact(FactRef(.day(day), measure), facts: sheet, timeZone: london)
            let nightFact = CardWording.fact(FactRef(.night(day), measure), facts: sheet, timeZone: london)
            let value = AnswerCheck.number(FactRef(.day(day), measure), in: sheet)
                ?? AnswerCheck.number(FactRef(.night(day), measure), in: sheet)
            if value != nil {
                let written = dayFact ?? nightFact
                #expect(written != nil, "\(measure)")
                #expect(written?.contains("logged") == true, "\(measure)")
            }
        }
    }

    @Test func aPatternSaysTheDirectionTheCheckerFound() {
        let recent = DateSpan(date("2026-11-19"), date("2026-11-21"))
        let earlier = DateSpan(date("2026-11-12"), date("2026-11-18"))
        let rose = AnswerCheck.accept(CardChoices(facts: [], patterns: [PatternChoice(.higher, .feeds, recent: recent,
                                                                                         earlier: earlier)]),
                                      offered: [], facts: sheet, checks: [:], timeZone: london)
        guard case .accepted(let checked) = rose else { Issue.record("turned down"); return }
        #expect(checked.patterns.count == 1)
        #expect(checked.patterns[0].hasPrefix("Feeds logged per day rose: 10 on average"))
        // A reversed trend can't be chosen into a sentence: "lower" over a rise is turned down.
        let fell = AnswerCheck.accept(CardChoices(facts: [], patterns: [PatternChoice(.lower, .feeds, recent: recent,
                                                                                         earlier: earlier)]),
                                      offered: [], facts: sheet, checks: [:], timeZone: london)
        if case .accepted = fell { Issue.record("a reversed trend was accepted") }
    }

    @Test func showingLeavesOutWhatNoLongerHolds() {
        let choices = CardChoices(facts: [FactRef(.day(date("2026-11-21")), .feeds), FactRef(.day(date("2026-09-01")), .feeds)],
                                  patterns: [PatternChoice(.lower, .feeds, recent: DateSpan(date("2026-11-19"), date("2026-11-21")),
                                                           earlier: DateSpan(date("2026-11-12"), date("2026-11-18")))])
        let strict = AnswerCheck.accept(choices, offered: [], facts: sheet, checks: [:], timeZone: london)
        if case .accepted = strict { Issue.record("strict check accepted a missing day") }
        let shown = AnswerCheck.accept(choices, offered: [], facts: sheet, checks: [:], timeZone: london, leaveOut: true)
        guard case .accepted(let checked) = shown else { Issue.record("nothing left"); return }
        #expect(checked.lines == ["11 feeds logged yesterday."])
        #expect(checked.patterns.isEmpty)
    }

    @Test func onlyOfferedTickedPassagesAndNeverAPairTogether() {
        let today = date("2026-11-22")
        let checks = Dictionary(uniqueKeysWithValues: NHSPassages.all.flatMap { [$0.id] + $0.summaries.map(\.id) }
            .map { ($0, today) })
        let facts = CardChoices(facts: [FactRef(.day(date("2026-11-21")), .feeds)],
                                passages: [PassageChoice("weight-how-often"), PassageChoice("formula-enough")])
        let strict = AnswerCheck.accept(facts, offered: ["weight-how-often", "formula-enough"], facts: sheet, checks: checks,
                                        timeZone: london)
        if case .accepted = strict { Issue.record("a not-with pair was accepted") }
        let notOffered = AnswerCheck.accept(CardChoices(facts: facts.facts, passages: [PassageChoice("night-and-day")]),
                                            offered: [], facts: sheet, checks: checks, timeZone: london)
        if case .accepted = notOffered { Issue.record("a passage not offered was accepted") }
        let shown = AnswerCheck.accept(facts, offered: ["weight-how-often", "formula-enough"], facts: sheet, checks: checks,
                                       timeZone: london, leaveOut: true)
        guard case .accepted(let checked) = shown else { Issue.record("nothing left"); return }
        #expect(checked.passages.map(\.passage.id) == ["weight-how-often"])
    }
}

@Suite("Cards: the form and the answer (D3)")
struct CardFormTests {
    let now = at(2026, 11, 22, 10)

    func job() -> CardJob? {
        let data = household(loggedDays(from: date("2026-11-09"), feeds: Array(repeating: 8, count: 13)))
        guard case .make(let job, _) = InsightCards.plan(.morning, data: consenting(data), babyID: baby, me: parentA,
                                                         participants: [parentA, parentB], tries: LocalCardTries(), now: now)
        else { return nil }
        return job
    }

    @Test func theFormNamesOnlyThisCardsDaysAndOfferedPassages() {
        guard let job = job() else { Issue.record("no card to make"); return }
        guard case .object(_, let fields) = job.form.root,
              case .list(let fact, _) = fields.first(where: { $0.name == "facts" })?.node,
              case .object(_, let factFields) = fact,
              case .oneOf(let scopes) = factFields.first(where: { $0.name == "scope" })?.node else {
            Issue.record("unexpected form"); return
        }
        #expect(Set(scopes) == ["day:2026-11-21", "night:2026-11-21"])
        #expect(job.request.passages.map(\.id) == job.offered)
    }

    @Test func aFactOutsideTheCardsDaysIsTurnedDown() {
        guard let job = job() else { Issue.record("no card to make"); return }
        let data = consenting(household(loggedDays(from: date("2026-11-09"), feeds: Array(repeating: 8, count: 13))))
        let outside = CardChoices(facts: [FactRef(.day(date("2026-11-10")), .feeds)])
        let (verdict, card) = InsightCards.accept(outside, job: job, data: data, babyID: baby, now: now)
        if case .accepted = verdict { Issue.record("a day outside the card was accepted") }
        #expect(card == nil)
        // A stored card naming such a day shows its other facts only.
        let stored = StoredCard(period: job.request.period,
                                choices: CardChoices(facts: [FactRef(.day(date("2026-11-10")), .feeds),
                                                             FactRef(.day(date("2026-11-21")), .feeds)]),
                                offered: [], seen: [:], made: 1, madeAt: now)
        #expect(InsightCards.show(stored, data: data, babyID: baby, now: now)?.lines == ["8 feeds logged yesterday."])
    }

    @Test func readingAnAnswer() {
        let good = Data("""
        {"facts":[{"scope":"night:2026-11-21","measure":"longestSleep"}],
         "patterns":[{"shape":"steady","measure":"feeds","nights":false,"recentFirst":"2026-11-19","recentLast":"2026-11-21",
                      "earlierFirst":"none","earlierLast":"none"}],
         "passages":[{"passage":"night-and-day","summary":"none"}]}
        """.utf8)
        let choices = InsightCards.read(good)
        #expect(choices?.facts == [FactRef(.night(date("2026-11-21")), .longestSleep)])
        #expect(choices?.patterns.first?.earlier == nil)
        #expect(choices?.passages == [PassageChoice("night-and-day")])
        let unknown = Data(#"{"facts":[{"scope":"yesterday","measure":"feeds"}],"patterns":[]}"#.utf8)
        #expect(InsightCards.read(unknown) == nil)
        #expect(InsightCards.read(Data("not json".utf8)) == nil)
    }

    @Test func whatIsSentHasNoTextNoMedicineAndTheAgeInWeeks() {
        var data = household(loggedDays(from: date("2026-11-09"), feeds: Array(repeating: 8, count: 13)))
        data.add(kind: .medicine, babyID: baby, startedAt: at(2026, 11, 21, 9), payload: EventPayload(), by: parentA,
                 timeZoneID: "Europe/London", now: at(2026, 11, 21, 9))
        for weeksBefore in [10, 6, 2] {
            let when = at(2026, 11, 21, 12).addingTimeInterval(-Double(weeksBefore) * 7 * 86_400)
            data.add(kind: .growth, babyID: baby, startedAt: when, payload: EventPayload(growth: GrowthDetails(weightGrams: 3500)),
                     by: parentA, timeZoneID: "Europe/London", now: when)
        }
        let sheet = data.insightFacts(babyID: baby, now: now)
        guard let period = InsightCards.morningPeriod(sheet) else { Issue.record("no period"); return }
        var withAge = sheet
        withAge.ageInDays = 23
        let (request, _) = InsightCards.request(period, facts: withAge, checks: [:], breastfeeds: false, bottleFeeds: true,
                                                timeZone: london)
        #expect(request.ageInWeeks == 3)
        // Weights: the 4 weeks' (2 weeks ago) and the one before them (6 weeks ago); not 10 weeks ago.
        #expect(request.weights.count == 2)
        let json = InsightCards.prompt(request, timeZone: london)
        #expect(!json.lowercased().contains("medicine"))
        #expect(!json.contains("ageInDays"))
        #expect(!json.contains(parentA.rawValue))
    }
}

@Suite("Cards: the weeks (D5)")
struct CardWeekTests {
    func week(_ now: Date) -> (PlainDate, PlainDate) {
        let period = InsightCards.weekPeriod(now: now, dayHours: .standard, timeZone: london)
        return (period.days.first, period.days.last)
    }

    @Test func lastMondayToSunday() {
        // Monday 23 November 2026, after the rota's morning: Monday 16 to Sunday 22.
        #expect(week(at(2026, 11, 23, 8)) == (date("2026-11-16"), date("2026-11-22")))
        // The same Monday before the morning: still the week before.
        #expect(week(at(2026, 11, 23, 3)) == (date("2026-11-09"), date("2026-11-15")))
        // A first open on Tuesday: last week all the same.
        #expect(week(at(2026, 11, 24, 15)) == (date("2026-11-16"), date("2026-11-22")))
        // Across the clocks going back (Sunday 25 October 2026).
        #expect(week(at(2026, 10, 26, 9)) == (date("2026-10-19"), date("2026-10-25")))
        // In another time zone with a 30-minute offset.
        let adelaide = TimeZone(identifier: "Australia/Adelaide")!
        let period = InsightCards.weekPeriod(now: at(2026, 11, 23, 9, in: adelaide), dayHours: .standard, timeZone: adelaide)
        #expect(period.days.first == date("2026-11-16"))
    }

    @Test func noWeekWithFewerThanThreeLoggedDays() {
        let data = consenting(household(loggedDays(from: date("2026-11-21"), feeds: [8, 8])))
        let plan = InsightCards.plan(.week, data: data, babyID: baby, me: parentA, participants: [parentA, parentB],
                                     tries: LocalCardTries(), now: at(2026, 11, 23, 9))
        #expect(plan == .none)
    }
}

/// Both parents' yes, as each would give it on their own phone.
func consenting(_ data: HouseholdData, at now: Date = at(2026, 11, 1, 12)) -> HouseholdData {
    var data = data
    data.setInsightYes(true, member: parentA, now: now)
    data.setInsightYes(true, member: parentB, now: now)
    return data
}

@Suite("Cards: the gate (D12, O2, A7)")
struct CardGateTests {
    let now = at(2026, 11, 22, 10)

    @Test func bothYesesFromTheShareOpenIt() {
        var data = HouseholdData()
        data.setInsightYes(true, member: parentA, now: now)
        let one = InsightCards.gate(data, me: parentA, participants: [parentA, parentB], now: now)
        #expect(one.make == .waitingForYes)
        data.setInsightYes(true, member: parentB, now: now)
        let both = InsightCards.gate(data, me: parentA, participants: [parentA, parentB], now: now)
        #expect(both.show == nil && both.make == nil)
        // Nothing is sent until the share's participants are read (after a launch or an
        // account switch), though a card made before may show.
        let unread = InsightCards.gate(data, me: parentA, participants: nil, now: now)
        #expect(unread.show == nil && unread.make == .notChecked)
        // A phone signed in as someone else in the share can't send.
        let stranger = InsightCards.gate(data, me: "someone-else", participants: [parentA, parentB], now: now)
        #expect(stranger.make == .notChecked)
        // A third participant without a yes closes it.
        let third = InsightCards.gate(data, me: parentA, participants: [parentA, parentB, "parent-c"], now: now)
        #expect(third.make == .waitingForYes)
        // One participant only: both parents' yes is needed.
        let alone = InsightCards.gate(data, me: parentA, participants: [parentA], now: now)
        #expect(alone.make == .waitingForYes)
    }

    @Test func eitherParentCanTurnItOff() {
        var data = consenting(HouseholdData())
        data.setInsightYes(false, member: parentB, now: now)
        let gate = InsightCards.gate(data, me: parentA, participants: [parentA, parentB], now: now)
        #expect(gate.show == .turnedOff && gate.make == .turnedOff)
    }

    @Test func twoWrongReportsIn30DaysPauseIt() {
        var data = consenting(HouseholdData())
        data.reportWrongCard(now: now)
        #expect(InsightCards.gate(data, me: parentA, participants: [parentA, parentB], now: now).make == nil)
        data.reportWrongCard(now: now.addingTimeInterval(.hours(1)))
        #expect(InsightCards.gate(data, me: parentA, participants: [parentA, parentB], now: now.addingTimeInterval(.hours(2))).make == .paused)
        data.resumeInsights(now: now.addingTimeInterval(.hours(3)))
        #expect(InsightCards.gate(data, me: parentA, participants: [parentA, parentB], now: now.addingTimeInterval(.hours(4))).make == nil)
        // Reports older than 30 days don't count.
        var old = consenting(HouseholdData())
        old.reportWrongCard(now: at(2026, 9, 1, 10))
        old.reportWrongCard(now: at(2026, 9, 2, 10))
        #expect(InsightCards.gate(old, me: parentA, participants: [parentA, parentB], now: now).make == nil)
    }
}

@Suite("Cards: made again only for entries a card didn't see (D4, O4, D10)")
struct CardRemakeTests {
    let made = at(2026, 11, 22, 7, 10)
    let days = loggedDays(from: date("2026-11-09"), feeds: Array(repeating: 8, count: 13))

    func plan(_ data: HouseholdData, now: Date, tries: LocalCardTries = LocalCardTries()) -> CardPlan {
        InsightCards.plan(.morning, data: data, babyID: baby, me: parentA, participants: [parentA, parentB], tries: tries,
                          now: now)
    }

    /// The household after a card was made at `made` from what it held then.
    func withCard(_ entries: [EventSnapshot], changedAt: [String: Date] = [:]) -> HouseholdData {
        var data = consenting(household(entries, changedAt: changedAt))
        guard case .make(let job, _) = plan(data, now: made),
              let choices = InsightCards.read(Data(#"{"facts":[{"scope":"day:2026-11-21","measure":"feeds"}],"patterns":[]}"#.utf8))
        else { Issue.record("no card made"); return data }
        let (verdict, card) = InsightCards.accept(choices, job: job, data: data, babyID: baby, now: made)
        guard case .accepted = verdict, let card else { Issue.record("turned down"); return data }
        let stored = data.storeInsightCard(card, now: made)
        #expect(stored)
        return data
    }

    @Test func aFirstCardIsMadeThenShown() {
        let data = withCard(days)
        guard case .show(let card) = plan(data, now: made.addingTimeInterval(.hours(1))) else {
            Issue.record("expected the stored card"); return
        }
        #expect(card.made == 1)
        #expect(InsightCards.show(card, data: data, babyID: baby, now: made)?.lines == ["8 feeds logged yesterday."])
    }

    @Test func aLateSyncedEntryWithAnOlderChangeTimeStillRemakes() {
        // The card saw an edit at 07:05; the other phone's 04:00 feed, logged at 04:05, arrives after.
        var data = withCard(days)
        data.add(kind: .feed, babyID: baby, startedAt: at(2026, 11, 22, 4), payload: bottle(90), by: parentB,
                 timeZoneID: "Europe/London", now: at(2026, 11, 22, 4, 5))
        guard case .make(let job, let showing) = plan(data, now: made.addingTimeInterval(.minutes(15))) else {
            Issue.record("expected a remake"); return
        }
        #expect(job.made == 2)
        #expect(showing != nil)
    }

    @Test func anEditOutsideItsDaysDoesntRemake() {
        var data = withCard(days)
        data.add(kind: .feed, babyID: baby, startedAt: at(2026, 11, 15, 12), payload: bottle(90), by: parentA,
                 timeZoneID: "Europe/London", now: made.addingTimeInterval(.minutes(30)))
        if case .make = plan(data, now: made.addingTimeInterval(.hours(1))) { Issue.record("remade for another day") }
    }

    @Test func notWithinTenMinutesAndAtMostThree() {
        var data = withCard(days)
        data.add(kind: .feed, babyID: baby, startedAt: at(2026, 11, 22, 4), payload: bottle(90), by: parentB,
                 timeZoneID: "Europe/London", now: made.addingTimeInterval(.minutes(1)))
        if case .make = plan(data, now: made.addingTimeInterval(.minutes(5))) { Issue.record("remade within 10 minutes") }
        guard var card = data.insightCard(.morning) else { Issue.record("no card"); return }
        card.made = InsightCards.maxCards
        data.putSetting(card, key: CardKind.morning.settingKey, now: made)
        if case .make = plan(data, now: made.addingTimeInterval(.hours(1))) { Issue.record("a fourth card") }
    }

    @Test func thisPhonesCallsAreCapped() {
        let data = consenting(household(days))
        guard let period = InsightCards.morningPeriod(data.insightFacts(babyID: baby, now: made)) else {
            Issue.record("no period"); return
        }
        var tries = LocalCardTries()
        for minute in 0..<InsightCards.maxCalls { tries.record(period, at: made.addingTimeInterval(.minutes(Double(minute) * 11))) }
        let capped = plan(data, now: made.addingTimeInterval(.hours(3)), tries: tries)
        #expect(capped == .closed(.later, nil))
        var one = LocalCardTries()
        one.record(period, at: made)
        #expect(plan(data, now: made.addingTimeInterval(.minutes(5)), tries: one) == .closed(.later, nil))
    }

    @Test func aCardFromFewerEntriesIsntSavedOverAFresherOne() {
        var data = withCard(days)
        guard let fresher = data.insightCard(.morning) else { Issue.record("no card"); return }
        var older = fresher
        older.seen = fresher.seen.filter { _ in false }
        older.madeAt = made.addingTimeInterval(.minutes(20))
        let olderStored = data.storeInsightCard(older, now: older.madeAt)
        #expect(!olderStored)
        // A card for an older night never replaces a newer one.
        var earlier = fresher
        earlier.period = CardPeriod(kind: .morning, days: DateSpan(date("2026-11-20"), date("2026-11-20")),
                                    nights: DateSpan(date("2026-11-20"), date("2026-11-20")))
        let earlierStored = data.storeInsightCard(earlier, now: made)
        #expect(!earlierStored)
        #expect(data.insightCard(.morning) == fresher)
    }
}

@Suite("Cards: NHS pairs never together (D6)")
struct CardPassagePairTests {
    @Test func theChooserOffersAtMostOneOfAPair() {
        let today = date("2026-11-25")
        let checks = Dictionary(uniqueKeysWithValues: NHSPassages.all.flatMap { [$0.id] + $0.summaries.map(\.id) }
            .map { ($0, today) })
        var offered: Set<String> = []
        for offset in 0..<60 {
            for limit in 1...4 {
                let ids = NHSPassages.choose(kinds: [.feed, .nappy, .weight], ageInDays: 20, breastfeeds: true, bottleFeeds: true,
                                             checks: checks, today: today.adding(days: offset), limit: limit).map(\.id)
                offered.formUnion(ids)
                for pair in NHSPassages.notWith {
                    let both = pair.isSubset(of: Set(ids))
                    #expect(!both, "\(ids)")
                }
            }
        }
        for pair in NHSPassages.notWith {
            #expect(pair.isSubset(of: offered), "each of \(pair) is still offered on some day")
        }
    }
}
