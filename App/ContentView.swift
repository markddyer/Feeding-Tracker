import FeedingCore
import SwiftUI

/// The app's root: once there is a household, four tabs (Home, History and Graphs, the user's
/// choice of 16 Nov 2026, and the Journal, design review D27), with Settings in Home's top bar. Both are system bars, so the iPhone
/// Duo moves them into its side bar by itself.
struct ContentView: View {
    private let model = AppModel.shared
    @AppStorage("setup.disclaimerSeen") private var disclaimerSeen = false
    @AppStorage("setup.inviteOffered") private var inviteOffered = false
    @AppStorage("setup.permissionsAsked") private var permissionsAsked = false
    @AppStorage(FeedingStyle.storageKey) private var feedingStyle = ""
    @AppStorage(LookSetting.storageKey) private var lookSetting = LookSetting.automatic.rawValue
    /// The last tap's Undo, shown under the home screen's buttons, from either column.
    @State private var undo: UndoAction?
    /// The arrangement's width and the home column's width. The second column is showing when the
    /// home column is clearly narrower than the whole (`ArrangementView` gives no direct signal).
    @State private var arrangementWidth: CGFloat = 0
    @State private var homeWidth: CGFloat = 0
    /// The screens opened from Home's top bar, so a tapped notification can go back to Home.
    @State private var path = NavigationPath()
    /// The Journal tab's screens, so a notice of a new first can open that first's page.
    @State private var journalPath = NavigationPath()
    /// A first a tapped notice asked for, handed to the Journal to open (`JournalView.openTarget`).
    @State private var journalTarget: String?
    @State private var tab: MainTab = Self.firstTab
    @Environment(\.scenePhase) private var scenePhase

    private enum MainTab: String, Hashable { case home, history, graphs, journal }
    /// The last tab, kept by iOS if it closes the app in the background, so a day return finds it
    /// (Codex review of D40); not after the parent quits the app.
    @SceneStorage("mainTab") private var savedTab: String?

    private enum Screen: Hashable {
        case settings
        #if FEEDING_DEV
        case tests
        #endif
    }

    /// Home, or in Feeding Dev the tab named by `-startTab history`, `graphs` or `journal` (for screenshots).
    private static var firstTab: MainTab {
        #if FEEDING_DEV
        switch UserDefaults.standard.string(forKey: "startTab") {
        case "history": return .history
        case "graphs": return .graphs
        case "journal": return .journal
        default: return .home
        }
        #else
        return .home
        #endif
    }

    private var secondColumnShowing: Bool {
        DayColumn.isShowing(homeWidth: homeWidth, arrangementWidth: arrangementWidth)
    }

    var body: some View {
        #if FEEDING_DEV
        if let screen = UserDefaults.standard.string(forKey: "openScreen"), let me = model.me, let baby = model.baby {
            DevScreen(name: screen, me: me, babyID: baby.name)
                .tint(Theme.accent)
        } else {
            main
        }
        #else
        main
        #endif
    }

    private var main: some View {
        Group {
            #if FEEDING_DEV
            if UserDefaults.standard.bool(forKey: "designGallery") {
                NavigationStack { DesignGalleryView() }
            } else {
                root
            }
            #else
            root
            #endif
        }
        // A tapped notification about an ask goes back to Home, where its card is.
        .onChange(of: NotificationTaps.shared.homeRequests) {
            path = NavigationPath()
            tab = .home
        }
        // A tapped notice of a new first opens its page, at any hour (design review D18, eng2 D1);
        // also when the tap started the app, before these screens were there.
        .onChange(of: NotificationTaps.shared.firstRequests) { openTappedFirst() }
        // At night, coming back after more than 5 minutes away opens Home (D40).
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background { NotificationTaps.shared.leftScreen() }
            if phase == .active { cameBack() }
        }
        .onChange(of: tab) { savedTab = tab.rawValue }
        .onAppear {
            #if FEEDING_DEV
            guard UserDefaults.standard.string(forKey: "startTab") == nil else { return }
            #endif
            if let savedTab, let restored = MainTab(rawValue: savedTab) { tab = restored }
        }
        .onChange(of: journalReady, initial: true) {
            openTappedFirst()
            // The export's notice that started the app: the Journal opens its Export screen.
            if journalReady, NotificationTaps.shared.pendingExport { tab = .journal }
        }
        // The export's notice: the Journal tab, which opens the Export screen as it was left.
        .onChange(of: NotificationTaps.shared.exportRequests) { if journalReady { tab = .journal } }
        .onChange(of: feedingStyle, initial: true) {
            model.widgets.feedingStyleChanged(feedingStyle)
            model.watch.update(model)
        }
        // The watch shows the same look as this phone.
        .onChange(of: lookSetting) {
            model.watch.update(model)
        }
        // Coral for controls (switches, pickers); the top bar's buttons use the text colour
        // as in the approved mockup, because coral text on cream is hard to read.
        .tint(Theme.accent)
        #if FEEDING_DEV
        .modifier(AlarmSpikeHooks())
        #endif
    }

    @ViewBuilder
    private var root: some View {
        if SetupView.isComplete(disclaimerSeen: disclaimerSeen, inviteOffered: inviteOffered,
                                permissionsAsked: permissionsAsked, feedingStyle: feedingStyle),
           let me = model.me, let baby = model.baby {
            TabView(selection: $tab) {
                Tab("Home", systemImage: "house", value: MainTab.home) {
                    home(me: me, babyID: baby.name)
                        .tint(Theme.accent)
                }
                Tab("History", systemImage: "clock.arrow.circlepath", value: MainTab.history) {
                    NavigationStack { HistoryView() }
                        .tint(Theme.accent)
                }
                Tab("Graphs", systemImage: "chart.bar", value: MainTab.graphs) {
                    NavigationStack { GraphsView() }
                        .tint(Theme.accent)
                }
                Tab("Journal", systemImage: "book.closed", value: MainTab.journal) {
                    // Never coral here: coral is for Start feed only (design review D5).
                    NavigationStack(path: $journalPath) {
                        JournalView(me: me, babyID: baby.name, path: $journalPath, target: $journalTarget)
                    }
                    .tint(Theme.text)
                }
            }
            // The chosen tab in the text colour, as the top bar's buttons: coral on cream is hard
            // to read. Each tab sets coral again for its own controls.
            .tint(Theme.text)
        } else {
            NavigationStack {
                SetupView()
                    .navigationTitle("Little Log")
                    .toolbar(removing: .title)
                    .modifier(TopBar(settings: model.baby != nil))
            }
        }
    }

    /// Back on the screen (design review D40, eng2 D1 and D3, `ReturnRule`): at night after more
    /// than 5 minutes away, Home's main screen, so Start feed is in front; never over a tap just
    /// made, and never with a form or panel open (nothing typed is lost); by day, as it was. A tap
    /// that comes after this still opens its own target.
    private func cameBack() {
        let taps = NotificationTaps.shared
        var away = taps.timeAway()
        taps.clearDeparture()
        Task {
            // A tap can arrive just after the return: it is given a moment, then wins (OV1).
            try? await Task.sleep(for: .milliseconds(800))
            guard journalReady else { return }
            let settings = model.store.data.householdSettings
            var now = Date()
            #if FEEDING_DEV && targetEnvironment(simulator)
            // `-pretendReturn night` (or `day`): as if back at 03:00 (or 14:00) on the household's
            // clock after 10 minutes away (tap tests); only on a real return.
            if let pretend = UserDefaults.standard.string(forKey: "pretendReturn"), away != nil {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = settings.timeZone
                away = 600
                now = calendar.date(bySettingHour: pretend == "night" ? 3 : 14, minute: 0, second: 0, of: Date()) ?? now
            }
            #endif
            let outcome = ReturnRule.outcome(tapped: taps.tappedSinceLeaving, awayFor: away, at: now,
                                             dayHours: settings.dayHours, timeZone: settings.timeZone,
                                             formOpen: Self.somethingOpen() || taps.formsOpen > 0)
            guard outcome == .home else { return }
            path = NavigationPath()
            tab = .home
        }
    }

    /// True while a form, panel or question is open over the tabs.
    private static func somethingOpen() -> Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
    }

    /// The tabs are showing (setup is done), so the Journal can open a tapped first.
    private var journalReady: Bool {
        SetupView.isComplete(disclaimerSeen: disclaimerSeen, inviteOffered: inviteOffered,
                             permissionsAsked: permissionsAsked, feedingStyle: feedingStyle)
            && model.me != nil && model.baby != nil
    }

    /// The first a notice was tapped for goes to the Journal tab, which opens it once it can;
    /// until the tabs are showing, it stays waiting (Codex review of X1).
    private func openTappedFirst() {
        guard journalReady, let id = NotificationTaps.shared.takePendingFirst() else { return }
        tab = .journal
        journalTarget = id
    }

    private func home(me: MemberID, babyID: String) -> some View {
        NavigationStack(path: $path) {
            // The unfolded iPhone Duo shows the day's tiles and feeds beside the home screen;
            // anywhere narrower shows the home screen alone (`05-visual-redesign.md`, "The Duo
            // unfolded"). On a real Duo the column shows open flat and in book pose, and hides
            // closed, in tent, in laptop pose and in Split View, with no code of ours.
            ArrangementView {
                HomeView(me: me, babyID: babyID, undo: $undo)
                    .environment(\.secondColumnShowing, secondColumnShowing)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { homeWidth = $0 }
            } secondary: {
                DayColumn(me: me, babyID: babyID, onUndo: { undo = $0 })
            }
            .arrangementViewStyle(.split.axes(.horizontal))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { arrangementWidth = $0 }
            // The page shows the greeting and the baby's name, so the bar shows only its
            // buttons. "Home" is still the back button's name on the next screen.
            .navigationTitle("Home")
            .toolbar(removing: .title)
            .modifier(TopBar(settings: true))
        }
    }

    /// Settings (and, in Feeding Dev, the tests) in the top bar, and the screens they open.
    private struct TopBar: ViewModifier {
        let settings: Bool

        func body(content: Content) -> some View {
            content
                .toolbar {
                    if settings {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink(value: Screen.settings) {
                                Label("Settings", systemImage: "gearshape")
                            }
                            .tint(Theme.text)
                        }
                    }
                    #if FEEDING_DEV
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(value: Screen.tests) {
                            Label("Tests", systemImage: "testtube.2")
                        }
                        .tint(Theme.text)
                    }
                    #endif
                }
                .navigationDestination(for: Screen.self) { screen in
                    switch screen {
                    case .settings: SettingsView()
                    #if FEEDING_DEV
                    case .tests: SpikeMenu()
                    #endif
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if FEEDING_DEV
/// The overnight alarm test watches from the app's first screen, as it did before the home screen.
struct AlarmSpikeHooks: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await AlarmSpikeStore.shared.observeAlarms() }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                AlarmSpikeStore.shared.recordAppActive()
                Task { await AlarmSpikeStore.shared.collectDeliveredNotifications() }
            }
    }
}

/// Feeding Dev only: one screen opened straight away, for screenshots. Launch with
/// `-openScreen history`, `settings`, `graphs`, `duo`, `earlierFeed`, `pumping`, `editLastFeed`,
/// `addFirst` (with `-firstTitle "First smile"` to fill What happened) or `firstPage` (with
/// `-firstID`, the sample first's ID; `sample-first-smile` by default, with `-sampleFirsts YES`),
/// or the move's two screens, `moveOut` and `moveIn` (`08-going-live.md`).
struct DevScreen: View {
    let name: String
    let me: MemberID
    let babyID: String

    var body: some View {
        switch name {
        case "history":
            NavigationStack { HistoryView() }
        case "settings":
            NavigationStack { SettingsView() }
        case "graphs":
            NavigationStack { GraphsView() }
        case "whoDidWhat":
            // With `-share.range day` (or `week`, `fourWeeks`, `all`) and `-share.breastfeederAsked YES`.
            NavigationStack { WhoDidWhatPage() }
        case "duo":
            DuoPreview(me: me, babyID: babyID)
        case "journalDuo":
            JournalDuoPreview(me: me, babyID: babyID)
        case "pumping":
            EventEditor(mode: .newPump, me: me, babyID: babyID)
        case "addFirst":
            FirstEditor(mode: .new(title: UserDefaults.standard.string(forKey: "firstTitle")), me: me, babyID: babyID) { _ in }
        case "editFirst":
            FirstEditor(mode: .edit(id: UserDefaults.standard.string(forKey: "firstID") ?? "sample-first-smile"), me: me,
                        babyID: babyID) { _ in }
        case "shareCard":
            ShareCardPreview(id: UserDefaults.standard.string(forKey: "firstID") ?? "sample-first-smile", babyID: babyID)
        case "export":
            ExportView(babyID: babyID)
        case "moveOut":
            NavigationStack { MoveOutScreen() }
        case "moveIn":
            NavigationStack { MoveInScreen() }
        case "firstsList":
            NavigationStack { FirstsListView(me: me, babyID: babyID) }
        case "firstPage":
            NavigationStack {
                FirstPage(id: UserDefaults.standard.string(forKey: "firstID") ?? "sample-first-smile", me: me, babyID: babyID)
            }
        case "editLastFeed":
            let last = AppModel.shared.store.data.visibleSnapshots(babyID: babyID)
                .filter { $0.event.isLiveFeed && $0.event.babyID == babyID }
                .max { $0.event.startedAt < $1.event.startedAt }
            EventEditor(mode: last.map { .edit(id: $0.id) } ?? .newFeed, me: me, babyID: babyID)
        default:
            EventEditor(mode: .newFeed, me: me, babyID: babyID)
        }
    }
}

/// Feeding Dev only: the two columns as the unfolded Duo shows them, drawn at the size measured on
/// a real Duo open flat (951 x 669 pt, less the 84 pt side bar and the 82 pt top inset), shrunk to
/// fit this screen. The simulator can't unfold a Duo by command, so this is for screenshots; the
/// real split comes from `ArrangementView`.
struct DuoPreview: View {
    let me: MemberID
    let babyID: String
    @State private var undo: UndoAction?

    var body: some View {
        let size = CGSize(width: 867, height: 587)
        GeometryReader { proxy in
            let scale = proxy.size.width / size.width
            HStack(spacing: 0) {
                HomeView(me: me, babyID: babyID, undo: $undo)
                    .environment(\.secondColumnShowing, true)
                    .frame(width: size.width / 2)
                DayColumn(me: me, babyID: babyID, onUndo: { undo = $0 })
                    .frame(width: size.width / 2)
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale, anchor: .topLeading)
            // The shrunk picture's own footprint, from the top left.
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
        }
        .background(Theme.surface.ignoresSafeArea())
    }
}

/// Feeding Dev only: the Journal as the unfolded Duo shows it (design review D34), the line on the
/// left and the newest first's page on the right, at the measured open size, shrunk to fit, as
/// `DuoPreview` does for Home. `JournalView` splits by itself at this width.
struct JournalDuoPreview: View {
    let me: MemberID
    let babyID: String

    var body: some View {
        let size = CGSize(width: 867, height: 587)
        GeometryReader { proxy in
            let scale = proxy.size.width / size.width
            NavigationStack { JournalView(me: me, babyID: babyID) }
                .environment(\.horizontalSizeClass, .regular)
                .frame(width: size.width, height: size.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
        }
        .background(Theme.surface.ignoresSafeArea())
    }
}

/// Feeding Dev only: a first's share card (design review D25), shrunk to fit, for screenshots.
struct ShareCardPreview: View {
    let id: String
    let babyID: String
    @State private var card: UIImage?

    var body: some View {
        Group {
            if let card {
                Image(uiImage: card).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.3).ignoresSafeArea())
        .task {
            let data = AppModel.shared.store.data
            guard let first = data.events[id]?.snapshot, let details = first.payload?.milestone,
                  let photo = details.media.first, let files = MediaFiles.appGroup() else { return }
            let day = PlainDate(first.event.startedAt, in: data.householdSettings.timeZone)
            let age = data.birthDate(babyID: babyID).flatMap { BabyAge(on: day, birthDate: $0) }?.words
            let share = FirstCardShare(photoURL: files.fileURL(photo), title: details.title, age: age)
            card = (try? await share.jpeg()).flatMap(UIImage.init(data:))
        }
    }
}

/// Feeding Dev only: the Phase 0 tests on real phones, and the sync test.
struct SpikeMenu: View {
    var body: some View {
        List {
            Section {
                NavigationLink("Household sync test (two phones)") { HouseholdDebugView() }
                NavigationLink("Alarm test (overnight)") { AlarmSpikeView() }
                NavigationLink("Duo fold test") { FoldSpikeView() }
                NavigationLink("Design pieces (both looks)") { DesignGalleryView() }
            } header: {
                Text("Tests")
            } footer: {
                Text("Little Log Dev only. These screens never appear in the real app.")
            }
        }
        .navigationTitle("Tests")
    }
}
#endif
