import Foundation
@testable import FeedingCore

let london = TimeZone(identifier: "Europe/London")!
let utc = TimeZone(secondsFromGMT: 0)!

/// An instant from a wall-clock reading in `timeZone`. Only use readings that exist once.
func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, in timeZone: TimeZone = london) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    return calendar.date(from: components)!
}

func date(_ string: String) -> PlainDate { PlainDate(string)! }

func time(_ string: String) -> TimeOfDay { TimeOfDay(string)! }

extension TimeInterval {
    static func minutes(_ n: Double) -> TimeInterval { n * 60 }
    static func hours(_ n: Double) -> TimeInterval { n * 3600 }
}

let parentA: MemberID = "parent-a"
let parentB: MemberID = "parent-b"
let baby = "baby-1"

/// Parent A is on duty on the night of 2026-11-13 and every second night from it.
let rotaFrom13Nov = Rota(startDate: date("2026-11-13"), firstOnDuty: parentA, secondOnDuty: parentB)

func feed(_ start: Date, id: String = UUID().uuidString, babyID: String = baby, kind: EventKind = .feed,
          deletedAt: Date? = nil, serverCreatedAt: Date? = nil) -> Event {
    Event(id: id, babyID: babyID, kind: kind, startedAt: start, timeZoneID: "Europe/London", loggedBy: parentA,
          createdAt: start, modifiedAt: start, deletedAt: deletedAt, serverCreatedAt: serverCreatedAt)
}

/// Runs `reconcile` with the defaults most tests share.
func run(
    _ events: [Event],
    me: MemberID = parentA,
    preferences: MemberPreferences = .init(),
    lastForegroundAt: Date? = nil,
    settings: HouseholdSettings = .init(),
    claims: [NightClaim] = [],
    pending: [PendingChange] = [],
    now: Date
) -> [DesiredAlert] {
    reconcile(
        events: events,
        settings: settings,
        roster: DutyRoster(rota: rotaFrom13Nov, claims: claims),
        pendingChanges: pending,
        me: Me(id: me, preferences: preferences, lastForegroundAt: lastForegroundAt),
        now: now
    )
}

/// A compact description of alerts, for readable expectations: "windowCloses.alarm@03:00".
func summary(_ alerts: [DesiredAlert], in timeZone: TimeZone = london) -> [String] {
    alerts.map { alert in
        let reading = WallClock.reading(alert.fireDate, in: timeZone)
        let seconds = Int(alert.fireDate.timeIntervalSince1970) % 60
        let suffix = seconds == 0 ? "" : ":\(seconds)"
        return "\(alert.purpose.rawValue).\(alert.mechanism.rawValue)@\(reading.time)\(suffix)"
    }
}

/// An event with decoded details, for the details, merge and insight tests.
func snapshot(_ start: Date, id: String = UUID().uuidString, babyID: String = baby, kind: EventKind = .feed,
              by: MemberID = parentA, createdAt: Date? = nil, deletedAt: Date? = nil,
              payload: EventPayload? = EventPayload()) -> EventSnapshot {
    EventSnapshot(
        event: Event(id: id, babyID: babyID, kind: kind, startedAt: start, timeZoneID: "Europe/London", loggedBy: by,
                     createdAt: createdAt ?? start, modifiedAt: createdAt ?? start, deletedAt: deletedAt),
        payload: payload)
}

/// A feed payload with one breast segment per side given, in order.
func breast(_ sides: BreastSide...) -> EventPayload {
    EventPayload(feed: FeedDetails(breast: sides.map { BreastSegment(side: $0) }))
}

func bottles(_ items: (MilkKind, Int?)...) -> EventPayload {
    EventPayload(feed: FeedDetails(bottles: items.map { Bottle(milk: $0.0, ml: $0.1) }))
}
