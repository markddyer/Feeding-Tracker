import FeedingCore
import Foundation
import Testing
@testable import FeedingDev

/// The words for sleep, nappies, medicine and growth: facts only, and weights in kilograms with
/// pounds and ounces beside (the users' choice N, 17 Nov 2026).
@Suite("Sleep, nappy, medicine and growth words")
struct CareTextTests {
    let london = TimeZone(identifier: "Europe/London")!

    @Test func weightsInKilogramsWithPoundsAndOunces() {
        #expect(CareText.kilograms(3850) == "3.85 kg")
        #expect(CareText.poundsAndOunces(3850) == "8 lb 8 oz")
        #expect(CareText.weight(3850) == "3.85 kg (8 lb 8 oz)")
        // 3.4 kg is 119.93 oz: rounded to 120 oz, which is 7 lb 8 oz.
        #expect(CareText.poundsAndOunces(3400) == "7 lb 8 oz")
        // 15.5 oz rounds up to a whole pound, never "0 lb 16 oz".
        #expect(CareText.poundsAndOunces(453) == "1 lb 0 oz")
    }

    @Test func aTypedWeightIsReadInKilograms() {
        #expect(CareText.grams(fromKilograms: "3.85") == 3850)
        #expect(CareText.grams(fromKilograms: "3,85 kg") == 3850)
        #expect(CareText.grams(fromKilograms: "3850") == nil)
        #expect(CareText.grams(fromKilograms: "") == nil)
        #expect(CareText.millimetres(fromCentimetres: "52.5") == 525)
        #expect(CareText.millimetres(fromCentimetres: "5") == nil)
        #expect(CareText.centimetres(525) == "52.5 cm")
    }

    @Test func aNappyInWords() {
        #expect(CareText.nappyKind(wee: true, poo: true) == "wee and poo")
        #expect(CareText.nappyLogged(wee: false, poo: true) == "Poo logged")
        #expect(CareText.nappyLine(NappyDetails(wee: false, poo: true, colour: .yellow, consistency: .loose)) == "Poo · yellow, loose")
        #expect(CareText.nappyLine(NappyDetails(wee: true, poo: true, colour: .green)) == "Wee and poo · green")
        #expect(CareText.nappyLine(NappyDetails(wee: true, poo: false)) == "Wee")
        // A colour from a newer app version still reads.
        #expect(CareText.nappyLine(NappyDetails(wee: false, poo: true, colour: "black")) == "Poo · black")
    }

    @Test func aWeeHasNoPooDetails() {
        #expect(CareText.pooDetails(NappyDetails(wee: true, poo: false, colour: .green)) == nil)
    }

    @Test func sleepInWords() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let asleep = SleepState.asleep(id: "s", since: now.addingTimeInterval(-80 * 60))
        #expect(CareText.sleepWord(asleep) == "Asleep")
        #expect(CareText.sleepElapsed(asleep, now: now) == "1h 20m")
        #expect(CareText.sleepButton(asleep) == "Woke up")
        #expect(CareText.sleepButton(.awake(since: now)) == "Fell asleep")
        #expect(CareText.sleepButton(.notLogged) == "Fell asleep")
        #expect(CareText.sleepElapsed(.notLogged, now: now) == nil)
    }

    @Test func lastGivenSaysWhenNeverWhenNext() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 18)))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 8, minute: 10)))
        let lastNight = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 20)))
        let older = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9)))
        // The phone's own time and date style ("08:10" in the UK, "8:10 AM" in the US).
        let clock = { (date: Date) in date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: london)) }
        #expect(CareText.lastGiven(morning, now: now, in: london) == clock(morning))
        #expect(CareText.lastGiven(lastNight, now: now, in: london) == "Yesterday \(clock(lastNight))")
        let day = older.formatted(Date.FormatStyle(timeZone: london).day().month(.abbreviated))
        #expect(CareText.lastGiven(older, now: now, in: london) == day)
        #expect(!CareText.lastGiven(older, now: now, in: london).contains(clock(older)))
    }

    /// No word that sounds like medical advice (CLAUDE.md, "Hard rules").
    @Test func noAdviceWords() {
        let now = Date()
        let words = [
            CareText.sleepWord(.notLogged), CareText.sleepWord(.awake(since: now)), CareText.sleepButton(.notLogged),
            CareText.nappyLine(NappyDetails(wee: true, poo: true, colour: .green, consistency: .liquid)),
            CareText.growthLine(GrowthDetails(weightGrams: 3850, lengthMM: 525, headMM: 360)),
            CareText.medicineLine(MedicineDetails(name: "Vitamin D", amount: "1 drop")),
        ] + PooColour.known.map(CareText.colourName) + PooConsistency.known.map(CareText.consistencyName)
        for text in words {
            for banned in ["due", "missed", "overdue", "should", "normal", "healthy", "worry", "next dose"] {
                #expect(!text.lowercased().contains(banned), "\(text) says \(banned)")
            }
        }
    }

    /// Change time's quick choices are earlier than the time logged, and say so.
    @Test func changeTimeChoicesSayEarlier() {
        #expect(CareText.minutesEarlier(5) == "5 min earlier")
    }

    /// On the days the clocks change, the rhythm rows place a time by the clock, so noon sits
    /// under "12" (Codex review, 17 Nov 2026).
    @Test(arguments: [(2026, 10, 25), (2026, 3, 29), (2026, 11, 17)])
    func noonSitsUnderTwelve(_ day: (Int, Int, Int)) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        let start = try #require(calendar.date(from: DateComponents(year: day.0, month: day.1, day: day.2)))
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let noon = try #require(calendar.date(from: DateComponents(year: day.0, month: day.1, day: day.2, hour: 12)))
        #expect(RhythmRow.clockShare(noon, dayStart: start, dayEnd: end, zone: london) == 0.5)
        #expect(RhythmRow.clockShare(start, dayStart: start, dayEnd: end, zone: london) == 0)
        #expect(RhythmRow.clockShare(end, dayStart: start, dayEnd: end, zone: london) == 1)
    }

    @Test func historyFiltersCoverEveryKind() {
        let all = HistoryFilter.all.kinds
        for filter in HistoryFilter.allCases where filter != .all {
            #expect(filter.kinds.isSubset(of: all))
        }
        // "All" shows every kind this build knows, bath included (it was once left out).
        #expect(all == Set(EventKind.known))
        #expect(all.contains(.bath))
        // And every kind has a button besides All (Baths added, 24 Nov 2026).
        let buttons = HistoryFilter.allCases.filter { $0 != .all }.reduce(into: Set<EventKind>()) { $0.formUnion($1.kinds) }
        #expect(buttons == all)
    }
}
