import FeedingCore
import Foundation

/// The Journal's words (`docs/planning/07-milestones-journal.md`, design review). A parent reads
/// "first", never "milestone" (D32). Facts only: never a typical age, never "late" or "early".
enum JournalText {
    /// The ideas under "What happened" and on the empty Journal (D38): everyday firsts, in this
    /// order every time, never marked done.
    static let ideas = ["First bath", "First laugh", "First smile", "First trip out", "First word",
                        "Grabbed a finger", "Rolled over", "Slept through"]

    static let addAFirst = "Add a first"
    static let emptyLine = "Each first you add goes on this line, with the baby's age."
    static let onItsWay = "On its way"
    static let onlyOnThisPhone = "Only on this iPhone"
    static let deleteQuestion = "Delete this first?"
    static let deleteWarning = "Its photos and videos will be removed from both phones for good once Undo ends."

    /// "30 Oct", with the year when it isn't this year (D31).
    static func date(_ day: PlainDate, today: PlainDate) -> String {
        FirstsListRow.words(day, withYear: day.year != today.year)
    }

    /// A group's heading on the line: the baby's age ("8 weeks", "Day of birth"), or with no
    /// birth date, the month ("October 2026").
    static func heading(_ group: JournalGroup) -> String {
        switch group {
        case .age(let age): return age.words
        case .month(let year, let month):
            let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                         "October", "November", "December"]
            return "\(names[month - 1]) \(year)"
        }
    }

    /// "6 weeks · 30 Oct" on a first's page; the date alone with no birth date.
    static func ageAndDate(age: BabyAge?, day: PlainDate, today: PlainDate) -> String {
        [age?.words, date(day, today: today)].compactMap { $0 }.joined(separator: " · ")
    }

    /// What VoiceOver reads for a first on the line (D35): "First smile, 6 weeks, 30 October,
    /// 1 photo, logged by Sam".
    static func spoken(title: String, age: BabyAge?, day: PlainDate, items: Int, by name: String?, status: String?) -> String {
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                      "October", "November", "December"]
        var parts = [title]
        if let age { parts.append(age.words) }
        parts.append("\(day.day) \(months[day.month - 1]) \(day.year)")
        if items > 0 { parts.append(items == 1 ? "1 photo" : "\(items) photos") }
        if let name { parts.append("logged by \(name)") }
        if let status { parts.append(status) }
        return parts.joined(separator: ", ")
    }

    /// The Undo bar's words (D15).
    static func added(_ title: String) -> String { "\(title) added" }
    static func deleted(_ title: String) -> String { "\(title) deleted" }
    static let photoRemoved = "Photo removed"

    /// Why a date is refused, in the parents' words.
    static func refusal(_ problem: MilestoneDateProblem, today: PlainDate) -> String {
        switch problem {
        case .inFuture: return "That time hasn't come yet."
        case .beforeBirth(let birth): return "That's before the birth date (\(date(birth, today: today)))."
        }
    }

    /// "74 / 80": shown near a limit only.
    static func count(_ text: String, limit: Int) -> String? {
        let used = text.count
        guard used >= limit - limit / 10 else { return nil }
        return "\(used.formatted()) / \(limit.formatted())"
    }

    /// What a photo picked from the phone couldn't do.
    static func refusal(_ refusal: MediaStore.Refusal) -> String {
        switch refusal {
        case .unreadablePhoto: "This photo couldn't be added."
        case .unreadableVideo: "This video couldn't be added."
        case .notEnoughSpace: "Not enough space on this iPhone."
        }
    }
}
