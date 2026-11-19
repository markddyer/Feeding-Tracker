import Foundation
import Testing
@testable import FeedingCore

// The move from Feeding Dev to Feeding (docs/planning/08-going-live.md): what goes in the file,
// how each parent's ID is matched, what comes in and what doesn't, and the file itself.

private let londonID = "Europe/London"
private let t0 = at(2026, 11, 18, 10, 0)
private let moveTime = at(2026, 11, 19, 15, 0)
/// The two parents in the real app: Parent A brings the move in.
private let realA: MemberID = "real-a"
private let realB: MemberID = "real-b"
private let realBaby = "real-baby"

private func member(_ id: MemberID, _ name: String, _ colour: String) throws -> PlainRecord {
    PlainRecord(type: .member, name: id.rawValue, modifiedAt: t0,
                payload: try PayloadCoder.encode(MemberPayload(displayName: name, colour: colour)))
}

/// Feeding Dev's household: feeds and a sleep by both parents, a first with three photos (one
/// removed), a deleted feed, another baby's feed, and settings.
private func devHousehold() throws -> (data: HouseholdData, first: String) {
    var data = HouseholdData()
    data.put(PlainRecord(type: .baby, name: baby, modifiedAt: t0,
                         payload: try PayloadCoder.encode(BabyPayload(name: "Baby", birthDate: date("2026-11-10")))))
    data.put(try member(parentA, "A", "coral"))
    data.put(try member(parentB, "B", "lilac"))
    let feed = data.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: londonID, now: t0)
    data.finishFeed(feed, by: parentB, now: t0.addingTimeInterval(.minutes(20)))
    data.add(kind: .sleep, babyID: baby, startedAt: t0.addingTimeInterval(.hours(1)), endedAt: t0.addingTimeInterval(.hours(2)),
             payload: EventPayload(), by: parentB, timeZoneID: londonID, now: t0.addingTimeInterval(.hours(2)))
    data.startFeed(babyID: baby, side: .right, by: parentB, timeZoneID: londonID, now: t0.addingTimeInterval(.hours(3)))
    let gone = data.startFeed(babyID: baby, side: nil, by: parentA, timeZoneID: londonID, now: t0.addingTimeInterval(.hours(4)))
    data.delete(gone, by: parentA, now: t0.addingTimeInterval(.hours(4)))
    data.startFeed(babyID: "other-baby", side: nil, by: parentA, timeZoneID: londonID, now: t0)
    let added = data.addMilestone(babyID: baby, title: "First smile", media: ["p1", "p2", "p3"],
                                  crops: ["p1": MediaCrop(x: 0.2, y: 0.4), "p3": MediaCrop(x: 0.7, y: 0.5)],
                                  at: t0, by: parentA, timeZoneID: londonID, now: t0)
    let first = try #require(added)
    data.updateHouseholdSettings(by: parentA, now: t0) { $0.window.closesAfter = .hours(3) }
    data.setRota(Rota(startDate: date("2026-11-13"), firstOnDuty: parentB, secondOnDuty: parentA), by: parentA, now: t0)
    data.setMedicines(["Vitamin D", "Iron"], now: t0)
    data.claimNight(date("2026-11-19"), by: parentB, now: t0)
    data.markDistinct("x", "y", by: parentB, now: t0)
    data.putSetting("https://example.invalid/share", key: SettingKey.photosShare, now: t0)
    data.acknowledgeChanges(by: parentB, now: t0)
    return (data, first)
}

/// The real app, set up: the baby, and both parents joined.
private func realHousehold(otherJoined: Bool = true) throws -> HouseholdData {
    var data = HouseholdData()
    data.put(PlainRecord(type: .baby, name: realBaby, modifiedAt: moveTime,
                         payload: try PayloadCoder.encode(BabyPayload(name: "Baby"))))
    data.put(try member(realA, "A", "sunflower"))
    if otherJoined { data.put(try member(realB, "B", "teal")) }
    return data
}

private func milestone(_ data: HouseholdData, _ id: String) -> MilestoneDetails? {
    data.events[id]?.snapshot.payload?.milestone
}

@Suite("The move from Feeding Dev")
struct HouseholdMoveTests {
    @Test("The move holds the baby's entries not deleted, and only the settings that move")
    func whatMoves() throws {
        let (dev, _) = try devHousehold()
        let move = dev.move(babyID: baby, by: parentA, now: moveTime)
        #expect(move.events.count == 4)
        #expect(move.counts == [.feed: 2, .sleep: 1, .milestone: 1])
        #expect(move.events.allSatisfy { $0.babyID == baby && $0.deletedAt == nil })
        #expect(move.mediaIDs == ["p1", "p2", "p3"])
        #expect(move.names == [parentA: "A", parentB: "B"])
        #expect(move.otherParents == [parentB])
        let keys = Set(move.plainRecords.map(\.key))
        #expect(keys.contains("Setting/\(SettingKey.rota)"))
        #expect(keys.contains("Setting/\(SettingKey.medicines)"))
        // A night taken stays behind: it could take a phone off duty before the other has it.
        #expect(!keys.contains("Setting/night-2026-11-19"))
        #expect(!keys.contains("Setting/\(SettingKey.photosShare)"))
        #expect(!keys.contains { $0.hasPrefix("Setting/change-") || $0.hasPrefix("Setting/ack-") })
    }

    @Test("Each parent's ID is matched: the maker becomes this parent, the other the other member")
    func idsMatched() throws {
        let (dev, _) = try devHousehold()
        let move = dev.move(babyID: baby, by: parentA, now: moveTime)
        var real = try realHousehold()
        let outcome = try real.bringIn(move, me: realA, carried: ["p1", "p2", "p3"], now: moveTime)
        #expect(outcome.added == [.feed: 2, .sleep: 1, .milestone: 1])
        #expect(outcome.alreadyHere == 0)
        let moved = real.allEvents
        #expect(moved.count == 4)
        #expect(Set(moved.map(\.babyID)) == [realBaby])
        #expect(Set(moved.map(\.loggedBy)) == [realA, realB])
        for event in moved {
            let original = try #require(move.events.first { $0.id == event.id })
            #expect(event.loggedBy == (original.loggedBy == parentA ? realA : realB))
            #expect(event.startedAt == original.startedAt)
            #expect(event.endedAt == original.endedAt)
            #expect(event.serverCreatedAt == nil)
            let stamps = try #require(real.events[event.id]?.snapshot.payload?.stamps)
            #expect(Set(stamps.values.map(\.by)).isSubset(of: [realA, realB]))
            let stored = try #require(real.events[event.id])
            #expect(stored.needsUpload)
            #expect(stored.systemFields == nil)
            #expect(stored.changedFields == EventField.fields(for: event.kind))
        }
        // The feed Parent A started and Parent B finished keeps who did what.
        let feed = try #require(moved.first { $0.kind == .feed && $0.loggedBy == realA })
        let stamps = try #require(real.events[feed.id]?.snapshot.payload?.stamps)
        #expect(stamps[EventField.endedAt.rawValue]?.by == realB)
        #expect(stamps[EventField.startedAt.rawValue]?.by == realA)
        // All of it goes to iCloud.
        #expect(real.eventsToUpload(now: moveTime).count == 4)
    }

    @Test("The baby's details, the colours, the medicines and the rota come too")
    func settingsCome() throws {
        let (dev, _) = try devHousehold()
        var real = try realHousehold()
        try real.bringIn(dev.move(babyID: baby, by: parentA, now: moveTime), me: realA, carried: [], now: moveTime)
        #expect(real.birthDate(babyID: realBaby) == date("2026-11-10"))
        #expect(real.currentBaby?.name == realBaby)
        let colours = Dictionary(uniqueKeysWithValues: real.plainRecords(of: .member).map {
            ($0.name, PayloadCoder.decode(MemberPayload.self, from: $0.payload)?.colour)
        })
        #expect(colours == [realA.rawValue: "coral", realB.rawValue: "lilac"])
        #expect(real.medicines == ["Vitamin D", "Iron"])
        #expect(real.householdSettings.window.closesAfter == .hours(3))
        #expect(real.rota == Rota(startDate: date("2026-11-13"), firstOnDuty: realB, secondOnDuty: realA))
        #expect(real.nightClaims.isEmpty)
        #expect(real.distinctFeeds.map(\.by) == [realB])
        #expect(real.plainRecord(.setting, SettingKey.photosShare) == nil)
        // The alert comes an hour sooner: a phone still on the old window would alert later, so
        // the change waits for the other phone to confirm it (the acknowledgement rule). So does
        // the rota, always: until then this phone alerts as if on duty.
        #expect(real.unacknowledgedChanges(by: realA).count == 2)
        #expect(real.setting(MoveReceipt.self, SettingKey.moveReceipt)?.by == realA)
    }

    @Test("A later window is no change to confirm: only the rota waits for the other phone")
    func laterWindowNeedsNoConfirming() throws {
        var (dev, _) = try devHousehold()
        dev.updateHouseholdSettings(by: parentA, now: t0) { $0.window.closesAfter = .hours(5) }
        var real = try realHousehold()
        try real.bringIn(dev.move(babyID: baby, by: parentA, now: moveTime), me: realA, carried: [], now: moveTime)
        #expect(real.householdSettings.window.closesAfter == .hours(5))
        #expect(real.unacknowledgedChanges(by: realA).count == 1)
    }

    @Test("The move never turns the alerts off, and leaves out a window Settings can't offer")
    func alertsStayOn() throws {
        var (dev, _) = try devHousehold()
        dev.updateHouseholdSettings(by: parentA, now: t0) { $0.window.alertsEnabled = false }
        var real = try realHousehold()
        try real.bringIn(dev.move(babyID: baby, by: parentA, now: moveTime), me: realA, carried: [], now: moveTime)
        #expect(real.householdSettings.window.alertsEnabled)
        #expect(real.householdSettings.window.closesAfter == .hours(3))

        var (odd, _) = try devHousehold()
        odd.updateHouseholdSettings(by: parentA, now: t0) { $0.window.closesAfter = .hours(400) }
        var other = try realHousehold()
        try other.bringIn(odd.move(babyID: baby, by: parentA, now: moveTime), me: realA, carried: [], now: moveTime)
        #expect(other.householdSettings.window == FeedWindowSettings())
    }

    @Test("A feed's start keeps Feeding Dev's cap from iCloud's time, so the alerts don't move later")
    func serverCapKept() throws {
        var dev = try devHousehold().data
        // The phone's clock ran an hour fast: iCloud got the feed an hour before its start.
        let fast = dev.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: londonID,
                                 now: t0.addingTimeInterval(.hours(6)))
        let stored = try #require(dev.eventsToUpload(now: .distantFuture).first { $0.event.id == fast })
        dev.didUploadEvent(fast, sentRevision: stored.localRevision, systemFields: Data([1]),
                           serverCreatedAt: t0.addingTimeInterval(.hours(5)))
        let devLatest = try #require(dev.allEvents.latestFeedStart(babyID: baby, now: .distantFuture))
        var real = try realHousehold()
        try real.bringIn(dev.move(babyID: baby, by: parentA, now: moveTime), me: realA, carried: [], now: moveTime)
        #expect(real.events[fast]?.event.startedAt == devLatest)
        #expect(real.allEvents.latestFeedStart(babyID: realBaby, now: .distantFuture) == devLatest)
    }

    @Test("A first keeps only the photos that came with it, and nothing removed")
    func firstsKeepCarriedPhotos() throws {
        var (dev, first) = try devHousehold()
        let original = try #require(dev.events[first]?.snapshot)
        let edited = dev.editMilestone(first, from: original, title: "First smile", note: nil, media: ["p1", "p3"], crops: nil,
                                       at: t0, by: parentA, now: t0.addingTimeInterval(60))
        #expect(edited)
        #expect(milestone(dev, first)?.removedMedia == ["p2"])
        var real = try realHousehold()
        try real.bringIn(dev.move(babyID: baby, by: parentA, now: moveTime), me: realA, carried: ["p1"], now: moveTime)
        let moved = try #require(milestone(real, first))
        #expect(moved.title == "First smile")
        #expect(moved.media == ["p1"])
        #expect(moved.crops == ["p1": MediaCrop(x: 0.2, y: 0.4)])
        #expect(moved.removedMedia.isEmpty)
    }

    @Test("Bringing the same move in twice changes nothing the second time")
    func twiceIsOnce() throws {
        let (dev, _) = try devHousehold()
        let move = dev.move(babyID: baby, by: parentA, now: moveTime)
        var real = try realHousehold()
        try real.bringIn(move, me: realA, carried: ["p1", "p2", "p3"], now: moveTime)
        let once = real
        let again = try real.bringIn(move, me: realA, carried: ["p1", "p2", "p3"], now: moveTime.addingTimeInterval(60))
        #expect(again.addedCount == 0)
        #expect(again.alreadyHere == 4)
        #expect(!again.settingsBrought)
        #expect(real == once)
    }

    @Test("A later move brings what the first one couldn't, and never undoes a change made since")
    func laterMoveCompletes() throws {
        let (dev, first) = try devHousehold()
        let move = dev.move(babyID: baby, by: parentA, now: moveTime)
        var real = try realHousehold()
        try real.bringIn(move, me: realA, carried: ["p1"], now: moveTime)
        #expect(milestone(real, first)?.media == ["p1"])
        // Changed in Feeding since: the window, and the medicines.
        real.updateHouseholdSettings(by: realA, now: moveTime.addingTimeInterval(60)) { $0.window.closesAfter = .hours(2.5) }
        real.setMedicines(["Vitamin D"], now: moveTime.addingTimeInterval(60))
        let later = try real.bringIn(move, me: realA, carried: ["p1", "p2", "p3"], now: moveTime.addingTimeInterval(120))
        #expect(later.firstsCompleted == 1)
        #expect(!later.settingsBrought)
        let completed = try #require(milestone(real, first))
        #expect(completed.media == ["p1", "p2", "p3"])
        #expect(completed.crops["p3"] == MediaCrop(x: 0.7, y: 0.5))
        #expect(real.events[first]?.needsUpload == true)
        #expect(real.householdSettings.window.closesAfter == .hours(2.5))
        #expect(real.medicines == ["Vitamin D"])
    }

    @Test("A photo two firsts name goes with the oldest only; another baby's entries never come")
    func ownersAndBabies() throws {
        var (dev, first) = try devHousehold()
        let added = dev.addMilestone(babyID: baby, title: "First laugh", media: ["p1", "p9"],
                                     at: t0.addingTimeInterval(60), by: parentA, timeZoneID: londonID,
                                     now: t0.addingTimeInterval(60))
        let second = try #require(added)
        var move = dev.move(babyID: baby, by: parentA, now: moveTime)
        #expect(move.mediaOwners == ["p1": first, "p2": first, "p3": first, "p9": second])
        move.events.append(feed(t0, babyID: "other-baby"))
        #expect(move.counts[.feed] == 2)
        var real = try realHousehold()
        try real.bringIn(move, me: realA, carried: ["p1", "p2", "p3", "p9"], now: moveTime)
        #expect(milestone(real, second)?.media == ["p9"])
        #expect(real.allEvents.count == 5)
    }

    @Test("A file made on the other parent's phone, or naming three parents, is refused")
    func whoseFile() throws {
        let (dev, _) = try devHousehold()
        // Made by Parent B in Feeding Dev, brought in by Parent A: each would become the other.
        let theirs = dev.move(babyID: baby, by: parentB, now: moveTime)
        var real = try realHousehold()
        let before = real
        #expect(real.moveProblem(theirs, me: realA) == .madeOnOtherPhone)
        #expect(throws: MoveProblem.madeOnOtherPhone) { try real.bringIn(theirs, me: realA, carried: [], now: moveTime) }
        #expect(real == before)
        // On Parent B's own phone it is fine.
        #expect(real.moveProblem(theirs, me: realB) == nil)

        var three = dev
        three.startFeed(babyID: baby, side: nil, by: "someone-else", timeZoneID: londonID, now: t0.addingTimeInterval(.hours(7)))
        #expect(real.moveProblem(three.move(babyID: baby, by: parentA, now: moveTime), me: realA) == .unclearParents)
    }

    @Test("An entry this build can't read stops the whole move")
    func unreadable() throws {
        let (dev, _) = try devHousehold()
        var move = dev.move(babyID: baby, by: parentA, now: moveTime)
        move.events[0].payload = Data(#"{"v":99}"#.utf8)
        let real = try realHousehold()
        #expect(real.moveProblem(move, me: realA) == .unreadableEntries)
    }

    @Test("Entries by the other parent wait until they have joined; nothing changes meanwhile")
    func otherParentFirst() throws {
        let (dev, _) = try devHousehold()
        let move = dev.move(babyID: baby, by: parentA, now: moveTime)
        var real = try realHousehold(otherJoined: false)
        let before = real
        #expect(real.moveProblem(move, me: realA) == .otherParentMissing)
        #expect(throws: MoveProblem.otherParentMissing) {
            try real.bringIn(move, me: realA, carried: [], now: moveTime)
        }
        #expect(real == before)
    }

    @Test("A move with only the maker's entries needs no other parent")
    func onlyMine() throws {
        var dev = HouseholdData()
        dev.put(try member(parentA, "A", "coral"))
        dev.startFeed(babyID: baby, side: .left, by: parentA, timeZoneID: londonID, now: t0)
        var real = try realHousehold(otherJoined: false)
        let outcome = try real.bringIn(dev.move(babyID: baby, by: parentA, now: moveTime), me: realA, carried: [], now: moveTime)
        #expect(outcome.addedCount == 1)
        #expect(real.allEvents.map(\.loggedBy) == [realA])
    }

    @Test("Before setup, nothing comes in")
    func notSetUp() throws {
        let (dev, _) = try devHousehold()
        let move = dev.move(babyID: baby, by: parentA, now: moveTime)
        var empty = HouseholdData()
        #expect(empty.moveProblem(move, me: nil) == .notSetUp)
        #expect(empty.moveProblem(move, me: realA) == .notSetUp)
        #expect(throws: MoveProblem.notSetUp) { try empty.bringIn(move, me: realA, carried: [], now: moveTime) }
        #expect(empty == HouseholdData())
    }

    @Test("The alerts run from the moved feeds: the latest start is the same in both apps")
    func alertsFromMovedFeeds() throws {
        let (dev, _) = try devHousehold()
        var real = try realHousehold()
        try real.bringIn(dev.move(babyID: baby, by: parentA, now: moveTime), me: realA, carried: [], now: moveTime)
        let devLatest = dev.allEvents.latestFeedStart(babyID: baby, now: moveTime)
        #expect(devLatest != nil)
        #expect(real.allEvents.latestFeedStart(babyID: realBaby, now: moveTime) == devLatest)
    }
}

@Suite("The move file")
struct MoveFileTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func file(_ folder: URL, _ name: String, bytes: Int, seed: UInt8) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0) &+ seed }).write(to: url)
        return url
    }

    @Test("What is written reads back: the contents, and each file and thumbnail byte for byte")
    func roundTrip() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (dev, _) = try devHousehold()
        let move = dev.move(babyID: baby, by: parentA, now: moveTime)
        // A file over one piece long, to cross a piece's edge.
        let items = [
            MoveFile.Item(id: "p1", file: try file(dir, "p1.file", bytes: (1 << 20) + 37, seed: 1),
                          thumbnail: try file(dir, "p1.thumbnail", bytes: 500, seed: 2)),
            MoveFile.Item(id: "p2", file: try file(dir, "p2.file", bytes: 3, seed: 3),
                          thumbnail: try file(dir, "p2.thumbnail", bytes: 0, seed: 4)),
        ]
        let url = dir.appendingPathComponent("household.\(MoveFile.fileExtension)")
        try MoveFile.write(move, items: items, to: url)
        let reader = try MoveFile.Reader(url: url)
        #expect(reader.move.events == move.events)
        #expect(reader.move.plainRecords == move.plainRecords)
        #expect(reader.move.media.map(\.id) == ["p1", "p2"])
        for (item, entry) in zip(items, reader.move.media) {
            let out = dir.appendingPathComponent("out-\(item.id)")
            try reader.extract(entry.file, to: out)
            #expect(try Data(contentsOf: out) == Data(contentsOf: item.file))
            try reader.extract(entry.thumbnail, to: out)
            #expect(try Data(contentsOf: out) == Data(contentsOf: item.thumbnail))
        }
    }

    @Test("Anything else, a file cut short, and a newer build's file are refused")
    func refused() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let other = try file(dir, "photo.jpg", bytes: 100, seed: 0)
        #expect(throws: MoveFile.Problem.notAMoveFile) { try MoveFile.Reader(url: other) }

        let (dev, _) = try devHousehold()
        let url = dir.appendingPathComponent("move.\(MoveFile.fileExtension)")
        let item = MoveFile.Item(id: "p1", file: try file(dir, "p1.file", bytes: 1000, seed: 1),
                                 thumbnail: try file(dir, "p1.thumbnail", bytes: 10, seed: 2))
        try MoveFile.write(dev.move(babyID: baby, by: parentA, now: moveTime), items: [item], to: url)
        let whole = try Data(contentsOf: url)
        let cut = dir.appendingPathComponent("cut.\(MoveFile.fileExtension)")
        try whole.prefix(whole.count - 500).write(to: cut)
        #expect(throws: MoveFile.Problem.notAMoveFile) { try MoveFile.Reader(url: cut) }

        var newer = dev.move(babyID: baby, by: parentA, now: moveTime)
        newer.v = HouseholdMove.currentVersion + 1
        let newerURL = dir.appendingPathComponent("newer.\(MoveFile.fileExtension)")
        try MoveFile.write(newer, items: [], to: newerURL)
        #expect(throws: MoveFile.Problem.newerVersion) { try MoveFile.Reader(url: newerURL) }
    }

    @Test("An item whose ID could name a file elsewhere is never written, and refused if read")
    func unsafeIDs() throws {
        #expect(MoveFile.isSafe("0E0C5D7A-1F2B-4C3D-9E8F-112233445566"))
        for id in ["", "../household", "a/b", "a.b", "é", String(repeating: "a", count: 65)] { #expect(!MoveFile.isSafe(id)) }

        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (dev, _) = try devHousehold()
        let url = dir.appendingPathComponent("move.\(MoveFile.fileExtension)")
        let bad = MoveFile.Item(id: "../x", file: try file(dir, "x.file", bytes: 10, seed: 1),
                                thumbnail: try file(dir, "x.thumbnail", bytes: 10, seed: 2))
        try MoveFile.write(dev.move(babyID: baby, by: parentA, now: moveTime), items: [bad], to: url)
        #expect(try MoveFile.Reader(url: url).move.media.isEmpty)

        var forged = dev.move(babyID: baby, by: parentA, now: moveTime)
        forged.media = [MovedMedia(id: "../x", file: ByteRange(offset: 0, length: 0), thumbnail: ByteRange(offset: 0, length: 0))]
        let contents = try MoveFile.encoder.encode(forged)
        var length = UInt64(contents.count).bigEndian
        let forgedURL = dir.appendingPathComponent("forged.\(MoveFile.fileExtension)")
        try (MoveFile.magic + Data(bytes: &length, count: 8) + contents).write(to: forgedURL)
        #expect(throws: MoveFile.Problem.notAMoveFile) { try MoveFile.Reader(url: forgedURL) }
    }

    @Test("A file that changes while it is being written stops the move file")
    func changedWhileWriting() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (dev, _) = try devHousehold()
        let missing = MoveFile.Item(id: "p1", file: dir.appendingPathComponent("gone.file"),
                                    thumbnail: dir.appendingPathComponent("gone.thumbnail"))
        let url = dir.appendingPathComponent("move.\(MoveFile.fileExtension)")
        #expect(throws: (any Error).self) {
            try MoveFile.write(dev.move(babyID: baby, by: parentA, now: moveTime), items: [missing], to: url)
        }
        // Nothing half written is left, under the name or beside it.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    /// A move file with `media` as its list of items and `bytes` after it.
    private func forged(_ dir: URL, media: [MovedMedia], bytes: Int, length: UInt64? = nil) throws -> URL {
        var move = try devHousehold().data.move(babyID: baby, by: parentA, now: moveTime)
        move.media = media
        let contents = try MoveFile.encoder.encode(move)
        var count = (length ?? UInt64(contents.count)).bigEndian
        let url = dir.appendingPathComponent("forged-\(UUID().uuidString).\(MoveFile.fileExtension)")
        try (MoveFile.magic + Data(bytes: &count, count: 8) + contents + Data(count: bytes)).write(to: url)
        return url
    }

    @Test("Items out of the writer's order, overlapping, named twice, or a list too long to read, are refused")
    func layoutChecked() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let range = { (offset: Int64, length: Int64) in ByteRange(offset: offset, length: length) }
        let good = MovedMedia(id: "p1", file: range(0, 10), thumbnail: range(10, 5))
        #expect(try MoveFile.Reader(url: forged(dir, media: [good], bytes: 15)).move.media == [good])
        let overlapping = [good, MovedMedia(id: "p2", file: range(0, 10), thumbnail: range(10, 5))]
        let twice = [good, MovedMedia(id: "p1", file: range(15, 1), thumbnail: range(16, 1))]
        let huge = [MovedMedia(id: "p1", file: range(0, .max), thumbnail: range(.max, 1))]
        for media in [overlapping, twice, huge] {
            #expect(throws: MoveFile.Problem.notAMoveFile) { try MoveFile.Reader(url: forged(dir, media: media, bytes: 40)) }
        }
        #expect(throws: MoveFile.Problem.notAMoveFile) {
            try MoveFile.Reader(url: forged(dir, media: [], bytes: 0, length: MoveFile.longestContents + 1))
        }
        let reader = try MoveFile.Reader(url: forged(dir, media: [good], bytes: 15))
        #expect(throws: MoveFile.Problem.notAMoveFile) { try reader.extract(range(10, 6), to: dir.appendingPathComponent("out")) }
    }
}
