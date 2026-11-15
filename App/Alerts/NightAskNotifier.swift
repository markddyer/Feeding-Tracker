import FeedingCore
import Foundation
import UserNotifications

/// Tells a parent about asks with an ordinary notification (the user's choice of 15 Nov 2026):
/// "Alex asks you to take tonight" on the asked phone, and the answer on the asker's phone. Not
/// an alarm and not Time Sensitive, so silent mode and Focus apply as usual.
///
/// The phone works out the news from its own data whenever data arrives (a push wakes the app in
/// the background), and keeps a note of what it told, so each one is told once.
@MainActor
final class NightAskNotifier {
    private let defaults: UserDefaults
    private static let toldKey = "nightAskNewsTold"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The IDs of the news already told, newest last.
    private var told: [String] {
        get { defaults.stringArray(forKey: Self.toldKey) ?? [] }
        set { defaults.set(Array(newValue.suffix(50)), forKey: Self.toldKey) }
    }

    func update(data: HouseholdData, me: MemberID?, names: [MemberID: String], now: Date = Date()) async {
        guard let me else { return }
        let news = data.nightAskNews(me: me, now: now)
        let center = UNUserNotificationCenter.current()

        // An ask that is no longer open (answered, taken back, or the night is over) leaves the
        // lock screen.
        let open = Set(news.filter { if case .asked = $0 { true } else { false } }.map(\.id))
        let closed = told.filter { $0.hasSuffix("-asked") && !open.contains($0) }
        if !closed.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: closed)
        }

        let new = news.filter { !told.contains($0.id) }
        guard !new.isEmpty else { return }
        // Noted before sending, so two updates close together can't send one twice.
        told += new.map(\.id)
        for item in new {
            let other: MemberID = switch item {
            case .asked(let ask): ask.askedBy
            case .taken(_, let by), .declined(_, let by): by
            }
            let text = HomeText.askNotification(item, name: names[other] ?? "The other parent")
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.interruptionLevel = .active
            content.threadIdentifier = "nightAsk"
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
        }
    }
}
