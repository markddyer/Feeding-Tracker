import FeedingCore
import FeedingInsights
import Foundation

// AI13's made-up households (`docs/planning/12-ai-insights-gauntlet.md`, step 2 D7 C): 30 recipes,
// each built into a household the same way on Linux (`ModelTestHouseholdsTests`, no AI) and in the
// simulator (`ModelTests/ModelTests.swift`, the real model). Never real data: every name, note and
// medicine here is made up, and the names and notes are "secrets" that must never reach a request.
//
// gstack-shortcut(dec-5b7b346c): 30 households can't tell a real change from chance; upgrade to 100
// households, gate at 90, when a run fails, when the model or package changes, or when a parent
// reports a wrong card.

/// One made-up household, ready for a card of `kind` at `now`.
struct ModelTestHousehold: Sendable {
    let name: String
    let kind: CardKind
    let data: HouseholdData
    let babyID: String
    let now: Date
    let parentA: MemberID
    let parentB: MemberID
    /// Words that must never be in what is sent: the names, the notes, the medicines.
    let secrets: [String]
}

/// How a household feeds, logs and lives, and when its card is made.
struct ModelTestRecipe: Sendable {
    enum Feeding: Sendable { case breast, formula, expressed, mixed }

    var name: String
    var kind: CardKind = .morning
    var zone = "Europe/London"
    /// When the card is made, on the household's clock: "2026-11-30 08:30". On or after 25 Nov 2026,
    /// as a tick made before the passages were copied (22 Nov 2026) doesn't count.
    var now: String
    /// Days logged before today (today is logged up to `now`).
    var days = 28
    /// The baby's age in whole weeks at `now`; nil for no birth date.
    var ageWeeks: Int? = 6
    var feeding: Feeding = .mixed
    /// Feeds a day at the start, and at the end (a trend), with `wakes` of them at night.
    var feeds = 8
    var feedsEnd: Int?
    var wakes = 3
    var sleep = true
    var nappies = true
    var pump = false
    /// Weights logged, a week apart, the last 2 days ago.
    var weights = 3
    var baths = false
    var medicines = true
    /// Parent A has ticked every NHS passage and summary.
    var ticked = true
    /// The last night feed was logged on both phones.
    var duplicates = false
    /// A feed is running at `now`.
    var running = false
    /// Days back from today with nothing logged.
    var gapDays: [Int] = []
}

enum ModelTestHouseholds {
    static let secrets = ["Rowan", "Jude", "Pip", "Vitamin D", "Gripe water", "SECRET-NOTE"]

    static let recipes: [ModelTestRecipe] = [
        // The morning card (20).
        ModelTestRecipe(name: "m01-mixed-steady", now: "2026-11-30 08:30"),
        ModelTestRecipe(name: "m02-breast-newborn", now: "2026-12-01 09:10", days: 9, ageWeeks: 1, feeding: .breast,
                        feeds: 10, feedsEnd: 12, wakes: 4, weights: 2),
        ModelTestRecipe(name: "m03-formula-older", now: "2026-11-28 07:40", ageWeeks: 16, feeding: .formula, feeds: 6,
                        wakes: 1, weights: 5),
        ModelTestRecipe(name: "m04-feeds-rising", now: "2026-12-02 08:15", ageWeeks: 8, feeds: 7, feedsEnd: 10),
        ModelTestRecipe(name: "m05-feeds-falling", now: "2026-12-03 10:30", ageWeeks: 10, feeding: .breast, feeds: 10,
                        feedsEnd: 7, wakes: 2),
        ModelTestRecipe(name: "m06-three-days", now: "2026-11-30 07:20", days: 3, ageWeeks: 2, feeding: .breast, feeds: 9,
                        weights: 0),
        ModelTestRecipe(name: "m07-feeds-only", now: "2026-12-04 08:00", ageWeeks: 4, feeding: .formula, sleep: false,
                        nappies: false, weights: 0, medicines: false),
        ModelTestRecipe(name: "m08-nappies-no-sleep", now: "2026-12-05 09:45", ageWeeks: 3, feeding: .breast, sleep: false),
        ModelTestRecipe(name: "m09-pumping", now: "2026-12-06 08:05", ageWeeks: 5, feeding: .expressed, pump: true),
        ModelTestRecipe(name: "m10-no-birth-date", now: "2026-12-07 11:50", ageWeeks: nil),
        ModelTestRecipe(name: "m11-no-ticks", now: "2026-11-29 08:20", ageWeeks: 7, ticked: false),
        ModelTestRecipe(name: "m12-both-phones", now: "2026-12-08 07:30", ageWeeks: 9, duplicates: true),
        ModelTestRecipe(name: "m13-feed-running", now: "2026-12-09 08:40", ageWeeks: 6, feeding: .breast, running: true),
        ModelTestRecipe(name: "m14-gap-days", now: "2026-12-10 09:00", ageWeeks: 11, gapDays: [3, 4, 9]),
        ModelTestRecipe(name: "m15-kolkata", zone: "Asia/Kolkata", now: "2026-12-11 08:10", ageWeeks: 5),
        ModelTestRecipe(name: "m16-new-york", zone: "America/New_York", now: "2026-12-12 07:45", ageWeeks: 12,
                        feeding: .formula, feeds: 7, wakes: 2),
        ModelTestRecipe(name: "m17-clocks-go-back", now: "2027-10-31 09:00", ageWeeks: 6),
        ModelTestRecipe(name: "m18-clocks-go-forward", now: "2027-03-28 08:30", ageWeeks: 4, feeding: .breast),
        ModelTestRecipe(name: "m19-many-wakes", now: "2026-12-14 07:15", ageWeeks: 3, feeding: .breast, feeds: 11, wakes: 6),
        ModelTestRecipe(name: "m20-baths-medicines", now: "2026-12-15 08:50", ageWeeks: 12, feeding: .formula, feeds: 6,
                        wakes: 1, baths: true),
        // "This week" (10).
        ModelTestRecipe(name: "w01-mixed-steady", kind: .week, now: "2026-11-30 10:00"),
        ModelTestRecipe(name: "w02-feeds-rising", kind: .week, now: "2026-12-02 15:00", ageWeeks: 9, feeds: 7, feedsEnd: 10),
        ModelTestRecipe(name: "w03-breast-falling", kind: .week, now: "2026-12-06 18:00", ageWeeks: 10, feeding: .breast,
                        feeds: 10, feedsEnd: 7, wakes: 2),
        ModelTestRecipe(name: "w04-three-days", kind: .week, now: "2026-12-07 10:00", days: 3, ageWeeks: 2, feeding: .breast,
                        feeds: 9, weights: 1),
        ModelTestRecipe(name: "w05-clocks-go-back", kind: .week, now: "2027-11-01 10:00", ageWeeks: 7),
        ModelTestRecipe(name: "w06-adelaide", kind: .week, zone: "Australia/Adelaide", now: "2026-12-08 09:30", ageWeeks: 8),
        ModelTestRecipe(name: "w07-formula-older", kind: .week, now: "2026-12-09 12:00", ageWeeks: 20, feeding: .formula,
                        feeds: 6, wakes: 1, weights: 5, baths: true),
        ModelTestRecipe(name: "w08-gap-days", kind: .week, now: "2026-11-30 10:00", ageWeeks: 6, gapDays: [2, 5, 12]),
        ModelTestRecipe(name: "w09-pumping", kind: .week, now: "2026-12-01 16:00", ageWeeks: 5, feeding: .expressed, pump: true),
        ModelTestRecipe(name: "w10-no-ticks-no-birth", kind: .week, now: "2026-12-03 09:00", ageWeeks: nil, ticked: false),
    ]

    /// The 30 households; with `bothYes` false, only Parent A has said yes.
    static func all(bothYes: Bool = true) -> [ModelTestHousehold] {
        recipes.enumerated().map { build($1, seed: UInt64($0 + 1), bothYes: bothYes) }
    }

    /// The household for `recipe`, the same every time for the same seed.
    static func build(_ recipe: ModelTestRecipe, seed: UInt64, bothYes: Bool = true) -> ModelTestHousehold {
        let zone = TimeZone(identifier: recipe.zone)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var random = SplitMix(seed: seed)
        let parts = recipe.now.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == ":" }).compactMap { Int($0) }
        let now = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3],
                                                     minute: parts[4]))!
        let today = PlainDate(now, in: zone)
        /// A time on `day`, `minutes` after its midnight (past 1440 runs into the next day).
        func at(_ day: PlainDate, _ minutes: Int) -> Date {
            let date = day.adding(days: minutes / 1440)
            let rest = minutes % 1440
            return calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day,
                                                      hour: rest / 60, minute: rest % 60))!
        }

        let a: MemberID = "model-test-parent-a", b: MemberID = "model-test-parent-b"
        let baby = "model-test-baby"
        let start = now.addingTimeInterval(-40 * 86400)
        var data = HouseholdData()
        data.updateHouseholdSettings(by: a, now: start) { $0.timeZoneID = recipe.zone }
        let birth = recipe.ageWeeks.map { today.adding(days: -($0 * 7) - random.int(0...6)) }
        data.put(PlainRecord(type: .baby, name: baby, modifiedAt: start,
                             payload: try? PayloadCoder.encode(BabyPayload(name: "Pip", birthDate: birth))))
        data.put(PlainRecord(type: .member, name: a.rawValue, modifiedAt: start,
                             payload: try? PayloadCoder.encode(MemberPayload(displayName: "Rowan", colour: "sunflower"))))
        data.put(PlainRecord(type: .member, name: b.rawValue, modifiedAt: start,
                             payload: try? PayloadCoder.encode(MemberPayload(displayName: "Jude", colour: "teal"))))

        var count = 0
        func add(_ kind: EventKind, _ startedAt: Date, minutes: Int? = nil, _ payload: EventPayload, by member: MemberID) {
            guard startedAt < now else { return }
            count += 1
            data.add(id: "\(recipe.name)-\(count)", kind: kind, babyID: baby, startedAt: startedAt,
                     endedAt: minutes.map { min(startedAt.addingTimeInterval(Double($0) * 60), now) },
                     payload: payload, by: member, timeZoneID: recipe.zone, now: startedAt)
        }
        func feedDetails(_ index: Int, ageDays: Int) -> FeedDetails {
            let ml = min(210, 60 + ageDays * 2) + random.int(-10...10)
            let breast = [BreastSegment(side: index.isMultiple(of: 2) ? .left : .right, durationSeconds: random.int(8...18) * 60),
                          BreastSegment(side: index.isMultiple(of: 2) ? .right : .left, durationSeconds: random.int(0...10) * 60)]
                .filter { ($0.durationSeconds ?? 0) > 0 }
            switch recipe.feeding {
            case .breast: return FeedDetails(breast: breast)
            case .formula: return FeedDetails(bottles: [Bottle(milk: .formula, ml: ml)])
            case .expressed: return FeedDetails(bottles: [Bottle(milk: .expressed, ml: ml)])
            case .mixed:
                return index % 3 == 1 ? FeedDetails(bottles: [Bottle(milk: .formula, ml: ml)]) : FeedDetails(breast: breast)
            }
        }

        let first = today.adding(days: -recipe.days)
        let total = max(1, recipe.days)
        var lastNightFeed: (Date, FeedDetails)?
        for offset in 0...recipe.days {
            let day = first.adding(days: offset)
            let back = today.days(since: day)
            if recipe.gapDays.contains(back) { continue }
            let ageDays = (birth.map { day.days(since: $0) } ?? 42)
            let perDay = recipe.feeds + Int((Double((recipe.feedsEnd ?? recipe.feeds) - recipe.feeds) * Double(offset)
                / Double(total)).rounded())
            let dayFeeds = max(1, perDay - recipe.wakes)
            // Day feeds from 07:30 to 20:30, night feeds from 22:00 to 06:00 the next morning.
            var feedTimes: [Int] = (0..<dayFeeds).map { 450 + $0 * (780 / max(1, dayFeeds - 1)) + random.int(-25...25) }
            feedTimes += (0..<recipe.wakes).map { 1320 + $0 * (480 / max(1, recipe.wakes)) + random.int(0...40) }
            for (index, minutes) in feedTimes.enumerated() {
                let time = at(day, max(0, minutes))
                let details = feedDetails(index, ageDays: ageDays)
                let note = random.int(0...7) == 0 ? "SECRET-NOTE: fussy at Rowan's mum's" : nil
                add(.feed, time, minutes: random.int(10...30), EventPayload(feed: details, note: note),
                    by: index.isMultiple(of: 2) ? a : b)
                if minutes >= 1320, time < now { lastNightFeed = (time, details) }
            }
            if recipe.sleep {
                // Naps by day after some feeds, and the night's sleep between its feeds.
                let dayTimes = feedTimes.filter { $0 < 1320 }.sorted()
                let naps = random.int(3...4)
                for (index, pair) in zip(dayTimes, dayTimes.dropFirst()).enumerated() where index < naps {
                    let length = min(pair.1 - pair.0 - 45, random.int(35...110))
                    if length >= 20 {
                        add(.sleep, at(day, pair.0 + 35), minutes: length, EventPayload(), by: index.isMultiple(of: 2) ? b : a)
                    }
                }
                let night = feedTimes.filter { $0 >= 1320 }.sorted()
                var from = 1290
                for feed in night + [1860] {
                    if feed - from > 40 { add(.sleep, at(day, from), minutes: feed - from - 10, EventPayload(), by: a) }
                    from = feed + 30
                }
            }
            if recipe.nappies {
                let poos = random.int(1...4)
                for index in 0..<random.int(6...9) {
                    add(.nappy, at(day, 420 + index * 150 + random.int(0...30)),
                        EventPayload(nappy: NappyDetails(wee: true, poo: index < poos)), by: index.isMultiple(of: 2) ? b : a)
                }
            }
            if recipe.pump {
                for session in 0..<random.int(2...3) {
                    add(.pump, at(day, 600 + session * 300), minutes: 20,
                        EventPayload(pump: PumpDetails(side: .both, leftML: random.int(40...80), rightML: random.int(40...80))), by: b)
                }
            }
            if recipe.baths, back % 3 == 0 { add(.bath, at(day, 1140), EventPayload(), by: a) }
            if recipe.medicines {
                let vitamin = at(day, 540 + random.int(0...30))
                if vitamin < now {
                    _ = data.addMedicine(id: "\(recipe.name)-vitamin-\(offset)", babyID: baby, MedicineDetails(name: "Vitamin D", amount: "1 drop"),
                                     at: vitamin, by: a, timeZoneID: recipe.zone, now: vitamin)
                }
                if offset % 4 == 0 {
                    let gripe = at(day, 1200)
                    if gripe < now {
                        _ = data.addMedicine(id: "\(recipe.name)-gripe-\(offset)", babyID: baby, MedicineDetails(name: "Gripe water", amount: "2.5 ml"),
                                         at: gripe, by: b, timeZoneID: recipe.zone, now: gripe)
                    }
                }
            }
        }
        if recipe.duplicates, let (time, details) = lastNightFeed {
            // The other phone logged the same feed 2 minutes later.
            add(.feed, time.addingTimeInterval(120), minutes: 15, EventPayload(feed: details), by: b)
        }
        if let ageWeeks = recipe.ageWeeks {
            for index in 0..<recipe.weights {
                let day = today.adding(days: -2 - 7 * (recipe.weights - 1 - index))
                let weeks = max(0, ageWeeks - (recipe.weights - 1 - index))
                let grams = 3300 + weeks * 190 + random.int(-40...40)
                let time = at(day, 660)
                _ = data.addGrowth(id: "\(recipe.name)-weight-\(index)", babyID: baby, GrowthDetails(weightGrams: grams), at: time,
                               by: b, timeZoneID: recipe.zone, now: time)
            }
        }
        if recipe.running {
            _ = data.startFeed(id: "\(recipe.name)-running", babyID: baby, side: .left, by: a, timeZoneID: recipe.zone,
                           now: now.addingTimeInterval(-10 * 60))
        }
        if recipe.ticked {
            for passage in NHSPassages.all {
                for id in [passage.id] + passage.summaries.map(\.id) {
                    data.setPassageCheck(id, checkedOn: today.adding(days: -3), now: start)
                }
            }
        }
        data.setInsightYes(true, member: a, now: start)
        if bothYes { data.setInsightYes(true, member: b, now: start) }
        return ModelTestHousehold(name: recipe.name, kind: recipe.kind, data: data, babyID: baby, now: now, parentA: a,
                                  parentB: b, secrets: secrets)
    }
}

/// A small random number maker that gives the same numbers on every platform for a seed.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
}
