import PersonalReaderCore
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model: AppModel?

  @State private var webPreviewDestination: WebPreviewDestination?

  var body: some View {
    content
      .sheet(item: $webPreviewDestination) { destination in
        WebPreviewView(destination: destination)
      }
  }

  @ViewBuilder
  private var content: some View {
    switch model {
    case .none:
      ContentUnavailableView(
        "Personal Reader",
        systemImage: "book.closed",
        description: Text("The local library could not be opened. Reinstall the app to reset it.")
      )
    case .some(let appModel):
      switch appModel.phase {
      case .loading:
        ProgressView("Opening your library…")
      case .setup:
        NavigationStack {
          SetupView()
        }
      case .ready:
        StoryListView()
          .environment(\.openURL, previewOpenURLAction)
          .transition(.opacity)
      }
    }
  }

  private var previewOpenURLAction: OpenURLAction {
    OpenURLAction { url in
      guard let destination = WebPreviewDestination(url: url) else {
        return .systemAction
      }
      webPreviewDestination = destination
      return .handled
    }
  }
}
