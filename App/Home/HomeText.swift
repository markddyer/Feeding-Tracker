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

    /// One chip per side, bottle and pumping session, in the order they were logged. `detailed`
    /// (History) names each bottle's milk and the pumping ("Formula 30 ml", "Pumped 120 ml");
    /// Home shows the amount only.
    static func chips(_ snapshot: EventSnapshot, detailed: Bool = false) -> [ChipFact] {
        guard let payload = snapshot.payload else {
            return [ChipFact(mark: nil, text: "Feed", spoken: "Feed. Its details need a newer version of the app.")]
        }
        var chips = (payload.feed?.breast ?? []).map(sideChip) + (payload.feed?.bottles ?? []).map { bottleChip($0, detailed: detailed) }
        if let pump = payload.pump {
            chips.append(ChipFact(mark: .pump, text: detailed ? "Pumped \(pump.totalML) ml" : "\(pump.totalML) ml",
                                  spoken: "Pumped \(pump.totalML) ml"))
        }
        if chips.isEmpty {
            chips.append(ChipFact(mark: nil, text: snapshot.event.kind == .pump ? "Pumping" : "Feed",
                                  spoken: snapshot.event.kind == .pump ? "Pumping" : "Feed"))
        }
        return chips
    }

    /// A side: its half-moon and minutes ("12m"), or the half-moon alone with no time.
    static func sideChip(_ segment: BreastSegment) -> ChipFact {
        let mark = FeedMark.side(segment.side)
        guard let seconds = segment.durationSeconds else { return ChipFact(mark: mark, text: "", spoken: mark.spoken) }
        let spokenTime = seconds < 60 ? "less than a minute" : spokenElapsed(TimeInterval(seconds))
        return ChipFact(mark: mark, text: sideMinutes(seconds), spoken: "\(mark.spoken), \(spokenTime)")
    }

    /// A bottle: its amount ("30 ml"), or its kind ("Formula") until the amount is known.
    static func bottleChip(_ bottle: Bottle, detailed: Bool = false) -> ChipFact {
        let spokenKind = bottle.milk == .formula ? "Formula bottle" : "Expressed milk bottle"
        let kind = milkName(bottle.milk, short: true)
        guard let ml = bottle.ml else { return ChipFact(mark: .bottle, text: kind, spoken: spokenKind) }
        return ChipFact(mark: .bottle, text: detailed ? "\(kind) \(ml) ml" : "\(ml) ml", spoken: "\(spokenKind), \(ml) ml")
    }

    /// A day heading in History: "Today", "Yesterday", or the date ("Thursday 12 November" in
    /// British English), read on the household's calendar.
    static func dayTitle(_ day: PlainDate, today: PlainDate, in timeZone: TimeZone, locale: Locale = .current) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: -1) { return "Yesterday" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else {
            return day.description
        }
        var style = Date.FormatStyle(timeZone: timeZone).weekday(.wide).day().month(.wide)
        style.locale = locale
        return noon.formatted(style)
    }

    /// "Formula", "Expressed milk" ("Expressed" where room is short).
    static func milkName(_ milk: MilkKind, short: Bool = false) -> String {
        milk == .formula ? "Formula" : (short ? "Expressed" : "Expressed milk")
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
