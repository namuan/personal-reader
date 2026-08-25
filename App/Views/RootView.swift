import PersonalReaderCore
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model: AppModel?

  var body: some View {
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
          .transition(.opacity)
      }
    }
  }
}
