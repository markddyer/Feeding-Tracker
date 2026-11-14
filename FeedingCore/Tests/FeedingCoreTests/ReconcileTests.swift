import Foundation
import Testing
@testable import FeedingCore

// The rota puts Parent A on duty on the night of 13 Nov, Parent B on 14 Nov, Parent A on 15 Nov.
// In November, London time equals UTC.

@Suite("reconcile: daytime")
struct ReconcileDaytimeTests {
    let lastFeed = at(2026, 11, 14, 10, 0)
    let now = at(2026, 11, 14, 10, 5)

    @Test func noFeedsMeansNoAlerts() {
        #expect(run([], now: now).isEmpty)
    }

    @Test func loudAlarmLayersAndTheBackup() {
        let alerts = run([feed(lastFeed)], now: now)
        #expect(summary(alerts) == [
            "windowCloses.alarm@14:00", "windowCloses.notification@14:00",
            "followUp.alarm@14:10", "followUp.notification@14:10",
            "backup.alarm@14:30", "backup.notification@14:30",
        ])
        #expect(alerts.allSatisfy { $0.lastFeedStart == lastFeed && $0.babyID == baby })
    }

    @Test func gentleNudgeStillGetsTheLoudBackup() {
        let prefs = MemberPreferences(dayStyle: .gentleNudge)
        #expect(summary(run([feed(lastFeed)], preferences: prefs, now: now)) == [
            "windowCloses.notification@14:00",
            "followUp.notification@14:10",
            "backup.alarm@14:30", "backup.notification@14:30",
        ])
    }

    @Test func bothParentsAreAlertedInTheDay() {
        let forB = run([feed(lastFeed)], me: parentB, preferences: MemberPreferences(dayStyle: .gentleNudge), now: now)
        #expect(summary(forB).first == "windowCloses.notification@14:00")
    }

    @Test func windowOpensNudgeWhenTurnedOn() {
        let prefs = MemberPreferences(windowOpensNudge: true)
        #expect(summary(run([feed(lastFeed)], preferences: prefs, now: now)).first == "windowOpens.notification@12:00")
        #expect(!summary(run([feed(lastFeed)], now: now)).contains { $0.hasPrefix("windowOpens") })
    }

    @Test func theBackupDelayIsASharedSetting() {
        let settings = HouseholdSettings(window: FeedWindowSettings(backupAfterClose: .minutes(45)))
        #expect(summary(run([feed(lastFeed)], settings: settings, now: now)).suffix(2) == [
            "backup.alarm@14:45", "backup.notification@14:45",
        ])
    }

    @Test func turningAlertsOffTurnsOffEverythingIncludingTheBackup() {
        let settings = HouseholdSettings(window: FeedWindowSettings(alertsEnabled: false))
        #expect(run([feed(lastFeed)], settings: settings, now: now).isEmpty)
    }

    @Test func keysAreStableForRepeatableScheduling() {
        let alerts = run([feed(lastFeed)], now: now)
        #expect(alerts.first?.key == "baby-1.windowCloses.alarm")
        #expect(Set(alerts.map(\.key)).count == alerts.count)
    }
}

@Suite("reconcile: which feed counts")
struct ReconcileFeedSelectionTests {
    let now = at(2026, 11, 14, 10, 30)

    @Test func theLatestFeedStartWinsWhateverTheOrder() {
        let feeds = [feed(at(2026, 11, 14, 8, 0)), feed(at(2026, 11, 14, 10, 0)), feed(at(2026, 11, 14, 6, 0))]
        #expect(summary(run(feeds, now: now)).first == "windowCloses.alarm@14:00")
        #expect(run(feeds, now: now) == run(feeds.reversed(), now: now))
    }

    @Test func deletedFeedsDoNotCount() {
        let feeds = [feed(at(2026, 11, 14, 8, 0)), feed(at(2026, 11, 14, 10, 0), deletedAt: at(2026, 11, 14, 10, 20))]
        #expect(summary(run(feeds, now: now)).first == "windowCloses.alarm@12:00")
    }

    @Test func pumpingAndUnknownKindsDoNotCount() {
        let events = [
            feed(at(2026, 11, 14, 8, 0)),
            feed(at(2026, 11, 14, 10, 0), kind: .pump),
            feed(at(2026, 11, 14, 10, 10), kind: "nappy"),
        ]
        #expect(summary(run(events, now: now)).first == "windowCloses.alarm@12:00")
    }

    @Test func aFastClockOnTheLoggingPhoneIsCappedByTheServerTime() {
        // The other phone's clock ran 20 minutes fast. The server created the record at 10:00.
        let event = feed(at(2026, 11, 14, 10, 20), serverCreatedAt: at(2026, 11, 14, 10, 0))
        #expect(summary(run([event], now: now)).first == "windowCloses.alarm@14:01")
    }

    @Test func anEarlierFeedLoggedLaterIsNotMoved() {
        let event = feed(at(2026, 11, 14, 9, 0), serverCreatedAt: at(2026, 11, 14, 10, 0))
        #expect(summary(run([event], now: now)).first == "windowCloses.alarm@13:00")
    }

    @Test func aFeedStartingInTheFutureCountsFromNow() {
        let event = feed(at(2026, 11, 14, 11, 0))
        #expect(summary(run([event], now: now)).first == "windowCloses.alarm@14:30")
    }

    @Test func eachBabyGetsItsOwnAlertsAndNoTwoAlarmsShareAMinute() {
        let feeds = [feed(at(2026, 11, 14, 10, 0)), feed(at(2026, 11, 14, 10, 0), babyID: "baby-2")]
        let alerts = run(feeds, now: now)
        #expect(Set(alerts.map(\.babyID)) == [baby, "baby-2"])
        let alarmMinutes = alerts.filter { $0.mechanism == .alarm }.map { Int($0.fireDate.timeIntervalSince1970) / 60 }
        #expect(alarmMinutes.count == 6)
        #expect(Set(alarmMinutes).count == 6)
        #expect(summary(alerts.filter { $0.babyID == "baby-2" && $0.mechanism == .alarm }) == [
            "windowCloses.alarm@14:01", "followUp.alarm@14:11", "backup.alarm@14:31",
        ])
    }

    @Test func alarmsWithinTheSameMinuteMoveToTheNextMinuteNeverEarlier() {
        let feeds = [feed(at(2026, 11, 14, 10, 0, 30)), feed(at(2026, 11, 14, 10, 0, 10), babyID: "baby-2")]
        let closes = run(feeds, now: now).filter { $0.mechanism == .alarm && $0.purpose == .windowCloses }
        #expect(summary(closes) == ["windowCloses.alarm@14:00:10", "windowCloses.alarm@14:01"])
        #expect(closes.map(\.babyID) == ["baby-2", baby])
    }
}

@Suite("reconcile: nights and duty")
struct ReconcileNightTests {
    // Night of 14 Nov: Parent B is on duty, Parent A is off.
    let lateFeed = at(2026, 11, 14, 22, 0)
    let now = at(2026, 11, 14, 22, 5)

    @Test func offDutyParentGetsOnlyTheBackup() {
        #expect(summary(run([feed(lateFeed)], me: parentA, now: now)) == [
            "backup.alarm@02:30", "backup.notification@02:30",
        ])
    }

    @Test func onDutyParentGetsTheirChosenNightStyle() {
        let gentle = MemberPreferences(nightStyle: .gentleNudge)
        #expect(summary(run([feed(lateFeed)], me: parentB, preferences: gentle, now: now)) == [
            "windowCloses.notification@02:00",
            "followUp.notification@02:10",
            "backup.alarm@02:30", "backup.notification@02:30",
        ])
        let loud = MemberPreferences(dayStyle: .gentleNudge, nightStyle: .loudAlarm)
        #expect(summary(run([feed(lateFeed)], me: parentB, preferences: loud, now: now)).first == "windowCloses.alarm@02:00")
    }

    @Test func windowOpensNudgeOnlyForTheParentOnDutyAtNight() {
        let prefs = MemberPreferences(windowOpensNudge: true)
        #expect(summary(run([feed(lateFeed)], me: parentB, preferences: prefs, now: now)).first == "windowOpens.notification@00:00")
        #expect(!summary(run([feed(lateFeed)], me: parentA, preferences: prefs, now: now)).contains { $0.hasPrefix("windowOpens") })
    }

    @Test func aClaimPutsTheClaimingParentOnDuty() {
        let claim = NightClaim(night: date("2026-11-14"), member: parentA, claimedAt: at(2026, 11, 14, 20, 0))
        #expect(summary(run([feed(lateFeed)], me: parentA, claims: [claim], now: now)).first == "windowCloses.alarm@02:00")
        #expect(summary(run([feed(lateFeed)], me: parentB, claims: [claim], now: now)) == [
            "backup.alarm@02:30", "backup.notification@02:30",
        ])
    }

    @Test func dayOrNightIsDecidedWhenTheAlertFiresNotWhenItIsScheduled() {
        // Fed at 17:30 in the day: the window closes at 21:30, in Parent B's night.
        let evening = at(2026, 11, 14, 17, 30)
        #expect(summary(run([feed(evening)], me: parentA, now: at(2026, 11, 14, 17, 35))) == [
            "backup.alarm@22:00", "backup.notification@22:00",
        ])
        // Fed at 16:59: the window closes at 20:59 (day) but the follow-up at 21:09 is night.
        let justBefore = at(2026, 11, 14, 16, 59)
        #expect(summary(run([feed(justBefore)], me: parentA, now: at(2026, 11, 14, 17, 0))) == [
            "windowCloses.alarm@20:59", "windowCloses.notification@20:59",
            "backup.alarm@21:29", "backup.notification@21:29",
        ])
    }

    @Test func dutyFollowsTheNightAcrossMidnight() {
        // Fed at 20:30 on 13 Nov (Parent A's night). Closes at 00:30 on 14 Nov: still the night of 13 Nov.
        let alerts = run([feed(at(2026, 11, 13, 20, 30))], me: parentA, now: at(2026, 11, 13, 20, 35))
        #expect(summary(alerts).first == "windowCloses.alarm@00:30")
        #expect(PlainDate(alerts[0].fireDate, in: london) == date("2026-11-14"))
    }
}

@Suite("reconcile: the morning lie-in")
struct ReconcileLieInTests {
    // Night of 14 Nov: Parent B on duty, Parent A off. Fed at 04:00 on 15 Nov: closes at 08:00.
    let earlyFeed = at(2026, 11, 15, 4, 0)
    let now = at(2026, 11, 15, 4, 5)
    let lieIn = MemberPreferences(lieInUntil: TimeOfDay(hour: 9))

    @Test func offDutyParentKeepsTheNightRulesUntilTheirLieInTime() {
        #expect(summary(run([feed(earlyFeed)], me: parentA, preferences: lieIn, now: now)) == [
            "backup.alarm@08:30", "backup.notification@08:30",
        ])
    }

    @Test func withoutALieInTheDayStartsAt7() {
        #expect(summary(run([feed(earlyFeed)], me: parentA, now: now)).first == "windowCloses.alarm@08:00")
    }

    @Test func openingTheAppAfterTheDayStartsEndsTheLieIn() {
        let opened = at(2026, 11, 15, 7, 30)
        let alerts = run([feed(earlyFeed)], me: parentA, preferences: lieIn, lastForegroundAt: opened, now: at(2026, 11, 15, 7, 31))
        #expect(summary(alerts).first == "windowCloses.alarm@08:00")
    }

    @Test func openingTheAppBeforeTheDayStartsDoesNotEndIt() {
        let opened = at(2026, 11, 15, 6, 30)
        let alerts = run([feed(earlyFeed)], me: parentA, preferences: lieIn, lastForegroundAt: opened, now: at(2026, 11, 15, 6, 31))
        #expect(summary(alerts) == ["backup.alarm@08:30", "backup.notification@08:30"])
    }

    @Test func theLieInEndsAtItsTime() {
        // Fed at 05:00: closes at 09:00, exactly when the lie-in ends.
        let alerts = run([feed(at(2026, 11, 15, 5, 0))], me: parentA, preferences: lieIn, now: at(2026, 11, 15, 5, 5))
        #expect(summary(alerts).first == "windowCloses.alarm@09:00")
    }

    @Test func theParentOnDutyLastNightIsNotHeldBack() {
        #expect(summary(run([feed(earlyFeed)], me: parentB, preferences: lieIn, now: now)).first == "windowCloses.alarm@08:00")
    }
}

@Suite("reconcile: changes waiting for the other phone")
struct ReconcilePendingTests {
    let lateFeed = at(2026, 11, 14, 22, 0)
    let now = at(2026, 11, 14, 22, 5)

    @Test func anUnconfirmedChangeMakesThisPhoneAlertAsIfOnDuty() {
        let pending = PendingChange(id: "undo-claim", madeBy: parentA, madeAt: at(2026, 11, 14, 21, 0))
        let gentle = MemberPreferences(nightStyle: .gentleNudge)
        #expect(summary(run([feed(lateFeed)], me: parentA, preferences: gentle, pending: [pending], now: now)) == [
            "windowCloses.notification@02:00",
            "followUp.notification@02:10",
            "backup.alarm@02:30", "backup.notification@02:30",
        ])
    }

    @Test func aConfirmedChangeNoLongerDoes() {
        let pending = PendingChange(id: "undo-claim", madeBy: parentA, madeAt: at(2026, 11, 14, 21, 0),
                                    acknowledgedAt: at(2026, 11, 14, 21, 2))
        #expect(summary(run([feed(lateFeed)], me: parentA, pending: [pending], now: now)) == [
            "backup.alarm@02:30", "backup.notification@02:30",
        ])
    }

    @Test func theOtherParentsPendingChangeDoesNotForceThisPhone() {
        let theirs = PendingChange(id: "x", madeBy: parentB, madeAt: at(2026, 11, 14, 21, 0))
        #expect(summary(run([feed(lateFeed)], me: parentA, pending: [theirs], now: now)).first == "backup.alarm@02:30")
    }

    @Test func theStricterOfTheOldAndNewSettingsApplies() {
        let new = HouseholdSettings(window: FeedWindowSettings(closesAfter: .hours(4), alertsEnabled: false))
        let old = HouseholdSettings(window: FeedWindowSettings(closesAfter: .hours(3), alertsEnabled: true))
        let pending = PendingChange(id: "settings", madeBy: parentA, madeAt: at(2026, 11, 14, 21, 0), previousSettings: old)
        let alerts = run([feed(lateFeed)], me: parentA, settings: new, pending: [pending], now: now)
        #expect(summary(alerts).first == "windowCloses.alarm@01:00")
        #expect(summary(alerts).last == "backup.notification@01:30")
    }
}

@Suite("reconcile: clocks, time zones and travel")
struct ReconcileClockTests {
    @Test func aWindowAcrossTheClocksGoingBackIsFourRealHours() {
        // 00:30 BST on 25 Oct 2026. Four real hours later the wall clock reads 03:30 GMT.
        let start = at(2026, 10, 24, 23, 30, in: utc)
        let alerts = run([feed(start)], me: parentA, now: start.addingTimeInterval(60))
        let close = alerts.first { $0.purpose == .windowCloses }
        #expect(close?.fireDate == start.addingTimeInterval(.hours(4)))
        #expect(summary(alerts).first == "windowCloses.alarm@03:30")
    }

    @Test func aWindowAcrossTheClocksGoingForwardIsFourRealHours() {
        // 23:30 GMT on 28 Mar 2026. Four real hours later the wall clock reads 04:30 BST.
        let start = at(2026, 3, 28, 23, 30, in: utc)
        let rota = Rota(startDate: date("2026-03-28"), firstOnDuty: parentA, secondOnDuty: parentB)
        let alerts = reconcile(events: [feed(start)], settings: .init(), roster: DutyRoster(rota: rota),
                               pendingChanges: [], me: Me(id: parentA), now: start.addingTimeInterval(60))
        #expect(alerts.first?.fireDate == start.addingTimeInterval(.hours(4)))
        #expect(summary(alerts).first == "windowCloses.alarm@04:30")
    }

    @Test func theClockBeingSetBackBringsAlertsBackRatherThanLosingThem() {
        let start = at(2026, 11, 14, 10, 0)
        #expect(!summary(run([feed(start)], now: at(2026, 11, 14, 14, 5))).contains("windowCloses.alarm@14:00"))
        #expect(summary(run([feed(start)], now: at(2026, 11, 14, 13, 0))).contains("windowCloses.alarm@14:00"))
    }

    @Test func pastAlertsAreLeftOutAndLaterLayersStay() {
        let start = at(2026, 11, 14, 10, 0)
        #expect(summary(run([feed(start)], now: at(2026, 11, 14, 14, 5))) == [
            "followUp.alarm@14:10", "followUp.notification@14:10",
            "backup.alarm@14:30", "backup.notification@14:30",
        ])
        #expect(run([feed(start)], now: at(2026, 11, 14, 14, 30)).isEmpty)
    }

    @Test func dayAndNightAreReadOnTheHouseholdClockNotThePhones() {
        // Fed at 21:30 UTC: the window closes at 01:30 UTC. In London that is night (Parent B's),
        // but for a household in New York it is 20:30, still day, so Parent A is alerted too.
        let start = at(2026, 11, 14, 21, 30, in: utc)
        let now = start.addingTimeInterval(60)
        #expect(summary(run([feed(start)], me: parentA, now: now)).first == "backup.alarm@02:00")
        let newYork = HouseholdSettings(timeZoneID: "America/New_York")
        let alerts = run([feed(start)], me: parentA, settings: newYork, now: now)
        #expect(summary(alerts, in: TimeZone(identifier: "America/New_York")!).first == "windowCloses.alarm@20:30")
    }

    @Test func anUnknownTimeZoneFallsBackToUTCOnBothPhones() {
        #expect(HouseholdSettings(timeZoneID: "Not/AZone").timeZone.secondsFromGMT() == 0)
    }

    @Test func halfHourHouseholdTimeZone() {
        // Kolkata is UTC+5:30. Fed at 11:00 UTC; closes at 15:00 UTC = 20:30 IST (day) and the
        // follow-up at 15:10 UTC = 20:40 IST (day). The backup at 15:30 UTC = 21:00 IST.
        let kolkata = HouseholdSettings(timeZoneID: "Asia/Kolkata")
        let start = at(2026, 11, 14, 11, 0, in: utc)
        let alerts = run([feed(start)], me: parentB, settings: kolkata, now: start.addingTimeInterval(60))
        #expect(summary(alerts, in: TimeZone(identifier: "Asia/Kolkata")!) == [
            "windowCloses.alarm@20:30", "windowCloses.notification@20:30",
            "followUp.alarm@20:40", "followUp.notification@20:40",
            "backup.alarm@21:00", "backup.notification@21:00",
        ])
    }
}
