import AVFoundation
import FeedingCore
import Photos
import SwiftUI
import UIKit

/// The camera, for a photo or a short video taken in the app (step 2). iPhone's own camera screen,
/// so the iPhone Duo's cameras and poses are iPhone's to handle. Videos stop at 15 seconds. With
/// the microphone turned off for the app, it takes photos only (journal plan).
struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    /// A video, copied out of the camera's own file at once; nil for photos only.
    var onVideo: ((URL) -> Void)?
    /// The camera's video couldn't be kept: the editor says so.
    var onFailure: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    /// The microphone was turned off for Feeding: videos would have no sound, so photos only.
    static var microphoneOff: Bool {
        [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = onVideo != nil && !Self.microphoneOff ? ["public.image", "public.movie"] : ["public.image"]
        picker.videoMaximumDuration = MediaSizes.longestVideo
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let movie = info[.mediaURL] as? URL, let onVideo = parent.onVideo {
                // The camera's file goes when the picker does: a copy is kept at once.
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("taken-\(UUID().uuidString).\(movie.pathExtension.isEmpty ? "mov" : movie.pathExtension)")
                if (try? FileManager.default.copyItem(at: movie, to: copy)) != nil {
                    onVideo(copy)
                } else {
                    parent.onFailure?()
                }
            } else if let image = info[.originalImage] as? UIImage {
                parent.onPhoto(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// iPhone's own trimmer, for a picked video longer than 15 seconds: the parent keeps the part
/// they want (the journal keeps 15 seconds). Cancel keeps the first 15 seconds.
struct VideoTrimmer: UIViewControllerRepresentable {
    let url: URL
    let onTrimmed: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIVideoEditorController {
        let editor = UIVideoEditorController()
        editor.videoPath = url.path
        editor.videoMaximumDuration = MediaSizes.longestVideo
        editor.videoQuality = .typeHigh
        editor.delegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ controller: UIVideoEditorController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIVideoEditorControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoTrimmer
        /// iPhone can report a save twice: only the first counts.
        private var done = false

        init(_ parent: VideoTrimmer) {
            self.parent = parent
        }

        func videoEditorController(_ editor: UIVideoEditorController, didSaveEditedVideoToPath editedVideoPath: String) {
            guard !done else { return }
            done = true
            // Its file goes with the editor: a copy is kept at once.
            let source = URL(fileURLWithPath: editedVideoPath)
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("trimmed-\(UUID().uuidString).\(source.pathExtension.isEmpty ? "mov" : source.pathExtension)")
            if (try? FileManager.default.copyItem(at: source, to: copy)) != nil { parent.onTrimmed(copy) }
            parent.dismiss()
        }

        func videoEditorController(_ editor: UIVideoEditorController, didFailWithError error: any Error) {
            parent.dismiss()
        }

        func videoEditorControllerDidCancel(_ editor: UIVideoEditorController) {
            parent.dismiss()
        }
    }
}

/// The one short screen before the camera is first used (design review D20): what it is for,
/// then iPhone asks.
struct CameraExplainer: View {
    let onGoOn: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Take a photo or video of a first").feedText(.title).accessibilityAddTraits(.isHeader)
            Text("Little Log uses the camera only when you tap it, to catch the moment, and the microphone for a video's sound. iPhone asks you once.")
                .feedText(.body)
            Text("A copy of each photo or video you take here is kept in your Photos too. iPhone asks about that after you save.")
                .feedText(.body)
                .foregroundStyle(Theme.textMuted)
            Spacer(minLength: 0)
            Button {
                dismiss()
                onGoOn()
            } label: {
                Text("Open the camera")
                    .feedText(.button)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(PressStyle())
            Button("Not now") { dismiss() }
                .feedText(.smallButton)
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .foregroundStyle(Theme.text)
        .padding(24)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

/// A photo taken in the app is also kept in the phone's Photos (journal plan, "No photo is lost"),
/// with the add-only permission, asked after Save (design review D20). If it is declined, or the
/// copy fails, the first is still saved, and the Journal says so once.
enum PhotosCopy {
    static let declinedKey = "journal.photosCopyDeclined"
    static let failedKey = "journal.photosCopyFailed"
    static let toldKey = "journal.photosCopyDeclinedTold"

    @MainActor
    static func keep(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            UserDefaults.standard.set(true, forKey: failedKey)
        }
    }

    /// A video taken in the app, from its kept original (`deleteAfter` false: the video queue
    /// deletes it when it is done with it).
    @MainActor
    static func keepVideo(_ url: URL, deleteAfter: Bool = true) async {
        defer { if deleteAfter { try? FileManager.default.removeItem(at: url) } }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } catch {
            UserDefaults.standard.set(true, forKey: failedKey)
        }
    }
}
