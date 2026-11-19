import Foundation
import Testing
@testable import FeedingCore

/// "Export the journal" (task T10): the file names and the list.
@Suite("Firsts: the export")
struct JournalExportTests {
    let t0 = at(2026, 11, 18, 10, 0)

    func household(birth: String? = "2026-09-17") throws -> HouseholdData {
        var data = HouseholdData()
        data.put(PlainRecord(type: .baby, name: baby, modifiedAt: t0,
                             payload: try PayloadCoder.encode(BabyPayload(name: "Baby", birthDate: birth.map(date)))))
        data.addMilestone(id: "smile", babyID: baby, title: "First smile", note: "At the morning feed.", media: ["m1", "m2"],
                          at: at(2026, 10, 31, 7, 0), by: parentA, timeZoneID: "Europe/London", now: t0)
        data.addMilestone(id: "cuddle", babyID: baby, title: "First cuddle", at: at(2026, 9, 17, 15, 0), by: parentB,
                          timeZoneID: "Europe/London", now: t0)
        data.addMilestone(id: "smile2", babyID: baby, title: "First smile", media: ["m3"], at: at(2026, 10, 31, 9, 0),
                          by: parentB, timeZoneID: "Europe/London", now: t0)
        data.addMilestone(id: "slash", babyID: baby, title: "Bath/night: 1st", media: ["m4"], at: at(2026, 11, 1, 9, 0),
                          by: parentB, timeZoneID: "Europe/London", now: t0)
        let gone = data.addMilestone(babyID: baby, title: "Deleted", media: ["m5"], at: at(2026, 11, 2, 9, 0), by: parentB,
                                     timeZoneID: "Europe/London", now: t0)
        data.delete(gone ?? "", by: parentB, now: t0)
        return data
    }

    @Test func eachItemIsNamedByDateAndTitleOldestFirst() throws {
        let plan = try household().journalExport(babyID: baby) { $0 == "m2" ? "mp4" : "jpg" }
        #expect(plan.items.map(\.fileName) == [
            "2026-10-31 First smile.jpg", "2026-10-31 First smile 2.mp4", "2026-10-31 First smile (2).jpg",
            "2026-11-01 Bath-night- 1st.jpg",
        ])
        #expect(plan.items.map(\.mediaID) == ["m1", "m2", "m3", "m4"])
    }

    @Test func theListHasEachFirstsDateAgeNoteAndItems() throws {
        let plan = try household().journalExport(babyID: baby) { _ in "jpg" }
        #expect(plan.listText.hasPrefix("Firsts\n\nFirst cuddle\n17 Sep 2026 · Day of birth\n\nFirst smile\n31 Oct 2026 · 6 weeks\nAt the morning feed.\nPhotos: 2026-10-31 First smile.jpg, 2026-10-31 First smile 2.jpg\n\n"))
        #expect(!plan.listText.contains("Deleted"))
    }

    @Test func withNoBirthDateTheListHasDatesOnly() throws {
        let plan = try household(birth: nil).journalExport(babyID: baby) { _ in "jpg" }
        #expect(plan.listText.contains("First cuddle\n17 Sep 2026\n"))
    }

    /// "Save without these": the left-out items aren't in the file, and the list says so.
    @Test func leftOutItemsAreNamedAsMissingInTheList() throws {
        let plan = try household().journalExport(babyID: baby, fileExtension: { _ in "jpg" }, leavingOut: ["m2", "m4"])
        #expect(plan.items.map(\.mediaID) == ["m1", "m3"])
        #expect(plan.listText.contains("This file leaves out 2 photos that weren't on this iPhone when it was made."))
        #expect(plan.listText.contains("Photo: 2026-10-31 First smile.jpg\nNot in this file: 1 photo"))
        #expect(!plan.listText.contains("First smile 2.jpg"))
    }

    /// Thirty family emoji fit the title's limits but not a file name: cut to whole characters.
    @Test func aTitleOfManyEmojiIsCutToASafeLength() {
        let name = HouseholdData.safeName(String(repeating: "👨‍👩‍👧‍👦", count: 30))
        #expect(name.utf8.count <= 120)
        #expect(name.allSatisfy { $0 == "👨‍👩‍👧‍👦" })
    }

    @Test func aTitleIsMadeSafeForAFileName() {
        #expect(HouseholdData.safeName("...hidden") == "hidden")
        #expect(HouseholdData.safeName("a\nb") == "a-b")
        #expect(HouseholdData.safeName("   ") == "First")
        #expect(HouseholdData.safeName(String(repeating: "x", count: 80)).count == 60)
    }
}
