import Foundation

// The Lock Screen's Sleep and nappy widget and the Control Center buttons for sleep, nappies and
// medicine (the users' choice F and the settled controls, 17 Nov 2026;
// `docs/planning/06-more-than-feeds.md`). Like the feed buttons, each runs in the app's process,
// so a tap saves and syncs as a tap in the app does. Facts only. None of it touches the alerts:
// `reconcile` counts feeds only.

/// What the Sleep and nappy widget and the Sleep control show: read from the household file, by
/// the widget extension as well as the app.
public struct CareGlance: Hashable, Sendable {
    /// Asleep (since when), awake (since when), or no sleep logged yet.
    public var sleep: SleepState
    /// The latest nappy change, and what it was. Nil before the first.
    public var lastNappyAt: Date?
    public var lastNappyWee: Bool
    public var lastNappyPoo: Bool
    /// The household's time zone, for showing times.
    public var timeZoneID: String

    public init(sleep: SleepState = .notLogged, lastNappyAt: Date? = nil, lastNappyWee: Bool = false,
                lastNappyPoo: Bool = false, timeZoneID: String = "Europe/London") {
        self.sleep = sleep
        self.lastNappyAt = lastNappyAt
        self.lastNappyWee = lastNappyWee
        self.lastNappyPoo = lastNappyPoo
        self.timeZoneID = timeZoneID
    }

    public var isAsleep: Bool {
        if case .asleep = sleep { return true }
        return false
    }

    /// When the baby fell asleep (while asleep) or woke up (while awake). Nil before the first
    /// sleep is logged.
    public var sleepSince: Date? {
        switch sleep {
        case .notLogged: nil
        case .asleep(_, let since): since
        case .awake(let since): since
        }
    }
}

/// What a quick sleep, nappy or medicine tap did.
public enum QuickCareResult: Hashable, Sendable {
    case fellAsleep(at: Date)
    /// A sleep is already running, so nothing was started.
    case alreadyAsleep(since: Date)
    case wokeUp(at: Date, asleepFor: TimeInterval)
    /// No sleep is running, so there was nothing to end.
    case notAsleep
    case nappy(at: Date, wee: Bool, poo: Bool)
    case medicine(at: Date, name: String)
}

extension HouseholdData {
    /// The facts for the Sleep and nappy widget and the Sleep control. Nil before there is a baby.
    public func careGlance(now: Date) -> CareGlance? {
        guard let babyID = currentBaby?.name else { return nil }
        let all = snapshots
        var glance = CareGlance(sleep: sleepState(all, babyID: babyID, now: now), timeZoneID: householdSettings.timeZoneID)
        if let nappy = lastNappy(all, babyID: babyID, now: now) {
            glance.lastNappyAt = nappy.at
            glance.lastNappyWee = nappy.wee
            glance.lastNappyPoo = nappy.poo
        }
        return glance
    }

    /// "Fell asleep" from outside the app. Nothing happens while a sleep runs. Sent at once: there
    /// is no Undo bar outside the app.
    public mutating func quickFellAsleep(babyID: String, by member: MemberID, timeZoneID: String, now: Date) -> QuickCareResult {
        if let running = sleepInProgress(babyID: babyID, now: now) { return .alreadyAsleep(since: running.event.startedAt) }
        let id = startSleep(babyID: babyID, by: member, timeZoneID: timeZoneID, now: now)
        events[id]?.uploadNotBefore = nil
        return .fellAsleep(at: now)
    }

    /// "Woke up" from outside the app: ends the sleep running now, whoever started it.
    public mutating func quickWokeUp(babyID: String, by member: MemberID, now: Date) -> QuickCareResult {
        guard let running = sleepInProgress(babyID: babyID, now: now) else { return .notAsleep }
        let ended = endSleep(babyID: babyID, by: member, now: now)
        guard !ended.isEmpty else { return .notAsleep }
        for id in ended { events[id]?.uploadNotBefore = nil }
        return .wokeUp(at: now, asleepFor: max(0, now.timeIntervalSince(running.event.startedAt)))
    }

    /// A nappy from outside the app: wee, poo or both, with no colour or consistency (the app's
    /// Nappy tile then offers "Add details").
    public mutating func quickNappy(babyID: String, wee: Bool, poo: Bool, by member: MemberID, timeZoneID: String,
                                    now: Date) -> QuickCareResult {
        let id = addNappy(babyID: babyID, wee: wee, poo: poo, by: member, timeZoneID: timeZoneID, now: now)
        events[id]?.uploadNotBefore = nil
        return .nappy(at: now, wee: wee, poo: poo)
    }

    /// A medicine from outside the app, named on the button. A blank name falls back to the first
    /// on the household's list.
    public mutating func quickMedicine(babyID: String, name: String, by member: MemberID, timeZoneID: String,
                                       now: Date) -> QuickCareResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = trimmed.isEmpty ? (medicines.first ?? Self.defaultMedicines[0]) : trimmed
        let id = addMedicine(babyID: babyID, MedicineDetails(name: chosen), by: member, timeZoneID: timeZoneID, now: now)
        events[id]?.uploadNotBefore = nil
        return .medicine(at: now, name: chosen)
    }
}
