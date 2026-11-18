import Foundation
import Testing
@testable import FeedingCore

@Suite("Household settings and the acknowledgement rule")
struct HouseholdSettingsTests {
    let t0 = at(2026, 11, 14, 10, 0)

    @Test func nothingSetMeansThePlanDefaults() {
        #expect(HouseholdData().householdSettings == HouseholdSettings())
        #expect(HouseholdData().rota == nil)
    }

    @Test func lengtheningTheWindowNeedsNoConfirmation() {
        var data = HouseholdData()
        data.updateHouseholdSettings(by: parentA, now: t0) { $0.window.closesAfter = .hours(5) }
        #expect(data.householdSettings.window.closesAfter == .hours(5))
        #expect(data.pendingChanges.isEmpty)
    }

    @Test func changesThatCouldSilenceTheOtherPhoneArePending() {
        let risky: [(inout HouseholdSettings) -> Void] = [
            { $0.window.closesAfter = .hours(3) },
            { $0.window.backupAfterClose = .minutes(20) },
            { $0.dayHours = DayHours(dayStart: time("06:00"), nightStart: time("21:00")) },
            { $0.timeZoneID = "Europe/Paris" },
        ]
        for change in risky {
            var data = HouseholdData()
            data.updateHouseholdSettings(by: parentA, now: t0, change)
            #expect(data.pendingChanges.count == 1)
            #expect(data.pendingChanges.first?.previousSettings == HouseholdSettings())
            #expect(data.pendingChanges.first?.madeBy == parentA)
        }
    }

    @Test func turningAlertsBackOnIsPendingButTurningThemOffIsNot() {
        var data = HouseholdData()
        data.updateHouseholdSettings(by: parentA, now: t0) { $0.window.alertsEnabled = false }
        #expect(data.pendingChanges.isEmpty)
        data.updateHouseholdSettings(by: parentA, now: t0.addingTimeInterval(60)) { $0.window.alertsEnabled = true }
        #expect(data.pendingChanges.count == 1)
    }

    @Test func noChangeWritesNothing() {
        var data = HouseholdData()
        data.updateHouseholdSettings(by: parentA, now: t0) { _ in }
        #expect(data.plainRecords.isEmpty)
    }

    @Test func onlyTheOtherParentCanConfirmAChange() {
        var data = HouseholdData()
        data.updateHouseholdSettings(by: parentA, now: t0) { $0.window.closesAfter = .hours(3) }
        data.acknowledgeChanges(by: parentA, now: t0.addingTimeInterval(10))
        #expect(data.unacknowledgedChanges(by: parentA).count == 1)

        let seenAt = t0.addingTimeInterval(60)
        data.acknowledgeChanges(by: parentB, now: seenAt)
        #expect(data.unacknowledgedChanges(by: parentA).isEmpty)
        #expect(data.pendingChanges.first?.acknowledgedAt == seenAt)
    }

    @Test func confirmingTwiceWritesOnce() {
        var data = HouseholdData()
        data.updateHouseholdSettings(by: parentA, now: t0) { $0.window.closesAfter = .hours(3) }
        data.acknowledgeChanges(by: parentB, now: t0.addingTimeInterval(60))
        let revision = data.plainRecords["Setting/ack-parent-b"]?.localRevision
        data.acknowledgeChanges(by: parentB, now: t0.addingTimeInterval(120))
        #expect(data.plainRecords["Setting/ack-parent-b"]?.localRevision == revision)
    }

    /// The rule end to end: Parent A shortens the window at night while off duty. Until Parent B's
    /// phone confirms, Parent A's phone alerts as if on duty, at the shorter window.
    @Test func anUnconfirmedChangeKeepsThisPhoneOnDuty() {
        var data = HouseholdData()
        data.setRota(rotaFrom13Nov, by: parentA, now: at(2026, 11, 13, 9, 0))
        // 14 Nov is Parent B's night. Last feed 21:30; a 3 h window closes at 00:30.
        let lastFeed = feed(at(2026, 11, 14, 21, 30))
        data.updateHouseholdSettings(by: parentA, now: at(2026, 11, 14, 21, 40)) { $0.window.closesAfter = .hours(3) }
        let now = at(2026, 11, 14, 21, 45)

        func alertsForA() -> [String] {
            let state = data.householdState
            return summary(reconcile(events: [lastFeed], settings: state.settings, roster: state.roster(for: parentA),
                                     pendingChanges: state.pendingChanges, me: Me(id: parentA), now: now))
        }
        #expect(alertsForA().first == "windowCloses.alarm@00:30")

        data.acknowledgeChanges(by: parentB, now: at(2026, 11, 14, 21, 50))
        #expect(alertsForA() == ["backup.alarm@01:00", "backup.notification@01:00"])
    }

    @Test func claimsAndTheirUndo() {
        var data = HouseholdData()
        let night = date("2026-11-14")
        data.claimNight(night, by: parentA, now: t0)
        #expect(data.nightClaims == [NightClaim(night: night, member: parentA, claimedAt: t0)])
        #expect(data.householdState.roster(for: parentA).onDuty(night: night) == parentA)
        let undoneByOther = data.undoClaim(night, by: parentB)
        #expect(!undoneByOther)
        let undone = data.undoClaim(night, by: parentA)
        #expect(undone)
        #expect(data.nightClaims.isEmpty)

        data.claimNight(night, by: parentA, now: t0)
        data.didUploadPlainRecord("Setting/night-2026-11-14", sentRevision: 1, systemFields: Data([1]))
        let undoneAfterSending = data.undoClaim(night, by: parentA)
        #expect(!undoneAfterSending)
    }

    @Test func settingTheRotaFirstIsNotPendingButChangingItIs() {
        var data = HouseholdData()
        data.setRota(rotaFrom13Nov, by: parentA, now: t0)
        #expect(data.rota == rotaFrom13Nov)
        #expect(data.pendingChanges.isEmpty)
        data.setRota(Rota(startDate: date("2026-11-14"), firstOnDuty: parentA, secondOnDuty: parentB), by: parentA, now: t0)
        #expect(data.pendingChanges.count == 1)
    }

    @Test func withNoRotaThisPhoneIsOnDutyEveryNight() {
        let roster = HouseholdData().householdState.roster(for: parentB)
        #expect(roster.onDuty(night: date("2026-11-14")) == parentB)
        #expect(roster.onDuty(night: date("2026-11-15")) == parentB)
    }
}

@Suite("Applying alerts to the phone")
struct AlertPlanTests {
    let lastFeed = at(2026, 11, 14, 10, 0)

    func alert(_ purpose: DesiredAlert.Purpose, _ mechanism: DesiredAlert.Mechanism, at hour: Int, _ minute: Int = 0) -> DesiredAlert {
        DesiredAlert(babyID: baby, purpose: purpose, mechanism: mechanism, fireDate: at(2026, 11, 14, hour, minute), lastFeedStart: lastFeed)
    }

    func ids() -> () -> UUID {
        var n = 0
        return {
            n += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
        }
    }

    @Test func newAlertsAreAllSet() {
        let desired = [alert(.windowCloses, .alarm, at: 14), alert(.windowCloses, .notification, at: 14)]
        let changes = planAlertChanges(desired: desired, scheduledAlarms: [], pendingNotifications: [:], newID: ids())
        #expect(changes.alarmsToSchedule.map(\.alert.key) == ["baby-1.windowCloses.alarm"])
        #expect(changes.notificationsToAdd.map(notificationIdentifier(for:)) == ["alert.baby-1.windowCloses.notification"])
        #expect(changes.alarmsAfter.count == 1)
        #expect(changes.alarmsToCancel.isEmpty)
    }

    @Test func anUnchangedPlanChangesNothing() {
        let desired = [alert(.windowCloses, .alarm, at: 14), alert(.windowCloses, .notification, at: 14)]
        let first = planAlertChanges(desired: desired, scheduledAlarms: [], pendingNotifications: [:], newID: ids())
        let again = planAlertChanges(desired: desired, scheduledAlarms: first.alarmsAfter,
                                     pendingNotifications: ["alert.baby-1.windowCloses.notification": at(2026, 11, 14, 14)])
        #expect(again.isEmpty)
        #expect(again.alarmsAfter == first.alarmsAfter)
    }

    @Test func aMovedAlarmIsReplacedNotChanged() {
        let old = ScheduledAlarm(key: "baby-1.windowCloses.alarm", alarmID: UUID(), fireDate: at(2026, 11, 14, 14))
        let changes = planAlertChanges(desired: [alert(.windowCloses, .alarm, at: 15)], scheduledAlarms: [old],
                                       pendingNotifications: [:], newID: ids())
        #expect(changes.alarmsToSchedule.count == 1)
        #expect(changes.alarmsToSchedule.first?.alarmID != old.alarmID)
        #expect(changes.alarmsToCancel == [old.alarmID])
        #expect(changes.alarmsAfter.map(\.fireDate) == [at(2026, 11, 14, 15)])
    }

    @Test func alertsNoLongerWantedGo() {
        let old = ScheduledAlarm(key: "baby-1.backup.alarm", alarmID: UUID(), fireDate: at(2026, 11, 14, 14, 30))
        let pending = ["alert.baby-1.backup.notification": at(2026, 11, 14, 14, 30), "spike.123": at(2026, 11, 15, 5)]
        let changes = planAlertChanges(desired: [], scheduledAlarms: [old], pendingNotifications: pending)
        #expect(changes.alarmsToCancel == [old.alarmID])
        #expect(changes.notificationsToRemove == ["alert.baby-1.backup.notification"])
        #expect(changes.alarmsAfter.isEmpty)
    }

    @Test func aMovedNotificationIsAddedAgain() {
        let changes = planAlertChanges(desired: [alert(.followUp, .notification, at: 14, 10)], scheduledAlarms: [],
                                       pendingNotifications: ["alert.baby-1.followUp.notification": at(2026, 11, 14, 13, 10)])
        #expect(changes.notificationsToAdd.count == 1)
        #expect(changes.notificationsToRemove.isEmpty)
    }
}

/// While a phone fills its data again after its file couldn't be read, what it knows may be
/// missing feeds: its plan is made as usual, but no alert it no longer wants is cancelled until its
/// time is long past (CEO review D18; Codex review of step 0, 18 Nov 2026).
@Suite("Alerts while waiting for iCloud")
struct WaitingForICloudAlertTests {
    let lastFeed = at(2026, 11, 14, 10, 0)
    let now = at(2026, 11, 14, 12, 0)

    func alert(_ purpose: DesiredAlert.Purpose, _ mechanism: DesiredAlert.Mechanism, at hour: Int, _ minute: Int = 0) -> DesiredAlert {
        DesiredAlert(babyID: baby, purpose: purpose, mechanism: mechanism, fireDate: at(2026, 11, 14, hour, minute), lastFeedStart: lastFeed)
    }

    let set = ScheduledAlarm(key: "baby-1.windowCloses.alarm", alarmID: UUID(), fireDate: at(2026, 11, 14, 14))

    /// Only a nappy came back so far: no feed alerts are wanted yet, and none is cancelled.
    @Test func nothingWantedYetCancelsNothing() {
        let pending = ["alert.baby-1.backup.notification": at(2026, 11, 14, 14, 30)]
        let changes = planAlertChanges(desired: [], scheduledAlarms: [set], pendingNotifications: pending,
                                       now: now, keepExisting: true)
        #expect(changes.alarmsToCancel.isEmpty)
        #expect(changes.notificationsToRemove.isEmpty)
        #expect(changes.alarmsAfter == [set])
    }

    /// An old alarm for the same alert never stops the new one being set, even after it has rung.
    @Test func aNewAlarmForTheSameAlertIsAlwaysSet() {
        let rung = ScheduledAlarm(key: "baby-1.windowCloses.alarm", alarmID: UUID(), fireDate: at(2026, 11, 14, 11))
        let changes = planAlertChanges(desired: [alert(.windowCloses, .alarm, at: 16)], scheduledAlarms: [rung],
                                       pendingNotifications: [:], now: now, keepExisting: true)
        #expect(changes.alarmsToSchedule.map(\.alert.fireDate) == [at(2026, 11, 14, 16)])
        #expect(changes.alarmsAfter.map(\.fireDate) == [at(2026, 11, 14, 16)])
    }

    @Test func anAlarmLongPastGoesEvenWhileWaiting() {
        let old = ScheduledAlarm(key: "baby-1.backup.alarm", alarmID: UUID(), fireDate: at(2026, 11, 14, 5))
        let changes = planAlertChanges(desired: [], scheduledAlarms: [old], pendingNotifications: [:],
                                       now: now, keepExisting: true)
        #expect(changes.alarmsToCancel == [old.alarmID])
    }

    /// Two alarms in one minute may both stay silent: a kept one goes when a wanted one rings then.
    @Test func aKeptAlarmInTheSameMinuteAsAWantedOneGoes() {
        let other = ScheduledAlarm(key: "baby-1.backup.alarm", alarmID: UUID(), fireDate: at(2026, 11, 14, 14, 0))
        let changes = planAlertChanges(desired: [alert(.windowCloses, .alarm, at: 14)], scheduledAlarms: [other],
                                       pendingNotifications: [:], now: now, keepExisting: true)
        #expect(changes.alarmsToCancel == [other.alarmID])
        #expect(changes.alarmsAfter.map(\.key) == ["baby-1.windowCloses.alarm"])
    }

    /// Once iCloud has sent the household back, the next plan tidies up.
    @Test func afterwardsAnUnwantedAlarmGoes() {
        let waiting = planAlertChanges(desired: [], scheduledAlarms: [set], pendingNotifications: [:],
                                       now: now, keepExisting: true)
        let after = planAlertChanges(desired: [], scheduledAlarms: waiting.alarmsAfter, pendingNotifications: [:], now: now)
        #expect(after.alarmsToCancel == [set.alarmID])
    }

    /// Undoing the only feed on a healthy phone (not waiting) still takes its alarm away.
    @Test func aHealthyPhoneStillCancels() {
        let changes = planAlertChanges(desired: [], scheduledAlarms: [set], pendingNotifications: [:], now: now)
        #expect(changes.alarmsToCancel == [set.alarmID])
    }
}

/// An alarm whose time has come may be ringing: only a newer feed stops it, never a nappy, a
/// sleep or any other change (Codex review, 17 Nov 2026).
@Suite("An alarm whose time has come")
struct SoundingAlarmTests {
    let lastFeed = at(2026, 11, 14, 10, 0)
    let fired = at(2026, 11, 14, 14, 0)

    func ringing(babyID: String? = baby, feed: Date? = nil) -> ScheduledAlarm {
        ScheduledAlarm(key: "\(baby).windowCloses.alarm", alarmID: UUID(), fireDate: fired, babyID: babyID,
                       lastFeedStart: babyID == nil ? nil : (feed ?? lastFeed))
    }

    @Test func itIsKeptWhileItsFeedIsStillTheLatest() {
        let alarm = ringing()
        let changes = planAlertChanges(desired: [], scheduledAlarms: [alarm], pendingNotifications: [:],
                                       now: fired.addingTimeInterval(60), latestFeedStarts: [baby: lastFeed])
        #expect(changes.alarmsToCancel.isEmpty)
        #expect(changes.alarmsAfter == [alarm])
    }

    @Test func aNewerFeedStopsIt() {
        let alarm = ringing()
        let changes = planAlertChanges(desired: [], scheduledAlarms: [alarm], pendingNotifications: [:],
                                       now: fired.addingTimeInterval(60), latestFeedStarts: [baby: fired])
        #expect(changes.alarmsToCancel == [alarm.alarmID])
    }

    @Test func aReplacementForTheSameAlertStopsIt() {
        let alarm = ringing()
        let later = DesiredAlert(babyID: baby, purpose: .windowCloses, mechanism: .alarm, fireDate: fired.addingTimeInterval(3600),
                                 lastFeedStart: lastFeed)
        let changes = planAlertChanges(desired: [later], scheduledAlarms: [alarm], pendingNotifications: [:],
                                       now: fired.addingTimeInterval(60), latestFeedStarts: [baby: lastFeed])
        #expect(changes.alarmsToCancel == [alarm.alarmID])
        #expect(changes.alarmsToSchedule.count == 1)
    }

    @Test func itIsLetGoSixHoursOn() {
        let alarm = ringing()
        let changes = planAlertChanges(desired: [], scheduledAlarms: [alarm], pendingNotifications: [:],
                                       now: fired.addingTimeInterval(soundingAlarmKept + 1), latestFeedStarts: [baby: lastFeed])
        #expect(changes.alarmsToCancel == [alarm.alarmID])
    }

    /// An alarm an older build remembered has no feed start: it goes as before.
    @Test func anAlarmFromAnOlderBuildGoesAsBefore() {
        let alarm = ringing(babyID: nil)
        let changes = planAlertChanges(desired: [], scheduledAlarms: [alarm], pendingNotifications: [:],
                                       now: fired.addingTimeInterval(60), latestFeedStarts: [baby: lastFeed])
        #expect(changes.alarmsToCancel == [alarm.alarmID])
    }

    @Test func anAlarmStillToComeGoesAsBeforeWhenNoLongerWanted() {
        let alarm = ringing()
        let changes = planAlertChanges(desired: [], scheduledAlarms: [alarm], pendingNotifications: [:],
                                       now: fired.addingTimeInterval(-60), latestFeedStarts: [baby: lastFeed])
        #expect(changes.alarmsToCancel == [alarm.alarmID])
    }

    @Test func newAlarmsRememberTheirFeed() {
        let alert = DesiredAlert(babyID: baby, purpose: .backup, mechanism: .alarm, fireDate: fired, lastFeedStart: lastFeed)
        let changes = planAlertChanges(desired: [alert], scheduledAlarms: [], pendingNotifications: [:])
        #expect(changes.alarmsAfter.first?.babyID == baby)
        #expect(changes.alarmsAfter.first?.lastFeedStart == lastFeed)
    }

    /// The whole path: a nappy logged a minute after the alarm rang leaves it ringing.
    @Test func aNappyLoggedAfterTheAlarmLeavesItRinging() {
        var data = HouseholdData()
        data.add(kind: .feed, babyID: baby, startedAt: lastFeed, endedAt: lastFeed.addingTimeInterval(1200),
                 payload: EventPayload(feed: FeedDetails()), by: parentA, timeZoneID: "Europe/London", now: lastFeed)
        let now = fired.addingTimeInterval(60)
        data.addNappy(babyID: baby, wee: true, poo: false, by: parentA, timeZoneID: "Europe/London", now: now)
        let latest = data.allEvents.latestFeedStart(babyID: baby, now: now).map { [baby: $0] } ?? [:]
        let alarm = ringing()
        let changes = planAlertChanges(desired: [], scheduledAlarms: [alarm], pendingNotifications: [:], now: now,
                                       latestFeedStarts: latest)
        #expect(changes.alarmsToCancel.isEmpty)
    }
}

@Suite("Alert wording")
struct AlertTextTests {
    let lastFeed = at(2026, 11, 14, 1, 50)

    func alert(_ purpose: DesiredAlert.Purpose, after minutes: Double) -> DesiredAlert {
        DesiredAlert(babyID: baby, purpose: purpose, mechanism: .alarm,
                     fireDate: lastFeed.addingTimeInterval(.minutes(minutes)), lastFeedStart: lastFeed)
    }

    @Test func durationsReadNaturally() {
        #expect(AlertText.duration(.minutes(45)) == "45 min")
        #expect(AlertText.duration(.hours(4)) == "4 h")
        #expect(AlertText.duration(.hours(4) + .minutes(10) + 59) == "4 h 10 min")
        #expect(AlertText.duration(-5) == "0 min")
    }

    @Test func theWordsAreFacts() {
        #expect(AlertText.title(for: alert(.windowCloses, after: 240)) == "4 h since the last feed started")
        #expect(AlertText.body(for: alert(.windowCloses, after: 240), timeZone: london) == "The last feed started at 01:50.")
        #expect(AlertText.title(for: alert(.backup, after: 270)) == "No feed logged for 4 h 30 min")
        #expect(AlertText.title(for: alert(.windowOpens, after: 120)) == "May be ready to feed")
    }

    @Test func noAlertSoundsLikeMedicalAdvice() {
        for purpose in DesiredAlert.Purpose.allCases {
            let a = alert(purpose, after: 250)
            let words = (AlertText.title(for: a) + " " + AlertText.body(for: a, timeZone: london))
                .lowercased().split { !$0.isLetter }.map(String.init)
            for forbidden in AlertText.forbiddenWords {
                #expect(!words.contains(forbidden), "\(purpose) alert says \"\(forbidden)\"")
            }
        }
    }
}
