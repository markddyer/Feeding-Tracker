#if FEEDING_DEV && targetEnvironment(simulator)
import FeedingCore
import Foundation

/// Simulator only: fills an empty store with a made-up day, to look at the screens. The names are
/// made up (the mockup's), with different first letters so the avatars differ.
/// Launch with `-sampleData YES`; add `-sampleFeedInProgress YES` for a feed running.
enum SampleData {
    @MainActor
    static func loadIfAsked(into store: HouseholdStore) {
        let defaults = UserDefaults.standard
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
            data.putSetting(Rota(startDate: PlainDate(now, in: .current), firstOnDuty: other, secondOnDuty: me),
                            key: SettingKey.rota, now: now)

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
            feed(hoursAgo: 1 + 40.0 / 60, by: other,
                 FeedDetails(breast: [BreastSegment(side: .left, durationSeconds: 720), BreastSegment(side: .right, durationSeconds: 480)],
                             bottles: [Bottle(milk: .formula, ml: 30)]))
            let pumpStart = now.addingTimeInterval(-3 * 3600)
            data.add(kind: .pump, babyID: "sample-baby", startedAt: pumpStart, endedAt: pumpStart.addingTimeInterval(20 * 60),
                     payload: EventPayload(pump: PumpDetails(side: .both, leftML: 50, rightML: 40)), by: other, timeZoneID: zone, now: pumpStart)
            if defaults.bool(forKey: "sampleFeedInProgress") {
                let id = data.startFeed(babyID: "sample-baby", side: .right, by: me, timeZoneID: zone, now: now.addingTimeInterval(-6 * 60))
                data.switchSide(id, to: .right, by: me, now: now.addingTimeInterval(-6 * 60))
            }
        }
    }
}
#endif
