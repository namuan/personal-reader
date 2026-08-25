import BackgroundTasks
import PersonalReaderCore
import SwiftUI

@main
struct PersonalReaderApp: App {
  @Environment(\.scenePhase) private var scenePhase

  @State private var environment: AppEnvironment
  @State private var model: AppModel?
  @State private var backgroundCoordinator = BackgroundRefreshCoordinator()

  init() {
    do {
      let liveEnvironment = try AppEnvironment.live()
      _environment = State(initialValue: liveEnvironment)
      let appModel = AppModel(environment: liveEnvironment)
      _model = State(initialValue: appModel)
      backgroundCoordinator.attach(appModel)
      backgroundCoordinator.register()
    } catch {
      fatalError("Personal Reader could not start: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .task {
          await model?.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
          handle(scenePhaseChange: newPhase)
        }
    }
  }

  private func handle(scenePhaseChange newPhase: ScenePhase) {
    guard newPhase == .background else { return }
    backgroundCoordinator.scheduleNextRefresh()
  }
}
