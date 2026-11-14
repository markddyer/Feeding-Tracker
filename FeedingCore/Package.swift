// swift-tools-version: 6.2
import PackageDescription

// FeedingCore depends on Foundation only, so `swift test` runs on Linux as well as macOS.
let package = Package(
    name: "FeedingCore",
    platforms: [
        .iOS("27.1"),
        .watchOS("27.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "FeedingCore", targets: ["FeedingCore"]),
    ],
    targets: [
        .target(name: "FeedingCore"),
        .testTarget(name: "FeedingCoreTests", dependencies: ["FeedingCore"]),
    ]
)
