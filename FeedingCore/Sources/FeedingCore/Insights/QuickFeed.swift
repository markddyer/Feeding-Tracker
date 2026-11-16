import Foundation

// Starting and finishing a feed without opening the app (plan v1, Phase 2; the user's choice of
// 16 Nov 2026): a Control Center or Lock Screen control, the Action Button and Siri. The app runs
// these in its own process, so a feed started this way sets the alarms and syncs like a tap in
// the app. The Lock Screen widget shows `FeedGlance`.

/// What the Lock Screen widget and the control show: read from the household file, by the widget
/// extension as well as the app.
public struct FeedGlance: Hashable, Sendable {
    /// The start of the latest feed, running or not. Nil before the first feed.
    public var lastFeedStart: Date?
    /// The start of the feed running now, if any.
    public var runningSince: Date?
    /// When the feeding window opens and closes, counted from the last feed's start.
    public var windowOpens: Date?
    public var windowCloses: Date?
    /// The household's time zone, for showing times.
    public var timeZoneID: String

    public init(lastFeedStart: Date? = nil, runningSince: Date? = nil, windowOpens: Date? = nil, windowCloses: Date? = nil,
                timeZoneID: String = "Europe/London") {
        self.lastFeedStart = lastFeedStart
        self.runningSince = runningSince
        self.windowOpens = windowOpens
        self.windowCloses = windowCloses
        self.timeZoneID = timeZoneID
    }

    /// How far through the window the time since the last feed is at `now`, from 0 to 1.
    public func windowProgress(at now: Date) -> Double {
        guard let lastFeedStart, let windowCloses, windowCloses > lastFeedStart else { return 0 }
        return min(1, max(0, now.timeIntervalSince(lastFeedStart) / windowCloses.timeIntervalSince(lastFeedStart)))
    }
}

/// What a quick start or finish did.
public enum QuickFeedResult: Hashable, Sendable {
    /// A feed started now, with the bottle chosen on the button, or with nothing chosen: the
    /// sides and bottles are then added in the app.
    case started(id: String, at: Date, bottle: MilkKind?)
    /// A feed is already running, so nothing was started.
    case alreadyRunning(EventSnapshot)
    /// The running feed was finished. `by` is who started it.
    case finished(EventSnapshot)
    /// No feed is running, so there was nothing to finish.
    case nothingRunning
}

extension HouseholdData {
    /// The baby the screens show: the first one not archived.
    public var currentBaby: PlainRecord? {
        plainRecords(of: .baby).first { $0.archivedAt == nil }
    }

    /// The facts for the Lock Screen widget and the control. Nil before there is a baby.
    public func glance(now: Date) -> FeedGlance? {
        guard let babyID = currentBaby?.name else { return nil }
        let settings = householdSettings
        var glance = FeedGlance(timeZoneID: settings.timeZoneID)
        glance.lastFeedStart = allEvents.latestFeedStart(babyID: babyID, now: now)
        glance.runningSince = feedInProgress(babyID: babyID)?.event.startedAt
        if let start = glance.lastFeedStart {
            let window = FeedWindow(lastFeedStart: start, settings: settings.window)
            glance.windowOpens = window.opensAt
            glance.windowCloses = window.closesAt
        }
        return glance
    }

    /// "Start feed" from outside the app, with a bottle when the button names one ("Formula").
    /// Nothing happens when a feed is already running, as the app shows that feed's buttons
    /// instead of Start feed. Sent at once: there is no Undo bar outside the app (Stop · discard in
    /// the app removes a feed started by mistake).
    public mutating func quickStartFeed(babyID: String, bottle: MilkKind? = nil, by member: MemberID, timeZoneID: String,
                                        now: Date) -> QuickFeedResult {
        if let running = feedInProgress(babyID: babyID) { return .alreadyRunning(running) }
        let id = startFeed(babyID: babyID, side: nil, bottle: bottle, by: member, timeZoneID: timeZoneID, now: now)
        events[id]?.uploadNotBefore = nil
        return .started(id: id, at: now, bottle: bottle)
    }

    /// "Finish feed" from outside the app: finishes the feed running now, whoever started it, as
    /// the app's Finish and "Finish for Sam" do.
    public mutating func quickFinishFeed(babyID: String, by member: MemberID, now: Date) -> QuickFeedResult {
        guard let running = feedInProgress(babyID: babyID) else { return .nothingRunning }
        _ = finishFeed(running.id, by: member, now: now)
        events[running.id]?.uploadNotBefore = nil
        return .finished(events[running.id]?.snapshot ?? running)
    }
}
