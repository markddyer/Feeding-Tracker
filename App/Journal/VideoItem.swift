import AVFoundation
import AVKit
import CoreImage
import FeedingCore
import SwiftUI

/// The play mark on a video's still (design review D36).
struct PlayMark: View {
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(Theme.text)
            .frame(width: size, height: size)
            .background(Theme.surface.opacity(0.92), in: Circle())
            .accessibilityHidden(true)
    }
}

/// One of a first's items on its page: a photo, or a video.
struct MediaItemView: View {
    let id: String
    /// The item on screen: a video that isn't stops.
    var isCurrent = true
    var cornerRadius: CGFloat = 26

    var body: some View {
        if AppModel.shared.isVideo(id) {
            // Its own player for its own video: never one carried over from another (Codex review).
            VideoItem(id: id, isCurrent: isCurrent, cornerRadius: cornerRadius)
                .id(id)
        } else {
            MediaPicture(id: id, full: true, cornerRadius: cornerRadius)
        }
    }
}

/// A video on a first's page (design review D36): never plays by itself, a still with a play mark
/// until tapped; by day its sound follows the Silent switch (`.ambient`); at night it starts muted
/// with "Sound on", and is dimmed like the photos (55% darker and less colour, task T18, rebuilt
/// when the look changes). It stops when another item is shown, the page closes or the app leaves
/// the screen. One still being made smaller shows its still with "Getting the video ready".
struct VideoItem: View {
    let id: String
    let isCurrent: Bool
    let cornerRadius: CGFloat

    @Environment(\.look) private var look
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var muted = false
    /// The start under way (its look applied first); a stop cancels it.
    @State private var starting: Task<Void, Never>?

    private let model = AppModel.shared

    var body: some View {
        let ready = MediaFiles.appGroup()?.hasFile(id) == true
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .overlay {
                        if look == .night { Color.black.opacity(0.55).allowsHitTesting(false) }
                    }
            } else {
                MediaPicture(id: id, full: true, cornerRadius: cornerRadius)
                if ready {
                    Button { play() } label: { PlayMark(size: 64) }
                        .accessibilityLabel("Play the video")
                } else if model.videos.isPending(id) {
                    VStack(spacing: 6) {
                        ComingRing()
                        Text("Getting the video ready").feedText(.small).foregroundStyle(Theme.textMuted)
                    }
                    .padding(10)
                    .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if player != nil, look == .night {
                Button(muted ? "Sound on" : "Sound off") {
                    muted.toggle()
                    player?.isMuted = muted
                }
                .feedText(.smallButton)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Theme.surface, in: Capsule())
                .padding(10)
            }
        }
        .id(model.media.fileVersions[id] ?? 0)
        .onChange(of: isCurrent) { if !isCurrent { stop() } }
        .onChange(of: scenePhase) { if scenePhase != .active { stop() } }
        .onChange(of: look) {
            // Night starts: muted at once, with "Sound on" (D36); the picture follows.
            if look == .night {
                muted = true
                player?.isMuted = true
            }
            if let item = player?.currentItem { Task { await applyLook(to: item) } }
        }
        .onDisappear { stop() }
    }

    private func play() {
        guard let files = MediaFiles.appGroup(), files.hasFile(id) else { return }
        // By day the Silent switch decides; nothing else of the app's sound is touched (`AppSound`,
        // the one owner of the sound mode, F16).
        AppSound.forVideo()
        let item = AVPlayerItem(asset: files.videoAsset(id))
        let player = AVPlayer(playerItem: item)
        muted = look == .night
        player.isMuted = muted
        self.player = player
        starting?.cancel()
        starting = Task {
            await applyLook(to: item)
            // Still this video, on screen, with the app open: only then does it play.
            guard !Task.isCancelled, self.player === player, isCurrent, scenePhase == .active else { return }
            player.play()
        }
    }

    /// At night, less colour (the 55% darkening is the overlay above); by day, as it is.
    private func applyLook(to item: AVPlayerItem) async {
        let wanted = look
        guard wanted == .night else {
            item.videoComposition = nil
            return
        }
        let composition = try? await AVVideoComposition.videoComposition(with: item.asset) { request in
            let output = request.sourceImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.6])
            request.finish(with: output, context: nil)
        }
        // Only if it is still night: a change back to day meanwhile wins.
        if look == wanted { item.videoComposition = composition }
    }

    private func stop() {
        starting?.cancel()
        starting = nil
        player?.pause()
        player = nil
    }
}
