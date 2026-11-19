import Foundation

/// Where the app opens when a parent comes back to it (design review D40; engineering re-review
/// eng2 D1 and D3). One rule for both a tap and a plain return:
/// - a tap on a notification, link or widget opens its own target, at any hour (eng2 D1);
/// - a plain return in the household's night hours, after more than 5 minutes away, opens Home's
///   main screen (screens pushed on Home closed), so Start feed is in front at 3am, unless a form
///   or panel is open: then nothing changes, so nothing typed is lost (eng2 D3);
/// - by day, or after a shorter time away, the app stays as it was.
public enum ReturnRule {
    /// How long away before a night return opens Home.
    public static let awayLongEnough: TimeInterval = 5 * 60

    public enum Outcome: Hashable, Sendable {
        /// Leave everything as it was.
        case stay
        /// Home's main screen.
        case home
        /// What was tapped.
        case tapped
    }

    /// The time away, from when the app left the screen to now, both read on the phone's boot
    /// clock (seconds since it started, counting sleep), which setting the time can't move. Kept
    /// across a launch, so a return after iOS closed the app counts too; nil from another boot
    /// (the phone was restarted: unknown), or with no departure noted.
    public static func timeAway(leftAt: Double?, leftInBoot: Int?, now: Double, boot: Int) -> TimeInterval? {
        guard let leftAt, leftInBoot == boot, now >= leftAt else { return nil }
        return now - leftAt
    }

    /// `awayFor`: the time since the app left the screen, on a clock that setting the time can't
    /// move (nil when unknown: the app was started afresh, which opens Home anyway).
    public static func outcome(tapped: Bool, awayFor: TimeInterval?, at now: Date, dayHours: DayHours,
                               timeZone: TimeZone, formOpen: Bool) -> Outcome {
        if tapped { return .tapped }
        guard let awayFor, awayFor > awayLongEnough, !formOpen else { return .stay }
        if case .night = dayHours.period(at: now, in: timeZone) { return .home }
        return .stay
    }
}
