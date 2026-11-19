import FeedingCore
import Foundation
import Testing
import UserNotifications
@testable import FeedingDev

/// Stands in for Notification Center: records what is added and removed, and can fail an add.
@MainActor
final class FakeNoticeCenter: NoticeCenter {
    var added: [String] = []
    var delivered: [String] = []
    var removed: [String] = []
    var failNext = false

    func add(_ request: UNNotificationRequest) async throws {
        if failNext {
            failNext = false
            throw CocoaError(.featureUnsupported)
        }
        added.append(request.identifier)
        delivered.append(request.identifier)
    }

    func deliveredIDs() async -> [String] { delivered }

    func remove(_ identifiers: [String]) {
        removed += identifiers
        delivered.removeAll { identifiers.contains($0) }
    }
}

/// Mutable state the tests' closures share.
@MainActor
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// The notice of a first logged on the other phone (journal X1, D8; design review D18, D19;
/// outside review O8; task T9).
@Suite("New-first notice")
@MainActor
struct NewFirstNotifierTests {
    let me: MemberID = "parent-a"
    let other: MemberID = "parent-b"
    let london = TimeZone(identifier: "Europe/London")!
    /// 19 Nov 2026, 14:00 in London: day.
    let day = Date(timeIntervalSince1970: 1_795_096_800)

    func first(_ id: String, by: MemberID? = nil, savedAgo: TimeInterval = 60, deleted: Bool = false, at now: Date? = nil) -> Event {
        let now = now ?? day
        return Event(id: id, babyID: "baby", kind: .milestone, startedAt: now - 3_600, timeZoneID: "Europe/London",
                     loggedBy: by ?? other, createdAt: now - savedAgo, modifiedAt: now - savedAgo,
                     deletedAt: deleted ? now - 10 : nil, serverCreatedAt: now - savedAgo)
    }

    func plan(_ firsts: [Event], known: Set<String>? = [], told: Set<String> = [], householdHere: Bool = true,
              wanted: Bool = true, now: Date? = nil) -> NewFirstNotifier.Plan {
        NewFirstNotifier.plan(firsts: firsts, known: known, told: told, householdHere: householdHere, me: me,
                              wanted: wanted, dayHours: .standard, timeZone: london, now: now ?? day)
    }

    // MARK: The rule

    @Test func aNewFirstFromTheOtherParentIsChosenOnce() {
        let chosen = plan([first("smile")])
        #expect(chosen.tell == ["smile"])
        // Known once its notice has gone, not before.
        #expect(chosen.known == [])
        #expect(plan([first("smile")], told: ["smile"]).tell.isEmpty)
    }

    /// Nothing before the household is on this phone, and nothing from its first download: that
    /// run only notes every first it brought.
    @Test func noneFromTheFirstDownload() {
        let before = plan([first("smile")], known: nil, householdHere: false)
        #expect(before.tell.isEmpty)
        #expect(before.known == nil)
        let firstDownload = plan([first("smile"), first("laugh")], known: nil)
        #expect(firstDownload.tell.isEmpty)
        #expect(firstDownload.known == ["smile", "laugh"])
    }

    @Test func notForMyOwnAnOldOneOneHeldBeforeOrWithTheSwitchOff() {
        #expect(plan([first("mine", by: me)]).tell.isEmpty)
        #expect(plan([first("old", savedAgo: 25 * 3_600)]).tell.isEmpty)
        // An edit: the phone held it already.
        #expect(plan([first("smile")], known: ["smile"]).tell.isEmpty)
        #expect(plan([first("smile")], wanted: false).tell.isEmpty)
        // A first deleted before it arrived.
        #expect(plan([first("gone", deleted: true)]).tell.isEmpty)
    }

    /// Design review D19: at night the level is the list only (`NewFirstRule`).
    @Test func atNightItGoesToTheListOnly() {
        let night = day + 9 * 3_600 // 23:00
        #expect(NewFirstRule.notice(for: first("smile", at: night), heldBefore: false, isInitialFetch: false, me: me,
                                    wanted: true, dayHours: .standard, timeZone: london, now: night) == .listOnly)
        #expect(NewFirstRule.notice(for: first("smile"), heldBefore: false, isInitialFetch: false, me: me,
                                    wanted: true, dayHours: .standard, timeZone: london, now: day) == .shown)
    }

    /// A notice still on the phone whose first was deleted or undone since is taken back; not
    /// while the file fills again from iCloud.
    @Test func aDeletedOrUndoneFirstsNoticeIsTakenBack() {
        let delivered = ["newFirst-smile", "newFirst-gone", "newFirst-undone", "nightAsk-x"]
        let firsts = [first("smile"), first("gone", deleted: true)]
        #expect(NewFirstNotifier.takeBack(delivered: delivered, firsts: firsts, refilling: false)
            == ["newFirst-gone", "newFirst-undone"])
        #expect(NewFirstNotifier.takeBack(delivered: delivered, firsts: firsts, refilling: true).isEmpty)
    }

    // MARK: Sending

    /// A household on this phone with the baby, and firsts from the other parent saved just now.
    func household(_ firsts: [(id: String, deleted: Bool)]) -> HouseholdData {
        var data = HouseholdData()
        data.put(PlainRecord(type: .baby, name: "baby", modifiedAt: Date(),
                             payload: try? PayloadCoder.encode(BabyPayload(name: "Baby"))))
        for item in firsts {
            data.addMilestone(id: item.id, babyID: "baby", title: "First \(item.id)", at: Date() - 3_600, by: other,
                              timeZoneID: "Europe/London", now: Date() - 60)
            for stored in data.eventsToUpload(now: .distantFuture) {
                data.didUploadEvent(stored.event.id, sentRevision: stored.localRevision, systemFields: Data([1]),
                                    serverCreatedAt: Date() - 60)
            }
            if item.deleted { data.delete(item.id, by: other, now: Date()) }
        }
        return data
    }

    func notifier(_ center: FakeNoticeCenter) throws -> (NewFirstNotifier, UserDefaults, String) {
        let suite = "x1-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (NewFirstNotifier(defaults: defaults, center: center), defaults, suite)
    }

    @Test func eachNewFirstIsToldOnceAndAFailedOneIsTriedAgain() async throws {
        let center = FakeNoticeCenter()
        let (notifier, defaults, suite) = try notifier(center)
        defer { defaults.removePersistentDomain(forName: suite) }
        // The first download: noted, not told.
        let before = household([("smile", false)])
        await notifier.update(planned: before, current: { before }, me: me, names: [other: "Alex"], fetchedOnce: true)
        #expect(center.added.isEmpty)
        // A new one arrives: told once.
        let after = household([("smile", false), ("laugh", false)])
        await notifier.update(planned: after, current: { after }, me: me, names: [other: "Alex"], fetchedOnce: true)
        #expect(center.added == ["newFirst-laugh"])
        await notifier.update(planned: after, current: { after }, me: me, names: [other: "Alex"], fetchedOnce: true)
        #expect(center.added == ["newFirst-laugh"])
        // One that couldn't be sent is tried again next time.
        let more = household([("smile", false), ("laugh", false), ("bath", false)])
        center.failNext = true
        await notifier.update(planned: more, current: { more }, me: me, names: [other: "Alex"], fetchedOnce: true)
        #expect(center.added == ["newFirst-laugh"])
        await notifier.update(planned: more, current: { more }, me: me, names: [other: "Alex"], fetchedOnce: true)
        #expect(center.added == ["newFirst-laugh", "newFirst-bath"])
    }

    /// Checked again just before sending: a first deleted meanwhile, or the switch turned off, sends nothing.
    @Test func aFirstDeletedOrTheSwitchTurnedOffMeanwhileSendsNothing() async throws {
        let center = FakeNoticeCenter()
        let (notifier, defaults, suite) = try notifier(center)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([String](), forKey: "journal.knownFirsts")
        let planned = household([("smile", false)])
        let deletedSince = household([("smile", true)])
        await notifier.update(planned: planned, current: { deletedSince }, me: me, names: [:], fetchedOnce: true)
        #expect(center.added.isEmpty)
        defaults.set([String](), forKey: "journal.knownFirsts")
        defaults.set(false, forKey: NewFirstNotifier.wantedKey)
        await notifier.update(planned: planned, current: { planned }, me: me, names: [:], fetchedOnce: true)
        #expect(center.added.isEmpty)
    }

    @Test func aNoticeIsTakenBackWhenItsFirstIsDeleted() async throws {
        let center = FakeNoticeCenter()
        let (notifier, defaults, suite) = try notifier(center)
        defer { defaults.removePersistentDomain(forName: suite) }
        center.delivered = ["newFirst-smile"]
        let deleted = household([("smile", true)])
        await notifier.update(planned: deleted, current: { deleted }, me: me, names: [:], fetchedOnce: true)
        #expect(center.removed == ["newFirst-smile"])
    }

    // MARK: Presentation and taps

    /// Outside voice OV6: with the app open, the notice is the list only at night and a banner with
    /// no sound by day; every other notification keeps its banner and sound.
    @Test func withTheAppOpenTheNoticeIsQuietAndFeedAlertsAreNot() {
        #expect(NotificationDelegate.presentation(for: "newFirst-smile", isNight: true) == [.list])
        #expect(NotificationDelegate.presentation(for: "newFirst-smile", isNight: false) == [.banner, .list])
        for other in ["feed-window-1", "nightAsk-2026-11-19-asked", "backup-1"] {
            #expect(NotificationDelegate.presentation(for: other, isNight: true) == [.banner, .list, .sound])
        }
    }

    @Test func aTapOnTheNoticeNamesItsFirst() {
        #expect(NotificationTaps.firstID("newFirst-ABC-123") == "ABC-123")
        #expect(NotificationTaps.firstID("newFirst-") == nil)
        #expect(NotificationTaps.firstID("nightAsk-x") == nil)
    }
}

/// Outside review O8 and the Codex review of X1: the notice starts only once the alerts are set,
/// is never awaited by the alert run, and a call during a run waits for a pass with its data.
@Suite("Alert runs and the notice")
@MainActor
struct AlertRunOrderTests {
    func reconciler(applying apply: @escaping Reconciler.ApplyAlerts) throws -> (Reconciler, () -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("runs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "runs-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = HouseholdStore(fileURL: folder.appendingPathComponent("household.json"), alarmsSet: { false })
        let reconciler = Reconciler(store: store, sync: HouseholdSync(store: store), defaults: defaults, applyAlerts: apply)
        return (reconciler, {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        })
    }

    @Test func theNoticeStartsAfterTheAlertsAreSet() async throws {
        let order = Box<[String]>([])
        let (reconciler, cleanUp) = try reconciler { _, _, _, _, _ in order.value.append("alerts set") }
        defer { cleanUp() }
        reconciler.onRunFinished = { _ in order.value.append("notice starts") }
        await reconciler.run()
        #expect(order.value == ["alerts set", "notice starts"])
    }

    /// A push's run, made while another run is setting alerts, returns only after a pass that
    /// began after it, so what the push brought is in the alerts before the app sleeps again.
    @Test func aCallDuringARunWaitsForThePassAfterIt() async throws {
        let passes = Box(0)
        let gate = Box<CheckedContinuation<Void, Never>?>(nil)
        let (reconciler, cleanUp) = try reconciler { _, _, _, _, _ in
            passes.value += 1
            if passes.value == 1 { await withCheckedContinuation { gate.value = $0 } }
        }
        defer { cleanUp() }
        let first = Task { await reconciler.run() }
        while gate.value == nil { await Task.yield() }
        let secondDone = Box(false)
        let second = Task {
            await reconciler.run()
            secondDone.value = true
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(!secondDone.value)
        #expect(passes.value == 1)
        gate.value?.resume()
        await second.value
        #expect(passes.value == 2)
        await first.value
    }
}
