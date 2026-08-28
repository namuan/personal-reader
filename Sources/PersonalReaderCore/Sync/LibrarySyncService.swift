import Foundation
import OSLog

private let librarySyncLogger = Logger(
  subsystem: "com.github.namuan.personalreader", category: "library-sync"
)

public struct SourceSyncResult: Equatable, Sendable {
  public let sourceId: String
  public let outcome: Result<RSSSyncOutcome, RSSSyncError>

  public var isSuccess: Bool {
    if case .success = outcome { return true }
    return false
  }
}

public struct LibraryRefreshReport: Equatable, Sendable {
  public let reddit: Result<SyncOutcome, SyncError>?
  public let sources: [SourceSyncResult]

  public var succeededCount: Int {
    var count = sources.filter(\.isSuccess).count
    if case .success = reddit { count += 1 }
    return count
  }

  public var totalAttempted: Int {
    var count = sources.count
    if reddit != nil { count += 1 }
    return count
  }
}

public actor LibrarySyncService {
  private let redditService: any RedditSyncing
  private let rssService: any RSSSyncing
  private let sourceStore: FeedSourceStore
  private let repository: StoryRepository
  private let redditConfigurationProvider: @Sendable () -> FeedConfiguration?
  private let redditMinimumInterval: TimeInterval
  private var isRefreshing = false

  public init(
    redditService: any RedditSyncing,
    rssService: any RSSSyncing,
    sourceStore: FeedSourceStore,
    repository: StoryRepository,
    redditConfigurationProvider: @escaping @Sendable () -> FeedConfiguration?,
    redditMinimumInterval: TimeInterval = 30 * 60
  ) {
    self.redditService = redditService
    self.rssService = rssService
    self.sourceStore = sourceStore
    self.repository = repository
    self.redditConfigurationProvider = redditConfigurationProvider
    self.redditMinimumInterval = redditMinimumInterval
  }

  public func refreshDueSources(
    reddit: Bool = true,
    force: Bool = false,
    now: Date = Date()
  ) async -> LibraryRefreshReport {
    if isRefreshing {
      librarySyncLogger.notice("library refresh skipped because another refresh is active")
      return LibraryRefreshReport(reddit: nil, sources: [])
    }
    isRefreshing = true
    defer { isRefreshing = false }

    let sources = ((try? sourceStore.fetchEnabled()) ?? []).filter { $0.kind == .rss }
    librarySyncLogger.notice(
      "library refresh started force=\(force, privacy: .public) reddit=\(reddit, privacy: .public) rssSources=\(sources.count, privacy: .public)"
    )
    let rssTasks = sources.map { source in
      Task { () -> SourceSyncResult in
        do {
          let outcome = try await rssService.sync(source: source, force: force, now: now)
          return SourceSyncResult(sourceId: source.id, outcome: .success(outcome))
        } catch let error as RSSSyncError {
          return SourceSyncResult(sourceId: source.id, outcome: .failure(error))
        } catch {
          return SourceSyncResult(
            sourceId: source.id,
            outcome: .failure(.malformedFeed(error.localizedDescription))
          )
        }
      }
    }

    var redditResult: Result<SyncOutcome, SyncError>? = nil
    if reddit, let configuration = redditConfigurationProvider() {
      do {
        let outcome = try await redditService.sync(
          configuration: configuration, force: force, now: now
        )
        redditResult = .success(outcome)
      } catch let error as SyncError {
        redditResult = .failure(error)
      } catch {
        redditResult = .failure(.networkFailure)
      }
    }

    var sourceResults: [SourceSyncResult] = []
    for task in rssTasks {
      sourceResults.append(await task.value)
    }
    let report = LibraryRefreshReport(reddit: redditResult, sources: sourceResults)
    let redditSucceeded: Bool
    if case .success = redditResult {
      redditSucceeded = true
    } else {
      redditSucceeded = false
    }
    librarySyncLogger.notice(
      "library refresh completed attempted=\(report.totalAttempted, privacy: .public) succeeded=\(report.succeededCount, privacy: .public) redditSucceeded=\(redditSucceeded, privacy: .public) rssFailed=\(sourceResults.count - sourceResults.filter(\.isSuccess).count, privacy: .public)"
    )
    return report
  }

  public func refreshSource(
    id sourceId: String,
    force: Bool = false,
    now: Date = Date()
  ) async -> SourceSyncResult {
    if sourceId == FeedSourceRecord.builtInRedditID() {
      guard let configuration = redditConfigurationProvider() else {
        return SourceSyncResult(
          sourceId: sourceId,
          outcome: .failure(.malformedFeed("Reddit credentials missing"))
        )
      }
      do {
        let outcome = try await redditService.sync(
          configuration: configuration, force: force, now: now
        )
        switch outcome {
        case .synced(let report):
          return SourceSyncResult(
            sourceId: sourceId,
            outcome: .success(
              RSSSyncOutcome(
                report: report,
                etag: nil,
                lastModified: nil,
                nextEligibleAt: now.addingTimeInterval(redditMinimumInterval)
              ))
          )
        case .skipped(let nextEligible):
          return SourceSyncResult(
            sourceId: sourceId,
            outcome: .failure(.notDue(nextEligibleAt: nextEligible))
          )
        }
      } catch let error as SyncError {
        return SourceSyncResult(sourceId: sourceId, outcome: .failure(mapReddit(error)))
      } catch {
        return SourceSyncResult(sourceId: sourceId, outcome: .failure(.networkFailure))
      }
    }
    guard let source = try? sourceStore.fetch(id: sourceId) else {
      return SourceSyncResult(
        sourceId: sourceId,
        outcome: .failure(.malformedFeed("Feed not found"))
      )
    }
    do {
      let outcome = try await rssService.sync(source: source, force: force, now: now)
      return SourceSyncResult(sourceId: sourceId, outcome: .success(outcome))
    } catch let error as RSSSyncError {
      return SourceSyncResult(sourceId: sourceId, outcome: .failure(error))
    } catch {
      return SourceSyncResult(sourceId: sourceId, outcome: .failure(.networkFailure))
    }
  }

  public func nextScheduledRefreshDate(now: Date = Date()) async -> Date? {
    let sources = ((try? sourceStore.fetchEnabled()) ?? []).filter { $0.kind == .rss }
    var candidates: [Date] = []
    let redditKey = StoryRepository.feedKey(for: FeedSourceRecord.builtInRedditID())
    if let state = try? repository.loadSyncState(feedKey: redditKey),
      let last = state.lastSuccessfulSyncDate
    {
      candidates.append(last.addingTimeInterval(redditMinimumInterval))
    }
    for source in sources {
      let feedKey = StoryRepository.feedKey(for: source.id)
      if let state = try? repository.loadSyncState(feedKey: feedKey),
        let last = state.lastSuccessfulSyncDate
      {
        candidates.append(last.addingTimeInterval(source.refreshInterval.seconds))
      }
    }
    return candidates.min()
  }

  public func loadOlderReddit(configuration: FeedConfiguration, now: Date = Date()) async throws
    -> OlderSyncOutcome
  {
    try await redditService.loadOlder(configuration: configuration, now: now)
  }

  public func hasReachedEndForReddit(configuration: FeedConfiguration) async throws -> Bool {
    try await redditService.hasReachedEnd(configuration: configuration)
  }

  private func mapReddit(_ error: SyncError) -> RSSSyncError {
    switch error {
    case .rateLimited(let retryAt): return .rateLimited(retryAt: retryAt)
    case .invalidCredentials: return .invalidCredentials
    case .offline: return .offline
    case .timedOut: return .timedOut
    case .serverFailure(let statusCode): return .serverFailure(statusCode: statusCode)
    case .malformedFeed(let description): return .malformedFeed(description)
    case .networkFailure: return .networkFailure
    case .cancelled: return .cancelled
    }
  }
}
