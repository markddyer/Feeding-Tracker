import Foundation

/// The words on alarms and notifications. Plain facts about time since the last feed started:
/// never "due", "missed", "overdue" or "should", no targets and no verdicts (plan v1). The baby's
/// name is left out, so nothing personal shows on the Lock Screen.
public enum AlertText {
    /// Words alerts must never contain. The tests check every alert against this list.
    public static let forbiddenWords = ["due", "missed", "overdue", "should", "target", "late"]

    public static func title(for alert: DesiredAlert) -> String {
        let elapsed = duration(alert.fireDate.timeIntervalSince(alert.lastFeedStart))
        switch alert.purpose {
        case .windowOpens: return "May be ready to feed"
        case .windowCloses, .followUp: return "\(elapsed) since the last feed started"
        case .backup: return "No feed logged for \(elapsed)"
        }
    }

    public static func body(for alert: DesiredAlert, timeZone: TimeZone) -> String {
        let started = WallClock.reading(alert.lastFeedStart, in: timeZone).time
        switch alert.purpose {
        case .windowOpens: return "Watch for feeding cues. The last feed started at \(started)."
        case .windowCloses: return "The last feed started at \(started)."
        case .followUp: return "No feed logged since \(started)."
        case .backup: return "The last feed started at \(started). This alarm rings on both phones."
        }
    }

    /// "4 h", "4 h 10 min", "45 min". Rounded down to the minute.
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        switch (hours, rest) {
        case (0, let m): return "\(m) min"
        case (let h, 0): return "\(h) h"
        case (let h, let m): return "\(h) h \(m) min"
        }
    }
}
