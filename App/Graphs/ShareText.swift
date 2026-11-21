import FeedingCore
import Foundation

/// The words on the "who did what" page, its tile and its lists (`09-who-does-what.md`). Facts
/// only: no winner, no score words, no "fair", no red or green (DESIGN.md's guarded rule, R1).
enum ShareText {
    static let title = "Who did what"
    static let tileTitle = "Who did what · last 7 nights"

    /// The page's ranges (design 1C).
    static func rangeTitle(_ range: SharePageRange) -> String {
        switch range {
        case .day: "Day"
        case .week: "7 days"
        case .fourWeeks: "4 weeks"
        case .all: "All"
        }
    }

    /// A line's heading. "Got up" under the 7 nights' dots; "Got up at night" on its own.
    static func kindTitle(_ kind: ShareKind, time: Bool = false, alone: Bool = false) -> String {
        switch kind {
        case .feeds: time ? "Feeding time" : "Feeds"
        case .nappies: "Nappies"
        case .settled: "Settled to sleep"
        case .medicines: "Medicines"
        case .baths: "Baths"
        case .pumping: time ? "Pumping time" : "Pumping"
        case .gotUpAtNight: alone ? "Got up at night" : "Got up"
        case .nightFeeds: "Night feeds"
        case .nightNappies: "Night nappies"
        }
    }

    /// "13h 30m", "25m", "0m".
    static func time(_ seconds: TimeInterval) -> String { HomeText.elapsed(seconds) }

    /// Lines that show a count and its time together: night feeds, and pumping (the plan's
    /// counting rules: "pumping (count and time)").
    static func showsTime(_ kind: ShareKind) -> Bool { kind == .nightFeeds || kind == .pumping }

    /// A number on a line: "24", or with the time for night feeds and pumping, "10 · 3h 40m".
    static func number(_ tally: ShareTally, kind: ShareKind, time: Bool) -> String {
        if time { return self.time(tally.seconds) }
        if showsTime(kind) { return "\(tally.count) · \(self.time(tally.seconds))" }
        return "\(tally.count)"
    }

    /// "Feeds, 31: Sam 24, Alex 7." For VoiceOver (6B).
    static func spokenLine(_ title: String, total: String, parts: [(String, String)]) -> String {
        "\(title), \(total): " + parts.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }

    /// The day picker (1C): "Today", "Yesterday", "Thu 19 Nov".
    static func dayName(_ day: PlainDate, today: PlainDate, in zone: TimeZone) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: -1) { return "Yesterday" }
        return GraphText.midday(day, in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Thursday night · slept 6h 40m": a night is named by its evening (1A).
    static func nightTitle(_ evening: PlainDate, slept: TimeInterval, in zone: TimeZone) -> String {
        let weekday = GraphText.midday(evening, in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide))
        return slept > 0 ? "\(weekday) night · slept \(time(slept))" : "\(weekday) night"
    }

    /// "Tue", under a night's column of dots.
    static func shortNight(_ evening: PlainDate, in zone: TimeZone) -> String {
        GraphText.midday(evening, in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated))
    }

    /// "Tuesday night: Sam got up twice, Alex once." / "Tuesday night: no wake-ups logged."
    static func spokenNight(_ evening: PlainDate, counts: [(String, Int)], in zone: TimeZone) -> String {
        let weekday = GraphText.midday(evening, in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide))
        let parts = counts.filter { $0.1 > 0 }.map { "\($0.0) got up \(times($0.1))" }
        return parts.isEmpty ? "\(weekday) night: no wake-ups logged." : "\(weekday) night: \(parts.joined(separator: ", "))."
    }

    static func times(_ count: Int) -> String {
        switch count {
        case 1: "once"
        case 2: "twice"
        default: "\(count) times"
        }
    }

    /// The empty page (DD13).
    static func nothingLogged(_ range: SharePageRange) -> String {
        let when = switch range {
        case .day: "on this day"
        case .week: "in these 7 days"
        case .fourWeeks: "in these 4 weeks"
        case .all: ""
        }
        let start = when.isEmpty ? "Nothing logged yet." : "Nothing logged \(when) yet."
        return "\(start) Each feed, nappy, sleep and bath you log shows here, with who did it."
    }

    /// Before the other parent joins (DD13).
    static let notJoined = "The other parent hasn't joined yet. Once they join on their own phone, their part shows here too."

    /// "Checked with iCloud 07:38" at the bottom; a failed or old check at the top (1D).
    static func checked(_ date: Date, in zone: TimeZone) -> String {
        "Checked with iCloud \(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))"
    }

    static let notCheckedYet = "Not checked with iCloud yet."

    static func checkProblem(since date: Date?, in zone: TimeZone) -> String {
        let since = date.map { " since \($0.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))" } ?? ""
        return "Couldn't check with iCloud\(since). Numbers may be missing the other phone's latest entries."
    }

    /// "Who breastfeeds?" not answered (2A): a quiet line at the top.
    static let quietBreastfeeds = "Breastfeeds count for whoever logged them"
    static let setBreastfeeds = "Set who breastfeeds"

    /// The "Who breastfeeds?" sheet (DD11, 2A).
    static let breastfeederQuestion = "Who breastfeeds?"
    static let breastfeederExplained = "Breastfeeds and pumping count for this parent, wherever they were logged. You can still change who did any entry."
    static let nobody = "Nobody"
    static let notNow = "Not now"

    static let swipeHint = "Swipe left or right to change the day."

    /// Home's morning line (DD4, 3A).
    static let lastNight = "Last night"

    static func slept(_ seconds: TimeInterval) -> String { "Slept \(time(seconds))" }

    /// "Last night: 3 feeds, 2 nappies, 2 wake-ups. Slept 6 hours 40 minutes." (3A)
    static func spokenLastNight(_ night: LastNight) -> String {
        func count(_ kind: ShareKind, _ one: String, _ many: String) -> String? {
            let n = night.items.filter { $0.kind == kind }.count
            return n == 0 ? nil : "\(n) \(n == 1 ? one : many)"
        }
        let parts = [count(.nightFeeds, "feed", "feeds"), count(.nightNappies, "nappy", "nappies"),
                     count(.gotUpAtNight, "wake-up", "wake-ups")].compactMap { $0 }
        let slept = night.sleptSeconds > 0 ? " Slept \(HomeText.spokenElapsed(night.sleptSeconds))." : ""
        return "Last night: \(parts.joined(separator: ", ")).\(slept)"
    }

    /// The list's number for VoiceOver: "7 entries", "3h 40m in all".
    static func listCount(_ tally: ShareTally, kind: ShareKind, time: Bool) -> String {
        if time { return "\(self.time(tally.seconds)) in all" }
        if showsTime(kind) { return "\(tally.count) \(tally.count == 1 ? "entry" : "entries"), \(self.time(tally.seconds))" }
        return "\(tally.count) \(tally.count == 1 ? "entry" : "entries")"
    }

    /// A list with nothing left in it (an entry removed while it was open).
    static let nothingHere = "Nothing here now."

    /// Under a row in a time list: "Added 25m".
    static func added(_ seconds: TimeInterval) -> String { "Added \(time(seconds))" }
    static let stillRunning = "Still running: adds its time when finished"

    /// A list's chips (DD10): "Sam · Nappies · 7 days".
    static func chips(member: String?, kind: String, range: String) -> [String] {
        [member, kind, range].compactMap { $0 }
    }

    /// What a row in a list says: "Feed · 25m", "Nappy · wee", "Woke up".
    static func what(_ item: ShareItem, snapshot: EventSnapshot?) -> String {
        switch item.kind {
        case .feeds, .nightFeeds:
            if let snapshot {
                let chips = HomeText.chips(snapshot).map(\.text)
                if !chips.isEmpty { return "Feed · " + chips.joined(separator: " · ") }
            }
            return "Feed"
        case .nappies, .nightNappies:
            if let nappy = snapshot?.payload?.nappy { return "Nappy · \(CareText.nappyKind(wee: nappy.wee, poo: nappy.poo))" }
            return "Nappy"
        case .settled: return "Fell asleep"
        case .gotUpAtNight: return "Woke up"
        case .medicines: return snapshot?.payload?.medicine?.name ?? "Medicine"
        case .baths: return "Bath"
        case .pumping: return "Pumping"
        }
    }
}
