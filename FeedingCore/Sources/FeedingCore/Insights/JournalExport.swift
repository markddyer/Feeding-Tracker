import Foundation

/// What "Export the journal" holds (journal plan, "Export ships with the first Journal build";
/// task T10): every photo and video, named by date and title, and a list of each first with its
/// date, the baby's age and the note. The parents' own copy, so nothing depends on iCloud alone.
public struct JournalExportPlan: Hashable, Sendable {
    public struct Item: Hashable, Sendable {
        public var mediaID: String
        /// The first it belongs to, for the names of missing items.
        public var title: String
        /// "2026-10-31 First smile.jpg"; a first's second item "2026-10-31 First smile 2.jpg".
        public var fileName: String

        public init(mediaID: String, title: String, fileName: String) {
            self.mediaID = mediaID
            self.title = title
            self.fileName = fileName
        }
    }

    /// Oldest first, in each first's own order.
    public var items: [Item]
    /// The list of firsts, as plain text (`Firsts.txt`).
    public var listText: String

    /// The list's own file name in the export.
    public static let listFileName = "Firsts.txt"

    public init(items: [Item], listText: String) {
        self.items = items
        self.listText = listText
    }
}

extension HouseholdData {
    /// The export of `babyID`'s firsts. `fileExtension` names each item's kind ("jpg", "mp4").
    /// `leavingOut`: items that couldn't be fetched ("Save without these"): not in the file, and
    /// the list says so, at the top and at each first, so it is never taken for a whole copy.
    public func journalExport(babyID: String, fileExtension: (String) -> String,
                              leavingOut: Set<String> = []) -> JournalExportPlan {
        let timeZone = householdSettings.timeZone
        let birth = birthDate(babyID: babyID)
        var used = Set<String>([JournalExportPlan.listFileName.lowercased()])
        var items: [JournalExportPlan.Item] = []
        var entries: [String] = []
        for first in milestones(babyID: babyID) {
            let day = PlainDate(first.event.startedAt, in: timeZone)
            let title = first.payload?.milestone?.title ?? "First"
            let age = birth.flatMap { BabyAge(on: day, birthDate: $0) }
            var names: [String] = []
            var leftOut = 0
            for (index, id) in (first.payload?.milestone?.media ?? []).enumerated() {
                if leavingOut.contains(id) {
                    leftOut += 1
                    continue
                }
                let base = "\(Self.isoDate(day)) \(Self.safeName(title))" + (index == 0 ? "" : " \(index + 1)")
                let name = Self.unused(base, fileExtension: fileExtension(id), in: &used)
                items.append(.init(mediaID: id, title: title, fileName: name))
                names.append(name)
            }
            var lines = [title, ([FirstsListRow.words(day, withYear: true)] + [age?.words].compactMap { $0 }).joined(separator: " · ")]
            if let note = first.payload?.note, !note.isEmpty { lines.append(note) }
            if !names.isEmpty { lines.append((names.count == 1 ? "Photo: " : "Photos: ") + names.joined(separator: ", ")) }
            if leftOut > 0 { lines.append("Not in this file: \(Self.photos(leftOut)) (not on this iPhone when it was made)") }
            entries.append(lines.joined(separator: "\n"))
        }
        let total = leavingOut.count
        let heading = total == 0 ? ["Firsts", ""]
            : ["Firsts", "", "This file leaves out \(Self.photos(total)) that weren't on this iPhone when it was made.", ""]
        let list = (heading + [entries.joined(separator: "\n\n")]).joined(separator: "\n")
        return JournalExportPlan(items: items, listText: list + "\n")
    }

    /// "1 photo", "3 photos".
    static func photos(_ count: Int) -> String { count == 1 ? "1 photo" : "\(count) photos" }

    /// "2026-10-31".
    static func isoDate(_ day: PlainDate) -> String {
        String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }

    /// A title as part of a file name: no slashes, colons or control characters, no leading dot,
    /// at most 60 characters and 120 bytes (a name of many emoji is too long for the disk
    /// otherwise; whole characters only, with room for the date, a count and the extension).
    public static func safeName(_ title: String) -> String {
        // Real control characters only: the joiners inside emoji such as a family stay.
        let controls = CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(0x1F)).union(CharacterSet(charactersIn: "\u{7F}"))
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|").union(controls).union(.newlines)
        let cleaned = String(String.UnicodeScalarView(title.unicodeScalars.map { banned.contains($0) ? "-" : $0 }))
            .trimmingCharacters(in: .whitespaces)
        var kept = ""
        for character in cleaned.drop(while: { $0 == "." }).prefix(60) {
            guard kept.utf8.count + String(character).utf8.count <= 120 else { break }
            kept.append(character)
        }
        let trimmed = kept.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "First" : trimmed
    }

    /// `base.ext`, or `base (2).ext` and on when that name is taken (two firsts, same day and title).
    static func unused(_ base: String, fileExtension: String, in used: inout Set<String>) -> String {
        var name = "\(base).\(fileExtension)"
        var copy = 2
        while used.contains(name.lowercased()) {
            name = "\(base) (\(copy)).\(fileExtension)"
            copy += 1
        }
        used.insert(name.lowercased())
        return name
    }
}
