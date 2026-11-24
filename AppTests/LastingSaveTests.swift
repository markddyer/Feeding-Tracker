import FeedingCore
import Foundation
import Testing
@testable import FeedingDev

/// Task T17 (eng OV3, "No photo is lost"): a first and its photo are never lost when the phone
/// can't write, or when the app stops part way through Save. Save writes the photo queue first,
/// then the first, each to its own file and checked; the first only counts as saved once it is in
/// this phone's file.
@Suite("Lasting Save")
@MainActor
struct LastingSaveTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lasting-\(UUID().uuidString)")
    let me: MemberID = "parent-a"
    let now = Date(timeIntervalSince1970: 1_795_000_000)

    func addFirst(_ data: inout HouseholdData) -> String? {
        data.addMilestone(id: "first-1", babyID: "baby", title: "First smile", media: ["photo-1"], at: now - 60, by: me,
                          timeZoneID: "Europe/London", now: now)
    }

    /// A store on a stand-in file, never reading the real App Group's alarms.
    func store(_ file: URL) -> HouseholdStore { HouseholdStore(fileURL: file, alarmsSet: { false }) }

    func upload(_ id: String) -> MediaUpload {
        MediaUpload(id: id, eventID: "first-1", byteSize: 10, payload: nil, queuedAt: now, pause: nil)
    }

    /// Sync and the alerts hear of the first only once it is in the file.
    @Test func aFirstIsInThePhonesFileBeforeAnythingHearsOfIt() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("household.json")
        let household = store(file)
        var inFileWhenHeard: [Bool] = []
        let inFile = { (try? HouseholdFile.load(from: file))??.events["first-1"] != nil }
        household.onLocalChange = { inFileWhenHeard.append(inFile()) }
        household.onDataChange = { inFileWhenHeard.append(inFile()) }
        let outcome = household.changeChecked { addFirst(&$0) }
        #expect(outcome.result == "first-1")
        #expect(outcome.saved)
        #expect(inFileWhenHeard == [true, true])
        // The app stopped and started again: the first is read back from the file.
        #expect(store(file).data.events["first-1"]?.snapshot.payload?.milestone?.title == "First smile")
    }

    @Test func aFirstThatCantBeWrittenIsPutBackAndNothingHearsOfIt() {
        // No such folder, so the write fails, as on a full phone.
        let household = store(folder.appendingPathComponent("missing/household.json"))
        let before = household.data
        var heard = 0
        household.onLocalChange = { heard += 1 }
        household.onDataChange = { heard += 1 }
        let outcome = household.changeChecked { addFirst(&$0) }
        #expect(outcome.result != nil)
        #expect(!outcome.saved)
        #expect(household.data == before)
        #expect(heard == 0)
    }

    /// The queue is its own file, read again at launch.
    @Test func theQueueIsInItsOwnFileAcrossARestart() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "lasting-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let household = store(folder.appendingPathComponent("household.json"))
        let queueFile = folder.appendingPathComponent("media-uploads.json")
        let first = MediaSync(store: household, household: HouseholdSync(store: household), files: nil, defaults: defaults,
                              queueFile: queueFile)
        #expect(first.add(upload("photo-1")))
        first.stop()
        #expect(FileManager.default.fileExists(atPath: queueFile.path))
        let restarted = MediaSync(store: household, household: HouseholdSync(store: household), files: nil, defaults: defaults,
                                  queueFile: queueFile)
        #expect(restarted.uploads.map(\.id) == ["photo-1"])
    }

    /// A queue this phone can't write refuses the photo, so Save stops before the first.
    @Test func aQueueThatCantBeWrittenRefusesThePhoto() throws {
        let suite = "lasting-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let household = store(folder.appendingPathComponent("missing/household.json"))
        let media = MediaSync(store: household, household: HouseholdSync(store: household), files: nil, defaults: defaults,
                              queueFile: folder.appendingPathComponent("missing/media-uploads.json"))
        #expect(!media.add(upload("photo-1")))
        #expect(media.uploads.isEmpty)
    }

    /// A queue an older build kept in the app's settings is read once, then kept in the file.
    @Test func aQueueFromAnOlderBuildMovesToTheFile() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "lasting-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([upload("older")]), forKey: "mediaUploads")
        let household = store(folder.appendingPathComponent("household.json"))
        let queueFile = folder.appendingPathComponent("media-uploads.json")
        let media = MediaSync(store: household, household: HouseholdSync(store: household), files: nil, defaults: defaults,
                              queueFile: queueFile)
        #expect(media.uploads.map(\.id) == ["older"])
        #expect(media.add(upload("newer")))
        media.stop()
        #expect(defaults.object(forKey: "mediaUploads") == nil)
        let restarted = MediaSync(store: household, household: HouseholdSync(store: household), files: nil, defaults: defaults,
                                  queueFile: queueFile)
        #expect(restarted.uploads.map(\.id) == ["older", "newer"])
    }

    /// Stopped after the queue was written and before the first: the photo waits for its first
    /// (the file may also be filling again from iCloud), and only a day later, with the file
    /// whole, is it dropped.
    @Test func aPhotoQueuedBeforeANewFirstWaitsForIt() {
        let item = upload("photo-1")
        #expect(MediaSync.readiness(item, stored: nil, waitingForICloud: false, now: now + 60) == .wait)
        #expect(MediaSync.readiness(item, stored: nil, waitingForICloud: true, now: now + 90_000) == .wait)
        #expect(MediaSync.readiness(item, stored: nil, waitingForICloud: false, now: now + 90_000) == .drop)
    }

    /// The same for an edit: a photo queued for a first that never came to name it goes a day later.
    @Test func aPhotoQueuedForAnEditThatNeverLandedGoesADayLater() throws {
        var data = HouseholdData()
        _ = addFirst(&data)
        let stored = try #require(data.events["first-1"])
        let replacement = upload("photo-2")
        #expect(MediaSync.readiness(replacement, stored: stored, waitingForICloud: false, now: now + 60) == .wait)
        #expect(MediaSync.readiness(replacement, stored: stored, waitingForICloud: true, now: now + 90_000) == .wait)
        #expect(MediaSync.readiness(replacement, stored: stored, waitingForICloud: false, now: now + 90_000) == .drop)
    }

    /// Once the first is saved, its photo goes when the first's Undo time is over.
    @Test func aSavedFirstsPhotoGoesAfterItsUndo() throws {
        var data = HouseholdData()
        _ = addFirst(&data)
        let stored = try #require(data.events["first-1"])
        let item = upload("photo-1")
        #expect(MediaSync.readiness(item, stored: stored, waitingForICloud: false, now: now + 1) == .wait)
        #expect(MediaSync.readiness(item, stored: stored, waitingForICloud: false, now: now + HouseholdData.undoWindow + 1) == .ready)
    }
}

/// Eng D6 (task T11): History's filters show what they showed before firsts existed.
@Suite("Kept as before: History's filters")
struct HistoryFilterTests {
    @Test func everyFilterShowsItsOwnEntriesWithFirstsPresent() {
        let t = Date(timeIntervalSince1970: 1_795_000_000)
        let me: MemberID = "parent-a"
        let zone = "Europe/London"
        var data = HouseholdData()
        data.startSleep(id: "sleep", babyID: "baby", startedAt: t, by: me, timeZoneID: zone, now: t)
        data.startFeed(id: "feed", babyID: "baby", side: .left, by: me, timeZoneID: zone, now: t + 3_600)
        data.add(id: "pump", kind: .pump, babyID: "baby", startedAt: t + 4_000, payload: EventPayload(pump: PumpDetails(side: .both)),
                 by: me, timeZoneID: zone, now: t + 4_000)
        data.addNappy(id: "nappy", babyID: "baby", wee: true, poo: true, at: t + 5_000, by: me, timeZoneID: zone, now: t + 5_000)
        data.addGrowth(id: "growth", babyID: "baby", GrowthDetails(weightGrams: 4_100), at: t + 6_000, by: me, timeZoneID: zone,
                       now: t + 6_000)
        data.addMedicine(id: "medicine", babyID: "baby", MedicineDetails(name: "Vitamin D"), at: t + 7_000, by: me,
                         timeZoneID: zone, now: t + 7_000)
        data.addNappy(id: "gone", babyID: "baby", wee: true, poo: false, at: t + 8_000, by: me, timeZoneID: zone, now: t + 8_000)
        data.delete("gone", by: me, now: t + 8_100)
        data.add(id: "bath", kind: .bath, babyID: "baby", startedAt: t + 7_500, payload: EventPayload(), by: me,
                 timeZoneID: zone, now: t + 7_500)

        var withFirsts = data
        withFirsts.addMilestone(id: "smile", babyID: "baby", title: "First smile", at: t + 2_000, by: me, timeZoneID: zone,
                                now: t + 9_000)
        withFirsts.addMilestone(id: "rolled", babyID: "baby", title: "Rolled over", at: t + 2_500, by: me, timeZoneID: zone,
                                now: t + 9_000)
        withFirsts.delete("rolled", by: me, now: t + 9_100)

        let expected: [HistoryFilter: [String]] = [
            .feeds: ["pump", "feed"], .sleep: ["sleep"], .nappies: ["nappy"], .medicine: ["medicine"], .baths: ["bath"],
            .growth: ["growth"],
        ]
        for (filter, ids) in expected {
            #expect(filter.entries(in: data, hidden: []).map(\.event.id) == ids, "\(filter) before firsts")
            #expect(filter.entries(in: withFirsts, hidden: []).map(\.event.id) == ids, "\(filter) with firsts")
        }
        #expect(HistoryFilter.all.entries(in: data, hidden: []).map(\.event.id)
            == ["bath", "medicine", "growth", "nappy", "pump", "feed", "sleep"])
        #expect(HistoryFilter.all.entries(in: withFirsts, hidden: []).map(\.event.id)
            == ["bath", "medicine", "growth", "nappy", "pump", "feed", "smile", "sleep"])
        #expect(HistoryFilter.firsts.entries(in: withFirsts, hidden: []).map(\.event.id) == ["smile"])
        #expect(HistoryFilter.firsts.entries(in: data, hidden: []).isEmpty)
        // A feed's copy logged on the other phone is left out.
        #expect(HistoryFilter.feeds.entries(in: withFirsts, hidden: ["pump"]).map(\.event.id) == ["feed"])
    }
}
