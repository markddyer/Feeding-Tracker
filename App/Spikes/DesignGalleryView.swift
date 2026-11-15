#if FEEDING_DEV
import FeedingCore
import SwiftUI

/// Feeding Dev only: every design piece in one place, to check against `DESIGN.md` in both
/// looks. Launch with `-designGallery YES` to open it straight away.
struct DesignGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Design pieces").feedText(.title)

                Tile(label: "Shapes") {
                    HStack(spacing: 16) {
                        FeedMarkView(.side(.left), size: 26)
                        FeedMarkView(.side(.right), size: 26)
                        FeedMarkView(.bottle, size: 26)
                        FeedMarkView(.pump, size: 26)
                    }
                }

                TileRow(shares: [1, 1.35]) {
                    Tile(label: "Next side", tint: Theme.breastTint) {
                        HStack(spacing: 8) {
                            FeedMarkView(.side(.left), size: 26, relativeTo: .title3)
                            Text("Left").feedText(.tileValue)
                        }
                    }
                    Tile(label: "Last feed", tint: Theme.bottleTint) {
                        FlowLayout(spacing: 6) {
                            Chip(.side(.left), "12m", spoken: "Left side, 12 minutes")
                            Chip(.side(.right), "8m", spoken: "Right side, 8 minutes")
                            Chip(.bottle, "30 ml")
                        }
                    }
                }

                Tile(label: "Pumping", tint: Theme.pumpTint) {
                    Chip(.pump, "120 ml", spoken: "Pumped 120 ml")
                }

                Tile(label: "Avatars") {
                    HStack(spacing: 10) {
                        Avatar(name: "Alex", colour: .sunflower)
                        Avatar(name: "Sam", colour: .teal)
                        Avatar(name: "Alex", colour: .sunflower, size: 26)
                        Avatar(name: "Sam", colour: .teal, size: 26)
                    }
                }

                Tile(label: "Text styles") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("2h 05m").feedText(.mainTime)
                        Text("Baby's name").feedText(.title)
                        Text("Start feed").feedText(.button)
                        Text("Today").feedText(.dayHeading)
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text("8").feedText(.total)
                            Text("240").feedText(.total)
                            Text("11:11").feedText(.total)
                            Text("00:00").feedText(.total)
                        }
                        Text("Body text in SF Pro Rounded.").feedText(.body)
                        Text("Feeding window 10:25").feedText(.subheadline).foregroundStyle(Theme.textMuted)
                    }
                }

                Tile(label: "Colours") {
                    let swatches: [(String, Color)] = [
                        ("primary", Theme.primary), ("track", Theme.track), ("window", Theme.window),
                        ("breast", Theme.breast), ("bottle", Theme.bottle), ("pump", Theme.pump),
                        ("notice", Theme.notice),
                    ]
                    HStack(spacing: 6) {
                        ForEach(swatches, id: \.0) { swatch in
                            RoundedRectangle(cornerRadius: 6).fill(swatch.1)
                                .frame(height: 28)
                                .accessibilityLabel(swatch.0)
                        }
                    }
                }
            }
            .padding(16)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Design pieces")
    }
}
#endif
