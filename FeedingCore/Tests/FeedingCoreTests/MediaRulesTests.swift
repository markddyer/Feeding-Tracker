import Foundation
import Testing
@testable import FeedingCore

// The rules for the firsts' photos and videos (`docs/planning/07-milestones-journal.md`, task T4).

private let start = at(2026, 11, 18, 10, 0)
private let megabyte: Int64 = 1_000_000

@Suite("Photos: the household allowance")
struct PhotoAllowanceTests {
    @Test func itStartsAt1GBAndEitherParentCanChangeIt() {
        var data = HouseholdData()
        #expect(data.photoAllowance == 1_000_000_000)
        data.setPhotoAllowance(2_000_000_000, now: start)
        #expect(data.photoAllowance == 2_000_000_000)
        #expect(data.plainRecordsToUpload().map(\.record.key) == ["Setting/photoAllowance"])
        data.setPhotoAllowance(0, now: start)
        #expect(data.photoAllowance == 2_000_000_000)
    }

    @Test func bothPhonesSaySoAt80PercentAndPauseWhenFull() {
        let limit: Int64 = 1_000_000_000
        #expect(AllowanceLevel(used: 799_999_999, limit: limit) == .fine)
        #expect(AllowanceLevel(used: 800_000_000, limit: limit) == .nearlyFull)
        #expect(AllowanceLevel(used: 999_999_999, limit: limit) == .nearlyFull)
        #expect(AllowanceLevel(used: limit, limit: limit) == .full)
        #expect(AllowanceLevel(used: limit + 1, limit: limit) == .full)
    }

    @Test func theTallyIsTheSumOfItsItems() {
        let tally = MediaTally(items: ["a": 3 * megabyte, "b": 7 * megabyte])
        #expect(tally.bytesUsed == 10 * megabyte)
        #expect(tally.removing("a").bytesUsed == 7 * megabyte)
        #expect(tally.removing("missing") == tally)
    }

    @Test func anItemThatFitsGoesIntoTheTally() {
        let tally = MediaTally(items: ["a": 900 * megabyte])
        #expect(tally.decide(adding: "b", bytes: 100 * megabyte, limit: 1_000 * megabyte)
            == .save(MediaTally(items: ["a": 900 * megabyte, "b": 100 * megabyte])))
        #expect(tally.decide(adding: "b", bytes: 100 * megabyte + 1, limit: 1_000 * megabyte) == .overLimit)
    }

    /// The tally record stays under iCloud's 1 MB, whatever the IDs: past its largest size,
    /// uploads pause.
    @Test func theTallyStopsGrowingBelow1MB() throws {
        let longID = { (n: Int) in String(repeating: "x", count: 72) + String(format: "%08d", n) }
        // About 89 bytes an item: the limit falls near 10,100 items.
        var tally = MediaTally(items: Dictionary(uniqueKeysWithValues: (0..<10_050).map { (longID($0), Int64(50_000)) }))
        var n = 10_050
        while case .save(let next) = tally.decide(adding: longID(n), bytes: 50_000, limit: .max) {
            tally = next
            n += 1
        }
        #expect(tally.decide(adding: longID(n), bytes: 50_000, limit: .max) == .overLimit)
        #expect(try PayloadCoder.encode(tally).count <= MediaTally.mostBytes)
        #expect(tally.items.count > 10_050)
    }

    /// The answer to a save was lost, but the tally lists the item: the save went through.
    @Test func anItemTheTallyListsIsAlreadySaved() {
        let tally = MediaTally(items: ["a": 900 * megabyte])
        #expect(tally.decide(adding: "a", bytes: 900 * megabyte, limit: 1_000 * megabyte) == .alreadySaved)
    }

    /// Both phones read the tally at 900 MB and each wants to add 80 MB. Parent A's phone saves
    /// first; Parent B's save clashes, it reads the tally again, and the limit is checked again.
    @Test func aClashChecksTheLimitAgain() {
        let limit = 1_000 * megabyte
        let read = MediaTally(items: ["old": 900 * megabyte])
        guard case .save(let afterA) = read.decide(adding: "fromA", bytes: 80 * megabyte, limit: limit) else {
            Issue.record("Parent A's item should fit")
            return
        }
        #expect(read.decide(adding: "fromB", bytes: 80 * megabyte, limit: limit) != .overLimit)
        #expect(afterA.decide(adding: "fromB", bytes: 80 * megabyte, limit: limit) == .overLimit)
        #expect(afterA.decide(adding: "fromB", bytes: 20 * megabyte, limit: limit)
            == .save(MediaTally(items: ["old": 900 * megabyte, "fromA": 80 * megabyte, "fromB": 20 * megabyte])))
    }

    @Test func theTallyEncodesTheSameOnBothPhones() throws {
        let one = try PayloadCoder.encode(MediaTally(items: ["b": 2, "a": 1, "c": 3]))
        let two = try PayloadCoder.encode(MediaTally(items: ["c": 3, "a": 1, "b": 2]))
        #expect(one == two)
        #expect(PayloadCoder.decode(MediaTally.self, from: one) == MediaTally(items: ["a": 1, "b": 2, "c": 3]))
    }

    /// Only the live firsts' photos are kept, and those Undo can still bring back.
    @Test func theItemsInUseAreTheLiveFirstsOnes() {
        var data = HouseholdData()
        data.addMilestone(id: "smile", babyID: baby, title: "First smile", media: ["m1", "m2"], at: start, by: parentA,
                          timeZoneID: "Europe/London", now: start)
        data.addMilestone(id: "laugh", babyID: baby, title: "First laugh", media: ["m3"], at: start, by: parentA,
                          timeZoneID: "Europe/London", now: start)
        data.saveEditor("smile", title: "First smile", media: ["m2"], at: start, by: parentA, now: start + 60)
        data.delete("laugh", by: parentA, now: start + 60)
        // Undo can still bring the others back, so the phone keeps them until it ends.
        #expect(data.mediaInUse == ["m1", "m2", "m3"])
        data.endUndoWindows()
        #expect(data.mediaInUse == ["m2"])
    }
}

@Suite("Photos: an item's details")
struct MediaDetailsTests {
    @Test func detailsRoundTripAndAnUnknownKindIsKept() throws {
        let video = MediaDetails(kind: .video, width: 1280, height: 720, durationSeconds: 12.5)
        #expect(PayloadCoder.decode(MediaDetails.self, from: try PayloadCoder.encode(video)) == video)
        let newer = Data(#"{"v":1,"kind":"audio","width":0,"height":0}"#.utf8)
        #expect(PayloadCoder.decode(MediaDetails.self, from: newer)?.kind == "audio")
        #expect(PayloadCoder.decode(MediaDetails.self, from: Data(#"{"v":2,"kind":"photo","width":1,"height":1}"#.utf8)) == nil)
    }
}

@Suite("Photos: space kept free for feeds")
struct SpaceRuleTests {
    @Test func theReserveIsAlwaysKept() {
        let reserve = SpaceRule.reserveBytes
        #expect(SpaceRule.fits(8 * megabyte, free: reserve + 8 * megabyte))
        #expect(!SpaceRule.fits(8 * megabyte, free: reserve + 8 * megabyte - 1))
        #expect(!SpaceRule.fits(0, free: reserve - 1))
    }

    /// An export counts what it still has to download and the packed file.
    @Test func anExportCountsItsDownloadsAndItsFile() {
        let free = SpaceRule.reserveBytes + 300 * megabyte
        #expect(SpaceRule.exportFits(toDownload: 100 * megabyte, packedFile: 200 * megabyte, free: free))
        #expect(!SpaceRule.exportFits(toDownload: 100 * megabyte, packedFile: 200 * megabyte + 1, free: free))
    }
}

@Suite("Photos: feeds go first")
struct TransferGateTests {
    @Test func aTransferStartsOnlyWhileNothingWaitsAndNoFetchRuns() {
        #expect(TransferGate(engineFetchRunning: false, entryWaitingFor: nil).mayStart)
        #expect(!TransferGate(engineFetchRunning: true, entryWaitingFor: nil).mayStart)
        #expect(!TransferGate(engineFetchRunning: false, entryWaitingFor: 0).mayStart)
    }

    /// Eng D3: an entry waiting 4.9 seconds behind a transfer lets it go on; at 5 seconds it stops.
    /// The wait is measured on a clock that setting the time can't move.
    @Test(arguments: [false, true])
    func anEntryWaiting5SecondsStopsATransfer(_ isDownload: Bool) {
        #expect(!TransferGate(engineFetchRunning: false, entryWaitingFor: 4.9).stopsTransferInFlight(isDownload: isDownload))
        #expect(TransferGate(engineFetchRunning: false, entryWaitingFor: 5).stopsTransferInFlight(isDownload: isDownload))
        #expect(!TransferGate(engineFetchRunning: false, entryWaitingFor: nil).stopsTransferInFlight(isDownload: isDownload))
    }

    /// Eng D9: a fetch starting stops a download at once; it starts again once the fetch is over.
    /// An upload in flight goes on; a new one waits for the fetch.
    @Test func aFetchStopsADownloadUntilItIsOver() {
        let fetching = TransferGate(engineFetchRunning: true, entryWaitingFor: nil)
        #expect(fetching.stopsTransferInFlight(isDownload: true))
        #expect(!fetching.stopsTransferInFlight(isDownload: false))
        #expect(!fetching.mayStart)
        #expect(TransferGate(engineFetchRunning: false, entryWaitingFor: nil).mayStart)
    }
}

@Suite("Photos: the clean-up")
struct MediaCleanUpTests {
    let me = "_parentA"
    let other = "_parentB"

    /// A first as this phone holds it, with its removed list already in iCloud unless `unsent`.
    func first(removed: [String] = [], removedAt: Date = start, unsent: Bool = false,
               payload: EventPayload? = nil) -> StoredEvent {
        var details = EventPayload(milestone: MilestoneDetails(title: "First smile", media: ["kept"], removedMedia: removed))
        details.setStamp(.removedMedia, FieldStamp(at: removedAt, by: parentB))
        let event = snapshot(start, id: "smile", kind: .milestone, payload: payload ?? details)
        return StoredEvent(event: (try? event.encoded()) ?? event.event, changedFields: unsent ? [.removedMedia] : [],
                           needsUpload: unsent, uploadNotBefore: nil, systemFields: Data([1]), localRevision: 1)
    }

    func decide(_ creator: String, first: StoredEvent?, isOwner: Bool = false, leftAt: [String: Date] = [:],
                now: Date) -> CleanUpDecision {
        MediaCleanUp.decide(MediaRecordFacts(id: "gone", eventID: "smile", creator: creator), first: first, me: me,
                            isOwner: isOwner, leftAt: leftAt, now: now)
    }

    @Test func onlyAnItemOnTheRemovedListIsEverDeleted() {
        #expect(decide(me, first: first(), now: start + 3600) == .keep)
        // An item that arrives before its first.
        #expect(decide(me, first: nil, now: start + 3600) == .keep)
        // A first this build can't read.
        var unreadable = first(removed: ["gone"])
        unreadable.event.payload = Data(#"{"v":99}"#.utf8)
        #expect(decide(me, first: unreadable, now: start + 3600) == .keep)
    }

    /// The parent who saved it deletes it, once the removal is older than Undo plus a minute.
    @Test func theMakersPhoneDeletesItAfterUndoAndAMinute() {
        let removed = first(removed: ["gone"])
        #expect(decide(me, first: removed, now: start + 69) == .waitUntil(start + 70))
        #expect(decide(me, first: removed, now: start + 70) == .delete)
        #expect(decide(other, first: removed, now: start + 3600) == .notThisPhone)
    }

    /// A removal not yet in iCloud can still be undone: it is never deleted, even with the clock
    /// moved on a day.
    @Test func aRemovalNotYetInICloudIsNeverDeleted() {
        #expect(decide(me, first: first(removed: ["gone"], unsent: true), now: start + 86_400) == .keep)
    }

    /// A parent who left can't delete their items: the owner's phone does, 30 days after.
    @Test func theOwnersPhoneDeletesALeaversItems30DaysAfter() {
        let removed = first(removed: ["gone"])
        let left = start + 86_400
        let thirtyDays = 30 * 86_400.0
        #expect(decide(other, first: removed, isOwner: true, now: left + thirtyDays) == .notThisPhone)
        #expect(decide(other, first: removed, isOwner: true, leftAt: [other: left], now: left + 86_400)
            == .waitUntil(left + thirtyDays))
        #expect(decide(other, first: removed, isOwner: true, leftAt: [other: left], now: left + thirtyDays) == .delete)
        #expect(decide(other, first: removed, isOwner: false, leftAt: [other: left], now: left + thirtyDays) == .notThisPhone)
    }
}

@Suite("Photos: the photos share's members")
struct PhotosShareTests {
    @Test func thePhotosShareFollowsTheHouseholdShare() {
        let changes = PhotosShareChanges(household: ["owner", "parentB", "joinedLater"], photos: ["owner", "parentB", "left"],
                                         owner: "owner")
        #expect(changes.add == ["joinedLater"])
        #expect(changes.remove == ["left"])
        #expect(PhotosShareChanges(household: ["owner", "parentB"], photos: ["parentB"], owner: "owner").isEmpty)
    }
}

@Suite("Photos: the \"Only on this iPhone\" mark")
struct OnlyHereTests {
    @Test func tenMinutesAfterSaveOrAtOnceWhenSendingStopped() {
        #expect(!OnlyHereRule.isOnlyHere(queuedAt: start, stopped: false, now: start + 599))
        #expect(OnlyHereRule.isOnlyHere(queuedAt: start, stopped: false, now: start + 600))
        #expect(OnlyHereRule.isOnlyHere(queuedAt: start, stopped: true, now: start))
    }

    @Test func theScreenLooksAgainWhenTheNextMarkIsDue() {
        #expect(OnlyHereRule.nextChange(queuedAt: [start, start + 120], now: start + 60) == start + 600)
        #expect(OnlyHereRule.nextChange(queuedAt: [start], now: start + 600) == nil)
        #expect(OnlyHereRule.nextChange(queuedAt: [], now: start) == nil)
    }
}

@Suite("Photos: telling the other phone of a new first")
struct NewFirstNoticeTests {
    func newFirst(by: MemberID = parentB, savedAt: Date? = at(2026, 11, 18, 9, 0), deletedAt: Date? = nil,
                  kind: EventKind = .milestone) -> Event {
        Event(id: "smile", babyID: baby, kind: kind, startedAt: at(2026, 11, 18, 8, 0), timeZoneID: "Europe/London",
              loggedBy: by, createdAt: at(2026, 11, 18, 9, 0), modifiedAt: at(2026, 11, 18, 9, 0), deletedAt: deletedAt,
              serverCreatedAt: savedAt)
    }

    func notice(_ first: Event, heldBefore: Bool = false, isInitialFetch: Bool = false, wanted: Bool = true,
                now: Date = at(2026, 11, 18, 10, 0)) -> NewFirstNotice? {
        NewFirstRule.notice(for: first, heldBefore: heldBefore, isInitialFetch: isInitialFetch, me: parentA, wanted: wanted,
                            dayHours: .standard, timeZone: london, now: now)
    }

    @Test func aNewFirstFromTheOtherParentIsShownByDayAndListedAtNight() {
        #expect(notice(newFirst()) == .shown)
        #expect(notice(newFirst(), now: at(2026, 11, 18, 23, 0)) == .listOnly)
        #expect(notice(newFirst(), now: at(2026, 11, 19, 6, 59)) == .listOnly)
    }

    /// Design review D19: the household's night hours, read on its own clock: 21:00 and 07:00
    /// exactly, and the night the clocks go back (25 Oct 2026, 02:00 BST becomes 01:00 GMT).
    @Test func theNightBoundariesAndAClockChange() {
        #expect(notice(newFirst(), now: at(2026, 11, 18, 20, 59)) == .shown)
        #expect(notice(newFirst(), now: at(2026, 11, 18, 21, 0)) == .listOnly)
        #expect(notice(newFirst(), now: at(2026, 11, 19, 7, 0)) == .shown)
        let saved = at(2026, 10, 25, 0, 0, in: TimeZone(identifier: "UTC")!) // 01:00 BST
        let first = newFirst(savedAt: saved)
        #expect(notice(first, now: saved + 3600) == .listOnly)       // 01:00 GMT, the second 01:00
        #expect(notice(first, now: saved + 6.5 * 3600) == .listOnly) // 06:30 GMT
        #expect(notice(first, now: saved + 7 * 3600) == .shown)      // 07:00 GMT
    }

    @Test func notForEditsRestoresOrTheFirstFetch() {
        #expect(notice(newFirst(), heldBefore: true) == nil)
        #expect(notice(newFirst(), isInitialFetch: true) == nil)
    }

    @Test func notForMyOwnOrDeletedOrOldOnesOrWhenTurnedOff() {
        #expect(notice(newFirst(by: parentA)) == nil)
        #expect(notice(newFirst(deletedAt: at(2026, 11, 18, 9, 30))) == nil)
        #expect(notice(newFirst(), wanted: false) == nil)
        #expect(notice(newFirst(kind: .nappy)) == nil)
        // Not yet saved by iCloud, so no save time to go by.
        #expect(notice(newFirst(savedAt: nil)) == nil)
        // Saved 24 hours ago, by iCloud's time: the first's own date doesn't matter.
        #expect(notice(newFirst(), now: at(2026, 11, 19, 8, 59)) == .shown)
        #expect(notice(newFirst(), now: at(2026, 11, 19, 9, 0)) == nil)
    }

    /// A phone clock a little behind iCloud's still shows a new first; one set back a day shows
    /// no old first as new.
    @Test func aClockBehindIClouds() {
        #expect(notice(newFirst(savedAt: at(2026, 11, 18, 10, 5))) == .shown)
        #expect(notice(newFirst(savedAt: at(2026, 11, 19, 10, 0))) == nil)
    }
}
