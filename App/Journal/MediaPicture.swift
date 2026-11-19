import FeedingCore
import ImageIO
import SwiftUI

/// One of a first's photos, or the drawn tile in its place (design review D10):
/// - no photo: the plain tile with the sparkle;
/// - a photo still coming from the other phone: the tile with a ring and "On its way".
/// A photo is cropped to fill from the middle. At night every photo shows at 45% brightness and
/// 60% colour (D24); controls and words keep their own night colours.
struct MediaPicture: View {
    /// The item, or nil for a first with no photo.
    let id: String?
    /// The full photo (a first's page) rather than the thumbnail (the line).
    var full = false
    var cornerRadius: CGFloat = 20

    @Environment(\.look) private var look
    /// The loaded picture, and what it was loaded for: shown only for that same item, so a first
    /// chosen next never shows the one before while its own loads.
    @State private var loaded: (key: String, image: UIImage)?

    var body: some View {
        // Asked again when this item's file arrives or goes (`MediaSync.fileVersions`).
        let key = "\(id ?? "-")|\(full)|\(id.map { AppModel.shared.media.fileVersions[$0] ?? 0 } ?? 0)"
        let image = loaded.flatMap { $0.key == key ? $0.image : nil }
            ?? loaded.flatMap { $0.key.hasPrefix("\(id ?? "-")|\(full)|") ? $0.image : nil }
        // The tile takes the size it is given; the photo fills it from the middle and is cut to it.
        // The photo never sets the size: a tall photo in a ZStack made the tile tall too, and it
        // spilled over the rows around it.
        Theme.surface.overlay {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .modifier(NightDimmed(look: look))
                    .accessibilityHidden(true)
            } else if id == nil {
                SparkleShape()
                    .fill(Theme.textMuted)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
            } else {
                VStack(spacing: 6) {
                    ComingRing()
                    Text(JournalText.onItsWay)
                        .feedText(.small)
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: key) {
            let image = await Self.load(id, full: full)
            // A load overtaken by another item's is dropped.
            guard !Task.isCancelled else { return }
            loaded = image.map { (key, $0) }
        }
    }

    /// The thumbnail, or the full photo drawn at about screen size (never the whole file at once).
    static func load(_ id: String?, full: Bool) async -> UIImage? {
        guard let id, let files = MediaFiles.appGroup() else { return nil }
        let url = full && files.hasFile(id) ? files.fileURL(id) : files.thumbnailURL(id)
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: full ? 1400 : 420,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        }.value
    }
}

/// Photos at night: 45% brightness and 60% colour (design review D24).
struct NightDimmed: ViewModifier {
    let look: Look

    func body(content: Content) -> some View {
        if look == .night {
            content.saturation(0.6).colorMultiply(Color(white: 0.45))
        } else {
            content
        }
    }
}

/// The small ring on a tile whose photo is still coming.
struct ComingRing: View {
    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 3)
            Circle().trim(from: 0, to: 0.25).stroke(Theme.textMuted, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}
