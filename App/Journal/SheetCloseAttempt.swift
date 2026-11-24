import SwiftUI
import UIKit

/// Calls `onAttempt` when a parent swipes down a sheet that `.interactiveDismissDisabled` holds
/// open (design review D37, engineering re-review finding 6). SwiftUI has no such callback, and
/// iOS 27.2's `dismissalConfirmationDialog` neither asked nor kept the sheet open
/// (`UITests/DiscardFlowTests`, 24 Nov 2026). This joins the sheet's presentation controller as
/// its delegate and passes every other call on to SwiftUI's own delegate, so the sheet's binding
/// still updates when it closes.
struct SheetCloseAttempt: UIViewControllerRepresentable {
    let onAttempt: @MainActor () -> Void

    func makeUIViewController(context: Context) -> Watcher { Watcher(onAttempt: onAttempt) }

    func updateUIViewController(_ watcher: Watcher, context: Context) {
        watcher.onAttempt = onAttempt
        watcher.attach()
    }

    final class Watcher: UIViewController, UIAdaptivePresentationControllerDelegate {
        var onAttempt: @MainActor () -> Void
        /// SwiftUI's own delegate, which every other call goes to.
        private weak var original: (any UIAdaptivePresentationControllerDelegate)?

        init(onAttempt: @escaping @MainActor () -> Void) {
            self.onAttempt = onAttempt
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }

        /// Joins the sheet this view is in: its topmost parent's presentation controller. Again
        /// after each update, in case SwiftUI set its own delegate back.
        func attach() {
            var top: UIViewController = self
            while let parent = top.parent { top = parent }
            guard let controller = top.presentationController, controller.delegate !== self else { return }
            original = controller.delegate
            controller.delegate = self
        }

        func presentationControllerDidAttemptToDismiss(_ controller: UIPresentationController) {
            original?.presentationControllerDidAttemptToDismiss?(controller)
            onAttempt()
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if let original, original.responds(to: selector) { return original }
            return super.forwardingTarget(for: selector)
        }
    }
}
