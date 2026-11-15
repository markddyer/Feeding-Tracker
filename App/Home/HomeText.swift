import FeedingCore
import Foundation

/// One fact on a chip: a shape, a short number, and the sentence VoiceOver says.
struct ChipFact: Hashable {
    var mark: FeedMark?
    var text: String
    var spoken: String
}

/// The words and numbers on the home screen, kept apart from the views so they can be tested.
/// Facts only: no "due", "missed", "overdue" or "should", no targets and no verdicts.
enum HomeText {
    /// "2h 05m", "45m": the time since the last feed started, rounded down to the minute.
    static func elapsed(_ seconds: TimeInterval) -> String {
        let (hours, minutes) = Self.hoursAndMinutes(seconds)
        return hours == 0 ? "\(minutes)m" : "\(hours)h \(minutes < 10 ? "0" : "")\(minutes)m"
    }

    /// The same time for VoiceOver: "2 hours, 5 minutes".
    static func spokenElapsed(_ seconds: TimeInterval) -> String {
        let (hours, minutes) = Self.hoursAndMinutes(seconds)
        let h = hours == 1 ? "1 hour" : "\(hours) hours"
        let m = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if hours == 0 { return m }
        return minutes == 0 ? h : "\(h), \(m)"
    }

    private static func hoursAndMinutes(_ seconds: TimeInterval) -> (Int, Int) {
        max(0, Int(seconds / 60)).quotientAndRemainder(dividingBy: 60)
    }

    static func greeting(_ part: PartOfDay) -> String {
        switch part {
        case .morning: "Good morning"
        case .afternoon: "Good afternoon"
        case .evening: "Good evening"
        case .night: "Night"
        }
    }

    /// The SF Symbol beside the greeting.
    static func greetingSymbol(_ part: PartOfDay) -> String {
        switch part {
        case .morning, .afternoon: "sun.max"
        case .evening: "sun.horizon"
        case .night: "moon"
        }
    }

    /// The chip beside the baby's name: "Born today", "1 day", "12 days".
    static func age(days: Int) -> String {
        switch days {
        case 0: "Born today"
        case 1: "1 day"
        default: "\(days) days"
        }
    }

    /// "Sam's on tonight", "You're on tonight".
    static func onTonight(_ name: String, isMe: Bool) -> String {
        isMe ? "You're on tonight" : "\(name)'s on tonight"
    }

    /// A breast segment's time on a chip: "12m", or "<1m" for under a minute.
    static func sideMinutes(_ seconds: Int) -> String {
        seconds < 60 ? "<1m" : "\(seconds / 60)m"
    }

    /// One chip per side, bottle and pumping session, in the order they were logged.
    static func chips(_ snapshot: EventSnapshot) -> [ChipFact] {
        guard let payload = snapshot.payload else {
            return [ChipFact(mark: nil, text: "Feed", spoken: "Feed. Its details need a newer version of the app.")]
        }
        var chips: [ChipFact] = []
        for segment in payload.feed?.breast ?? [] {
            let mark = FeedMark.side(segment.side)
            if let seconds = segment.durationSeconds {
                let spokenTime = seconds < 60 ? "less than a minute" : spokenElapsed(TimeInterval(seconds))
                chips.append(ChipFact(mark: mark, text: sideMinutes(seconds), spoken: "\(mark.spoken), \(spokenTime)"))
            } else {
                chips.append(ChipFact(mark: mark, text: "", spoken: mark.spoken))
            }
        }
        for bottle in payload.feed?.bottles ?? [] {
            let milk = bottle.milk == .formula ? "Formula bottle" : "Expressed milk bottle"
            chips.append(ChipFact(mark: .bottle, text: bottle.ml.map { "\($0) ml" } ?? "",
                                  spoken: bottle.ml.map { "\(milk), \($0) ml" } ?? milk))
        }
        if let pump = payload.pump {
            chips.append(ChipFact(mark: .pump, text: "\(pump.totalML) ml", spoken: "Pumped \(pump.totalML) ml"))
        }
        if chips.isEmpty {
            chips.append(ChipFact(mark: nil, text: snapshot.event.kind == .pump ? "Pumping" : "Feed",
                                  spoken: snapshot.event.kind == .pump ? "Pumping" : "Feed"))
        }
        return chips
    }

    /// What a chart bar stands for, for VoiceOver: "breast and bottle".
    static func kinds(_ feed: DayChartFeed) -> String {
        switch (feed.breast, feed.bottle) {
        case (true, true): "breast and bottle"
        case (true, false): "breast"
        case (false, true): "bottle"
        case (false, false): "feed"
        }
    }
}
