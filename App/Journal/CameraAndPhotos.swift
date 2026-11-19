import Photos
import SwiftUI
import UIKit

/// The camera, for a photo taken in the app (step 1: photos only). iPhone's own camera screen, so
/// the iPhone Duo's cameras and poses are iPhone's to handle.
struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
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
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
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
            Text("Take a photo of a first").feedText(.title).accessibilityAddTraits(.isHeader)
            Text("Feeding uses the camera only when you tap it, to catch the moment. iPhone asks you once.")
                .feedText(.body)
            Text("A copy of each photo you take here is kept in your Photos too. iPhone asks about that after you save.")
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
/// with the add-only permission, asked after Save (design review D20). If it is declined, the first
/// is still saved, and the Journal says so once.
enum PhotosCopy {
    static let declinedKey = "journal.photosCopyDeclined"
    static let toldKey = "journal.photosCopyDeclinedTold"

    @MainActor
    static func keep(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return
        }
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
