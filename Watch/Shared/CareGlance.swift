import FeedingCore
import SwiftUI

// Sleep and nappies on the watch (`06-more-than-feeds.md`, pick I and the watch face pieces,
// 17 Nov 2026), shared by the watch app and the watch face. Facts only: how long and when. No
// "due", "missed", "overdue" or "should".

enum CareText {
    /// "Asleep", "Awake", or "Sleep" before the first sleep is logged.
    static func sleepLabel(_ sleep: WatchSleep?) -> String {
        guard let sleep else { return "Sleep" }
        return sleep.asleep ? "Asleep" : "Awake"
    }

    /// "Asleep 1 hour, 20 minutes", for VoiceOver.
    static func spokenSleep(_ sleep: WatchSleep?, now: Date) -> String {
        guard let sleep else { return "No sleep logged yet" }
        return "\(sleepLabel(sleep)) \(GlanceText.spokenElapsed(now.timeIntervalSince(sleep.since)))"
    }

    /// "40m ago", or "just now" in the first minute.
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        return seconds < 60 ? "just now" : "\(GlanceText.elapsed(seconds)) ago"
    }

    /// "Wee", "Poo", "Wee and poo", or "Dry".
    static func nappyKind(wee: Bool, poo: Bool) -> String {
        switch (wee, poo) {
        case (true, true): "Wee and poo"
        case (true, false): "Wee"
        case (false, true): "Poo"
        case (false, false): "Dry"
        }
    }

    /// A poo's colour, as the phone names it (`App/Home/CareText.swift`), in lower case for a line.
    static func colourName(_ colour: PooColour) -> String {
        switch colour {
        case .brown: "brown"
        case .yellow: "yellow"
        case .green: "green"
        case .other: "other colour"
        default: colour.rawValue
        }
    }

    static func consistencyName(_ consistency: PooConsistency) -> String {
        switch consistency {
        case .liquid: "liquid"
        case .loose: "loose"
        case .firm: "firm"
        default: consistency.rawValue
        }
    }

    /// "09:10" today, "yesterday", or "19 Nov": the phone's Medicine and Bath tiles' words, shorter
    /// for the watch (no time for an earlier day).
    static func lastGiven(_ date: Date, now: Date, timeZoneID: String) -> String {
        let zone = TimeZone(identifier: timeZoneID) ?? .current
        let time = GlanceText.clock(date, timeZoneID: timeZoneID)
        let day = PlainDate(date, in: zone)
        let today = PlainDate(now, in: zone)
        if day == today { return time }
        if day == today.adding(days: -1) { return "yesterday" }
        return date.formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated))
    }

    /// "Nappy, wee and poo, 40 minutes ago", for VoiceOver.
    static func spokenNappy(_ nappy: WatchNappy?, now: Date) -> String {
        guard let nappy else { return "No nappy logged yet" }
        let seconds = now.timeIntervalSince(nappy.at)
        let when = seconds < 60 ? "just now" : "\(GlanceText.spokenElapsed(seconds)) ago"
        // A poo's colour and consistency too, once added, as the row shows them (outside review of
        // step 1, P3).
        let details = [nappy.colour.map(colourName), nappy.consistency.map(consistencyName)].compactMap { $0 }
        return (["Nappy", nappyKind(wee: nappy.wee, poo: nappy.poo).lowercased()] + details + [when]).joined(separator: ", ")
    }
}

/// A nappy's shape: the drop for wee, the swirl for poo, both side by side for both. A dry nappy
/// shows the drop. With no colours given, both take the foreground (the watch face's tint).
struct NappyMark: View {
    let wee: Bool
    let poo: Bool
    let size: CGFloat
    var weeColour: Color?
    var pooColour: Color?

    var body: some View {
        HStack(spacing: -size * 0.18) {
            if wee || !poo {
                shape(DropShape(), weeColour)
            }
            if poo {
                shape(PooShape(), pooColour)
            }
        }
        .accessibilityHidden(true)
    }

    private func shape<S: Shape>(_ shape: S, _ colour: Color?) -> some View {
        shape
            .fill(colour.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
            .frame(width: size, height: size)
    }
}
