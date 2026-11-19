import FeedingCore
import Foundation
import UserNotifications

/// Tells this parent when the other parent logs a first (journal plan, "The other phone is told of
/// a new first", X1, D8): an ordinary notification with no sound, "Alex logged a first: First
/// smile". Never an alarm and never time-sensitive. In the household's night hours it goes to the
/// list without lighting the screen (design review D19). A tap opens that first (D18).
///
/// It starts once an alert run is over, from the data that run planned the alerts from (outside
/// review O8), and runs on its own, so nothing here can hold up an alarm. Each phone can turn it
/// off in Settings. It keeps a note of the firsts it has seen, so it tells of each new one once,
/// and of none that came with the household's first fetch after setting up or reinstalling.
@MainActor
final class NewFirstNotifier {
    /// "Tell me about new firsts" in Settings, on this phone. On unless turned off.
    static let wantedKey = "journal.newFirstNotices"
    private static let knownKey = "journal.knownFirsts"
    private static let toldKey = "journal.newFirstsTold"
    /// Every notice's identifier starts with this, then the first's ID.
    nonisolated static let prefix = "newFirst-"

    private let defaults: UserDefaults
    private let center: NoticeCenter

    init(defaults: UserDefaults, center: NoticeCenter = UNUserNotificationCenter.current()) {
        self.defaults = defaults
        self.center = center
    }

    /// Which firsts to tell of, and the firsts seen so far (nil: note nothing yet).
    struct Plan: Equatable {
        var tell: [String]
        var known: Set<String>?
    }

    /// The pure part, for the tests. `known` is nil until the household is on this phone (a full
    /// fetch has finished, the baby is here, and the file isn't filling again from iCloud): that
    /// run only notes every first it holds, so none from the first download is told.
    static func plan(firsts: [Event], known: Set<String>?, told: Set<String>, householdHere: Bool, me: MemberID,
                     wanted: Bool, dayHours: DayHours, timeZone: TimeZone, now: Date) -> Plan {
        let ids = Set(firsts.map(\.id))
        guard let known else { return Plan(tell: [], known: householdHere ? ids : nil) }
        let tell = firsts
            .filter { !told.contains($0.id) }
            .filter {
                NewFirstRule.notice(for: $0, heldBefore: known.contains($0.id), isInitialFetch: false, me: me,
                                    wanted: wanted, dayHours: dayHours, timeZone: timeZone, now: now) != nil
            }
            .sorted { ($0.serverCreatedAt ?? .distantPast, $0.id) < ($1.serverCreatedAt ?? .distantPast, $1.id) }
            .map(\.id)
        // A first chosen to tell of becomes known only once its notice has gone, so one that
        // couldn't be sent is tried again next time.
        return Plan(tell: tell, known: known.union(ids).subtracting(tell))
    }

    /// The notices still in Notification Center whose first was deleted or undone since: taken
    /// back. Not while the file fills again from iCloud, when a first can be missing for a while.
    static func takeBack(delivered: [String], firsts: [Event], refilling: Bool) -> [String] {
        guard !refilling else { return [] }
        let live = Set(firsts.filter { $0.deletedAt == nil }.map(\.id))
        return delivered.filter { $0.hasPrefix(prefix) && !live.contains(String($0.dropFirst(prefix.count))) }
    }

    /// `planned` is the data the alerts were just planned from; `current` is read again before
    /// each notice, so a first deleted, a switch turned off or night starting meanwhile counts.
    func update(planned: HouseholdData, current: () -> HouseholdData, me: MemberID?, names: [MemberID: String],
                fetchedOnce: Bool) async {
        guard let me else { return }
        let now = Date()
        let refilling = planned.isWaitingForICloud(now: now)
        let firsts = planned.allEvents.filter { $0.kind == .milestone }
        let knownBefore = defaults.stringArray(forKey: Self.knownKey).map(Set.init)
        let told = defaults.stringArray(forKey: Self.toldKey) ?? []
        let settings = planned.householdSettings
        let plan = Self.plan(firsts: firsts, known: knownBefore, told: Set(told),
                             householdHere: fetchedOnce && planned.currentBaby != nil && !refilling, me: me,
                             wanted: wanted, dayHours: settings.dayHours, timeZone: settings.timeZone, now: now)
        if let known = plan.known, known != knownBefore { defaults.set(known.sorted(), forKey: Self.knownKey) }

        let delivered = await center.deliveredIDs()
        let gone = Self.takeBack(delivered: delivered, firsts: current().allEvents.filter { $0.kind == .milestone },
                                 refilling: refilling)
        if !gone.isEmpty { center.remove(gone) }

        for id in plan.tell {
            // Checked again now: still there, still wanted, and the level for this moment.
            let data = current()
            let live = data.householdSettings
            guard let first = data.events[id]?.snapshot,
                  let notice = NewFirstRule.notice(for: first.event, heldBefore: false, isInitialFetch: false, me: me,
                                                   wanted: wanted, dayHours: live.dayHours, timeZone: live.timeZone,
                                                   now: Date()) else { continue }
            // Noted before sending, so two runs close together can't tell of one twice; taken off
            // again if it couldn't be sent, so the next run tries it again.
            remember(id)
            let content = UNMutableNotificationContent()
            content.body = JournalText.newFirstNotice(name: names[first.event.loggedBy] ?? "The other parent",
                                                      title: first.payload?.milestone?.title)
            // No sound, ever: an ordinary notice by day, the list only at night.
            content.sound = nil
            content.interruptionLevel = notice == .listOnly ? .passive : .active
            content.threadIdentifier = "newFirst"
            content.userInfo = ["firstID": id]
            do {
                try await center.add(UNNotificationRequest(identifier: Self.prefix + id, content: content, trigger: nil))
                know(id)
            } catch {
                forget(id)
            }
        }
    }

    private var wanted: Bool { defaults.object(forKey: Self.wantedKey) as? Bool ?? true }

    private func remember(_ id: String) {
        let told = defaults.stringArray(forKey: Self.toldKey) ?? []
        defaults.set(Array((told + [id]).suffix(500)), forKey: Self.toldKey)
    }

    private func know(_ id: String) {
        let known = defaults.stringArray(forKey: Self.knownKey) ?? []
        guard !known.contains(id) else { return }
        defaults.set((known + [id]).sorted(), forKey: Self.knownKey)
    }

    private func forget(_ id: String) {
        let told = defaults.stringArray(forKey: Self.toldKey) ?? []
        defaults.set(told.filter { $0 != id }, forKey: Self.toldKey)
    }
}

/// The part of Notification Center the notice uses, so the tests can stand in for it.
@MainActor
protocol NoticeCenter {
    func add(_ request: UNNotificationRequest) async throws
    func deliveredIDs() async -> [String]
    func remove(_ identifiers: [String])
}

extension UNUserNotificationCenter: NoticeCenter {
    func deliveredIDs() async -> [String] {
        await deliveredNotifications().map(\.request.identifier)
    }

    func remove(_ identifiers: [String]) {
        removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
