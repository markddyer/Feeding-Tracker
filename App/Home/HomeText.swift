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
    /// "2h 05m", "45m": the time since the last feed started, rounded down to the minute. The
    /// same words as the Lock Screen widget (`GlanceText`).
    static func elapsed(_ seconds: TimeInterval) -> String {
        GlanceText.elapsed(seconds)
    }

    /// The same time for VoiceOver: "2 hours, 5 minutes".
    static func spokenElapsed(_ seconds: TimeInterval) -> String {
        GlanceText.spokenElapsed(seconds)
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

    /// Nobody is on tonight: no rota, or a parent tapped "Both phones tonight".
    static let bothPhonesTonight = "Both phones alert tonight"

    /// Gives a taken night back, so both phones alert (`BothPhonesNight`).
    static let bothPhonesButton = "Both phones tonight"

    // MARK: Asking the other parent to take a night

    /// The card on the asked parent's Home: "Alex asks you to take tonight".
    static func askedOfMe(by name: String) -> String {
        "\(name) asks you to take tonight"
    }

    /// The button in the Nights tile: "Ask Sam to take it" after "You're on tonight". When nobody
    /// is on (no rota yet: both phones alert) there is no line before it, so it says which night.
    static func askButton(_ name: String, nobodyOn: Bool = false) -> String {
        nobodyOn ? "Ask \(name) to take tonight" : "Ask \(name) to take it"
    }

    /// The asker's line while there is no answer. A request, not a hand-off: nothing changes
    /// until the answer is yes.
    static func askWaiting(_ name: String, nobodyOn: Bool = false) -> String {
        nobodyOn
            ? "You asked \(name) to take tonight. Both phones alert until \(name) says yes."
            : "You asked \(name) to take tonight. You stay on until \(name) says yes."
    }

    static func askDeclined(_ name: String) -> String {
        "\(name) said not tonight."
    }

    /// An ordinary notification about an ask: the title and the body.
    static func askNotification(_ news: NightAskNews, name: String, nobodyOn: Bool = false) -> (title: String, body: String) {
        switch news {
        case .asked: ("Nights", "\(name) asks you to take tonight.")
        case .taken: ("Nights", "\(name) is taking tonight.")
        case .declined: ("Nights", "\(name) said not tonight. " + (nobodyOn ? "Both phones alert tonight." : "You're still on tonight."))
        }
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

    // MARK: Home's folded parts (`13-calm-home.md`, CH6)

    /// Today's heading line: "7 feeds · 210 ml · 90 ml pumped". Bottles and pumping only when
    /// there were some.
    static func daySummary(_ totals: FeedSummary) -> String {
        var parts = ["\(totals.feeds) \(totals.feeds == 1 ? "feed" : "feeds")"]
        let bottles = totals.expressedML + totals.formulaML
        if bottles > 0 { parts.append("\(bottles) ml") }
        if totals.pumpedML > 0 {
            parts.append("\(totals.pumpedML) ml pumped")
        } else if totals.pumpSessions > 0 {
            parts.append(totals.pumpSessions == 1 ? "1 pumping" : "\(totals.pumpSessions) pumpings")
        }
        return parts.joined(separator: " · ")
    }

    /// Recent: the last 24 hours' entries of every kind but firsts, newest first, each shown once
    /// when both phones logged it (as History does).
    static func recentEntries(_ facts: HomeFacts) -> [EventSnapshot] {
        let data = facts.data
        let hidden = Set((data.duplicatePairs(babyID: facts.babyID) + data.careDuplicatePairs(babyID: facts.babyID)).map(\.duplicate))
        let since = facts.now.addingTimeInterval(-24 * 3600)
        return data.events.values
            .filter {
                $0.event.babyID == facts.babyID && $0.event.deletedAt == nil && $0.event.kind != .milestone
                    && !hidden.contains($0.event.id) && $0.event.startedAt >= since && $0.event.startedAt <= facts.now
            }
            .sorted { ($0.event.startedAt, $0.event.id) > ($1.event.startedAt, $1.event.id) }
            .map(\.snapshot)
    }

    /// Recent's heading line: the newest entry in a few words, "Wee and poo, 12:43".
    static func recentSummary(_ entry: EventSnapshot, facts: HomeFacts) -> String {
        let event = entry.event
        let what: String = switch event.kind {
        case .feed: event.endedAt == nil ? "Feed running" : "Feed"
        case .pump: "Pumping"
        case .sleep: event.endedAt == nil ? "Fell asleep" : "Sleep"
        case .nappy: entry.payload?.nappy.map { CareText.nappyKind(wee: $0.wee, poo: $0.poo).capitalizedFirst } ?? "Nappy"
        case .medicine: entry.payload?.medicine?.name ?? "Medicine"
        case .bath: "Bath"
        case .growth: "Growth"
        default: "Entry"
        }
        return "\(what), \(facts.clock(event.startedAt))"
    }
}
