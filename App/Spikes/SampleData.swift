#if FEEDING_DEV && targetEnvironment(simulator)
import FeedingCore
import Foundation

/// Simulator only: fills an empty store with a made-up day, to look at the screens. The names are
/// made up (the mockup's), with different first letters so the avatars differ.
/// Launch with `-sampleData YES`. Add `-sampleFeedInProgress` for a feed: `YES` (breast, running),
/// `bottle` (a formula bottle running), `other` (the other parent's feed running) or
/// `finishedForMe` (this parent's feed, finished by the other parent, waiting for its details).
/// Add `-sampleDuplicate YES` for the last feed logged on both phones, and `-sampleNightAsk` with
/// `fromOther`, `mine`, `declined`, `meOnDuty`, `noRota` or `takenByOther` for an ask to take tonight.
/// Every sample day has sleeps, nappies and Vitamin D; the baby is asleep (1h 20m) unless
/// `-sampleSleep awake`, and the last nappy (40m ago) is a poo with no details yet.
enum SampleData {
    @MainActor
    static func loadIfAsked(into store: HouseholdStore) {
        let defaults = UserDefaults.standard
        // `-sampleDataFresh YES` starts again from an empty store (the UI tests' audit uses it).
        if defaults.bool(forKey: "sampleDataFresh") {
            store.change { $0 = HouseholdData() }
        }
        guard defaults.bool(forKey: "sampleData"), store.data.events.isEmpty else { return }
        let me: MemberID = "simulator-parent"
        let other: MemberID = "other-parent"
        let now = Date()
        let zone = TimeZone.current.identifier
        store.change { data in
            data.put(PlainRecord(type: .baby, name: "sample-baby", modifiedAt: now,
                                 payload: try? PayloadCoder.encode(BabyPayload(name: "Baby",
                                                                               birthDate: PlainDate(now, in: .current).adding(days: -12)))))
            data.put(PlainRecord(type: .member, name: me.rawValue, modifiedAt: now,
                                 payload: try? PayloadCoder.encode(MemberPayload(displayName: "Alex", colour: "sunflower"))))
            data.put(PlainRecord(type: .member, name: other.rawValue, modifiedAt: now,
                                 payload: try? PayloadCoder.encode(MemberPayload(displayName: "Sam", colour: "teal"))))
            // `-sampleNightAsk noRota`: no rota yet, so nobody is on and both phones alert.
            // `takenByOther`: no rota either, and Sam took tonight after this parent asked.
            if !["noRota", "takenByOther"].contains(defaults.string(forKey: "sampleNightAsk")) {
                data.putSetting(Rota(startDate: PlainDate(now, in: .current), firstOnDuty: other, secondOnDuty: me),
                                key: SettingKey.rota, now: now)
            }

            func feed(hoursAgo: Double, by member: MemberID, _ details: FeedDetails, minutes: Double = 25) {
                let start = now.addingTimeInterval(-hoursAgo * 3600)
                data.add(kind: .feed, babyID: "sample-baby", startedAt: start, endedAt: start.addingTimeInterval(minutes * 60),
                         payload: EventPayload(feed: details), by: member, timeZoneID: zone, now: start)
            }
            feed(hoursAgo: 13, by: me, FeedDetails(breast: [BreastSegment(side: .left, durationSeconds: 900)]))
            feed(hoursAgo: 10, by: other, FeedDetails(bottles: [Bottle(milk: .expressed, ml: 90)]))
            feed(hoursAgo: 7, by: me, FeedDetails(breast: [BreastSegment(side: .right, durationSeconds: 600)],
                                                 bottles: [Bottle(milk: .formula, ml: 30)]))
            feed(hoursAgo: 4.5, by: other, FeedDetails(bottles: [Bottle(milk: .formula, ml: 60)]))
            // Two feeds close together before the last one, as in a busy evening.
            feed(hoursAgo: 2 + 45.0 / 60, by: me, FeedDetails(breast: [BreastSegment(side: .left, durationSeconds: 720)]), minutes: 12)
            feed(hoursAgo: 2 + 15.0 / 60, by: me, FeedDetails(breast: [BreastSegment(side: .right, durationSeconds: 600)]), minutes: 10)
            feed(hoursAgo: 1 + 40.0 / 60, by: other,
                 FeedDetails(breast: [BreastSegment(side: .left, durationSeconds: 720), BreastSegment(side: .right, durationSeconds: 480)],
                             bottles: [Bottle(milk: .formula, ml: 30)]))
            if defaults.bool(forKey: "sampleDuplicate") {
                // This phone logged the last feed too, 2 minutes after the other phone did.
                feed(hoursAgo: 1 + 38.0 / 60, by: me, FeedDetails(breast: [BreastSegment(side: .left, durationSeconds: 660)]), minutes: 20)
            }
            // Sleeps, nappies, Vitamin D and weights (06-more-than-feeds.md), on every sample day.
            // `-sampleSleep awake` ends the last sleep 25 minutes ago; otherwise the baby is asleep.
            func care(dayBack: Int) {
                let base = Double(dayBack) * 24
                let sleeps: [(Double, Double)] = [(23.6, 21.5), (19.2, 17.0), (15.8, 14.6), (12.4, 11.0), (8.9, 7.1),
                                                  (6.4, 4.9), (4.4, 2.9)]
                for (from, to) in sleeps {
                    let start = now.addingTimeInterval(-(base + from) * 3600)
                    data.add(kind: .sleep, babyID: "sample-baby", startedAt: start, endedAt: now.addingTimeInterval(-(base + to) * 3600),
                             payload: EventPayload(), by: dayBack.isMultiple(of: 2) ? me : other, timeZoneID: zone, now: start)
                }
                let nappies: [(Double, Bool, Bool, PooColour?, PooConsistency?)] = [
                    (22.8, true, false, nil, nil), (18.9, true, true, .yellow, .loose), (15.1, true, false, nil, nil),
                    (11.7, true, false, nil, nil), (8.2, true, true, .yellow, nil), (5.0, true, false, nil, nil),
                    (2.2, true, Double(dayBack).truncatingRemainder(dividingBy: 2) == 0, nil, nil),
                ]
                for (hoursAgo, wee, poo, colour, consistency) in nappies {
                    let at = now.addingTimeInterval(-(base + hoursAgo) * 3600)
                    data.add(kind: .nappy, babyID: "sample-baby", startedAt: at,
                             payload: EventPayload(nappy: NappyDetails(wee: wee, poo: poo, colour: colour, consistency: consistency)),
                             by: dayBack.isMultiple(of: 2) ? other : me, timeZoneID: zone, now: at)
                }
                let vitamin = now.addingTimeInterval(-(base + 3.3) * 3600)
                data.addMedicine(babyID: "sample-baby", MedicineDetails(name: "Vitamin D"), at: vitamin, by: me, timeZoneID: zone, now: vitamin)
            }
            care(dayBack: 0)
            if defaults.string(forKey: "sampleSleep") != "awake" {
                // Asleep for the last 1h 20m.
                data.startSleep(babyID: "sample-baby", startedAt: now.addingTimeInterval(-80 * 60), by: other, timeZoneID: zone,
                                now: now.addingTimeInterval(-80 * 60))
            } else {
                let start = now.addingTimeInterval(-100 * 60)
                data.add(kind: .sleep, babyID: "sample-baby", startedAt: start, endedAt: now.addingTimeInterval(-25 * 60),
                         payload: EventPayload(), by: other, timeZoneID: zone, now: start)
            }
            // A poo 40 minutes ago with no details yet: the Nappy tile offers "Add details".
            let lastNappy = now.addingTimeInterval(-40 * 60)
            data.add(kind: .nappy, babyID: "sample-baby", startedAt: lastNappy,
                     payload: EventPayload(nappy: NappyDetails(wee: true, poo: true)), by: me, timeZoneID: zone, now: lastNappy)
            for (daysAgo, grams, length, head) in [(26, 3400, 510, 350), (21, 3180, nil, nil), (16, 3350, nil, nil),
                                                   (12, 3520, 525, 360), (5, 3850, nil, nil)] as [(Int, Int, Int?, Int?)] {
                let at = now.addingTimeInterval(-Double(daysAgo) * 86400 + 3600)
                data.addGrowth(babyID: "sample-baby", GrowthDetails(weightGrams: grams, lengthMM: length, headMM: head), at: at,
                               by: other, timeZoneID: zone, now: at)
            }
            let pumpStart = now.addingTimeInterval(-3 * 3600)
            data.add(kind: .pump, babyID: "sample-baby", startedAt: pumpStart, endedAt: pumpStart.addingTimeInterval(20 * 60),
                     payload: EventPayload(pump: PumpDetails(side: .both, leftML: 50, rightML: 40)), by: other, timeZoneID: zone, now: pumpStart)
            // `-sampleWeek YES`: six more made-up days before these, for the Graphs tab
            // (`-sampleWeek 30` for thirty).
            let extraDays = defaults.integer(forKey: "sampleWeek") > 0 ? defaults.integer(forKey: "sampleWeek")
                : defaults.bool(forKey: "sampleWeek") ? 6 : 0
            if extraDays > 0 {
                let jitter = [0, 0.3, -0.2, 0.5, 0, -0.4, 0.2, 1.8, 0, 0.1]
                for dayBack in 1...extraDays {
                    for k in 0..<(7 + dayBack % 3) {
                        let hoursAgo = 13.5 + Double(dayBack - 1) * 24 + Double(k) * 2.6 + jitter[k]
                        let who = k.isMultiple(of: 2) ? me : other
                        switch k % 3 {
                        case 0:
                            feed(hoursAgo: hoursAgo, by: who, FeedDetails(breast: [
                                BreastSegment(side: .left, durationSeconds: 540 + dayBack * 60),
                                BreastSegment(side: .right, durationSeconds: 420 + (dayBack % 2) * 180)]))
                        case 1:
                            feed(hoursAgo: hoursAgo, by: who, FeedDetails(bottles: [Bottle(milk: .formula, ml: 60 + 10 * (dayBack % 3))]))
                        default:
                            feed(hoursAgo: hoursAgo, by: who, FeedDetails(breast: [BreastSegment(side: .right, durationSeconds: 360)],
                                                                          bottles: [Bottle(milk: .expressed, ml: 40 + 10 * (dayBack % 2))]))
                        }
                    }
                    care(dayBack: dayBack)
                    let pump = now.addingTimeInterval(-(Double(dayBack) * 24 + 3) * 3600)
                    data.add(kind: .pump, babyID: "sample-baby", startedAt: pump, endedAt: pump.addingTimeInterval(20 * 60),
                             payload: EventPayload(pump: PumpDetails(side: .both, leftML: 40 + dayBack * 5, rightML: 45)),
                             by: other, timeZoneID: zone, now: pump)
                }
            }
            switch defaults.string(forKey: "sampleFeedInProgress") {
            case "YES", "breast":
                // Left for 8 minutes, then Right running for 4 (the mockup's feed).
                let id = data.startFeed(babyID: "sample-baby", side: .left, by: me, timeZoneID: zone, now: now.addingTimeInterval(-12 * 60))
                data.switchSide(id, to: .right, by: me, now: now.addingTimeInterval(-4 * 60))
            case "bottle":
                data.startFeed(babyID: "sample-baby", side: nil, bottle: .formula, by: me, timeZoneID: zone, now: now.addingTimeInterval(-6 * 60))
            case "other":
                data.startFeed(babyID: "sample-baby", side: .left, by: other, timeZoneID: zone, now: now.addingTimeInterval(-9 * 60))
            case "finishedForMe":
                // This parent's feed, finished by the other parent, waiting for its details.
                let bottleOnly = defaults.string(forKey: FeedingStyle.storageKey) == FeedingStyle.bottleOnly.rawValue
                let id = data.startFeed(babyID: "sample-baby", side: nil, bottle: bottleOnly ? .formula : nil, by: me,
                                        timeZoneID: zone, now: now.addingTimeInterval(-25 * 60))
                data.finishFeed(id, by: other, now: now.addingTimeInterval(-5 * 60))
            default:
                break
            }
            // An ask to take tonight: `fromOther` (Sam asks this parent: the card), `mine` (this
            // parent asked, no answer yet), `declined` (Sam said not tonight) or `meOnDuty` (this
            // parent is on tonight, with the button to ask).
            let tonight = data.householdSettings.tonight(at: now)
            let ask = defaults.string(forKey: "sampleNightAsk")
            if let ask, ["fromOther", "mine", "declined", "meOnDuty"].contains(ask) {
                let asker = ask == "fromOther" ? other : me
                data.claimNight(tonight, by: asker, now: now.addingTimeInterval(-3600))
                if ask != "meOnDuty" {
                    data.askNight(tonight, by: asker, now: now.addingTimeInterval(-300))
                }
                if ask == "declined" {
                    data.declineAsk(tonight, by: other, now: now.addingTimeInterval(-120))
                }
            }
            if ask == "takenByOther" {
                data.askNight(tonight, by: me, now: now.addingTimeInterval(-300))
                data.claimNight(tonight, by: other, now: now.addingTimeInterval(-120))
            }
        }
    }
}
#endif
