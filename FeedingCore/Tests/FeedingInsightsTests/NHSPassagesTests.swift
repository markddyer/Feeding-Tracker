import Foundation
import Testing
import FeedingCore
@testable import FeedingInsights

// The NHS passages and their chooser (task AI4; A4, D10, R7 with D9, finding 3, O8).

@Suite("NHS passages")
struct NHSPassagesTests {
    let today = date("2026-11-25")

    /// Every passage and summary checked today.
    var allChecked: PassageChecks {
        Dictionary(uniqueKeysWithValues: NHSPassages.all.flatMap { [$0.id] + $0.summaries.map(\.id) }.map { ($0, today) })
    }

    @Test func everyPassageIsComplete() {
        let ids = NHSPassages.all.flatMap { [$0.id] + $0.summaries.map(\.id) }
        #expect(Set(ids).count == ids.count, "IDs must be unique")
        // The plan's library is 25 to 60 passages (A4).
        #expect((25...60).contains(NHSPassages.all.count))
        for passage in NHSPassages.all {
            #expect(passage.url.hasPrefix("https://www.nhs.uk/"), "\(passage.id)")
            #expect(!passage.page.isEmpty && !passage.words.isEmpty, "\(passage.id)")
            #expect(!passage.topics.isEmpty, "\(passage.id)")
            #expect(!passage.summaries.isEmpty, "\(passage.id)")
            #expect(passage.copied == NHSPassages.copied)
            #expect(passage.words.hasPrefix("##"), "\(passage.id) starts with its section's heading")
            #expect(!passage.words.contains("https://"), "\(passage.id) has no picture credits")
            #expect(!passage.words.contains("Information:"), "\(passage.id) has no box labels")
            for line in passage.words.split(separator: "\n") {
                let linkLine = ["Find out", "Read more", "Read the", "Learn how", "See when"].contains { line.hasPrefix($0) }
                #expect(!linkLine, "\(passage.id) has a link to another page: \(line)")
            }
        }
        let urgentCount = NHSPassages.all.filter { $0.isUrgent }.count
        #expect(urgentCount == 1)
    }

    @Test func postnatalDepressionAlwaysComesWithUrgentHelp() {
        for (lead, partner) in NHSPassages.shownWith {
            #expect(NHSPassages.passage(lead) != nil && NHSPassages.passage(partner) != nil)
        }
        // With both checked, at any limit and on any day, urgent help comes straight after it.
        for offset in 0..<30 {
            for limit in 1...4 {
                let shown = NHSPassages.choose(topics: [.parentsMood], ageInDays: 30, breastfeeds: true, bottleFeeds: true,
                                               checks: allChecked, today: today.adding(days: offset), limit: limit)
                let ids = shown.map(\.id)
                if let index = ids.firstIndex(of: "postnatal-depression-help") {
                    #expect(ids.count > index + 1 && ids[index + 1] == "mental-health-urgent", "\(ids)")
                    #expect(ids.filter { $0 == "mental-health-urgent" }.count == 1, "\(ids)")
                }
            }
        }
        let everyDay = (0..<30).flatMap { offset in
            NHSPassages.choose(topics: [.parentsMood], ageInDays: 30, breastfeeds: true, bottleFeeds: true,
                               checks: allChecked, today: today.adding(days: offset), limit: 1).map(\.id)
        }
        #expect(everyDay.contains("postnatal-depression-help"))
        // Urgent help not checked: the postnatal depression passage is never offered.
        var checks = allChecked
        checks["mental-health-urgent"] = nil
        for offset in 0..<30 {
            let shown = NHSPassages.choose(topics: [.parentsMood], ageInDays: 30, breastfeeds: true, bottleFeeds: true,
                                           checks: checks, today: today.adding(days: offset), limit: 4)
            #expect(!shown.contains { $0.id == "postnatal-depression-help" })
        }
    }

    @Test func everyTopicHasAPassage() {
        for topic in InsightTopic.allCases {
            let has = NHSPassages.all.contains { $0.topics.contains(topic) }
            #expect(has, "\(topic)")
        }
        // A bath logged can bring a bathing passage.
        let bath = NHSPassages.choose(kinds: [.bath], ageInDays: 30, breastfeeds: true, bottleFeeds: false,
                                      checks: allChecked, today: today, limit: 5)
        #expect(!bath.isEmpty)
        let allBathing = bath.allSatisfy { $0.topics.contains(.bathing) }
        #expect(allBathing)
        // A breastfeeding-only household never gets a formula passage.
        let breastOnly = NHSPassages.choose(kinds: [.feed, .nappy, .weight], ageInDays: 30, breastfeeds: true,
                                            bottleFeeds: false, checks: allChecked, today: today, limit: 40)
        let anyBottle = breastOnly.contains { $0.feeding == .bottleFeeding }
        #expect(!anyBottle)
    }

    @Test func theUrgentListHasTheCallLines() {
        let words = NHSPassages.urgent.words
        #expect(words.contains("Immediate action required: Call 999 or go to A&E if:"))
        #expect(words.contains("Urgent advice: Call NHS 111 if:"))
        #expect(words.contains("has not had a pee in the past 12 hours"))
    }

    @Test func theCreditTheNHSAsksFor() {
        #expect(NHSPassages.urgent.attribution == "Information from the NHS website, as at 22/11/26")
        #expect(NHSPassages.licenceStatement == "Information from the NHS website is licensed under the Open Government Licence v3.0")
    }

    @Test func nothingIsOfferedUntilChecked() {
        #expect(NHSPassages.choose(kinds: [.feed, .nappy, .sleep], ageInDays: 10, breastfeeds: true, bottleFeeds: true,
                                   checks: [:], today: today, limit: 3).isEmpty)
        #expect(NHSPassages.needsChecking([:], today: today).count
                == NHSPassages.all.count + NHSPassages.all.flatMap(\.summaries).count)
        #expect(NHSPassages.needsChecking(allChecked, today: today).isEmpty)
    }

    @Test func checksLastNinetyDays() {
        let id = "night-and-day"
        let checkedOn = date("2026-11-23")
        #expect(NHSPassages.isChecked(id, copied: NHSPassages.copied, checks: [id: checkedOn], today: checkedOn.adding(days: 90)))
        #expect(!NHSPassages.isChecked(id, copied: NHSPassages.copied, checks: [id: checkedOn], today: checkedOn.adding(days: 91)))
        // Checked before the copy was made: the copy is new, so it needs checking.
        #expect(!NHSPassages.isChecked(id, copied: NHSPassages.copied, checks: [id: date("2026-11-21")], today: today))
        // A check dated after today (a clock set back) doesn't count.
        #expect(!NHSPassages.isChecked(id, copied: NHSPassages.copied, checks: [id: today.adding(days: 1)], today: today))
    }

    @Test func pickedByKindAgeAndFeeding() {
        let picks = NHSPassages.choose(kinds: [.sleep], ageInDays: 10, breastfeeds: false, bottleFeeds: true,
                                       checks: allChecked, today: today, limit: 20)
        #expect(!picks.isEmpty)
        let sleepTopics = Set(InsightTopic.topics(for: .sleep))
        let aboutSleep = picks.allSatisfy { !sleepTopics.isDisjoint(with: $0.topics) }
        #expect(aboutSleep)
        let anyUrgent = picks.contains { $0.isUrgent }
        #expect(!anyUrgent)

        // A bottle-only household never gets a breastfeeding passage (A8).
        let bottleOnly = NHSPassages.choose(kinds: [.feed], ageInDays: 10, breastfeeds: false, bottleFeeds: true,
                                            checks: allChecked, today: today, limit: 20)
        #expect(!bottleOnly.isEmpty)
        let anyBreastfeeding = bottleOnly.contains { $0.feeding == .breastfeeding }
        #expect(!anyBreastfeeding)

        // With no birth date, only passages for any age.
        let noAge = NHSPassages.choose(kinds: [.feed, .nappy, .sleep], ageInDays: nil, breastfeeds: true, bottleFeeds: true,
                                       checks: allChecked, today: today, limit: 20)
        let allAnyAge = noAge.allSatisfy { $0.ageInDays == nil }
        #expect(allAnyAge)
        // An older baby: no newborn-only passages.
        let older = NHSPassages.choose(kinds: [.sleep], ageInDays: 200, breastfeeds: true, bottleFeeds: true,
                                       checks: allChecked, today: today, limit: 20)
        let hasNewborn = older.contains { $0.id == "newborn-sleep" }
        #expect(!hasNewborn)
    }

    @Test func theSamePicksForTheSameDayAndTheyTurn() {
        let pick = { (day: PlainDate) in
            NHSPassages.choose(kinds: [.feed, .nappy, .sleep], ageInDays: 10, breastfeeds: true, bottleFeeds: true,
                               checks: allChecked, today: day, limit: 2).map(\.id)
        }
        #expect(pick(today) == pick(today))
        #expect(pick(today).count == 2)
        let tenDays = Set((0..<10).map { pick(today.adding(days: $0)) })
        #expect(tenDays.count > 1)
    }

    @Test func neverChosenByHowMuch() {
        // Finding 3 and O8: the same kinds and age with every value changed give the same pick.
        let now = at(2026, 11, 25, 10)
        func household(nappies: Int, ml: Int) -> [EventSnapshot] {
            (0..<nappies).map { entry(.nappy, at(2026, 11, 24, 6).addingTimeInterval(.hours(Double($0))), payload: nappy()) }
                + [entry(.feed, at(2026, 11, 24, 9), payload: bottle(ml)),
                   entry(.sleep, at(2026, 11, 24, 13), end: at(2026, 11, 24, 14))]
        }
        let few = facts(household(nappies: 2, ml: 30), now: now, birth: date("2026-11-10"))
        let many = facts(household(nappies: 9, ml: 180), now: now, birth: date("2026-11-10"))
        #expect(few.yesterday?.wees != many.yesterday?.wees)
        let checks = allChecked
        let fewPicks = NHSPassages.choose(for: few, checks: checks, limit: 4)
        #expect(!fewPicks.isEmpty)
        for limit in 1...4 {
            #expect(NHSPassages.choose(for: few, checks: checks, limit: limit).map(\.id)
                    == NHSPassages.choose(for: many, checks: checks, limit: limit).map(\.id))
        }
    }

    @Test func checksAreKeptInTheHousehold() {
        var data = HouseholdData()
        let t0 = at(2026, 11, 23, 9)
        #expect(data.passageChecks.isEmpty)
        data.setPassageCheck("night-and-day", checkedOn: date("2026-11-23"), now: t0)
        data.setPassageCheck("night-and-day-s1", checkedOn: date("2026-11-23"), now: t0)
        #expect(data.passageChecks == ["night-and-day": date("2026-11-23"), "night-and-day-s1": date("2026-11-23")])
        // One Setting record each, so ticks of different passages never clash.
        let names = Set(data.plainRecords(of: .setting).map(\.name))
        #expect(names == ["passageCheck-night-and-day", "passageCheck-night-and-day-s1"])

        // Taking the tick off: the record stays, with no date, so the other phone hears of it.
        data.setPassageCheck("night-and-day-s1", checkedOn: nil, now: t0.addingTimeInterval(60))
        #expect(data.passageChecks == ["night-and-day": date("2026-11-23")])
        #expect(data.plainRecords(of: .setting).count == 2)

        // The same check again changes nothing.
        let before = data.plainRecords(of: .setting)
        data.setPassageCheck("night-and-day", checkedOn: date("2026-11-23"), now: t0.addingTimeInterval(120))
        #expect(data.plainRecords(of: .setting) == before)

        #expect(!NHSPassages.needsChecking(data.passageChecks, today: date("2026-11-23")).contains("night-and-day"))
        #expect(NHSPassages.needsChecking(data.passageChecks, today: date("2026-11-23")).contains("night-and-day-s1"))
    }

    @Test func summariesAreGeneralAndApart() {
        for passage in NHSPassages.all {
            for summary in passage.summaries {
                #expect(summary.id.hasPrefix(passage.id), "\(summary.id)")
                let words = WordReader.words(summary.words)
                for aboutTheBaby in ["she", "he", "her", "his", "your", "logged"] {
                    #expect(!words.contains(aboutTheBaby), "\(summary.id) speaks of the baby or the log: \(aboutTheBaby)")
                }
            }
        }
    }
}

// AI insights step 4: the "About … ›" link on a form (D5 A, D6 A, F12, Y7).
@Suite("NHS passages for a link")
struct NHSLinkPassagesTests {
    let today = date("2026-11-25")
    var allChecked: PassageChecks {
        Dictionary(uniqueKeysWithValues: NHSPassages.all.flatMap { [$0.id] + $0.summaries.map(\.id) }.map { ($0, today) })
    }

    @Test func aBottleOnlyHouseholdIsNeverOfferedBreastfeeding() {
        let bottleOnly = NHSPassages.forLink(.feed, ageInDays: 10, breastfeeds: false, bottleFeeds: true,
                                             checks: allChecked, today: today)
        #expect(!bottleOnly.isEmpty)
        #expect(!bottleOnly.contains { $0.feeding == .breastfeeding })
        let both = NHSPassages.forLink(.feed, ageInDays: 10, breastfeeds: true, bottleFeeds: true, checks: allChecked, today: today)
        #expect(both.contains { $0.feeding == .breastfeeding })
    }

    @Test func onlyTickedPassagesWithinNinetyDays() {
        #expect(NHSPassages.forLink(.nappy, ageInDays: 10, breastfeeds: true, bottleFeeds: false, checks: [:], today: today).isEmpty)
        let late = today.adding(days: NHSPassages.checkEveryDays + 1)
        #expect(NHSPassages.forLink(.nappy, ageInDays: 10, breastfeeds: true, bottleFeeds: false, checks: allChecked, today: late).isEmpty)
    }

    /// Y7: the link lists every passage for its subject, so a pair a card never shows together is
    /// never dropped (they open one at a time); in the library's order, the same every day.
    @Test func nothingIsDroppedAndNothingTurnsByDay() {
        let nappies = NHSPassages.forLink(.nappy, ageInDays: 10, breastfeeds: true, bottleFeeds: false,
                                          checks: allChecked, today: today)
        let ids = nappies.map(\.id)
        #expect(ids.contains("poo-how-often") && ids.contains("feeding-well-signs"))
        #expect(ids == NHSPassages.all.map(\.id).filter(ids.contains), "the library's order")
        let tomorrow = NHSPassages.forLink(.nappy, ageInDays: 11, breastfeeds: true, bottleFeeds: false,
                                           checks: allChecked, today: today.adding(days: 1))
        #expect(tomorrow.map(\.id) == ids)
        #expect(!nappies.contains { $0.isUrgent })
    }

    @Test func aPassageIsNamedByItsFirstHeading() throws {
        let passage = try #require(NHSPassages.passage("poo-how-often"))
        #expect(!passage.title.hasPrefix("#"))
        #expect(passage.words.contains("## " + passage.title))
    }
}
