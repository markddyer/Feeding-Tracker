// swift-tools-version: 6.2
import PackageDescription

// FeedingCore depends on Foundation only, so `swift test` runs on Linux as well as macOS.
//
// FeedingInsights holds the AI insights' parts with no AI (`docs/planning/12-ai-insights-gauntlet.md`,
// step 1). It may use FeedingCore; FeedingCore, with `reconcile` and the alarms, can never use it,
// so the build fails if alarm code reaches for insight code (R1, A6). Foundation only as well.
let package = Package(
    name: "FeedingCore",
    platforms: [
        .iOS("27.1"),
        .watchOS("27.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "FeedingCore", targets: ["FeedingCore"]),
        .library(name: "FeedingInsights", targets: ["FeedingInsights"]),
    ],
    targets: [
        .target(name: "FeedingCore"),
        .target(name: "FeedingInsights", dependencies: ["FeedingCore"]),
        .testTarget(name: "FeedingCoreTests", dependencies: ["FeedingCore"]),
        .testTarget(name: "FeedingInsightsTests", dependencies: ["FeedingInsights", "FeedingCore"]),
    ]
)
