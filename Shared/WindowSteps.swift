import CoreGraphics
import FeedingCore
import Foundation

// The feeding window bar's rules, shared by the phone (Home's top tile, `App/Home/WindowBar.swift`),
// the watch app and the watch face, so all three say and draw the same thing: one line in words
// (where now is, then what comes next), then the bar in parts, the wait after the feed, the
// feeding window, and (with alerts on) a short part up to the backup alarm. The window opens and
// never closes: past the alert it stays "In the feeding window" and only the colours deepen (the
// users' choices B and C and the follow-ups, 21 Nov 2026; `DESIGN.md`, "Window bar"). Facts only:
// "opens", "alert at", "backup alarm", "since". Never "closed", "due", "missed" or "overdue".

/// Where now is against the window: the parts of the bar, and the words for them.
struct WindowSteps {
    enum Phase: Equatable {
        case beforeWindow
        /// The window is open; the alert is still to come.
        case inWindow
        /// The window is still open, and the alert time has passed.
        case afterAlert
    }

    enum PartKind: Equatable {
        case sinceFeed
        case window
        case backup
    }

    /// One part of the bar, in seconds after the last feed started.
    struct Part: Equatable, Identifiable {
        let kind: PartKind
        let from: TimeInterval
        let to: TimeInterval
        var id: PartKind { kind }
    }

    let lastFeed: Date
    let opensAt: Date
    /// When the alert rings (`FeedWindow.closesAt`). The window stays open after it.
    let alertAt: Date
    /// When the backup alarm rings on both phones; nil with alerts off.
    let backupAt: Date?
    let alertsEnabled: Bool
    let now: Date

    init(window: FeedWindow, settings: FeedWindowSettings, now: Date) {
        lastFeed = window.lastFeedStart
        opensAt = window.opensAt
        alertAt = window.closesAt
        alertsEnabled = settings.alertsEnabled
        backupAt = settings.alertsEnabled && settings.backupAfterClose > 0
            ? window.closesAt.addingTimeInterval(settings.backupAfterClose) : nil
        self.now = now
    }

    var elapsed: TimeInterval { max(0, now.timeIntervalSince(lastFeed)) }

    var phase: Phase {
        if now >= alertAt { return .afterAlert }
        if now >= opensAt { return .inWindow }
        return .beforeWindow
    }

    /// The bar's parts, oldest first. A window that opens at the alert (or later) has no part of
    /// its own.
    var parts: [Part] {
        let opens = max(0, opensAt.timeIntervalSince(lastFeed))
        let closes = max(0, alertAt.timeIntervalSince(lastFeed))
        var parts: [Part] = []
        if min(opens, closes) > 0 { parts.append(Part(kind: .sinceFeed, from: 0, to: min(opens, closes))) }
        if closes > opens { parts.append(Part(kind: .window, from: opens, to: closes)) }
        if let backupAt, backupAt > alertAt {
            parts.append(Part(kind: .backup, from: closes, to: backupAt.timeIntervalSince(lastFeed)))
        }
        return parts
    }

    /// The parts with their times under the bar: the window and the backup. The last feed's time
    /// is in the tile, over the bar.
    var labelled: [Part] { parts.filter { $0.kind != .sinceFeed } }

    /// How full a part is now, from 0 to 1.
    func filled(_ part: Part) -> Double {
        guard part.to > part.from else { return elapsed >= part.to ? 1 : 0 }
        return min(1, max(0, (elapsed - part.from) / (part.to - part.from)))
    }

    /// The part now is in: the last one once the bar is full.
    var currentPart: PartKind? {
        parts.first { elapsed < $0.to }?.kind ?? parts.last?.kind
    }

    /// Each part's place on a bar `width` wide, with `gap` between parts. A part is never
    /// narrower than `minimum`, so the backup's short stretch stays visible.
    func frames(width: CGFloat, gap: CGFloat = 3, minimum: CGFloat = 26) -> [(part: Part, x: CGFloat, width: CGFloat)] {
        let parts = parts
        guard let total = parts.last?.to, total > 0 else { return [] }
        let room = max(0, width - gap * CGFloat(parts.count - 1))
        var widths = parts.map { room * CGFloat(($0.to - $0.from) / total) }
        // Give a short part its minimum, taken from the others in proportion.
        let short = widths.indices.filter { widths[$0] < minimum }
        let added = short.reduce(CGFloat(0)) { $0 + minimum - widths[$1] }
        let others = widths.indices.filter { !short.contains($0) }
        let othersWidth = others.reduce(CGFloat(0)) { $0 + widths[$1] }
        if added > 0, othersWidth > added {
            for i in short { widths[i] = minimum }
            for i in others { widths[i] -= added * widths[i] / othersWidth }
        }
        var x: CGFloat = 0
        return zip(parts, widths).map { part, partWidth in
            defer { x += partWidth + gap }
            return (part, x, partWidth)
        }
    }

    /// Where now sits on a bar `width` wide: inside the part it is in, at the bar's end once the
    /// bar is full.
    func nowX(width: CGFloat, gap: CGFloat = 3, minimum: CGFloat = 26) -> CGFloat {
        let frames = frames(width: width, gap: gap, minimum: minimum)
        guard let frame = frames.first(where: { $0.part.kind == currentPart }) else { return 0 }
        return frame.x + frame.width * filled(frame.part)
    }

    /// The line over the bar: where now is, then what comes next. "Window opens in 20m" · "at
    /// 15:22"; then "In the feeding window" · "alert at 17:22", · "backup alarm 17:52", and once
    /// both have rung · "since 15:22".
    /// `short`: "In the window", for a small watch, where the line has one row and the time after
    /// it must still show (outside review of step 2 of `11-watch-parity.md`).
    func line(_ clock: (Date) -> String, short: Bool = false) -> (main: String, more: String) {
        let off = alertsEnabled ? "" : " · alerts off"
        let inWindow = short ? "In the window" : "In the feeding window"
        switch phase {
        case .beforeWindow:
            return ("Window opens in \(GlanceText.elapsed(untilOpens))", " · at \(clock(opensAt))" + off)
        case .inWindow:
            return (inWindow, alertsEnabled ? " · alert at \(clock(alertAt))" : " · since \(clock(opensAt))" + off)
        case .afterAlert:
            if let backupAt, now < backupAt {
                return (inWindow, " · backup alarm \(clock(backupAt))")
            }
            return (inWindow, " · since \(clock(opensAt))" + off)
        }
    }

    /// The minutes to the window's opening, rounded up, so "in 0m" never shows before it opens.
    private var untilOpens: TimeInterval {
        (max(0, opensAt.timeIntervalSince(now)) / 60).rounded(.up) * 60
    }

    /// A part's name and times, under the bar.
    func label(_ kind: PartKind, _ clock: (Date) -> String) -> (name: String, time: String) {
        switch kind {
        case .sinceFeed: ("Last feed", clock(lastFeed))
        case .window: ("Feeding window", "from \(clock(opensAt))")
        case .backup: ("Backup", backupAt.map(clock) ?? "")
        }
    }

    /// The bar as sentences, for VoiceOver, after the tile's own "Last feed started …".
    func spoken(_ clock: (Date) -> String) -> String {
        let place = switch phase {
        case .beforeWindow: "The window opens in \(GlanceText.spokenElapsed(untilOpens))."
        case .inWindow, .afterAlert: "Now in the feeding window."
        }
        let alerts = backupAt.map { " Alert at \(clock(alertAt)), backup alarm at \(clock($0))." }
            ?? (alertsEnabled ? " Alert at \(clock(alertAt))." : " Alerts are off.")
        return "Feeding window from \(clock(opensAt)). \(place)\(alerts)"
    }
}
