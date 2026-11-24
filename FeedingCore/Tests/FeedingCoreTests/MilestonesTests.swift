import Foundation
import Testing
@testable import FeedingCore

// The baby's firsts (`docs/planning/07-milestones-journal.md`, task T3): the payload, the limits,
// the removed list, the baby's age, the Firsts list, and the alerts left alone.

private let londonID = "Europe/London"
private let t0 = at(2026, 11, 18, 10, 0)

/// What iCloud holds once `data` has sent its changes to the event. The event must be waiting to
/// be sent.
private func sent(_ data: inout HouseholdData, _ id: String, tag: UInt8 = 1) -> Event {
    guard let stored = data.eventsToUpload(now: .distantFuture).first(where: { $0.event.id == id }) else {
        Issue.record("\(id) wasn't waiting to be sent")
        return data.events[id]!.event
    }
    data.didUploadEvent(id, sentRevision: stored.localRevision, systemFields: Data([tag]), serverCreatedAt: stored.event.createdAt)
    return data.events[id]!.event
}

private func details(_ data: HouseholdData, _ id: String) -> MilestoneDetails? {
    data.events[id]?.snapshot.payload?.milestone
}

private func withBirthDate(_ birth: String, _ data: HouseholdData = HouseholdData()) throws -> HouseholdData {
    var data = data
    data.put(PlainRecord(type: .baby, name: baby, modifiedAt: t0,
                         payload: try PayloadCoder.encode(BabyPayload(name: "Baby", birthDate: date(birth)))))
    return data
}

extension HouseholdData {
    /// Opens the editor on the first as it is now and saves it at once.
    @discardableResult
    mutating func saveEditor(_ id: String, title: String, note: String? = nil, media: [String],
                             crops: [String: MediaCrop]? = nil, at: Date, by member: MemberID, now: Date) -> Bool {
        guard let original = events[id]?.snapshot else { return false }
        return editMilestone(id, from: original, title: title, note: note, media: media, crops: crops, at: at, by: member,
                             now: now)
    }
}

@Suite("Firsts: the payload")
struct MilestonePayloadTests {
    @Test func aFirstIsVersion3AndOtherKindsKeepTheirVersions() {
        #expect(EventPayload(milestone: MilestoneDetails(title: "First smile")).v == 3)
        #expect(EventPayload(feed: FeedDetails()).v == 1)
        #expect(EventPayload(nappy: NappyDetails(wee: true, poo: false)).v == 2)
        var payload = EventPayload(note: "x")
        payload.milestone = MilestoneDetails(title: "First smile")
        #expect(payload.v == 3)
    }

    /// A build that knows version 2 at most leaves a first unread, so it can never save one back
    /// without its title and photos.
    @Test func anOlderBuildDoesNotReadAFirst() throws {
        struct OlderBuildPayload: VersionedPayload {
            static var currentVersion: Int { 2 }
            var v: Int
        }
        let bytes = try PayloadCoder.encode(EventPayload(milestone: MilestoneDetails(title: "First smile", media: ["m1"])))
        #expect(PayloadCoder.decode(OlderBuildPayload.self, from: bytes) == nil)
        let back = try #require(PayloadCoder.decode(EventPayload.self, from: bytes))
        #expect(back.milestone == MilestoneDetails(title: "First smile", media: ["m1"]))
    }

    @Test func addingAFirstStampsItsOwnFields() throws {
        var data = HouseholdData()
        let added1 = data.addMilestone(babyID: baby, title: "First smile", note: "At bath time", media: ["m1"],
                                       at: t0, by: parentA, timeZoneID: londonID, now: t0)
        let id = try #require(added1)
        let stored = try #require(data.events[id])
        #expect(stored.event.kind == .milestone)
        #expect(stored.changedFields == [.startedAt, .endedAt, .deletedAt, .note, .title, .media, .removedMedia, .crops])
        let payload = try #require(stored.snapshot.payload)
        #expect(payload.milestone == MilestoneDetails(title: "First smile", media: ["m1"]))
        #expect(payload.note == "At bath time")
        #expect(payload.stamp(.title) == FieldStamp(at: t0, by: parentA))
    }

    @Test func aFirstNeedsATitle() {
        var data = HouseholdData()
        let added2 = data.addMilestone(babyID: baby, title: "  \n ", at: t0, by: parentA, timeZoneID: londonID, now: t0)
        #expect(added2 == nil)
        #expect(data.events.isEmpty)
    }

    @Test func aTitleIsOneTrimmedLineAndAnEmptyNoteIsNone() throws {
        var data = HouseholdData()
        let added3 = data.addMilestone(babyID: baby, title: "  First\nsmile ", note: " \n ", at: t0,
                                       by: parentA, timeZoneID: londonID, now: t0)
        let id = try #require(added3)
        #expect(details(data, id)?.title == "First smile")
        #expect(data.events[id]?.snapshot.payload?.note == nil)
    }

    /// Trimming takes whole characters: an accent on a space goes with it, never left alone.
    @Test func trimmingNeverLeavesAnAccentWithoutItsLetter() {
        let title = HouseholdData.cleanTitle(" \u{0301}First smile \u{0301}")
        #expect(title == "First smile")
        #expect(HouseholdData.cleanNote("\n \u{0301}Sat up\n") == "Sat up")
    }

    @Test func aMediaListHoldsNoRepeatsNoRemovedItemsAndAtMostFour() {
        let first = MilestoneDetails(title: "x", media: ["a", "a", "b", "gone", "c", "d", "e"], removedMedia: ["gone", "gone"])
        #expect(first.media == ["a", "b", "c", "d"])
        #expect(first.removedMedia == ["gone"])
    }

    /// Merging a first's fields never gives a feed a first's details, which would raise its
    /// version and hide it from an older build.
    @Test func aFeedNeverGainsAFirstsDetails() {
        var feedCopy = snapshot(t0, payload: EventPayload(feed: FeedDetails(bottles: [Bottle(milk: .formula, ml: 60)])))
        let other = snapshot(t0, payload: EventPayload(feed: FeedDetails()))
        for field: EventField in [.title, .media, .removedMedia] { feedCopy.copy(field, from: other) }
        #expect(feedCopy.payload?.milestone == nil)
        #expect(feedCopy.payload?.v == 1)
    }
}

@Suite("Firsts: limits")
struct MilestoneLimitTests {
    @Test func theTitleStopsAt80CharactersAndTheNoteAt5000() throws {
        var data = HouseholdData()
        let added4 = data.addMilestone(babyID: baby, title: String(repeating: "a", count: 100),
                                       note: String(repeating: "b", count: 6_000), at: t0, by: parentA,
                                       timeZoneID: londonID, now: t0)
        let id = try #require(added4)
        #expect(details(data, id)?.title.count == 80)
        #expect(data.events[id]?.snapshot.payload?.note?.count == 5_000)
    }

    /// 4-byte emoji fit both limits whole, and the first stays far under iCloud's 1 MB.
    @Test func atBothLimitsInEmojiAFirstIsFarUnder1MB() throws {
        var data = HouseholdData()
        let added5 = data.addMilestone(babyID: baby, title: String(repeating: "😀", count: 90),
                                       note: String(repeating: "😀", count: 6_000), at: t0, by: parentA,
                                       timeZoneID: londonID, now: t0)
        let id = try #require(added5)
        #expect(details(data, id)?.title.count == 80)
        #expect(data.events[id]?.snapshot.payload?.note?.count == 5_000)
        #expect(try #require(data.events[id]?.event.payload).count < 64 * 1_024)
    }

    /// One character can hold many code points ("e" with 50 accents is one character of 101
    /// bytes), so the byte limits stop the text first, and never inside a character (OE9).
    @Test func manyCodePointsInACharacterStopAtTheByteLimit() {
        let heavy = "e" + String(repeating: "\u{0301}", count: 50)
        #expect(heavy.count == 1)
        #expect(heavy.utf8.count == 101)
        let long = String(repeating: heavy, count: 5_000)
        let note = MilestoneLimits.note(long)
        #expect(note.utf8.count <= MilestoneLimits.noteBytes)
        #expect(note.count == MilestoneLimits.noteBytes / 101)
        #expect(long.hasPrefix(note))
        let title = MilestoneLimits.title(long)
        #expect(title.utf8.count <= MilestoneLimits.titleBytes)
        #expect(title.count == MilestoneLimits.titleBytes / 101)
    }

    /// Whatever is typed, the encoded first stays far under 1 MB, even text that JSON writes at
    /// six bytes a character.
    @Test(arguments: ["😀", "e" + String(repeating: "\u{0301}", count: 50), "\u{01}", "\"", "👨‍👩‍👧‍👦"])
    func everyKindOfTextStaysFarUnder1MB(_ piece: String) throws {
        var data = HouseholdData()
        let text = "x" + String(repeating: piece, count: 40_000)
        let added6 = data.addMilestone(babyID: baby, title: text, note: text, media: ["m1", "m2", "m3", "m4"],
                                       at: t0, by: parentA, timeZoneID: londonID, now: t0)
        let id = try #require(added6)
        #expect(try #require(data.events[id]?.event.payload).count < 256 * 1_024)
    }
}

@Suite("Firsts: removed photos stay removed")
struct RemovedMediaTests {
    /// Parent A's phone and Parent B's, each holding the first with three photos.
    func twoPhones() throws -> (a: HouseholdData, b: HouseholdData, id: String) {
        var a = HouseholdData()
        let added7 = a.addMilestone(babyID: baby, title: "First smile", media: ["m1", "m2", "m3"], at: t0,
                                    by: parentA, timeZoneID: londonID, now: t0)
        let id = try #require(added7)
        var b = HouseholdData()
        b.receiveEvent(sent(&a, id), systemFields: Data([1]))
        return (a, b, id)
    }

    @Test func removingAnItemAddsItToTheRemovedList() throws {
        var (a, _, id) = try twoPhones()
        let saved8 = a.saveEditor(id, title: "First smile", note: nil, media: ["m3", "m1"], at: t0, by: parentA, now: t0 + 60)
        #expect(saved8)
        #expect(details(a, id) == MilestoneDetails(title: "First smile", media: ["m3", "m1"], removedMedia: ["m2"]))
        #expect(a.events[id]?.changedFields == [.media, .removedMedia])
    }

    @Test func aRemovedItemCantBeAddedBack() throws {
        var (a, _, id) = try twoPhones()
        a.saveEditor(id, title: "First smile", note: nil, media: ["m1"], at: t0, by: parentA, now: t0 + 60)
        a.saveEditor(id, title: "First smile", note: nil, media: ["m1", "m2", "m4"], at: t0, by: parentA, now: t0 + 120)
        #expect(details(a, id)?.media == ["m1", "m4"])
        #expect(details(a, id)?.removedMedia == ["m2", "m3"])
    }

    /// Eng D10: Parent B removes a photo; Parent A, offline, puts the photos in a new order later.
    /// A's order wins, as the later change, but the removed photo stays out on both phones.
    @Test func anOfflineReorderAfterARemovalLeavesTheItemOutOnBothPhones() throws {
        var (a, b, id) = try twoPhones()
        let saved9 = b.saveEditor(id, title: "First smile", note: nil, media: ["m1", "m3"], at: t0, by: parentB, now: t0 + 60)
        #expect(saved9)
        let fromB = sent(&b, id, tag: 2)
        let saved10 = a.saveEditor(id, title: "First smile", note: nil, media: ["m3", "m2", "m1"], at: t0, by: parentA, now: t0 + 120)
        #expect(saved10)
        let outcome11 = a.receiveEvent(fromB, systemFields: Data([2]))
        #expect(outcome11 == .merged(applied: [.media], overruled: []))
        #expect(details(a, id) == MilestoneDetails(title: "First smile", media: ["m3", "m1"], removedMedia: ["m2"]))
        b.receiveEvent(sent(&a, id, tag: 3), systemFields: Data([3]))
        #expect(details(b, id) == details(a, id))
    }

    /// Both phones remove a different photo at about the same time: both stay removed, whichever
    /// change is later.
    @Test(arguments: [30.0, 90.0])
    func removalsOnBothPhonesAreJoined(_ secondsForA: Double) throws {
        var (a, b, id) = try twoPhones()
        b.saveEditor(id, title: "First smile", note: nil, media: ["m1", "m2"], at: t0, by: parentB, now: t0 + 60)
        let fromB = sent(&b, id, tag: 2)
        a.saveEditor(id, title: "First smile", note: nil, media: ["m2", "m3"], at: t0, by: parentA, now: t0 + secondsForA)
        let outcome = a.receiveEvent(fromB, systemFields: Data([2]))
        #expect(details(a, id) == MilestoneDetails(title: "First smile", media: ["m2"], removedMedia: ["m1", "m3"]))
        guard case .merged(let applied, _) = outcome else { Issue.record("not merged: \(outcome)"); return }
        #expect(applied.contains(.removedMedia))
        b.receiveEvent(sent(&a, id, tag: 3), systemFields: Data([3]))
        #expect(details(b, id) == details(a, id))
    }

    /// Copying the removed list from an older copy joins it, so it never shrinks.
    @Test func copyingTheRemovedListNeverShrinksIt() {
        var mine = snapshot(t0, kind: .milestone,
                            payload: EventPayload(milestone: MilestoneDetails(title: "x", media: ["m1"], removedMedia: ["m2"])))
        let older = snapshot(t0, kind: .milestone,
                             payload: EventPayload(milestone: MilestoneDetails(title: "x", media: ["m1", "m2", "m3"])))
        mine.copy(.removedMedia, from: older)
        #expect(mine.payload?.milestone?.removedMedia == ["m2"])
        mine.copy(.media, from: older)
        #expect(mine.payload?.milestone?.media == ["m1", "m3"])
    }

    /// Both phones removed the same photo: the removed list isn't counted as this phone's change
    /// again, and its stamp stays iCloud's, so both phones keep the same one.
    @Test func theSameRemovalOnBothPhonesIsNotCountedTwice() throws {
        var (a, b, id) = try twoPhones()
        b.saveEditor(id, title: "First smile", media: ["m1", "m3"], at: t0, by: parentB, now: t0 + 10)
        b.saveEditor(id, title: "First smile", media: ["m3", "m1"], at: t0, by: parentB, now: t0 + 30)
        let fromB = sent(&b, id, tag: 2)
        a.saveEditor(id, title: "First smile", media: ["m1", "m3"], at: t0, by: parentA, now: t0 + 20)
        let outcome = a.receiveEvent(fromB, systemFields: Data([2]))
        #expect(outcome == .merged(applied: [], overruled: [.media]))
        #expect(details(a, id) == details(b, id))
        #expect(a.events[id]?.snapshot.payload?.stamp(.removedMedia) == b.events[id]?.snapshot.payload?.stamp(.removedMedia))
        #expect(a.eventsToUpload(now: t0 + 60).isEmpty)
    }

    /// iCloud's copy can arrive late, after a newer one. A removal this phone already has is kept,
    /// and sent again, so the photo never comes back.
    @Test func anOlderCopyArrivingLateCantBringARemovedPhotoBack() throws {
        var (a, b, id) = try twoPhones()
        let beforeRemoval = a.events[id]!.event
        b.saveEditor(id, title: "First smile", media: ["m1", "m3"], at: t0, by: parentB, now: t0 + 60)
        a.receiveEvent(sent(&b, id, tag: 2), systemFields: Data([2]))
        #expect(details(a, id)?.media == ["m1", "m3"])
        let outcome = a.receiveEvent(beforeRemoval, systemFields: Data([1]))
        #expect(outcome == .merged(applied: [.media, .removedMedia], overruled: []))
        #expect(details(a, id) == MilestoneDetails(title: "First smile", media: ["m1", "m3"], removedMedia: ["m2"]))
        #expect(a.eventsToUpload(now: t0 + 120).map(\.event.id) == [id])
    }

    /// The same, with this phone holding an unsent change to another field.
    @Test func anOlderCopyCantBringARemovedPhotoBackPastAnotherChange() throws {
        var (a, b, id) = try twoPhones()
        let beforeRemoval = a.events[id]!.event
        b.saveEditor(id, title: "First smile", media: ["m1", "m3"], at: t0, by: parentB, now: t0 + 60)
        a.receiveEvent(sent(&b, id, tag: 2), systemFields: Data([2]))
        a.saveEditor(id, title: "First smile", note: "In the bath", media: ["m1", "m3"], at: t0, by: parentA, now: t0 + 90)
        let outcome = a.receiveEvent(beforeRemoval, systemFields: Data([1]))
        #expect(outcome == .merged(applied: [.note, .media, .removedMedia], overruled: []))
        #expect(details(a, id)?.media == ["m1", "m3"])
        #expect(details(a, id)?.removedMedia == ["m2"])
    }

    /// Parent B's editor was open while Parent A added a photo. B changes only the title: A's photo
    /// stays, and nothing is removed.
    @Test func anEditorOpenWhileAPhotoArrivedKeepsThatPhoto() throws {
        var (a, b, id) = try twoPhones()
        let editorOpenedOn = try #require(b.events[id]?.snapshot)
        a.saveEditor(id, title: "First smile", media: ["m1", "m2", "m3", "m4"], at: t0, by: parentA, now: t0 + 30)
        b.receiveEvent(sent(&a, id, tag: 2), systemFields: Data([2]))
        let saved = b.editMilestone(id, from: editorOpenedOn, title: "First real smile", note: nil,
                                    media: ["m1", "m2", "m3"], at: t0, by: parentB, now: t0 + 60)
        #expect(saved)
        #expect(details(b, id) == MilestoneDetails(title: "First real smile", media: ["m1", "m2", "m3", "m4"]))
        // B took a photo out meanwhile: only that one is removed; A's stays, after B's.
        let reopened = try #require(b.events[id]?.snapshot)
        let removedOne = b.editMilestone(id, from: editorOpenedOn, title: "First real smile", note: nil,
                                         media: ["m3", "m1"], at: t0, by: parentB, now: t0 + 90)
        #expect(removedOne)
        #expect(details(b, id) == MilestoneDetails(title: "First real smile", media: ["m3", "m1", "m4"], removedMedia: ["m2"]))
        #expect(reopened.payload?.milestone?.removedMedia == [])
    }

    /// The parents' choice A (18 Nov 2026): each phone adds a photo at the same time. Both photos
    /// stay, on both phones, in the same order, whichever phone sends first.
    @Test(arguments: [true, false])
    func photosAddedOnBothPhonesAtOnceAreBothKept(_ laterSendsFirst: Bool) throws {
        var a = HouseholdData()
        let added = a.addMilestone(babyID: baby, title: "First smile", media: ["m1"], at: t0, by: parentA,
                                   timeZoneID: londonID, now: t0)
        let id = try #require(added)
        var b = HouseholdData()
        b.receiveEvent(sent(&a, id), systemFields: Data([1]))
        a.saveEditor(id, title: "First smile", media: ["m1", "fromA"], at: t0, by: parentA, now: t0 + 30)
        b.saveEditor(id, title: "First smile", media: ["fromB", "m1"], at: t0, by: parentB, now: t0 + 60)
        if laterSendsFirst {
            a.receiveEvent(sent(&b, id, tag: 2), systemFields: Data([2]))
            b.receiveEvent(sent(&a, id, tag: 3), systemFields: Data([3]))
        } else {
            b.receiveEvent(sent(&a, id, tag: 2), systemFields: Data([2]))
            a.receiveEvent(sent(&b, id, tag: 3), systemFields: Data([3]))
        }
        #expect(details(a, id)?.media == ["fromB", "m1", "fromA"])
        #expect(details(b, id) == details(a, id))
        #expect(details(a, id)?.removedMedia == [])
        #expect(a.eventsToUpload(now: .distantFuture).isEmpty)
        #expect(b.eventsToUpload(now: .distantFuture).isEmpty)
    }

    /// The other phone put the photos in a new order while this editor was open; the parent only
    /// added one: the new order stays, with the added photo at the end.
    @Test func anEditorThatOnlyAddsKeepsTheOtherPhonesOrder() throws {
        var (a, b, id) = try twoPhones()
        let editorOpenedOn = try #require(b.events[id]?.snapshot)
        a.saveEditor(id, title: "First smile", media: ["m3", "m1", "m2"], at: t0, by: parentA, now: t0 + 30)
        b.receiveEvent(sent(&a, id, tag: 2), systemFields: Data([2]))
        let saved = b.editMilestone(id, from: editorOpenedOn, title: "First smile", note: nil,
                                    media: ["m1", "m2", "m3", "m4"], at: t0, by: parentB, now: t0 + 60)
        #expect(saved)
        #expect(details(b, id)?.media == ["m3", "m1", "m2", "m4"])
    }

    /// The parent moved a photo: the parent's order is used, then the other phone's new photo.
    @Test func anEditorThatReordersUsesThatOrder() throws {
        var (a, b, id) = try twoPhones()
        let editorOpenedOn = try #require(b.events[id]?.snapshot)
        a.saveEditor(id, title: "First smile", media: ["m1", "m2", "m3", "fromA"], at: t0, by: parentA, now: t0 + 30)
        b.receiveEvent(sent(&a, id, tag: 2), systemFields: Data([2]))
        let saved = b.editMilestone(id, from: editorOpenedOn, title: "First smile", note: nil,
                                    media: ["m3", "m2"], at: t0, by: parentB, now: t0 + 60)
        #expect(saved)
        #expect(details(b, id) == MilestoneDetails(title: "First smile", media: ["m3", "m2", "fromA"], removedMedia: ["m1"]))
    }

    /// Three photos, one added on each phone: the editor's save would make five, so it is refused,
    /// never cut.
    @Test func anEditorSaveThatWouldPassFourIsRefused() throws {
        var (a, b, id) = try twoPhones()
        let editorOpenedOn = try #require(b.events[id]?.snapshot)
        a.saveEditor(id, title: "First smile", media: ["m1", "m2", "m3", "fromA"], at: t0, by: parentA, now: t0 + 30)
        b.receiveEvent(sent(&a, id, tag: 2), systemFields: Data([2]))
        let saved = b.editMilestone(id, from: editorOpenedOn, title: "First smile", note: nil,
                                    media: ["m1", "m2", "m3", "fromB"], at: t0, by: parentB, now: t0 + 60)
        #expect(!saved)
        #expect(details(b, id)?.media == ["m1", "m2", "m3", "fromA"])
    }

    /// More than four photos and videos are refused, never cut silently.
    @Test func moreThanFourItemsAreRefused() throws {
        var (a, _, id) = try twoPhones()
        let saved = a.saveEditor(id, title: "First smile", media: ["m1", "m2", "m3", "m4", "m5"], at: t0, by: parentA, now: t0 + 60)
        #expect(!saved)
        #expect(details(a, id)?.media == ["m1", "m2", "m3"])
        let added = a.addMilestone(babyID: baby, title: "First bath", media: ["a", "b", "c", "d", "e"], at: t0,
                                   by: parentA, timeZoneID: londonID, now: t0)
        #expect(added == nil)
    }
}

/// Outside review O6 and outside voice OE4: a first's delete and a photo taken out wait on this
/// phone for the Undo window, so Undo brings the photos back and nothing ever left the phone.
@Suite("Firsts: deletes held for Undo")
struct HeldChangeTests {
    /// A first with two photos, already in iCloud.
    func synced() throws -> (data: HouseholdData, id: String) {
        var data = HouseholdData()
        let added = data.addMilestone(babyID: baby, title: "First smile", note: "In the bath", media: ["p1", "p2"], at: t0,
                                      by: parentA, timeZoneID: londonID, now: t0)
        let id = try #require(added)
        _ = sent(&data, id)
        return (data, id)
    }

    @Test func aDeletePutsItsPhotosOnTheRemovedListAndWaits() throws {
        var (data, id) = try synced()
        let deleteAt = t0 + 300
        let deleted = data.deleteMilestone(id, by: parentA, now: deleteAt)
        #expect(deleted)
        #expect(data.events[id]?.event.deletedAt == deleteAt)
        #expect(details(data, id) == MilestoneDetails(title: "First smile", media: [], removedMedia: ["p1", "p2"]))
        #expect(data.eventsToUpload(now: deleteAt + 9.9).isEmpty)
        #expect(!HouseholdData.mayUpload(data.events[id]!, now: deleteAt + 9.9))
        #expect(HouseholdData.mayUpload(data.events[id]!, now: deleteAt + 10))
        // Undo can still bring the photos back, so they stay on the phone until then.
        #expect(data.mediaInUse == ["p1", "p2"])
    }

    @Test func undoWithinTheWindowBringsEverythingBack() throws {
        var (data, id) = try synced()
        data.delete(id, by: parentA, now: t0 + 300)
        let undone = data.undoHeld(id, by: parentA, now: t0 + 305)
        #expect(undone)
        #expect(data.events[id]?.event.deletedAt == nil)
        #expect(details(data, id) == MilestoneDetails(title: "First smile", media: ["p1", "p2"]))
        #expect(data.events[id]?.snapshot.payload?.note == "In the bath")
        #expect(data.events[id]?.heldUndo == nil)
    }

    @Test func noUndoOnceTheWindowHasPassedOrTheChangeWasSent() throws {
        var (data, id) = try synced()
        data.delete(id, by: parentA, now: t0 + 300)
        let late = data.undoHeld(id, by: parentA, now: t0 + 310)
        #expect(!late)
        _ = sent(&data, id)
        #expect(data.events[id]?.heldUndo == nil)
        // Brought back later: the words only; the photos are gone for good.
        data.restore(id, by: parentA, now: t0 + 400)
        #expect(details(data, id) == MilestoneDetails(title: "First smile", media: [], removedMedia: ["p1", "p2"]))
        #expect(data.mediaInUse.isEmpty)
    }

    /// Going to the background ends the hold and Undo together (OE4).
    @Test func goingToTheBackgroundEndsTheHoldAndUndo() throws {
        var (data, id) = try synced()
        data.delete(id, by: parentA, now: t0 + 300)
        data.endUndoWindows()
        #expect(data.eventsToUpload(now: t0 + 301).map(\.event.id) == [id])
        let afterBackground = data.undoHeld(id, by: parentA, now: t0 + 302)
        #expect(!afterBackground)
    }

    /// A photo taken out in the editor: held, and Undo puts it back in its place.
    @Test func aPhotoTakenOutIsHeldAndUndoPutsItBack() throws {
        var (data, id) = try synced()
        let original = try #require(data.events[id]?.snapshot)
        let saved = data.editMilestone(id, from: original, title: "First smile", note: "In the bath", media: ["p2"],
                                       at: t0, by: parentA, now: t0 + 300)
        #expect(saved)
        #expect(data.events[id]?.heldUndo == HeldUndo(undeletes: false, media: ["p1", "p2"], addedRemovals: ["p1"]))
        #expect(data.eventsToUpload(now: t0 + 305).isEmpty)
        let undone = data.undoHeld(id, by: parentA, now: t0 + 305)
        #expect(undone)
        #expect(details(data, id) == MilestoneDetails(title: "First smile", media: ["p1", "p2"]))
    }

    /// An edit that takes nothing out isn't held.
    @Test func anEditThatTakesNothingOutGoesAtOnce() throws {
        var (data, id) = try synced()
        let original = try #require(data.events[id]?.snapshot)
        data.editMilestone(id, from: original, title: "First big smile", note: "In the bath", media: ["p2", "p1"],
                           at: t0, by: parentA, now: t0 + 300)
        #expect(data.events[id]?.heldUndo == nil)
        #expect(data.eventsToUpload(now: t0 + 300).map(\.event.id) == [id])
    }

    /// The other phone's copy arriving during the hold keeps the hold, and Undo still works.
    @Test func aCopyArrivingDuringTheHoldKeepsIt() throws {
        var (a, id) = try synced()
        var b = HouseholdData()
        b.receiveEvent(a.events[id]!.event, systemFields: Data([1]))
        b.saveEditor(id, title: "First smile!", note: "In the bath", media: ["p1", "p2"], at: t0, by: parentB, now: t0 + 290)
        let fromB = sent(&b, id, tag: 2)
        a.delete(id, by: parentA, now: t0 + 300)
        a.receiveEvent(fromB, systemFields: Data([2]))
        #expect(a.eventsToUpload(now: t0 + 305).isEmpty)
        let undone = a.undoHeld(id, by: parentA, now: t0 + 306)
        #expect(undone)
        #expect(a.events[id]?.event.deletedAt == nil)
        #expect(details(a, id) == MilestoneDetails(title: "First smile!", media: ["p1", "p2"]))
    }

    /// Step 1's "replace the photo": Undo gives the old photo back, and the new one is never sent.
    @Test func undoAfterAReplaceGivesTheOldPhotoBack() throws {
        var (data, id) = try synced()
        let original = try #require(data.events[id]?.snapshot)
        data.editMilestone(id, from: original, title: "First smile", note: "In the bath", media: ["p1", "new"],
                           at: t0, by: parentA, now: t0 + 300)
        let undone = data.undoHeld(id, by: parentA, now: t0 + 305)
        #expect(undone)
        #expect(details(data, id) == MilestoneDetails(title: "First smile", media: ["p1", "p2"], removedMedia: ["new"]))
    }

    /// Parent B removed a photo, and it is in iCloud. Parent A removed it too, from an older copy,
    /// and Undoes: B's removal stands.
    @Test func undoNeverBringsBackAPhotoTheOtherPhoneRemoved() throws {
        var (a, id) = try synced()
        var b = HouseholdData()
        b.receiveEvent(a.events[id]!.event, systemFields: Data([1]))
        b.saveEditor(id, title: "First smile", note: "In the bath", media: ["p1"], at: t0, by: parentB, now: t0 + 200)
        let fromB = sent(&b, id, tag: 2)
        let original = try #require(a.events[id]?.snapshot)
        a.editMilestone(id, from: original, title: "First smile", note: "In the bath", media: ["p1"], at: t0, by: parentA, now: t0 + 300)
        a.receiveEvent(fromB, systemFields: Data([2]))
        #expect(a.events[id]?.heldUndo?.addedRemovals == [])
        let undone = a.undoHeld(id, by: parentA, now: t0 + 305)
        #expect(undone)
        #expect(details(a, id) == MilestoneDetails(title: "First smile", media: ["p1"], removedMedia: ["p2"]))
    }

    /// Two saves inside one Undo window, with a photo from the other phone arriving between them:
    /// Undo brings that photo back too.
    @Test func undoKeepsAPhotoThatArrivedBetweenTwoHeldSaves() throws {
        var (a, id) = try synced()
        var b = HouseholdData()
        b.receiveEvent(a.events[id]!.event, systemFields: Data([1]))
        let first = try #require(a.events[id]?.snapshot)
        a.editMilestone(id, from: first, title: "First smile", note: "In the bath", media: ["p2"], at: t0, by: parentA, now: t0 + 300)
        b.saveEditor(id, title: "First smile", note: "In the bath", media: ["p1", "p2", "fromB"], at: t0, by: parentB, now: t0 + 301)
        a.receiveEvent(sent(&b, id, tag: 2), systemFields: Data([2]))
        #expect(details(a, id)?.media == ["p2", "fromB"])
        let second = try #require(a.events[id]?.snapshot)
        a.editMilestone(id, from: second, title: "First smile", note: "In the bath", media: ["p2"], at: t0, by: parentA, now: t0 + 303)
        let undone = a.undoHeld(id, by: parentA, now: t0 + 305)
        #expect(undone)
        #expect(details(a, id)?.media == ["p1", "p2", "fromB"])
        #expect(details(a, id)?.removedMedia == [])
    }

    /// Parent B adds a photo while Parent A deletes the first: the deleted first keeps no photo,
    /// and B's goes onto the removed list, so it is cleaned up.
    @Test func aPhotoAddedWhileTheFirstWasDeletedIsRemovedToo() throws {
        var (a, id) = try synced()
        var b = HouseholdData()
        b.receiveEvent(a.events[id]!.event, systemFields: Data([1]))
        a.delete(id, by: parentA, now: t0 + 300)
        a.endUndoWindows()
        let fromA = sent(&a, id, tag: 2)
        b.saveEditor(id, title: "First smile", note: "In the bath", media: ["p1", "p2", "fromB"], at: t0, by: parentB, now: t0 + 299)
        b.receiveEvent(fromA, systemFields: Data([2]))
        #expect(b.events[id]?.event.deletedAt != nil)
        #expect(details(b, id) == MilestoneDetails(title: "First smile", media: [], removedMedia: ["fromB", "p1", "p2"]))
    }

    /// Parent A deletes the first; during the hold, Parent B's new photo arrives. Undo brings the
    /// first back with B's photo too, not removed.
    @Test func undoOfADeleteKeepsAPhotoTheOtherPhoneAddedMeanwhile() throws {
        var (a, id) = try synced()
        var b = HouseholdData()
        b.receiveEvent(a.events[id]!.event, systemFields: Data([1]))
        a.delete(id, by: parentA, now: t0 + 300)
        b.saveEditor(id, title: "First smile", note: "In the bath", media: ["p1", "p2", "fromB"], at: t0, by: parentB, now: t0 + 302)
        a.receiveEvent(sent(&b, id, tag: 2), systemFields: Data([2]))
        #expect(details(a, id)?.media == [])
        let undone = a.undoHeld(id, by: parentA, now: t0 + 305)
        #expect(undone)
        #expect(a.events[id]?.event.deletedAt == nil)
        #expect(details(a, id) == MilestoneDetails(title: "First smile", media: ["p1", "p2", "fromB"]))
    }

    /// The hold is kept in the household file.
    @Test func theHoldIsSavedInTheFile() throws {
        var (data, id) = try synced()
        data.delete(id, by: parentA, now: t0 + 300)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let back = try decoder.decode(HouseholdData.self, from: try encoder.encode(data))
        #expect(back.events[id]?.heldUndo == data.events[id]?.heldUndo)
        #expect(back.events[id]?.heldUndo != nil)
    }
}

@Suite("Firsts: the baby's age")
struct BabyAgeTests {
    @Test(arguments: [
        ("2026-11-01", "2026-11-01", "Day of birth"),
        ("2026-11-01", "2026-11-02", "1 day"),
        ("2026-11-01", "2026-11-14", "13 days"),
        ("2026-11-01", "2026-11-15", "2 weeks"),
        ("2026-11-01", "2027-01-31", "13 weeks"),
        ("2026-11-01", "2027-02-01", "3 months"),
        ("2026-11-01", "2028-10-31", "23 months"),
        ("2026-11-01", "2028-11-01", "2 years"),
        ("2026-11-01", "2028-12-01", "2 years 1 month"),
        ("2026-11-01", "2029-02-15", "2 years 3 months"),
        // A birth day the month doesn't have completes on the 1st of the next month.
        ("2027-01-31", "2027-04-30", "12 weeks"),
        ("2027-01-31", "2027-05-01", "3 months"),
        ("2028-02-29", "2030-02-28", "23 months"),
        ("2028-02-29", "2030-03-01", "2 years"),
    ])
    func theAgeUsesTheRightUnit(_ birth: String, _ day: String, _ words: String) throws {
        let age = try #require(BabyAge(on: date(day), birthDate: date(birth)))
        #expect(age.words == words)
    }

    @Test func noAgeBeforeTheBirthDate() {
        #expect(BabyAge(on: date("2026-10-31"), birthDate: date("2026-11-01")) == nil)
    }

    /// The age follows the household's calendar, at the clock changes and at midnight.
    @Test func clockChangesAndMidnight() {
        let springForward = date("2027-03-27")
        #expect(BabyAge(at: at(2027, 3, 28, 0, 30), birthDate: springForward, in: london)?.words == "1 day")
        #expect(BabyAge(at: at(2027, 3, 28, 3, 0), birthDate: springForward, in: london)?.words == "1 day")
        let fallBack = date("2026-10-24")
        #expect(BabyAge(at: at(2026, 10, 24, 23, 30), birthDate: fallBack, in: london) == .dayOfBirth)
        #expect(BabyAge(at: at(2026, 10, 25, 0, 30), birthDate: fallBack, in: london)?.words == "1 day")
        #expect(BabyAge(at: at(2026, 10, 25, 23, 59), birthDate: fallBack, in: london)?.words == "1 day")
        let born = date("2026-11-18")
        #expect(BabyAge(at: at(2026, 11, 18, 23, 59, 59), birthDate: born, in: london) == .dayOfBirth)
        #expect(BabyAge(at: at(2026, 11, 19, 0, 0), birthDate: born, in: london)?.words == "1 day")
    }

    /// A 30-minute time zone: 19:00 in London is 00:30 the next day in Kolkata.
    @Test func aThirtyMinuteTimeZone() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let moment = at(2026, 11, 20, 19, 0, in: utc)
        #expect(BabyAge(at: moment, birthDate: date("2026-11-20"), in: kolkata)?.words == "1 day")
        #expect(BabyAge(at: moment, birthDate: date("2026-11-20"), in: utc) == .dayOfBirth)
    }

    /// A first logged while away uses the household's calendar, not the phone's.
    @Test func travelUsesTheHouseholdsCalendar() throws {
        var data = try withBirthDate("2026-11-20")
        let newYork = TimeZone(identifier: "America/New_York")!
        let moment = at(2026, 11, 20, 23, 30, in: newYork)
        let added13 = data.addMilestone(babyID: baby, title: "First trip out", at: moment, by: parentA,
                                        timeZoneID: "America/New_York", now: moment + 60)
        try #require(added13 != nil)
        let row = try #require(data.firstsList(babyID: baby).first)
        #expect(row.date == date("2026-11-21"))
        #expect(row.age == .days(1))
    }

    @Test func theGroupsUseTheAgeOrTheMonth() {
        #expect(JournalGroup(day: date("2027-01-10"), birthDate: date("2026-11-01")) == .age(.weeks(10)))
        #expect(JournalGroup(day: date("2027-01-10"), birthDate: nil) == .month(year: 2027, month: 1))
    }
}

@Suite("Firsts: the date from the photo")
struct MilestoneWhenTests {
    @Test func theEarliestPhotosTimeIsUsedWhenItIsMoreThanFiveMinutesAgo() {
        let now = at(2026, 11, 18, 10, 0)
        // Another day: the photo's time.
        #expect(MilestoneWhen.fromPhotos(takenAt: [at(2026, 10, 30, 7, 40), at(2026, 10, 31, 9, 0)], now: now) == at(2026, 10, 30, 7, 40))
        // Earlier today, two hours ago: the photo's time too (eng2 D2).
        #expect(MilestoneWhen.fromPhotos(takenAt: [now - 7200], now: now) == now - 7200)
        // Two minutes ago, or with no time in the photo: now.
        #expect(MilestoneWhen.fromPhotos(takenAt: [now - 120], now: now) == nil)
        #expect(MilestoneWhen.fromPhotos(takenAt: [], now: now) == nil)
    }

    /// Outside voice OV5: a photo's time arriving late never changes a When the parent set; a
    /// When set by photos goes back once those photos are taken out.
    @Test func thePhotosTimeFollowsOnlyWhileTheParentHasntSetWhen() {
        let now = at(2026, 11, 18, 10, 0)
        let photo = now - 7200
        let parents = at(2026, 11, 17, 18, 0)
        // Nobody set When: the photo's time, marked as from the photo.
        var result = MilestoneWhen.follow(when: now, fromPhoto: false, touched: false, takenAt: [photo], fallback: now, now: now)
        #expect(result.when == photo && result.fromPhoto)
        // The parent set When, then the photo's time arrived: the parent's time stays.
        result = MilestoneWhen.follow(when: parents, fromPhoto: false, touched: true, takenAt: [photo], fallback: now, now: now)
        #expect(result.when == parents && !result.fromPhoto)
        // The photo that set When was taken out: back to the first's own time.
        result = MilestoneWhen.follow(when: photo, fromPhoto: true, touched: false, takenAt: [], fallback: parents, now: now)
        #expect(result.when == parents && !result.fromPhoto)
        // A photo taken just now changes nothing.
        result = MilestoneWhen.follow(when: parents, fromPhoto: false, touched: false, takenAt: [now - 60], fallback: now, now: now)
        #expect(result.when == parents && !result.fromPhoto)
    }
}

@Suite("Firsts: dates refused")
struct MilestoneDateTests {
    @Test func aDateBeforeTheBirthOrInTheFutureIsRefused() throws {
        var data = try withBirthDate("2026-11-18")
        #expect(data.milestoneDateProblem(t0 + 60, babyID: baby, now: t0) == .inFuture)
        #expect(data.milestoneDateProblem(at(2026, 11, 17, 23, 59), babyID: baby, now: t0) == .beforeBirth(date("2026-11-18")))
        #expect(data.milestoneDateProblem(at(2026, 11, 18, 0, 0), babyID: baby, now: t0) == nil)
        let added14 = data.addMilestone(babyID: baby, title: "x", at: t0 + 60, by: parentA, timeZoneID: londonID, now: t0)
        #expect(added14 == nil)
        let added15 = data.addMilestone(babyID: baby, title: "x", at: t0 - 86_400, by: parentA, timeZoneID: londonID, now: t0)
        #expect(added15 == nil)
        #expect(data.events.isEmpty)
    }

    /// Born today: a first that day says "Day of birth".
    @Test func bornToday() throws {
        var data = try withBirthDate("2026-11-18")
        let added16 = data.addMilestone(babyID: baby, title: "First cuddle", at: t0, by: parentA, timeZoneID: londonID, now: t0)
        try #require(added16 != nil)
        #expect(data.firstsList(babyID: baby).first?.age == .dayOfBirth)
    }

    /// A clock set back makes a saved first look like the future. Its words can still be
    /// changed; only a new date is checked against the phone's clock.
    @Test func aClockSetBackStillLetsAFirstBeEdited() throws {
        var data = HouseholdData()
        let added17 = data.addMilestone(babyID: baby, title: "First smile", at: t0, by: parentA,
                                        timeZoneID: londonID, now: t0)
        let id = try #require(added17)
        let setBack = t0 - 86_400
        let saved18 = data.saveEditor(id, title: "First big smile", note: nil, media: [], at: t0, by: parentA, now: setBack)
        #expect(saved18)
        #expect(details(data, id)?.title == "First big smile")
        let saved19 = data.saveEditor(id, title: "First big smile", note: nil, media: [], at: t0 + 60, by: parentA, now: setBack)
        #expect(!saved19)
        #expect(data.events[id]?.event.startedAt == t0)
    }

    @Test func theBirthDateIsSetOnTheBabysRecordKeepingTheName() throws {
        var data = try withBirthDate("2026-11-10")
        data.addMilestone(id: "smile", babyID: baby, title: "First smile", at: at(2026, 11, 15, 9, 0), by: parentA,
                          timeZoneID: londonID, now: t0)
        let refused = data.setBirthDate(date("2026-11-16"), babyID: baby, now: t0)
        #expect(refused?.id == "smile")
        #expect(data.birthDate(babyID: baby) == date("2026-11-10"))
        #expect(data.setBirthDate(date("2026-11-08"), babyID: baby, now: t0) == nil)
        #expect(data.birthDate(babyID: baby) == date("2026-11-08"))
        let record = try #require(data.plainRecord(.baby, baby))
        #expect(PayloadCoder.decode(BabyPayload.self, from: record.payload)?.name == "Baby")
        #expect(data.plainRecordsToUpload().contains { $0.record.key == record.key })
    }

    /// A first deleted a moment ago can still come back with Undo, so it still blocks a later
    /// birth date.
    @Test func aFirstUndoCanBringBackStillBlocksTheBirthDate() throws {
        var data = try withBirthDate("2026-11-01")
        data.addMilestone(id: "smile", babyID: baby, title: "First smile", at: at(2026, 11, 5, 9, 0), by: parentA,
                          timeZoneID: londonID, now: t0)
        data.endUndoWindows()
        data.delete("smile", by: parentA, now: t0)
        #expect(data.firstBefore(birthDate: date("2026-11-10"), babyID: baby)?.id == "smile")
        data.endUndoWindows()
        #expect(data.firstBefore(birthDate: date("2026-11-10"), babyID: baby) == nil)
    }

    /// A first deleted on the other phone while this editor was open isn't changed.
    @Test func anEditorCantChangeAFirstDeletedMeanwhile() throws {
        var data = HouseholdData()
        let added = data.addMilestone(id: "smile", babyID: baby, title: "First smile", at: t0, by: parentA,
                                      timeZoneID: londonID, now: t0)
        try #require(added != nil)
        let opened = try #require(data.events["smile"]?.snapshot)
        data.delete("smile", by: parentB, now: t0 + 60)
        let saved = data.editMilestone("smile", from: opened, title: "First big smile", note: nil, media: [], at: t0,
                                       by: parentA, now: t0 + 120)
        #expect(!saved)
        #expect(details(data, "smile")?.title == "First smile")
    }

    /// The birth date can't be set after a first; the refusal names the earliest one in the way.
    @Test func aBirthDateAfterAFirstNamesIt() throws {
        var data = HouseholdData()
        let later = at(2027, 1, 1, 9, 0)
        data.addMilestone(id: "smile", babyID: baby, title: "First smile", at: at(2026, 10, 30, 7, 40), by: parentA,
                          timeZoneID: londonID, now: later)
        data.addMilestone(id: "laugh", babyID: baby, title: "First laugh", at: at(2026, 11, 5, 8, 0), by: parentA,
                          timeZoneID: londonID, now: later)
        #expect(data.firstBefore(birthDate: date("2026-11-10"), babyID: baby)?.id == "smile")
        #expect(data.firstBefore(birthDate: date("2026-10-30"), babyID: baby) == nil)
    }
}

@Suite("Firsts: the Firsts list")
struct FirstsListTests {
    func household(birth: String?) throws -> HouseholdData {
        var data = try birth.map { try withBirthDate($0) } ?? HouseholdData()
        let later = at(2027, 6, 1, 9, 0)
        data.addMilestone(id: "rolled", babyID: baby, title: "Rolled over", at: at(2027, 3, 3, 9, 0), by: parentB,
                          timeZoneID: londonID, now: later)
        data.addMilestone(id: "smile", babyID: baby, title: "First smile", at: at(2026, 11, 25, 7, 40), by: parentA,
                          timeZoneID: londonID, now: later)
        data.addMilestone(id: "laugh", babyID: baby, title: "First laugh", at: at(2026, 12, 10, 8, 0), by: parentA,
                          timeZoneID: londonID, now: later)
        data.delete("laugh", by: parentA, now: later)
        data.addMilestone(id: "other", babyID: "baby-2", title: "Someone else's", at: at(2026, 12, 1, 8, 0), by: parentA,
                          timeZoneID: londonID, now: later)
        data.addNappy(babyID: baby, wee: true, poo: false, at: at(2026, 12, 2, 8, 0), by: parentA, timeZoneID: londonID, now: later)
        return data
    }

    @Test func oldestFirstWithTheAgeAndTheYearWhenItIsNotThisYear() throws {
        let rows = try household(birth: "2026-11-01").firstsList(babyID: baby)
        #expect(rows.map(\.id) == ["smile", "rolled"])
        #expect(rows.map { $0.line(today: date("2026-12-31")) } == ["First smile · 3 weeks · 25 Nov",
                                                                     "Rolled over · 4 months · 3 Mar 2027"])
        #expect(rows.copiedText == "First smile · 3 weeks · 25 Nov 2026\nRolled over · 4 months · 3 Mar 2027")
    }

    @Test func withNoBirthDateItShowsDatesOnly() throws {
        let rows = try household(birth: nil).firstsList(babyID: baby)
        #expect(rows.allSatisfy { $0.age == nil })
        #expect(rows.map { $0.line(today: date("2027-04-01")) } == ["First smile · 25 Nov 2026", "Rolled over · 3 Mar"])
    }
}

/// The alarms count feeds only: firsts added, edited or deleted never set, move or silence one.
@Suite("Firsts: the alerts count feeds only")
struct MilestoneAlertTests {
    @Test(arguments: [at(2026, 11, 14, 10, 0), at(2026, 11, 15, 22, 0), at(2026, 11, 16, 1, 30)])
    func theSameAlertsWithOrWithoutFirsts(_ lastFeed: Date) throws {
        let feeds = [feed(lastFeed.addingTimeInterval(.hours(-3))), feed(lastFeed)]
        var first = feed(lastFeed.addingTimeInterval(.minutes(20)), kind: .milestone)
        first.payload = try PayloadCoder.encode(EventPayload(milestone: MilestoneDetails(title: "First smile", media: ["m1"])))
        let deleted = feed(lastFeed.addingTimeInterval(.minutes(236)), kind: .milestone,
                           deletedAt: lastFeed.addingTimeInterval(.minutes(237)))
        for now in [lastFeed.addingTimeInterval(.minutes(5)), lastFeed.addingTimeInterval(.minutes(238))] {
            let plain = run(feeds, now: now)
            #expect(!plain.isEmpty)
            #expect(run(feeds + [first, deleted], now: now) == plain)
        }
    }

    @Test func aBabyWithOnlyFirstsHasNoAlerts() throws {
        var data = HouseholdData()
        let added20 = data.addMilestone(babyID: baby, title: "First smile", at: t0, by: parentA, timeZoneID: londonID, now: t0)
        try #require(added20 != nil)
        #expect(run(data.allEvents, now: t0 + 600).isEmpty)
    }
}

/// Design review D39 and the parents' choice of 19 Nov 2026: the square on the Journal's line
/// shows the part of the photo a parent dragged it to; the first's page shows the whole photo.
@Suite("Firsts: each photo's square")
struct MediaCropTests {
    /// Parent A's phone and Parent B's, each holding the first with two photos.
    func twoPhones() throws -> (a: HouseholdData, b: HouseholdData, id: String) {
        var a = HouseholdData()
        let added = a.addMilestone(babyID: baby, title: "First smile", media: ["m1", "m2"], at: t0,
                                   by: parentA, timeZoneID: londonID, now: t0)
        let id = try #require(added)
        var b = HouseholdData()
        b.receiveEvent(sent(&a, id), systemFields: Data([1]))
        return (a, b, id)
    }

    /// A first with a photo moved is version 4, which an older build leaves unread, so it can't
    /// save the first back without its crops. A first nobody cropped is written as version 3 was.
    @Test func aCropMakesVersion4AndAnUncroppedFirstStaysVersion3() throws {
        struct Version3Build: VersionedPayload {
            static var currentVersion: Int { 3 }
            var v: Int
        }
        let plain = EventPayload(milestone: MilestoneDetails(title: "First smile", media: ["m1"]))
        #expect(plain.v == 3)
        let plainBytes = try PayloadCoder.encode(plain)
        #expect(!String(decoding: plainBytes, as: UTF8.self).contains("crops"))
        #expect(PayloadCoder.decode(Version3Build.self, from: plainBytes) != nil)
        let cropped = EventPayload(milestone: MilestoneDetails(title: "First smile", media: ["m1"],
                                                               crops: ["m1": MediaCrop(x: 0.5, y: 0.3)]))
        #expect(cropped.v == 4)
        let croppedBytes = try PayloadCoder.encode(cropped)
        #expect(PayloadCoder.decode(Version3Build.self, from: croppedBytes) == nil)
        #expect(PayloadCoder.decode(EventPayload.self, from: croppedBytes)?.milestone?.crops == ["m1": MediaCrop(x: 0.5, y: 0.3)])
    }

    @Test func theMiddleARemovedPhotosCropAndOddNumbersAreNotKept() {
        let details = MilestoneDetails(title: "First smile", media: ["m1", "m2"], removedMedia: ["m3"],
                                       crops: ["m1": .middle, "m2": MediaCrop(x: 2, y: -1), "m3": MediaCrop(x: 0.1, y: 0.1)])
        #expect(details.crops == ["m2": MediaCrop(x: 1, y: 0)])
        #expect(MediaCrop(x: .nan, y: .infinity) == .middle)
    }

    /// A wide photo moves only sideways, a tall one only up and down, and the square never leaves
    /// the photo.
    @Test func theSquareStaysInsideThePhoto() {
        #expect(MediaCrop(x: 0, y: 0.1).clamped(width: 1200, height: 900) == MediaCrop(x: 0.375, y: 0.5))
        #expect(MediaCrop(x: 0.9, y: 0.9).clamped(width: 900, height: 1200) == MediaCrop(x: 0.5, y: 0.625))
        #expect(MediaCrop(x: 0.2, y: 0.8).clamped(width: 1000, height: 1000) == .middle)
    }

    @Test func thePhotoFillsTheSquareWithTheCropInTheMiddle() {
        // 1200 x 900 in a 90-point square: drawn 120 x 90.
        let middle = MediaCrop.middle.placement(width: 1200, height: 900, box: 90)
        #expect(middle.width == 120 && middle.height == 90)
        #expect(middle.x == -15 && middle.y == 0)
        // The left edge: the photo's left side at the square's left side, never a gap.
        let left = MediaCrop(x: 0, y: 0.5).placement(width: 1200, height: 900, box: 90)
        #expect(left.x == 0)
    }

    /// The photo follows the finger: dragging a tall photo down shows more of its top.
    @Test func aDragMovesThePhotoWithTheFinger() {
        // 900 x 1200 in a 90-point square: drawn 90 x 120.
        let down = MediaCrop.middle.dragged(dx: 0, dy: 6, width: 900, height: 1200, box: 90)
        #expect(down == MediaCrop(x: 0.5, y: 0.45))
        let farDown = MediaCrop.middle.dragged(dx: 0, dy: 500, width: 900, height: 1200, box: 90)
        #expect(farDown == MediaCrop(x: 0.5, y: 0.375))
        // Sideways does nothing on a tall photo.
        #expect(MediaCrop.middle.dragged(dx: 40, dy: 0, width: 900, height: 1200, box: 90) == .middle)
    }

    @Test func aNewFirstKeepsOnlyItsOwnPhotosCrops() throws {
        var data = HouseholdData()
        let added = data.addMilestone(babyID: baby, title: "First smile", media: ["m1"],
                                      crops: ["m1": MediaCrop(x: 0.5, y: 0.4), "draft": MediaCrop(x: 0.5, y: 0.1)],
                                      at: t0, by: parentA, timeZoneID: londonID, now: t0)
        let id = try #require(added)
        #expect(details(data, id)?.crops == ["m1": MediaCrop(x: 0.5, y: 0.4)])
        #expect(data.events[id]?.snapshot.payload?.v == 4)
    }

    /// An editor open while the other phone moved one photo saves only the photo moved here.
    @Test func anEditorChangesOnlyTheCropsItMoved() throws {
        var (a, b, id) = try twoPhones()
        let editorOpenedOn = try #require(b.events[id]?.snapshot)
        let movedOnA = a.saveEditor(id, title: "First smile", media: ["m1", "m2"], crops: ["m1": MediaCrop(x: 0.5, y: 0.4)],
                                    at: t0, by: parentA, now: t0 + 30)
        #expect(movedOnA)
        b.receiveEvent(sent(&a, id, tag: 2), systemFields: Data([2]))
        let movedOnB = b.editMilestone(id, from: editorOpenedOn, title: "First smile", note: nil, media: ["m1", "m2"],
                                       crops: ["m2": MediaCrop(x: 0.3, y: 0.5)], at: t0, by: parentB, now: t0 + 60)
        #expect(movedOnB)
        #expect(details(b, id)?.crops == ["m1": MediaCrop(x: 0.5, y: 0.4), "m2": MediaCrop(x: 0.3, y: 0.5)])
        #expect(b.events[id]?.changedFields == [.crops])
    }

    /// A crop for a photo the first never held (one picked, moved and replaced in the editor) is
    /// never saved, so it can't make the first version 4 for nothing.
    @Test func aCropForAPhotoTheFirstDoesntHoldIsNotSaved() throws {
        var (a, _, id) = try twoPhones()
        a.saveEditor(id, title: "First smile", media: ["m1", "m2"], crops: ["draft": MediaCrop(x: 0.5, y: 0.2)],
                     at: t0, by: parentA, now: t0 + 30)
        #expect(details(a, id)?.crops == [:])
        #expect(a.events[id]?.snapshot.payload?.v == 3)
    }

    /// Undo of a photo taken out puts it back in its place in the square.
    @Test func undoPutsAPhotoBackWithItsCrop() throws {
        var (a, _, id) = try twoPhones()
        let crop = MediaCrop(x: 0.5, y: 0.3)
        a.saveEditor(id, title: "First smile", media: ["m1", "m2"], crops: ["m2": crop], at: t0, by: parentA, now: t0 + 30)
        _ = sent(&a, id, tag: 2)
        a.saveEditor(id, title: "First smile", media: ["m1"], crops: [:], at: t0, by: parentA, now: t0 + 60)
        #expect(details(a, id)?.crops == [:])
        let undone = a.undoHeld(id, by: parentA, now: t0 + 61)
        #expect(undone)
        #expect(details(a, id)?.media == ["m1", "m2"])
        #expect(details(a, id)?.crops == ["m2": crop])
    }

    /// A cover the parent chose stays the cover, even with a photo the other phone added meanwhile.
    @Test func aChosenCoverStaysFirstWhenTheOtherPhoneAdded() throws {
        var (a, b, id) = try twoPhones()
        let editorOpenedOn = try #require(b.events[id]?.snapshot)
        a.saveEditor(id, title: "First smile", media: ["m1", "m2", "x"], at: t0, by: parentA, now: t0 + 30)
        b.receiveEvent(sent(&a, id, tag: 2), systemFields: Data([2]))
        // B took m1 out and added m3 and m4, making m4 the cover.
        let saved = b.editMilestone(id, from: editorOpenedOn, title: "First smile", note: nil, media: ["m4", "m2", "m3"],
                                    at: t0, by: parentB, now: t0 + 60)
        #expect(saved)
        #expect(details(b, id)?.media.first == "m4")
        #expect(Set(details(b, id)?.media ?? []) == ["m4", "m2", "m3", "x"])
    }

    /// Undo never drops a photo to make room (Codex review of step 2): A takes out m4, which B never
    /// saw, and B adds e; bringing m4 back would make 5, so Undo changes nothing.
    @Test func undoThatWouldPassFourChangesNothing() throws {
        var (a, b, id) = try twoPhones()
        a.saveEditor(id, title: "First smile", media: ["m1", "m2", "m3"], at: t0, by: parentA, now: t0 + 10)
        b.receiveEvent(sent(&a, id, tag: 2), systemFields: Data([2]))
        a.saveEditor(id, title: "First smile", media: ["m1", "m2", "m3", "m4"], at: t0, by: parentA, now: t0 + 20)
        a.saveEditor(id, title: "First smile", media: ["m1", "m2", "m3"], at: t0, by: parentA, now: t0 + 30)
        b.saveEditor(id, title: "First smile", media: ["m1", "m2", "m3", "e"], at: t0, by: parentB, now: t0 + 31)
        a.receiveEvent(sent(&b, id, tag: 3), systemFields: Data([3]))
        #expect(details(a, id)?.media == ["m1", "m2", "m3", "e"])
        #expect(a.undoWouldPassTheLimit(id))
        let before = details(a, id)
        let undone = a.undoHeld(id, by: parentA, now: t0 + 35)
        #expect(!undone)
        #expect(details(a, id) == before)
    }

    /// Eng2 D4: a video that couldn't be made smaller leaves both phones' lists, so the other
    /// phone stops waiting for it.
    @Test func aFailedVideoLeavesBothPhonesLists() throws {
        var (a, b, id) = try twoPhones()
        let dropped = a.dropFailedMedia("m2", from: id, by: parentA, now: t0 + 30)
        #expect(dropped)
        #expect(details(a, id)?.media == ["m1"])
        #expect(details(a, id)?.removedMedia == ["m2"])
        b.receiveEvent(sent(&a, id, tag: 2), systemFields: Data([2]))
        #expect(details(b, id)?.media == ["m1"])
        let notHeld = a.dropFailedMedia("other", from: id, by: parentA, now: t0 + 40)
        #expect(!notHeld)
    }

    @Test func takingAPhotoOutDropsItsCrop() throws {
        var (a, _, id) = try twoPhones()
        a.saveEditor(id, title: "First smile", media: ["m1", "m2"],
                     crops: ["m1": MediaCrop(x: 0.5, y: 0.4), "m2": MediaCrop(x: 0.4, y: 0.5)], at: t0, by: parentA, now: t0 + 30)
        a.saveEditor(id, title: "First smile", media: ["m2"], crops: ["m2": MediaCrop(x: 0.4, y: 0.5)], at: t0, by: parentA,
                     now: t0 + 60)
        #expect(details(a, id)?.crops == ["m2": MediaCrop(x: 0.4, y: 0.5)])
    }

    /// Eng2 D5 A: the crops merge as one field. Both phones, offline, move a different photo:
    /// the later change wins whole, and the other photo goes back to its last synced place. Both
    /// ways round, so the phone whose own change is later keeps it too.
    @Test(arguments: [true, false])
    func cropsOnBothPhonesAtOnceTheLaterWinsWhole(_ aIsLater: Bool) throws {
        var (a, b, id) = try twoPhones()
        let cropA = MediaCrop(x: 0.5, y: 0.4), cropB = MediaCrop(x: 0.3, y: 0.5)
        a.saveEditor(id, title: "First smile", media: ["m1", "m2"], crops: ["m1": cropA],
                     at: t0, by: parentA, now: t0 + (aIsLater ? 90 : 60))
        b.saveEditor(id, title: "First smile", media: ["m1", "m2"], crops: ["m2": cropB],
                     at: t0, by: parentB, now: t0 + (aIsLater ? 60 : 90))
        let fromB = sent(&b, id, tag: 2)
        a.receiveEvent(fromB, systemFields: Data([2]))
        let winner = aIsLater ? ["m1": cropA] : ["m2": cropB]
        #expect(details(a, id)?.crops == winner)
        #expect(details(a, id)?.media == ["m1", "m2"])
        // Once A sends, B ends with the same.
        if aIsLater {
            b.receiveEvent(sent(&a, id, tag: 3), systemFields: Data([3]))
            #expect(details(b, id)?.crops == winner)
        }
    }
}
