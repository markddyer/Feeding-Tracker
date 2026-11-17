import FeedingCore
import SwiftUI
import UIKit

/// The colours from `DESIGN.md`, each with a day value and a night value.
///
/// The look sets the app's colour scheme (day is light, night is dark: see `LookModifier`), and
/// every colour here follows the colour scheme. So one name works in both looks, and sheets,
/// pickers and the keyboard switch with the rest. Change a value here only together with
/// `DESIGN.md`, and recheck its contrast.
enum Theme {
    static let background = Color(day: 0xFFF4E2, night: 0x0A0807)
    static let surface = Color(day: 0xFFE6C7, night: 0x1C1612)
    static let text = Color(day: 0x3A2A1E, night: 0xE8D6C2)
    static let textMuted = Color(day: 0x745F4E, night: 0x978472)
    /// The coral main button, and the time so far on the ring and the bar.
    static let primary = Color(day: 0xFF8E6E, night: 0xB9714F)
    static let onPrimary = Color(day: 0x3A1A0E, night: 0x120A06)
    /// The empty part of the ring and the window bar.
    static let track = Color(day: 0xFFE0BD, night: 0x231B15)
    /// The shaded feeding window on the bar.
    static let window = Color(day: 0xFFC9A8, night: 0x4A3022)

    // Kinds of feed: the plain colour fills big areas, `Mark` draws small shapes and chart bars,
    // `Tint` fills tiles and rows. At night the plain colour does the mark's job too.
    static let breast = Color(day: 0xF07C8F, night: 0xA85A68)
    static let breastMark = Color(day: 0xD2465F, night: 0xA85A68)
    static let breastTint = Color(day: 0xFFDDE3, night: 0x22151A)
    static let bottle = Color(day: 0x5FA8E8, night: 0x4A7299)
    static let bottleMark = Color(day: 0x2F7BC4, night: 0x4A7299)
    static let bottleTint = Color(day: 0xDCEEFF, night: 0x141B24)
    static let pump = Color(day: 0x4FB58C, night: 0x3D7A60)
    static let pumpMark = Color(day: 0x23885F, night: 0x3D7A60)
    static let pumpTint = Color(day: 0xD6F2E2, night: 0x121D17)

    // The Graphs tab (the user's choices of 16 Nov 2026). A second shade of a kind, beside its
    // mark in one bar or pair: expressed milk above formula, and the right breast beside the left.
    // At night they are lighter than the mark, so they still stand out on a dark tile.
    static let bottleSoft = Color(day: 0x5FA8E8, night: 0x6E93BA)
    static let breastSoft = Color(day: 0xF07C8F, night: 0xC27F8C)
    /// Bars that are no kind of feed (feeds per day, the time between feeds).
    static let chart = Color(day: 0x3A2A1E, night: 0x978472)
    /// The strip behind Home's 24-hour chart (the users' choice, 17 Nov 2026): deeper than `track`
    /// so it stands out from its card, but no deeper, or the feed blocks on it drop under 3:1.
    static let chartStrip = Color(day: 0xFCD5AE, night: 0x2A2119)

    // Sleep and nappies (06-more-than-feeds.md; the users accepted them with round two, 17 Nov
    // 2026). The same three jobs as a feed kind: plain, mark, tint. One tint for every nappy.
    static let sleep = Color(day: 0x8B8FE0, night: 0x6A6DB0)
    static let sleepMark = Color(day: 0x5A5EC4, night: 0x6A6DB0)
    static let sleepTint = Color(day: 0xE6E6FA, night: 0x15152A)
    /// Sleep in the day, beside night sleep (`sleepMark`) on the Graphs tab: lighter at night, as
    /// the other soft shades are.
    static let sleepSoft = Color(day: 0x8B8FE0, night: 0x9497D0)
    static let wee = Color(day: 0xF0C23B, night: 0x9C832F)
    static let weeMark = Color(day: 0x8F6D00, night: 0x9C832F)
    static let poo = Color(day: 0x9C6B3E, night: 0x9A6E48)
    static let pooMark = Color(day: 0x7E5128, night: 0x9A6E48)
    static let nappyTint = Color(day: 0xFFF0C8, night: 0x1E190C)
    /// A poo's colour, shown as a swatch beside its name ("Brown"): the colour it names, never a
    /// verdict. Always with its word, so it doesn't rely on colour.
    static let pooBrown = Color(day: 0x8B5A2B, night: 0x7A5434)
    static let pooYellow = Color(day: 0xD9A521, night: 0x9C7E2A)
    static let pooGreen = Color(day: 0x6E8B3D, night: 0x5E7A3A)

    // The two parents' default colours (sunflower and teal).
    static let parent1 = Color(day: 0xF2B33D, night: 0x9C7A30)
    static let onParent1 = Color(day: 0x3A1A0E, night: 0x120A06)
    static let parent1Tint = Color(day: 0xFDEBC4, night: 0x221B0E)
    static let parent2 = Color(day: 0x3FA796, night: 0x2A695E)
    static let onParent2 = Color(day: 0x3A1A0E, night: 0xE8D6C2)
    static let parent2Tint = Color(day: 0xD3EFEA, night: 0x0F1E1B)

    // The four other colours a parent can pick ("Your colour").
    static let lavender = Color(day: 0xA78BDF, night: 0x68568A)
    static let onLavender = Color(day: 0x3A1A0E, night: 0xE8D6C2)
    static let lavenderTint = Color(day: 0xE9E2F7, night: 0x17131E)
    static let plum = Color(day: 0x9E4F88, night: 0x6F375F)
    static let onPlum = Color(day: 0xFFF4E2, night: 0xE8D6C2)
    static let plumTint = Color(day: 0xE7D3E1, night: 0x180C15)
    static let caramel = Color(day: 0xC99260, night: 0x79583A)
    static let onCaramel = Color(day: 0x3A1A0E, night: 0xE8D6C2)
    static let caramelTint = Color(day: 0xF2E4D7, night: 0x1B130D)
    static let stone = Color(day: 0x9A948C, night: 0x615D58)
    static let onStone = Color(day: 0x3A1A0E, night: 0xE8D6C2)
    static let stoneTint = Color(day: 0xE6E4E2, night: 0x151513)

    /// Problems with the app only, such as sync failing. A muted orange, never red, and never
    /// about the baby.
    static let notice = Color(day: 0xE07A2F, night: 0xA0582A)

    // The names the screens used before the redesign. Each screen moves to the names above as it
    // is redesigned (`05-visual-redesign.md`, build order), and these go once none is left.
    static let secondaryText = textMuted
    static let accent = primary
    static let raisedSurface = track
    static let warning = notice
}

extension Color {
    /// A colour with a day value and a night value, given as 0xRRGGBB.
    init(day: UInt32, night: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? night : day)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

extension EnvironmentValues {
    /// The look on screen. The look sets the colour scheme, so the two always agree.
    var look: Look { colorScheme == .dark ? .night : .day }
}

extension LookSetting {
    /// Where this phone keeps its choice (`@AppStorage`). Feeding Dev can be launched with
    /// `-look.setting alwaysNight` (or `alwaysDay`, `matchPhone`) to pick a look for screenshots.
    static let storageKey = "look.setting"

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .alwaysDay: "Always day"
        case .alwaysNight: "Always night"
        case .matchPhone: "Match iPhone"
        }
    }
}

/// Sets the day or night look on the whole app (`DESIGN.md`, "Day and night"), switches it on
/// time, and cross-fades the change over 0.3 seconds.
struct LookModifier: ViewModifier {
    @AppStorage(LookSetting.storageKey) private var settingName = LookSetting.automatic.rawValue
    /// The phone's own Dark Mode when the setting is Match iPhone; otherwise the look itself.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    /// Moved on when the look is due to change, and whenever the clock may have jumped.
    @State private var now = Date()

    func body(content: Content) -> some View {
        let setting = LookSetting(rawValue: settingName) ?? .automatic
        let household = AppModel.shared.store.data.householdSettings
        let resolution = setting.resolve(dayHours: household.dayHours, timeZone: household.timeZone,
                                         phoneIsDark: colorScheme == .dark, now: now)
        // Match iPhone leaves the colour scheme to the phone. The others set it, so nothing
        // flashes white at night, sheets and the keyboard included.
        let scheme: ColorScheme? = setting == .matchPhone ? nil : (resolution.look == .night ? .dark : .light)
        content
            .preferredColorScheme(scheme)
            .onChange(of: scheme) { LookCrossFade.run() }
            .task(id: resolution.nextChange) {
                guard let next = resolution.nextChange else { return }
                // A little after the change, so the wall clock reads past it.
                try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 0.5))
                guard !Task.isCancelled else { return }
                now = Date()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = Date() }
            }
            // The clock set by hand, a time zone change, or a daylight saving change.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                now = Date()
            }
    }
}

/// A 0.3 second cross-fade between looks: a picture of the old screen laid on top, then faded
/// out. A fade only, so it suits the night look and Reduce Motion.
@MainActor
enum LookCrossFade {
    static func run() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let window, let picture = window.snapshotView(afterScreenUpdates: false) else { return }
        window.addSubview(picture)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            picture.alpha = 0
        } completion: { _ in
            picture.removeFromSuperview()
        }
    }
}
