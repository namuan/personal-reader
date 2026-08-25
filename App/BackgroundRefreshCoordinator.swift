import BackgroundTasks
import PersonalReaderCore

@MainActor
final class BackgroundRefreshCoordinator {
  static let taskIdentifier = "com.example.PersonalReader.backgroundRefresh"

  private weak var model: AppModel?
  private var refreshTask: Task<Void, Never>?

  func attach(_ model: AppModel) {
    self.model = model
  }

  func register() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.taskIdentifier,
      using: nil
    ) { [weak self] task in
      Task { @MainActor in
        guard let refreshTask = task as? BGAppRefreshTask else {
          task.setTaskCompleted(success: false)
          return
        }
        self?.handle(refreshTask)
      }
    }
  }

  func scheduleNextRefresh(after date: Date? = nil) {
    let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
    let earliest = max(date ?? .distantPast, Date.now.addingTimeInterval(30 * 60))
    request.earliestBeginDate = earliest
    try? BGTaskScheduler.shared.submit(request)
  }

  private func handle(_ task: BGAppRefreshTask) {
    task.expirationHandler = { [weak self] in
      Task { @MainActor in
        self?.refreshTask?.cancel()
        task.setTaskCompleted(success: false)
      }
    }

    refreshTask = Task { [weak self] in
      await self?.model?.refresh(force: false, isBackground: true)
      let completedSuccessfully = !Task.isCancelled
      task.setTaskCompleted(success: completedSuccessfully)
      self?.scheduleNextRefresh()
    }
  }
}
