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
            let pumpStart = now.addingTimeInterval(-3 * 3600)
            data.add(kind: .pump, babyID: "sample-baby", startedAt: pumpStart, endedAt: pumpStart.addingTimeInterval(20 * 60),
                     payload: EventPayload(pump: PumpDetails(side: .both, leftML: 50, rightML: 40)), by: other, timeZoneID: zone, now: pumpStart)
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
