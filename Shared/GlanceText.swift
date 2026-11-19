import FeedingCore
import Foundation

// Shared by the app and the widget extension (the Lock Screen widget and the control).

/// Words and numbers for the glances outside the app, and the words the quick actions say. Facts
/// only, as on the home screen: no "due", "missed", "overdue" or "should", and no verdicts.
enum GlanceText {
    /// "2h 05m", "45m": a time since, rounded down to the minute.
    static func elapsed(_ seconds: TimeInterval) -> String {
        let (hours, minutes) = hoursAndMinutes(seconds)
        return hours == 0 ? "\(minutes)m" : "\(hours)h \(minutes < 10 ? "0" : "")\(minutes)m"
    }

    /// "2:05", "45m": the same time, short enough for the Lock Screen's small circle.
    static func compactElapsed(_ seconds: TimeInterval) -> String {
        let (hours, minutes) = hoursAndMinutes(seconds)
        return hours == 0 ? "\(minutes)m" : "\(hours):\(minutes < 10 ? "0" : "")\(minutes)"
    }

    /// The same time for VoiceOver: "2 hours, 5 minutes".
    static func spokenElapsed(_ seconds: TimeInterval) -> String {
        let (hours, minutes) = hoursAndMinutes(seconds)
        let h = hours == 1 ? "1 hour" : "\(hours) hours"
        let m = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if hours == 0 { return m }
        return minutes == 0 ? h : "\(h), \(m)"
    }

    private static func hoursAndMinutes(_ seconds: TimeInterval) -> (Int, Int) {
        max(0, Int(seconds / 60)).quotientAndRemainder(dividingBy: 60)
    }

    /// "03:50", on the household's clock.
    static func clock(_ date: Date, timeZoneID: String) -> String {
        let zone = TimeZone(identifier: timeZoneID) ?? .current
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }

    // MARK: What a quick start or finish says (Siri and Shortcuts show it; a control doesn't)

    static func said(_ result: QuickFeedResult, me: MemberID, names: [MemberID: String], timeZoneID: String, now: Date) -> String {
        switch result {
        case .started(_, let at, let bottle):
            let time = clock(at, timeZoneID: timeZoneID)
            switch bottle {
            case .formula: return "Formula bottle started at \(time). Add the amount in the app when it's finished."
            case .expressed: return "Expressed milk bottle started at \(time). Add the amount in the app when it's finished."
            case nil: return "Feed started at \(time). Add the sides and bottles in the app."
            }
        case .alreadyRunning(let feed):
            let who = feed.event.loggedBy == me ? "Your" : "\(names[feed.event.loggedBy] ?? "The other parent")'s"
            return "\(who) feed is running, started at \(clock(feed.event.startedAt, timeZoneID: timeZoneID))."
        case .finished(let feed):
            let minutes = spokenElapsed((feed.event.endedAt ?? now).timeIntervalSince(feed.event.startedAt))
            let whose = feed.event.loggedBy == me ? "Feed" : "\(names[feed.event.loggedBy] ?? "The other parent")'s feed"
            return "\(whose) finished, after \(minutes)."
        case .nothingRunning:
            return "No feed is running."
        }
    }

    // MARK: What a quick sleep, nappy or medicine tap says

    static func said(_ result: QuickCareResult, timeZoneID: String) -> String {
        switch result {
        case .fellAsleep(let at):
            return "Fell asleep at \(clock(at, timeZoneID: timeZoneID))."
        case .alreadyAsleep(let since):
            return "Asleep since \(clock(since, timeZoneID: timeZoneID))."
        case .wokeUp(let at, let asleepFor):
            return "Woke up at \(clock(at, timeZoneID: timeZoneID)), after \(spokenElapsed(asleepFor)) asleep."
        case .notAsleep:
            return "No sleep is running."
        case .nappy(let at, let wee, let poo):
            let what = wee && poo ? "Wee and poo" : poo ? "Poo" : "Wee"
            return "\(what) logged at \(clock(at, timeZoneID: timeZoneID))."
        case .medicine(let at, let name):
            return "\(name) logged at \(clock(at, timeZoneID: timeZoneID))."
        }
    }

    /// The nappy's kind in a few letters, for the widget's line: "wee", "poo", "wee and poo".
    static func nappyKind(wee: Bool, poo: Bool) -> String {
        wee && poo ? "wee and poo" : poo ? "poo" : wee ? "wee" : "dry"
    }

    static let notSetUp = "Open Little Log to set it up first."
}
