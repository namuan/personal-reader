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
    return controller
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

  final class Coordinator: NSObject, SFSafariViewControllerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
      self.onFinish = onFinish
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
      onFinish()
    }
  }
}
