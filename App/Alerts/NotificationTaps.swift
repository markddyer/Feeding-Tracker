import Darwin
import FeedingCore
import Foundation
import Observation
import SwiftUI
import UserNotifications

/// Shows the app's notifications while it is open, and opens Home at the top when a notification
/// about an ask is tapped, so its card is in view. (The first phone test of the night ask found
/// that a tap seemed to do nothing: the app opened wherever it was left.) A notice of a new first
/// opens that first's page (design review D18), at any hour (eng2 D1).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        #if FEEDING_DEV
        _ = await SpikeNotificationDelegate.shared.userNotificationCenter(center, willPresent: notification)
        #endif
        let identifier = notification.request.identifier
        // Feed alerts and asks answer at once, as before; only a new first's notice looks at the hour.
        // An alert stops a reply being read aloud, so it is heard (AI insights step 4, Y4).
        guard NotificationTaps.firstID(identifier) != nil else {
            await MainActor.run { ReadAloud.shared.alertCame() }
            return [.banner, .list, .sound]
        }
        let isNight = await MainActor.run {
            let settings = AppModel.shared.store.data.householdSettings
            if case .night = settings.dayHours.period(at: Date(), in: settings.timeZone) { return true }
            return false
        }
        return Self.presentation(for: identifier, isNight: isNight)
    }

    /// With the app open: a new first's notice in the list only at night, a banner with no sound
    /// by day (design review D19, outside voice OV6); every other notification as before.
    nonisolated static func presentation(for identifier: String, isNight: Bool) -> UNNotificationPresentationOptions {
        guard NotificationTaps.firstID(identifier) != nil else { return [.banner, .list, .sound] }
        return isNight ? [.list] : [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        #if FEEDING_DEV
        await SpikeNotificationDelegate.shared.userNotificationCenter(center, didReceive: response)
        #endif
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let identifier = response.notification.request.identifier
        if let first = NotificationTaps.firstID(identifier) {
            await MainActor.run { NotificationTaps.shared.showFirst(first) }
        } else if identifier == JournalExporter.noticeID {
            await MainActor.run { NotificationTaps.shared.showExport() }
        } else if identifier == HelpNotice.babyID {
            // A danger sign said to Siri on a locked phone (doc 15, V6 B).
            await MainActor.run {
                HelpNotice.clear()
                HelpPresenter.show()
            }
        } else if identifier == HelpNotice.parentID {
            await MainActor.run {
                HelpNotice.clear()
                NotificationTaps.shared.showAsk()
            }
        } else if NotificationTaps.opensHome(identifier) {
            await MainActor.run { NotificationTaps.shared.showHome() }
        }
    }
}

/// Asks the screens to go back to Home and scroll to its top.
@MainActor @Observable
final class NotificationTaps {
    static let shared = NotificationTaps()

    /// Goes up by one for each request; the screens watch it.
    private(set) var homeRequests = 0
    /// Goes up by one for each first to open; the screens watch it, and take `pendingFirst`.
    private(set) var firstRequests = 0
    /// The first a tap asked for, kept until the screens open it (a tap can come before they are
    /// there, when it starts the app).
    @ObservationIgnored private var pendingFirst: String?

    /// A notification was tapped since the app last left the screen: the return that comes with
    /// it, before or after, never overrides what was tapped (eng2 D1, OV1; Codex review of D40).
    @ObservationIgnored private(set) var tappedSinceLeaving = false
    /// Forms pushed on a screen's stack that are open now (Settings › Medicines): a night return
    /// keeps them, as it keeps a sheet (eng2 D3).
    @ObservationIgnored var formsOpen = 0

    private static let departureKey = "returnRule.leftAt"
    private static let departureBootKey = "returnRule.leftInBoot"

    /// The app left the screen: noted on the boot clock, kept across a launch (iOS may close the
    /// app meanwhile).
    func leftScreen() {
        tappedSinceLeaving = false
        UserDefaults.standard.set(BootClock.now(), forKey: Self.departureKey)
        UserDefaults.standard.set(BootClock.boot(), forKey: Self.departureBootKey)
    }

    /// The time since the app left the screen; nil when unknown.
    func timeAway() -> TimeInterval? {
        let defaults = UserDefaults.standard
        return ReturnRule.timeAway(leftAt: defaults.object(forKey: Self.departureKey) as? Double,
                                   leftInBoot: defaults.object(forKey: Self.departureBootKey) as? Int,
                                   now: BootClock.now(), boot: BootClock.boot())
    }

    /// Back on the screen: the departure is used once.
    func clearDeparture() {
        UserDefaults.standard.removeObject(forKey: Self.departureKey)
    }

    func showHome() {
        tappedSinceLeaving = true
        homeRequests += 1
    }

    /// Goes up by one for each tap on the export's notice; `pendingExport` holds it until the
    /// Journal opens the Export screen.
    private(set) var exportRequests = 0
    private(set) var pendingExport = false

    func showExport() {
        tappedSinceLeaving = true
        pendingExport = true
        exportRequests += 1
    }

    /// True once, when the export's notice was tapped.
    func takePendingExport() -> Bool {
        defer { pendingExport = false }
        return pendingExport
    }

    /// Goes up by one for each Siri question (AI insights step 4): the app goes to Home once no
    /// form is open (F13), then `askOpenRequests` opens Ask.
    private(set) var askRequests = 0
    /// Goes up by one when Home may open Ask; `takeAskOpen` says whether one waits.
    private(set) var askOpenRequests = 0
    @ObservationIgnored private var askOpenPending = false

    @ObservationIgnored private var askPending = false

    func showAsk() {
        tappedSinceLeaving = true
        askPending = true
        askRequests += 1
    }

    /// True once per Siri question: also when the request came before the screens were up, as on a
    /// cold launch from Siri (Codex step 4 review, 10).
    func takeAskRequest() -> Bool {
        defer { askPending = false }
        return askPending
    }

    /// Home is in front and no form is open: Ask may open.
    func openAsk() {
        askOpenPending = true
        askOpenRequests += 1
    }

    func takeAskOpen() -> Bool {
        defer { askOpenPending = false }
        return askOpenPending
    }

    func showFirst(_ id: String) {
        tappedSinceLeaving = true
        pendingFirst = id
        firstRequests += 1
    }

    /// The first waiting to be opened, once.
    func takePendingFirst() -> String? {
        defer { pendingFirst = nil }
        return pendingFirst
    }

    /// The first a notice is about, from its identifier (`NewFirstNotifier.prefix`).
    nonisolated static func firstID(_ identifier: String) -> String? {
        guard identifier.hasPrefix(NewFirstNotifier.prefix) else { return nil }
        let id = String(identifier.dropFirst(NewFirstNotifier.prefix.count))
        return id.isEmpty ? nil : id
    }

    /// The notifications whose tap opens Home: those about an ask (`NightAskNews.id`), and the
    /// feed alerts (`alert.`), so Start feed is in front (Codex review of D40).
    nonisolated static func opensHome(_ identifier: String) -> Bool {
        identifier.hasPrefix("nightAsk-") || identifier.hasPrefix("alert.")
    }
}

/// The phone's boot clock: seconds since it started, counting sleep (Darwin's `CLOCK_MONOTONIC`),
/// which setting the time can't move; and which boot it is, so two boots are never compared.
enum BootClock {
    static func now() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    static func boot() -> Int {
        var booted = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &booted, &size, nil, 0)
        return booted.tv_sec
    }
}

/// A form on a screen's stack (not a sheet): while it is open, a night return leaves it in front.
struct FormOnScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { NotificationTaps.shared.formsOpen += 1 }
            .onDisappear { NotificationTaps.shared.formsOpen = max(0, NotificationTaps.shared.formsOpen - 1) }
    }
}
