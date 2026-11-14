import FeedingCore
import SwiftUI

/// Phase 0 placeholder. The real home screen comes in Phase 1.
struct ContentView: View {
    private let settings = HouseholdSettings()

    var body: some View {
        NavigationStack {
            #if FEEDING_DEV
            SpikeMenu(settings: settings)
            #else
            placeholder
            #endif
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Feeding")
                .font(.largeTitle.bold())
            Text("Phase 0 skeleton")
                .foregroundStyle(.secondary)
            Text("Window closes \(Int(settings.window.closesAfter / 3600)) h after a feed starts")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // True black edge to edge, under the iPhone Duo's side bar too.
        .background(Color.black.ignoresSafeArea())
    }
}

#if FEEDING_DEV
/// Feeding Dev only: the Phase 0 tests on real phones.
private struct SpikeMenu: View {
    let settings: HouseholdSettings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                NavigationLink("Alarm test (overnight)") { AlarmSpikeView() }
                NavigationLink("Duo fold test") { FoldSpikeView() }
                NavigationLink("Shared log test (two phones)") { SyncSpikeView() }
            } header: {
                Text("Phase 0 tests")
            } footer: {
                Text("Feeding Dev only. These screens never appear in the real app.")
            }
        }
        .navigationTitle("Feeding Dev")
        .task { await AlarmSpikeStore.shared.observeAlarms() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            AlarmSpikeStore.shared.recordAppActive()
            Task { await AlarmSpikeStore.shared.collectDeliveredNotifications() }
            Task { await SyncSpikeStore.shared.fetchNow() }
        }
    }
}
#endif

#Preview {
    ContentView()
}
