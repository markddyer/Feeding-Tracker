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

    var body: some View {
        NavigationStack {
            Group {
                if SetupView.isComplete(disclaimerSeen: disclaimerSeen, inviteOffered: inviteOffered,
                                        permissionsAsked: permissionsAsked, feedingStyle: feedingStyle),
                   let me = model.me, let baby = model.baby {
                    // The unfolded iPhone Duo shows the timeline beside the home screen; anywhere
                    // narrower shows the home screen alone (plan v1, "The Duo unfolded").
                    ArrangementView {
                        HomeView(me: me, babyID: baby.name)
                    } secondary: {
                        DayTimelineView(me: me, babyID: baby.name)
                    }
                    .arrangementViewStyle(.split.axes(.horizontal))
                } else {
                    SetupView()
                }
            }
            .toolbar {
                if model.baby != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            HistoryView()
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
                #if FEEDING_DEV
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SpikeMenu()
                    } label: {
                        Label("Tests", systemImage: "testtube.2")
                    }
                }
                #endif
            }
            .navigationTitle(model.baby.flatMap { PayloadCoder.decode(BabyPayload.self, from: $0.payload)?.name } ?? "Feeding")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.accent)
        #if FEEDING_DEV
        .modifier(AlarmSpikeHooks())
        #endif
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

/// Feeding Dev only: the Phase 0 tests on real phones, and the sync test.
struct SpikeMenu: View {
    var body: some View {
        List {
            Section {
                NavigationLink("Household sync test (two phones)") { HouseholdDebugView() }
                NavigationLink("Alarm test (overnight)") { AlarmSpikeView() }
                NavigationLink("Duo fold test") { FoldSpikeView() }
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
