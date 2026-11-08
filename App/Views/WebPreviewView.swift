import SafariServices
import SwiftUI

struct WebPreviewDestination: Identifiable, Equatable {
  let url: URL

  var id: String { url.absoluteString }

  init?(url: URL?) {
    guard let url,
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else {
      return nil
    }
    self.url = url
  }
}

struct WebPreviewView: View {
  let destination: WebPreviewDestination

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    SafariPreviewController(url: destination.url) {
      dismiss()
    }
    .ignoresSafeArea()
  }
}

private struct SafariPreviewController: UIViewControllerRepresentable {
  let url: URL
  let onFinish: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onFinish: onFinish)
  }

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let configuration = SFSafariViewController.Configuration()
    configuration.entersReaderIfAvailable = false
    configuration.barCollapsingEnabled = true

    let controller = SFSafariViewController(url: url, configuration: configuration)
    controller.dismissButtonStyle = .close
    controller.delegate = context.coordinator

    // SwiftUI presents this controller inside a sheet, so provide the edge dismissal
    // explicitly rather than relying on Safari's own modal presentation gestures.
    let dismissSwipe = UIPanGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleDismissSwipe(_:))
    )
    dismissSwipe.cancelsTouchesInView = false
    dismissSwipe.delegate = context.coordinator
    controller.view.addGestureRecognizer(dismissSwipe)

    return controller
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

  @MainActor
  final class Coordinator: NSObject, @preconcurrency SFSafariViewControllerDelegate, UIGestureRecognizerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
      self.onFinish = onFinish
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer,
        let view = recognizer.view
      else { return true }
      let location = recognizer.location(in: view)
      let velocity = recognizer.velocity(in: view)
      let edgeWidth = max(44, view.safeAreaInsets.left + 16)
      return location.x <= edgeWidth && velocity.x > abs(velocity.y) * 1.5
    }

    @objc func handleDismissSwipe(_ recognizer: UIPanGestureRecognizer) {
      guard recognizer.state == .ended, let view = recognizer.view else { return }
      let translation = recognizer.translation(in: view)
      // Require a deliberate horizontal swipe; short or cancelled drags stay in Safari.
      guard translation.x >= 80, translation.x > abs(translation.y) * 1.5 else { return }
      onFinish()
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      // Let Safari continue handling page scrolling and its own navigation gestures.
      true
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
      onFinish()
    }
  }
}
