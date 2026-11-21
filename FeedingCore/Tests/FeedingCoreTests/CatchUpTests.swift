import Foundation
import Testing
@testable import FeedingCore

// An alert that a change moved into the past before it went off goes off at once (the users'
// choice A, 21 Nov 2026, from the outside review of `11-watch-parity.md`): `passedAlerts`,
// `catchUpAlerts` and `planAlertChanges(passed:)`.
//
// A daytime feed at 10:00 on 14 Nov (London, which is UTC in November): the window closes at 14:00,
// the follow-up at 14:10, the backup at 14:30. Parent A, loud alarm by day.
@Suite("Alerts moved into the past go off at once")
struct CatchUpTests {
    let feedID = "the-feed"

    func feedAt(_ start: Date) -> Event { feed(start, id: feedID) }

    func passed(_ events: [Event], preferences: MemberPreferences = .init(), now: Date) -> [DesiredAlert] {
        passedAlerts(events: events, settings: .init(), roster: DutyRoster(rota: rotaFrom13Nov, claims: []),
                     pendingChanges: [], me: Me(id: parentA, preferences: preferences), now: now)
    }

    /// What the phone had set after planning `alerts`: their alarms and their notifications.
    func setFor(_ alerts: [DesiredAlert]) -> (alarms: [ScheduledAlarm], notifications: [String: Date]) {
        let alarms = alerts.filter { $0.mechanism == .alarm }.map {
            ScheduledAlarm(key: $0.key, alarmID: UUID(), fireDate: $0.fireDate, babyID: $0.babyID, lastFeedStart: $0.lastFeedStart)
        }
        let notifications = Dictionary(uniqueKeysWithValues: alerts.filter { $0.mechanism == .notification }
            .map { (notificationIdentifier(for: $0), $0.fireDate) })
        return (alarms, notifications)
    }

    func catchUp(after change: [Event], before: [Event], preferences: MemberPreferences = .init(),
                 plannedAt: Date, now: Date) -> [DesiredAlert] {
        let set = setFor(run(before, preferences: preferences, now: plannedAt))
        let desired = run(change, preferences: preferences, now: now)
        return catchUpAlerts(passed: passed(change, preferences: preferences, now: now), desired: desired,
                             scheduledAlarms: set.alarms, pendingNotifications: set.notifications, now: now)
    }

    /// The feed's start moved 30 minutes earlier at 13:55: the close (13:30) and the follow-up
    /// (13:40) are now past and never went off; the strongest, the follow-up, goes off at once.
    @Test func aFeedMovedEarlierSetsOffTheStrongestPassedAlertAtOnce() {
        let now = at(2026, 11, 14, 13, 55)
        let alerts = catchUp(after: [feedAt(at(2026, 11, 14, 9, 30))], before: [feedAt(at(2026, 11, 14, 10))],
                             plannedAt: at(2026, 11, 14, 10, 5), now: now)
        #expect(summary(alerts) == ["followUp.alarm@13:55:5", "followUp.notification@13:55:5"])
        #expect(alerts.allSatisfy { $0.lastFeedStart == at(2026, 11, 14, 9, 30) })
        // The backup is still to come, at 14:00, and stays where it is.
        #expect(summary(run([feedAt(at(2026, 11, 14, 9, 30))], now: now)) == ["backup.alarm@14:00", "backup.notification@14:00"])
    }

    @Test func whenAllThreeArePastTheBackupGoesOff() {
        let alerts = catchUp(after: [feedAt(at(2026, 11, 14, 9))], before: [feedAt(at(2026, 11, 14, 10))],
                             plannedAt: at(2026, 11, 14, 10, 5), now: at(2026, 11, 14, 13, 55))
        #expect(summary(alerts) == ["backup.alarm@13:55:5", "backup.notification@13:55:5"])
    }

    /// The latest feed deleted at 15:00: the feed before it, at 9:00, is the latest again, and all
    /// its alerts are long past. The phone had the deleted feed's alerts still to come: the backup
    /// goes off at once.
    @Test func aDeletedLatestFeedSetsOffTheEarlierFeedsBackup() {
        let earlier = feed(at(2026, 11, 14, 9), id: "earlier")
        let later = feed(at(2026, 11, 14, 13), id: "later")
        var deleted = later
        deleted.deletedAt = at(2026, 11, 14, 15)
        let alerts = catchUp(after: [earlier, deleted], before: [earlier, later],
                             plannedAt: at(2026, 11, 14, 13, 5), now: at(2026, 11, 14, 15))
        #expect(summary(alerts) == ["backup.alarm@15:00:5", "backup.notification@15:00:5"])
    }

    /// An alert that already went off (its time passed with nothing changed) isn't set off again.
    @Test func anAlertThatAlreadyWentOffIsNotSetOffAgain() {
        let feed = [feedAt(at(2026, 11, 14, 10))]
        let alerts = catchUp(after: feed, before: feed, plannedAt: at(2026, 11, 14, 10, 5), now: at(2026, 11, 14, 14, 20))
        #expect(alerts.isEmpty)
    }

    /// A phone that had nothing set (a new phone, alerts just turned on) sets nothing off.
    @Test func nothingSetMeansNothingCaughtUp() {
        let now = at(2026, 11, 14, 13, 55)
        let change = [feedAt(at(2026, 11, 14, 9))]
        #expect(catchUpAlerts(passed: passed(change, now: now), desired: run(change, now: now), scheduledAlarms: [],
                              pendingNotifications: [:], now: now).isEmpty)
    }

    /// A gentle nudge stays a nudge: only the notification is caught up for the follow-up.
    @Test func theParentsStyleHolds() {
        let prefs = MemberPreferences(dayStyle: .gentleNudge)
        let alerts = catchUp(after: [feedAt(at(2026, 11, 14, 9, 30))], before: [feedAt(at(2026, 11, 14, 10))],
                             preferences: prefs, plannedAt: at(2026, 11, 14, 10, 5), now: at(2026, 11, 14, 13, 55))
        #expect(summary(alerts) == ["followUp.notification@13:55:5"])
    }

    /// The window-opens nudge is never caught up.
    @Test func theWindowOpensNudgeIsNeverCaughtUp() {
        let prefs = MemberPreferences(windowOpensNudge: true)
        // Moved 10 minutes earlier at 11:55: the window now opened at 11:50, before it was set to.
        let alerts = catchUp(after: [feedAt(at(2026, 11, 14, 9, 50))], before: [feedAt(at(2026, 11, 14, 10))],
                             preferences: prefs, plannedAt: at(2026, 11, 14, 10, 5), now: at(2026, 11, 14, 11, 55))
        #expect(alerts.isEmpty)
    }

    /// The planner sets the caught-up alarm and cancels the old ones; run again moments later, it
    /// changes nothing, so the alert is never put off; once it has gone off it isn't set again.
    @Test func thePlannerSetsItOnceAndNeverPutsItOff() {
        let before = run([feedAt(at(2026, 11, 14, 10))], now: at(2026, 11, 14, 10, 5))
        let first = planAlertChanges(desired: before, scheduledAlarms: [], pendingNotifications: [:])
        let change = [feedAt(at(2026, 11, 14, 9, 30))]
        var pending = setFor(before).notifications

        let now = at(2026, 11, 14, 13, 55)
        let moved = planAlertChanges(desired: run(change, now: now), scheduledAlarms: first.alarmsAfter,
                                     pendingNotifications: pending, now: now, passed: passed(change, now: now))
        let caughtUp = moved.alarmsToSchedule.map(\.alert).filter { $0.purpose == .followUp }
        #expect(summary(caughtUp) == ["followUp.alarm@13:55:5"])
        #expect(moved.notificationsToAdd.contains { $0.purpose == .followUp && $0.fireDate == now.addingTimeInterval(5) })
        // The old close and follow-up alarms (14:00, 14:10) go.
        #expect(moved.alarmsToCancel.count == 3)
        for alert in moved.notificationsToAdd { pending[notificationIdentifier(for: alert)] = alert.fireDate }
        pending.removeValue(forKey: "alert.baby-1.windowCloses.notification")

        let moments = now.addingTimeInterval(3)
        let again = planAlertChanges(desired: run(change, now: moments), scheduledAlarms: moved.alarmsAfter,
                                     pendingNotifications: pending, now: moments, passed: passed(change, now: moments))
        #expect(again.isEmpty)

        // It went off at 13:55:05 and its notification was delivered: nothing is set again.
        pending.removeValue(forKey: "alert.baby-1.followUp.notification")
        let later = at(2026, 11, 14, 13, 57)
        let afterwards = planAlertChanges(desired: run(change, now: later), scheduledAlarms: moved.alarmsAfter,
                                          pendingNotifications: pending, now: later,
                                          latestFeedStarts: [baby: at(2026, 11, 14, 9, 30)], passed: passed(change, now: later))
        #expect(afterwards.alarmsToSchedule.isEmpty)
        #expect(!afterwards.notificationsToAdd.contains { $0.purpose == .followUp })
        // The alarm that went off is kept, as it may still be ringing (`stillSounding`).
        #expect(afterwards.alarmsToCancel.isEmpty)
    }

    /// Never two alarms in one minute: the caught-up one moves to the next free minute.
    @Test func theCaughtUpAlarmKeepsAMinuteToItself() {
        // Moved 30 minutes earlier at 13:59:58: the follow-up (13:40) is caught up at 14:00:03,
        // the minute the backup (14:00) rings in, so it goes at 14:01.
        let alerts = catchUp(after: [feedAt(at(2026, 11, 14, 9, 30))], before: [feedAt(at(2026, 11, 14, 10))],
                             plannedAt: at(2026, 11, 14, 10, 5), now: at(2026, 11, 14, 13, 59, 58))
        #expect(summary(alerts) == ["followUp.alarm@14:01", "followUp.notification@14:01"])
    }
}
