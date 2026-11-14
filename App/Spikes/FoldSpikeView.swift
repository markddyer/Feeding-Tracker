#if FEEDING_DEV
import SwiftUI
import UIKit

// Phase 0, spike 3: fold and unfold the iPhone Duo during a fake feed. The screen also measures
// what the app sees in each pose (sizes, safe area, fold region, hinge) for the shared Duo notes,
// and tries the plan's two-column layout (ArrangementView, split side by side).

struct FoldReading: Codable, Hashable {
    var time: Date
    var label: String?
    var windowSize: String
    var safeArea: String
    var sceneBounds: String
    var screenBounds: String
    var screenPixels: String
    var displayScale: Double
    var sizeClasses: String
    var barEdge: String
    var hinge: String
    var regions: [String]
    var secondColumnShown: Bool
    var fakeFeedRunning: Bool

    /// Everything except the time and label, to log only real changes.
    var signature: String {
        [windowSize, safeArea, sceneBounds, screenBounds, sizeClasses, barEdge, hinge, regions.joined(separator: ";"),
         String(secondColumnShown)].joined(separator: "|")
    }
}

struct FoldSpikeLog: Codable {
    var readings: [FoldReading] = []
    static let fileName = "fold-spike.json"

    static func load() -> FoldSpikeLog { SpikeFile.load(FoldSpikeLog.self, from: fileName) ?? FoldSpikeLog() }

    mutating func append(_ reading: FoldReading) {
        readings.append(reading)
        if readings.count > 2000 { readings.removeFirst(readings.count - 2000) }
        SpikeFile.save(self, to: Self.fileName)
    }
}

struct FoldSpikeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.displayScale) private var displayScale
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge

    @State private var hinge: DeviceHinge?
    @State private var secondColumnShown = false
    @State private var log = FoldSpikeLog.load()
    @State private var savedLabel: String?
    @AppStorage("spike.fakeFeedStart") private var fakeFeedStart: Double = 0

    private let poses = ["Closed", "Open flat", "Book", "Laptop", "Tent", "Split View", "Sideways closed", "Sideways open"]

    var body: some View {
        GeometryReader { proxy in
            let reading = makeReading(proxy)
            ArrangementView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        fakeFeed
                        poseButtons(reading)
                        readout(reading)
                    }
                    .padding()
                }
            } secondary: {
                VStack(spacing: 8) {
                    Text("Second column")
                        .font(.headline)
                    Text("The day's timeline will go here. It shows only when the Duo is open.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.08))
                .onAppear { secondColumnShown = true }
                .onDisappear { secondColumnShown = false }
            }
            .arrangementViewStyle(.split.axes(.horizontal))
            .onChange(of: reading.signature, initial: true) {
                log.append(reading)
            }
        }
        .onHingeChange { _, newContext in
            hinge = newContext.hinge
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Duo fold test")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Fake feed

    private var fakeFeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fake feed").font(.headline)
            if fakeFeedStart > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince1970 - fakeFeedStart)
                    Text("Running for \(elapsed / 60) min \(elapsed % 60) s")
                        .font(.title2.monospacedDigit())
                }
                Text("Fold and unfold the Duo. The time should keep counting from the same start.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Finish fake feed") { fakeFeedStart = 0 }
                    .buttonStyle(.bordered)
            } else {
                Button("Start fake feed") { fakeFeedStart = Date().timeIntervalSince1970 }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Pose labels

    private func poseButtons(_ reading: FoldReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save this pose").font(.headline)
            Text("Hold the Duo in a pose, then tap its name.")
                .font(.footnote).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(poses, id: \.self) { pose in
                    Button(pose) {
                        var labelled = reading
                        labelled.label = pose
                        labelled.time = Date()
                        log.append(labelled)
                        savedLabel = pose
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
            if let savedLabel {
                Text("Saved: \(savedLabel)").font(.footnote)
            }
            ShareLink(item: SpikeFile.url(FoldSpikeLog.fileName)) {
                Label("Share the measurements file", systemImage: "square.and.arrow.up")
            }
            .font(.footnote)
        }
    }

    // MARK: Readout

    private func readout(_ reading: FoldReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What the app sees").font(.headline)
            row("Window (pt)", reading.windowSize)
            row("Safe area T,L,B,R", reading.safeArea)
            row("Scene (pt)", reading.sceneBounds)
            row("Screen (pt)", reading.screenBounds)
            row("Screen (px)", reading.screenPixels)
            row("Scale", String(format: "%.2f", reading.displayScale))
            row("Size classes W,H", reading.sizeClasses)
            row("Side bar edge", reading.barEdge)
            row("Hinge", reading.hinge)
            row("Second column", reading.secondColumnShown ? "shown" : "hidden")
            ForEach(reading.regions, id: \.self) { region in
                Text(region).font(.caption.monospaced())
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption.bold()).frame(width: 130, alignment: .leading)
            Text(value).font(.caption.monospaced())
        }
    }

    // MARK: Measuring

    private func makeReading(_ proxy: GeometryProxy) -> FoldReading {
        let insets = proxy.safeAreaInsets
        let full = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                          height: proxy.size.height + insets.top + insets.bottom)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let regions = proxy.reservedRegions(kind: .occlusion, options: .includeInactive).map { describe($0, "occlusion") }
            + proxy.reservedRegions(kind: .division, options: .includeInactive).map { describe($0, "fold") }
        return FoldReading(
            time: Date(),
            label: nil,
            windowSize: size(full),
            safeArea: [insets.top, insets.leading, insets.bottom, insets.trailing].map { number($0) }.joined(separator: ","),
            sceneBounds: scene.map { size($0.effectiveGeometry.coordinateSpace.bounds.size) } ?? "?",
            screenBounds: scene.map { size($0.screen.bounds.size) } ?? "?",
            screenPixels: scene.map { size($0.screen.nativeBounds.size) } ?? "?",
            displayScale: displayScale,
            sizeClasses: "\(name(horizontalSizeClass)),\(name(verticalSizeClass))",
            barEdge: toolbarVerticalEdge.map { $0 == .leading ? "leading" : "trailing" } ?? "none",
            hinge: hingeText,
            regions: regions,
            secondColumnShown: secondColumnShown,
            fakeFeedRunning: fakeFeedStart > 0
        )
    }

    private var hingeText: String {
        guard let hinge else { return "no hinge reported" }
        let status = switch hinge.status {
        case .closed: "closed"
        case .partiallyOpen: "partly open"
        case .fullyOpen: "fully open"
        default: "other"
        }
        // Rounded to 5 degrees so a slow fold doesn't log hundreds of near-identical lines.
        let degrees = Int((hinge.angle.degrees / 5).rounded() * 5)
        return "\(status), \(degrees)°"
    }

    private func describe(_ region: ReservedRegion, _ kind: String) -> String {
        let f = region.frame
        let m = region.margins
        return "\(kind) \(region.isActive ? "active" : "inactive") x\(number(f.minX)) y\(number(f.minY)) \(number(f.width))x\(number(f.height)) margins \(number(m.top)),\(number(m.leading)),\(number(m.bottom)),\(number(m.trailing))"
    }

    private func size(_ s: CGSize) -> String { "\(number(s.width)) x \(number(s.height))" }

    private func number(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func name(_ sizeClass: UserInterfaceSizeClass?) -> String {
        switch sizeClass {
        case .compact: "compact"
        case .regular: "regular"
        default: "none"
        }
    }
}
#endif
