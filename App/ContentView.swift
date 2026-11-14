import FeedingCore
import SwiftUI

/// Phase 0 placeholder. The real home screen comes in Phase 1.
struct ContentView: View {
    private let settings = HouseholdSettings()

    var body: some View {
        NavigationStack {
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
}

#Preview {
    ContentView()
}
