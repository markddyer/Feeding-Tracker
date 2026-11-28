import FeedingCore
import Foundation

// What Siri says when logging by voice (`docs/planning/15-hands-free-siri.md`), the same on the
// phone and the watch. Facts only, as on the home screen: no "due", "missed", "overdue",
// "enough", "too much" or "should", and no verdicts (hard rules). A parent is "they".

enum SiriText {
    // MARK: Questions

    static func howMuch(_ milk: MilkKind, baby: String) -> String {
        "How much \(milkName(milk)) did \(baby) drink, in ml?"
    }

    static func isThatRight(_ ml: Int, _ milk: MilkKind) -> String {
        "\(ml) ml of \(milkName(milk)). Is that right?"
    }

    static let whichMilk = "Formula or expressed milk?"
    static let whichSides = "Which side: left, right, left then right, or right then left?"
    static let weeOrPoo = "Wee, poo or both?"
    static let whatColour = "What colour? Yellow, green, brown, pale or other. Or say skip."
    static let whatTexture = "Liquid, loose or firm? Or say skip."
    static let whichMedicine = "Which one?"

    // MARK: Answers

    /// "Feed finished at 03:35, after 25 minutes. 90 ml of formula." The details are what the
    /// feed has once Siri's questions are answered.
    static func finished(_ feed: EventSnapshot, me: MemberID, names: [MemberID: String], timeZoneID: String,
                         now: Date) -> String {
        let by = feed.event.loggedBy == me ? nil : names[feed.event.loggedBy] ?? "The other parent"
        return finished(by: by, start: feed.event.startedAt, end: feed.event.endedAt ?? now,
                        details: feed.payload?.feed ?? FeedDetails(), timeZoneID: timeZoneID)
    }

    /// The same from the watch's facts. `by` is the other parent's name, or nil for this parent's
    /// own feed.
    static func finished(by: String?, start: Date, end: Date, details: FeedDetails, timeZoneID: String) -> String {
        let whose = by.map { "\($0)'s feed" } ?? "Feed"
        let length = GlanceText.spokenElapsed(end.timeIntervalSince(start))
        var said = "\(whose) finished at \(GlanceText.clock(end, timeZoneID: timeZoneID)), after \(length)."
        if let what = detailsSaid(details) { said += " \(what)" }
        return said
    }

    /// A feed running, started at 03:10: "Your feed is running, started at 03:10."
    static func running(by: String?, since: Date, timeZoneID: String) -> String {
        "\(by.map { "\($0)'s" } ?? "Your") feed is running, started at \(GlanceText.clock(since, timeZoneID: timeZoneID))."
    }

    /// "Left, then right. 90 ml of formula.", or nil with nothing logged.
    static func detailsSaid(_ details: FeedDetails) -> String? {
        var parts: [String] = []
        let sides = details.breast.map { $0.side == .left ? "left" : "right" }
        switch sides.count {
        case 0: break
        case 1: parts.append("\(sides[0].capitalized) side.")
        default: parts.append(upperFirst(sides.joined(separator: ", then ")) + ".")
        }
        for bottle in details.bottles {
            if let ml = bottle.ml {
                parts.append("\(ml) ml of \(milkName(bottle.milk)).")
            } else {
                parts.append("\(upperFirst(milkName(bottle.milk))), no amount.")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static let amountNotSaved = "The amount isn't saved. Add it in the app."

    /// The other parent saved the amount while Siri was asking: theirs is kept.
    static func amountAlreadySaved(_ ml: Int, _ milk: MilkKind) -> String {
        "\(ml) ml of \(milkName(milk)) was already saved, so it's kept."
    }

    /// The watch: the phone saved some of the answers, not all.
    static let notAllSaved = "Your iPhone couldn't save all of that. Check the feed in Little Log."

    /// "Log a medicine" with nothing on the household's list.
    static let noMedicines = "There are no medicines on your list. Add one in Little Log's Settings."

    /// "Add a bottle" saved: "60 ml of formula added to the 03:10 feed."
    static func bottleAdded(ml: Int?, milk: MilkKind, feedStart: Date, timeZoneID: String) -> String {
        let time = GlanceText.clock(feedStart, timeZoneID: timeZoneID)
        guard let ml else { return "\(upperFirst(milkName(milk))) added to the \(time) feed, with no amount." }
        return "\(ml) ml of \(milkName(milk)) added to the \(time) feed."
    }

    static let runningHasBottle = "This feed already has its bottle. Say \"Finish the feed in Little Log\" to give the amount."
    static let runningNotMine = "The other parent's feed is running. Only the parent who started it adds its bottle."
    static func alreadyHas(_ milk: MilkKind, feedStart: Date, timeZoneID: String) -> String {
        "The \(GlanceText.clock(feedStart, timeZoneID: timeZoneID)) feed already has \(milkName(milk)). Change it in the app."
    }
    static let noFeed = "There's no feed to add it to. Start a feed first."

    /// A nappy and its details: "Poo logged at 03:40, yellow, loose."
    static func nappy(at: Date, wee: Bool, poo: Bool, colour: PooColour?, consistency: PooConsistency?,
                      timeZoneID: String) -> String {
        let what = wee && poo ? "Wee and poo" : poo ? "Poo" : "Wee"
        var details: [String] = []
        if let colour { details.append(colourName(colour)) }
        if let consistency { details.append(textureName(consistency)) }
        let time = GlanceText.clock(at, timeZoneID: timeZoneID)
        return details.isEmpty ? "\(what) logged at \(time)." : "\(what) logged at \(time), \(details.joined(separator: ", "))."
    }

    static func medicine(_ name: String, at: Date, timeZoneID: String) -> String {
        "\(name) logged at \(GlanceText.clock(at, timeZoneID: timeZoneID))."
    }

    /// The watch, with no answer from the phone yet: the tap waits in the watch's queue, and goes
    /// when the phone is in reach.
    static let onItsWay = "It's on its way to your iPhone."
    /// The watch: the phone turned the tap down (the entry changed or went meanwhile).
    static let phoneRefused = "Your iPhone couldn't save that. Open Little Log on your iPhone."
    /// The watch, before the phone has sent anything.
    static let watchNotSetUp = "Open Little Log on your iPhone first."

    // MARK: Words

    private static func upperFirst(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    static func milkName(_ milk: MilkKind) -> String {
        milk == .formula ? "formula" : "expressed milk"
    }

    static func colourName(_ colour: PooColour) -> String {
        switch colour {
        case .yellow: "yellow"
        case .green: "green"
        case .brown: "brown"
        case .pale: "pale"
        default: "other colour"
        }
    }

    static func textureName(_ consistency: PooConsistency) -> String {
        switch consistency {
        case .liquid: "liquid"
        case .loose: "loose"
        case .firm: "firm"
        default: "other"
        }
    }
}

