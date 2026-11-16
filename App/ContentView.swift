import FeedingCore
import SwiftUI

/// The app's root: the home screen once there is a household, with History and Settings in the
/// system toolbar (so the iPhone Duo moves them into its side bar by itself).
struct ContentView: View {
    private let model = AppModel.shared
    @AppStorage("setup.disclaimerSeen") private var disclaimerSeen = false
    @AppStorage("setup.inviteOffered") private var inviteOffered = false
    @AppStorage("setup.permissionsAsked") private var permissionsAsked = false
    @AppStorage(FeedingStyle.storageKey) private var feedingStyle = ""
    /// The last tap's Undo, shown under the home screen's buttons, from either column.
    @State private var undo: UndoAction?
    /// The arrangement's width and the home column's width. The second column is showing when the
    /// home column is clearly narrower than the whole (`ArrangementView` gives no direct signal).
    @State private var arrangementWidth: CGFloat = 0
    @State private var homeWidth: CGFloat = 0
    /// The screens opened from the top bar, so a tapped notification can go back to Home.
    @State private var path = NavigationPath()

    private enum Screen: Hashable {
        case history, settings
        #if FEEDING_DEV
        case tests
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
        NavigationStack(path: $path) {
            Group {
                #if FEEDING_DEV
                if UserDefaults.standard.bool(forKey: "designGallery") {
                    DesignGalleryView()
                } else {
                    screens
                }
                #else
                screens
                #endif
            }
            .toolbar {
                if model.baby != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Screen.history) {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        .tint(Theme.text)
                    }
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
                case .history: HistoryView()
                case .settings: SettingsView()
                #if FEEDING_DEV
                case .tests: SpikeMenu()
                #endif
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        // A tapped notification about an ask goes back to Home, where its card is.
        .onChange(of: NotificationTaps.shared.homeRequests) {
            path = NavigationPath()
        }
        .onChange(of: feedingStyle, initial: true) {
            model.widgets.feedingStyleChanged(feedingStyle)
        }
        // Coral for controls (switches, pickers); the top bar's buttons use the text colour
        // as in the approved mockup, because coral text on cream is hard to read.
        .tint(Theme.accent)
        #if FEEDING_DEV
        .modifier(AlarmSpikeHooks())
        #endif
    }

    @ViewBuilder
    private var screens: some View {
        if SetupView.isComplete(disclaimerSeen: disclaimerSeen, inviteOffered: inviteOffered,
                                permissionsAsked: permissionsAsked, feedingStyle: feedingStyle),
           let me = model.me, let baby = model.baby {
            // The unfolded iPhone Duo shows the day's tiles and feeds beside the home screen;
            // anywhere narrower shows the home screen alone (`05-visual-redesign.md`, "The Duo
            // unfolded"). On a real Duo the column shows open flat and in book pose, and hides
            // closed, in tent, in laptop pose and in Split View, with no code of ours.
            ArrangementView {
                HomeView(me: me, babyID: baby.name, undo: $undo)
                    .environment(\.secondColumnShowing, secondColumnShowing)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { homeWidth = $0 }
            } secondary: {
                DayColumn(me: me, babyID: baby.name, onUndo: { undo = $0 })
            }
            .arrangementViewStyle(.split.axes(.horizontal))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { arrangementWidth = $0 }
            // The page shows the greeting and the baby's name, so the bar shows only its
            // buttons. "Home" is still the back button's name on the next screen.
            .navigationTitle("Home")
            .toolbar(removing: .title)
        } else {
            SetupView()
                .navigationTitle("Feeding")
                .toolbar(removing: .title)
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
/// `-openScreen history`, `settings`, `duo`, `earlierFeed`, `pumping` or `editLastFeed`.
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
        case "duo":
            DuoPreview(me: me, babyID: babyID)
        case "pumping":
            EventEditor(mode: .newPump, me: me, babyID: babyID)
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
                Text("Feeding Dev only. These screens never appear in the real app.")
            }
        }
        .navigationTitle("Tests")
    }
}
#endif
