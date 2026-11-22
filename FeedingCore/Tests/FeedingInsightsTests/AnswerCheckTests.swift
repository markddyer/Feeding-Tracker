import Foundation
import Testing
import FeedingCore
@testable import FeedingInsights

// The answer checker (task AI3; A1, R5, R6, R7 with D9, O2, O6, O7). Fixed sample forms stand in
// for the AI: what the model really writes is for step 2's model tests.

/// `count` bottle feeds spread evenly over a day, each followed by a wet nappy, so the day has no
/// long stretch with nothing logged.
func steadyDay(_ year: Int, _ month: Int, _ day: Int, feeds count: Int, ml: Int? = 90) -> [EventSnapshot] {
    (0..<count).flatMap { index -> [EventSnapshot] in
        let start = at(year, month, day, 0).addingTimeInterval(.hours(24.0 / Double(count) * Double(index) + 0.5))
        return [entry(.feed, start, end: start.addingTimeInterval(.minutes(20)), payload: bottle(ml)),
                entry(.nappy, start.addingTimeInterval(.minutes(25)), payload: nappy())]
    }
}

@Suite("Answer check: the AI's own words")
struct AnswerCheckWordTests {
    let now = at(2026, 11, 20, 10)
    var sheet: InsightFacts {
        facts([entry(.sleep, at(2026, 11, 19, 22), end: at(2026, 11, 20, 5)),
               entry(.feed, at(2026, 11, 19, 10), payload: bottle(90))], now: now)
    }

    func verdict(_ lines: [ProposedLine], needsHelp: Bool = false) -> AnswerVerdict {
        AnswerCheck.accept(CardProposal(lines: lines, needsHelpNow: needsHelp), facts: sheet, checks: [:], timeZone: london)
    }

    func reasons(_ verdict: AnswerVerdict) -> [Rejection.Reason] {
        if case .rejected(let problems, _) = verdict { return problems.map(\.reason) }
        return []
    }

    @Test func theAppWritesTheNumbers() {
        let card = verdict([ProposedLine("The longest sleep last night was {1}, from {2}.",
                                         facts: [FactRef(.lastNight, .longestSleep), FactRef(.lastNight, .longestSleepStart)])])
        guard case .accepted(let checked) = card else { Issue.record("rejected: \(reasons(card))"); return }
        #expect(checked.lines == ["The longest sleep last night was 7h, from 22:00."])
        #expect(checked.factsRevision == sheet.revision)
    }

    @Test(arguments: [
        ("She had 9 feeds yesterday.", Rejection.Reason.number("9")),
        ("She had nine feeds yesterday.", .number("nine")),
        ("Feeds came twice as often.", .number("twice")),
        ("A couple of long sleeps.", .number("couple")),
        ("Asleep for hours.", .number("hours")),
        ("Asleep after midnight.", .dateOrTime("midnight")),
        ("The longest sleep was on Sunday.", .dateOrTime("sunday")),
        ("She should sleep longer tonight.", .dateOrTime("tonight")),
    ])
    func noNumberOfItsOwn(_ text: String, _ reason: Rejection.Reason) {
        #expect(reasons(verdict([ProposedLine(text)])) == [reason])
    }

    @Test(arguments: [
        ("That is completely normal.", "normal"),
        ("There's no need to call for help.", "call"),
        ("Nothing to worry about here.", "worry"),
        ("This might be colic.", "colic"),
        ("The NHS says this happens.", "nhs"),
        ("She is getting enough milk.", "enough"),
        ("Give her a dose of Calpol.", "dose"),
        ("It's probably a growth spurt.", "growth spurt"),
        ("You did most of the night feeds, which isn't fair.", "fair"),
        ("Feeds were lower than usual.", "usual"),
    ])
    func noVerdictsCausesOrBlame(_ text: String, _ banned: String) {
        #expect(reasons(verdict([ProposedLine(text)])).first == .banned(banned))
    }

    @Test func plainWordsAndShouldAreFine() {
        // "should" is allowed (D5); a fall said as a logged fact too (R6).
        let card = verdict([ProposedLine("Fewer feeds were logged yesterday, {1} in all, and sleep should come in stretches.",
                                         facts: [FactRef(.yesterday, .feeds)])])
        guard case .accepted(let checked) = card else { Issue.record("rejected: \(reasons(card))"); return }
        #expect(checked.lines == ["Fewer feeds were logged yesterday, 1 in all, and sleep should come in stretches."])
    }

    @Test func unknownFactsAndPlaceholders() {
        #expect(reasons(verdict([ProposedLine("Slept {1}.", facts: [FactRef(.night(date("2026-10-01")), .slept)])]))
                == [.unknownFact])
        // A night's measure asked of a day.
        #expect(reasons(verdict([ProposedLine("Slept {1}.", facts: [FactRef(.yesterday, .slept)])])) == [.unknownFact])
        #expect(reasons(verdict([ProposedLine("Slept {2}.", facts: [FactRef(.lastNight, .slept)])])) == [.unknownPlaceholder("2")])
        #expect(reasons(verdict([ProposedLine("Slept {recent}.")])) == [.unknownPlaceholder("recent")])
        #expect(reasons(verdict([ProposedLine("Slept {1.", facts: [FactRef(.lastNight, .slept)])])) == [.unknownPlaceholder("{")])
    }

    @Test func limits() {
        let line = ProposedLine("Sleep was logged.")
        #expect(reasons(verdict([])) == [.tooMany])
        #expect(reasons(verdict(Array(repeating: line, count: 4))) == [.tooMany])
        #expect(reasons(verdict([ProposedLine(String(repeating: "logged ", count: 40))])) == [.tooLong])
    }

    @Test func theNeedsHelpFlagSurvivesARejection() {
        #expect(verdict([ProposedLine("That is normal.")], needsHelp: true) == .rejected(
            [Rejection(part: "line 1", reason: .banned("normal"))], needsHelpNow: true))
        guard case .accepted(let checked) = verdict([ProposedLine("Sleep was logged.")], needsHelp: true) else {
            Issue.record("rejected"); return
        }
        #expect(checked.needsHelpNow)
    }

    @Test func howTheAppWritesValues() {
        #expect(AnswerCheck.write(.hours(3) + .minutes(10), unit: .seconds, timeZone: london) == "3h 10m")
        #expect(AnswerCheck.write(.minutes(45), unit: .seconds, timeZone: london) == "45m")
        #expect(AnswerCheck.write(.hours(2), unit: .seconds, timeZone: london) == "2h")
        #expect(AnswerCheck.write(150, unit: .ml, timeZone: london) == "150 ml")
        #expect(AnswerCheck.write(4120, unit: .grams, timeZone: london) == "4.12 kg")
        #expect(AnswerCheck.write(4005, unit: .grams, timeZone: london) == "4.01 kg")
        #expect(AnswerCheck.write(180, unit: .gramsChange, timeZone: london) == "+180 g")
        #expect(AnswerCheck.write(-60, unit: .gramsChange, timeZone: london) == "-60 g")
        #expect(AnswerCheck.write(at(2026, 11, 19, 23, 40).timeIntervalSince1970, unit: .time, timeZone: london) == "23:40")
    }
}

@Suite("Answer check: patterns")
struct AnswerCheckPatternTests {
    let now = at(2026, 11, 20, 10)

    func check(_ claim: PatternClaim, _ entries: [EventSnapshot]) -> Result<[String: String], Rejection.Reason> {
        AnswerCheck.check(claim, facts: facts(entries, now: now), timeZone: london)
    }

    var moreFeedsLately: [EventSnapshot] {
        steadyDay(2026, 11, 15, feeds: 6) + steadyDay(2026, 11, 16, feeds: 6) + steadyDay(2026, 11, 17, feeds: 6)
            + steadyDay(2026, 11, 18, feeds: 9) + steadyDay(2026, 11, 19, feeds: 9)
    }

    @Test func higherAndLower() {
        let higher = PatternClaim(.higher, .feeds, recent: DateSpan(date("2026-11-18"), date("2026-11-19")),
                                  earlier: DateSpan(date("2026-11-15"), date("2026-11-17")),
                                  template: "More feeds logged lately: {recent} a day, from {earlier}.")
        #expect(check(higher, moreFeedsLately) == .success(["recent": "9", "earlier": "6"]))
        var lower = higher
        lower.shape = .lower
        #expect(check(lower, moreFeedsLately) == .failure(.patternUntrue))
        // The earlier days must come first.
        var overlapping = higher
        overlapping.earlier = DateSpan(date("2026-11-17"), date("2026-11-18"))
        #expect(check(overlapping, moreFeedsLately) == .failure(.patternSpan))
    }

    @Test func numbersThatWouldReadTheSame() {
        // 8 and 8 feeds, then 8, 8 and 9: about 8.3 against 8, both written "8".
        let entries = steadyDay(2026, 11, 15, feeds: 8) + steadyDay(2026, 11, 16, feeds: 8)
            + steadyDay(2026, 11, 17, feeds: 8) + steadyDay(2026, 11, 18, feeds: 8) + steadyDay(2026, 11, 19, feeds: 9)
        let claim = PatternClaim(.higher, .feeds, recent: DateSpan(date("2026-11-17"), date("2026-11-19")),
                                 earlier: DateSpan(date("2026-11-15"), date("2026-11-16")), template: "{recent} {earlier}")
        #expect(check(claim, entries) == .failure(.readsTheSame))
    }

    @Test func aFallIsAPlainFactUnlessTheLogHasGaps() {
        let fewerLately = steadyDay(2026, 11, 16, feeds: 8) + steadyDay(2026, 11, 17, feeds: 8)
            + steadyDay(2026, 11, 18, feeds: 6) + steadyDay(2026, 11, 19, feeds: 6)
        let claim = PatternClaim(.lower, .wees, recent: DateSpan(date("2026-11-18"), date("2026-11-19")),
                                 earlier: DateSpan(date("2026-11-16"), date("2026-11-17")),
                                 template: "Fewer wet nappies logged lately: {recent} a day, from {earlier}.")
        #expect(check(claim, fewerLately) == .success(["recent": "6", "earlier": "8"]))
        // A day with a long stretch of nothing logged: a forgotten entry looks like a fall (R6).
        let gappy = steadyDay(2026, 11, 16, feeds: 8) + steadyDay(2026, 11, 17, feeds: 8)
            + steadyDay(2026, 11, 18, feeds: 6) + steadyDay(2026, 11, 19, feeds: 3)
        #expect(check(claim, gappy) == .failure(.emptyStretch))
    }

    @Test func amountsOnlyFromCompleteDays() {
        let entries = steadyDay(2026, 11, 17, feeds: 8) + steadyDay(2026, 11, 18, feeds: 8)
            + steadyDay(2026, 11, 19, feeds: 8, ml: nil)
        let claim = PatternClaim(.most, .bottleML, recent: DateSpan(date("2026-11-18"), date("2026-11-18")),
                                 earlier: DateSpan(date("2026-11-17"), date("2026-11-19")), template: "{value} {when}")
        #expect(check(claim, entries) == .failure(.incompleteDays))
    }

    @Test func theMostOfAStretch() {
        var entries: [EventSnapshot] = []
        for day in 13...19 {
            let hours: Double = day == 17 ? 5 : 3
            entries.append(entry(.sleep, at(2026, 11, day, 22), end: at(2026, 11, day, 22).addingTimeInterval(.hours(hours))))
        }
        let claim = PatternClaim(.most, .longestSleep, nights: true, recent: DateSpan(date("2026-11-17"), date("2026-11-17")),
                                 earlier: DateSpan(date("2026-11-13"), date("2026-11-19")),
                                 template: "The longest sleep of the last {days} nights was {value}, on {when}.")
        #expect(check(claim, entries) == .success(["value": "5h", "when": "Tuesday night", "days": "7"]))
        var wrongNight = claim
        wrongNight.recent = DateSpan(date("2026-11-18"), date("2026-11-18"))
        #expect(check(wrongNight, entries) == .failure(.patternUntrue))
    }

    @Test func runsAndSteadyDays() {
        let rising = steadyDay(2026, 11, 17, feeds: 6) + steadyDay(2026, 11, 18, feeds: 7) + steadyDay(2026, 11, 19, feeds: 8)
        let run = PatternClaim(.risingRun, .feeds, recent: DateSpan(date("2026-11-17"), date("2026-11-19")),
                               template: "Feeds rose each day for {days} days.")
        #expect(check(run, rising) == .success(["days": "3"]))
        var falling = run
        falling.shape = .fallingRun
        #expect(check(falling, rising) == .failure(.patternUntrue))
        let tooShort = PatternClaim(.risingRun, .feeds, recent: DateSpan(date("2026-11-18"), date("2026-11-19")), template: "")
        #expect(check(tooShort, rising) == .failure(.patternSpan))

        let steady = steadyDay(2026, 11, 17, feeds: 8) + steadyDay(2026, 11, 18, feeds: 8) + steadyDay(2026, 11, 19, feeds: 9)
        let same = PatternClaim(.steady, .feeds, recent: DateSpan(date("2026-11-17"), date("2026-11-19")),
                                template: "Feeds stayed between {low} and {high} a day.")
        #expect(check(same, steady) == .success(["low": "8", "high": "9", "days": "3"]))
        #expect(check(same, rising) == .failure(.patternUntrue))
    }

    @Test func theLongestSleepComesAfterTheBath() {
        var after: [EventSnapshot] = []
        var before: [EventSnapshot] = []
        for day in 16...18 {
            after += [entry(.bath, at(2026, 11, day, 18, 30)),
                      entry(.sleep, at(2026, 11, day, 19, 30), end: at(2026, 11, day + 1, 1))]
            before += [entry(.bath, at(2026, 11, day, 18, 30)),
                       entry(.sleep, at(2026, 11, day, 19, 30), end: at(2026, 11, day, 21, 30)),
                       entry(.sleep, at(2026, 11, day + 1, 0), end: at(2026, 11, day + 1, 5))]
        }
        let claim = PatternClaim(.comesAfter, .longestSleep, nights: true,
                                 recent: DateSpan(date("2026-11-16"), date("2026-11-18")),
                                 template: "On {count} of the {of} nights with a bath, the longest sleep began soon after it.")
        #expect(check(claim, after) == .success(["count": "3", "of": "3"]))
        #expect(check(claim, before) == .failure(.patternUntrue))
        var days = claim
        days.nights = false
        #expect(check(days, after) == .failure(.patternSpan))
    }
}

@Suite("Answer check: passages")
struct AnswerCheckPassageTests {
    let now = at(2026, 11, 25, 10)
    var bottleOnly: InsightFacts {
        facts(steadyDay(2026, 11, 24, feeds: 8) + [entry(.sleep, at(2026, 11, 24, 22), end: at(2026, 11, 25, 4))],
              now: now, birth: date("2026-11-10"))
    }
    var allChecked: PassageChecks {
        Dictionary(uniqueKeysWithValues: NHSPassages.all.flatMap { [$0.id] + $0.summaries.map(\.id) }
            .map { ($0, date("2026-11-24")) })
    }

    func verdict(_ passages: [PassageChoice], checks: PassageChecks) -> AnswerVerdict {
        AnswerCheck.accept(CardProposal(lines: [ProposedLine("Sleep and feeds were logged.")], passages: passages),
                           facts: bottleOnly, checks: checks, timeZone: london)
    }

    @Test func onlyCheckedPassagesAndSummaries() {
        let choice = PassageChoice("night-and-day", summary: "night-and-day-s1")
        guard case .accepted(let card) = verdict([choice], checks: allChecked) else { Issue.record("rejected"); return }
        #expect(card.passages.map(\.passage.id) == ["night-and-day"])
        #expect(card.passages.first?.summary?.id == "night-and-day-s1")

        // Not yet checked by Parent A.
        #expect(verdict([choice], checks: [:]) == .rejected(
            [Rejection(part: "passage", reason: .unknownPassage("night-and-day"))], needsHelpNow: false))
        // The summary not yet checked: the card is turned down, and the AI tries again.
        var noSummary = allChecked
        noSummary["night-and-day-s1"] = nil
        #expect(verdict([choice], checks: noSummary) == .rejected(
            [Rejection(part: "passage", reason: .unknownSummary("night-and-day-s1"))], needsHelpNow: false))
        // Another passage's summary.
        #expect(verdict([PassageChoice("night-and-day", summary: "newborn-sleep-s1")], checks: allChecked) == .rejected(
            [Rejection(part: "passage", reason: .unknownSummary("newborn-sleep-s1"))], needsHelpNow: false))
    }

    @Test func neverABreastfeedingPassageForABottleOnlyHousehold() {
        #expect(verdict([PassageChoice("feeding-well-signs")], checks: allChecked) == .rejected(
            [Rejection(part: "passage", reason: .unknownPassage("feeding-well-signs"))], needsHelpNow: false))
        guard case .accepted = verdict([PassageChoice("bottle-guided")], checks: allChecked) else {
            Issue.record("the bottle passage was turned down"); return
        }
    }

    @Test func neverTheUrgentList() {
        // The urgent list belongs to the Get help now card, which no AI opens on its own words.
        #expect(verdict([PassageChoice("urgent-help")], checks: allChecked) == .rejected(
            [Rejection(part: "passage", reason: .unknownPassage("urgent-help"))], needsHelpNow: false))
    }
}
