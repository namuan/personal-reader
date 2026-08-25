import Foundation

public struct SyncPolicy: Equatable, Sendable {
  public let minimumInterval: TimeInterval
  public let maximumStories: Int
  public let retentionInterval: TimeInterval
  public let backoffSchedule: [TimeInterval]

  public static let standard = SyncPolicy()

  public init(
    minimumInterval: TimeInterval = 30 * 60,
    maximumStories: Int = 50,
    retentionInterval: TimeInterval = 14 * 24 * 60 * 60,
    backoffSchedule: [TimeInterval] = [60, 120, 240, 480, 960, 1800]
  ) {
    self.minimumInterval = minimumInterval
    self.maximumStories = maximumStories
    self.retentionInterval = retentionInterval
    self.backoffSchedule = backoffSchedule
  }

  public func backoffDelay(afterAttempt attempt: Int) -> TimeInterval {
    guard !backoffSchedule.isEmpty else { return minimumInterval }
    let index = min(max(attempt - 1, 0), backoffSchedule.count - 1)
    return backoffSchedule[index]
  }
}

public enum SyncOutcome: Equatable, Sendable {
  case synced(SyncReport)
  case skipped(nextAllowedAt: Date)
}

public enum OlderSyncOutcome: Equatable, Sendable {
  case loaded(SyncReport)
  case exhausted
  case skipped(nextAllowedAt: Date)
}

public enum SyncError: Error, Equatable, Sendable {
  case rateLimited(retryAt: Date)
  case invalidCredentials
  case offline
  case timedOut
  case serverFailure(statusCode: Int)
  case malformedFeed(String?)
  case networkFailure
  case cancelled
}

public actor StorySyncService {
  private let feedClient: any FeedFetching
  private let parser: any StoryParsing
  private let repository: StoryRepository
  private let policy: SyncPolicy
  private var isSyncing = false

  public init(
    feedClient: any FeedFetching,
    parser: any StoryParsing,
    repository: StoryRepository,
    policy: SyncPolicy = .standard
  ) {
    self.feedClient = feedClient
    self.parser = parser
    self.repository = repository
    self.policy = policy
  }

  public func sync(
    configuration: FeedConfiguration,
    force: Bool = false,
    now: Date = Date()
  ) async throws -> SyncOutcome {
    let state =
      try repository.loadSyncState(feedKey: configuration.feedKey)
      ?? SyncState(feedKey: configuration.feedKey)
    let nextEligible = nextEligibleDate(state: state, now: now, force: force)

    if isSyncing {
      return .skipped(nextAllowedAt: nextEligible ?? now)
    }
    if let nextEligible, nextEligible > now {
      return .skipped(nextAllowedAt: nextEligible)
    }
    isSyncing = true
    defer { isSyncing = false }

    do {
      let data = try await feedClient.fetch(configuration: configuration)
      let stories = Array(try parse(data).prefix(policy.maximumStories))
      let report = try repository.applySync(
        stories: stories,
        syncStateUpdate: SyncStateUpdate(
          feedKey: configuration.feedKey,
          lastSuccessfulSyncAt: Int64(now.timeIntervalSince1970),
          rateLimitAttempt: 0,
          olderCursor: state.olderCursor ?? stories.last?.id
        ),
        retentionCutoff: retentionCutoff(for: configuration, now: now)
      )
      return .synced(report)
    } catch let error as FeedClientError {
      throw mappedError(error, state: state, now: now)
    } catch let error as RSSParserError {
      throw SyncError.malformedFeed(errorDescription(of: error))
    } catch let error as URLError {
      throw transportError(urlError: error)
    } catch is CancellationError {
      throw SyncError.cancelled
    }
  }

  public func loadOlder(
    configuration: FeedConfiguration,
    now: Date = Date()
  ) async throws -> OlderSyncOutcome {
    let state =
      try repository.loadSyncState(feedKey: configuration.feedKey)
      ?? SyncState(feedKey: configuration.feedKey)
    if state.hasReachedEnd {
      return .exhausted
    }
    if let retryNotBefore = state.retryNotBeforeDate, retryNotBefore > now {
      return .skipped(nextAllowedAt: retryNotBefore)
    }
    if isSyncing {
      return .skipped(nextAllowedAt: now)
    }
    let cursor: String?
    if let olderCursor = state.olderCursor {
      cursor = olderCursor
    } else {
      cursor = try repository.oldestStoryID()
    }
    guard let cursor else {
      return .exhausted
    }

    isSyncing = true
    defer { isSyncing = false }

    do {
      let data = try await feedClient.fetch(configuration: configuration, after: cursor)
      let stories = Array(try parse(data).prefix(policy.maximumStories))
      let hasReachedEnd = stories.isEmpty || stories.last?.id == cursor
      let report = try repository.applySync(
        stories: stories,
        syncStateUpdate: SyncStateUpdate(
          feedKey: configuration.feedKey,
          lastSuccessfulSyncAt: Int64(now.timeIntervalSince1970),
          rateLimitAttempt: 0,
          olderCursor: stories.last?.id ?? cursor,
          hasReachedEnd: hasReachedEnd
        ),
        retentionCutoff: retentionCutoff(for: configuration, now: now)
      )
      return hasReachedEnd ? .exhausted : .loaded(report)
    } catch let error as FeedClientError {
      throw mappedError(error, state: state, now: now)
    } catch let error as RSSParserError {
      throw SyncError.malformedFeed(errorDescription(of: error))
    } catch let error as URLError {
      throw transportError(urlError: error)
    } catch is CancellationError {
      throw SyncError.cancelled
    }
  }

  public func hasReachedEnd(configuration: FeedConfiguration) throws -> Bool {
    try repository.loadSyncState(feedKey: configuration.feedKey)?.hasReachedEnd ?? false
  }

  private func retentionCutoff(for configuration: FeedConfiguration, now: Date) -> Int64 {
    switch configuration.source {
    case .subreddits:
      return Int64(now.addingTimeInterval(-policy.retentionInterval).timeIntervalSince1970)
    case .privateListing:
      return .min
    }
  }

  private func transportError(urlError: URLError) -> SyncError {
    switch urlError.code {
    case .timedOut:
      return .timedOut
    case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost,
      .cannotConnectToHost, .dnsLookupFailed:
      return .offline
    case .cancelled:
      return .cancelled
    default:
      return .networkFailure
    }
  }

  public func retryDate(configuration: FeedConfiguration) throws -> Date? {
    try repository.loadSyncState(feedKey: configuration.feedKey)?.retryNotBeforeDate
  }

  private func nextEligibleDate(
    state: SyncState,
    now: Date,
    force: Bool
  ) -> Date? {
    var candidates: [Date] = []
    if let retryNotBefore = state.retryNotBeforeDate {
      candidates.append(retryNotBefore)
    }
    if !force, let lastSuccess = state.lastSuccessfulSyncDate {
      candidates.append(lastSuccess.addingTimeInterval(policy.minimumInterval))
    }
    return candidates.max()
  }

  private func mappedError(
    _ error: FeedClientError,
    state: SyncState,
    now: Date
  ) -> SyncError {
    switch error {
    case .rateLimited(let retryAfter):
      let attempt = state.rateLimitAttempt + 1
      let delay = max(retryAfter ?? 0, policy.backoffDelay(afterAttempt: attempt))
      let retryAt = now.addingTimeInterval(delay)
      _ = try? repository.recordRateLimit(
        feedKey: state.feedKey,
        retryNotBefore: Int64(retryAt.timeIntervalSince1970),
        attempt: attempt
      )
      return .rateLimited(retryAt: retryAt)
    case .invalidCredentials:
      return .invalidCredentials
    case .offline:
      return .offline
    case .timedOut:
      return .timedOut
    case .serverError(let statusCode):
      return .serverFailure(statusCode: statusCode)
    case .cancelled:
      return .cancelled
    case .unexpectedStatus, .invalidResponse, .transportFailure:
      return .networkFailure
    }
  }

  private func parse(_ data: Data) throws -> [Story] {
    try parser.parse(data)
  }

  private func errorDescription(of error: RSSParserError) -> String? {
    if case .invalidXML(let description) = error {
      return description
    }
    return nil
  }
}
