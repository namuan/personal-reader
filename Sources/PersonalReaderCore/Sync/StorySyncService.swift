import Foundation
import OSLog

private let redditSyncLogger = Logger(
  subsystem: "com.github.namuan.personalreader", category: "reddit-sync"
)

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

public protocol RedditSyncing: Sendable {
  func sync(
    configuration: FeedConfiguration,
    force: Bool,
    now: Date
  ) async throws -> SyncOutcome

  func loadOlder(
    configuration: FeedConfiguration,
    now: Date
  ) async throws -> OlderSyncOutcome

  func hasReachedEnd(configuration: FeedConfiguration) async throws -> Bool
}

public protocol RSSSyncing: Sendable {
  func sync(
    source: FeedSourceRecord,
    force: Bool,
    now: Date
  ) async throws -> RSSSyncOutcome
}

public actor StorySyncService: RedditSyncing {
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
    let feedKey = FeedSourceRecord.builtInRedditID()
    let state =
      try repository.loadSyncState(feedKey: feedKey)
      ?? SyncState(feedKey: feedKey)
    let nextEligible = nextEligibleDate(state: state, now: now, force: force)

    if isSyncing {
      redditSyncLogger.notice("Reddit refresh skipped because a Reddit sync is active")
      return .skipped(nextAllowedAt: nextEligible ?? now)
    }
    if let nextEligible, nextEligible > now {
      redditSyncLogger.notice("Reddit refresh skipped because it is not due")
      return .skipped(nextAllowedAt: nextEligible)
    }
    redditSyncLogger.notice("Reddit refresh started force=\(force, privacy: .public)")
    isSyncing = true
    defer { isSyncing = false }

    do {
      let data = try await feedClient.fetch(configuration: configuration)
      let stories = try parse(data, sourceId: FeedSourceRecord.builtInRedditID())
      let capped = Array(stories.prefix(policy.maximumStories))
      let report = try repository.applySync(
        stories: capped,
        syncStateUpdate: SyncStateUpdate(
          feedKey: feedKey,
          lastSuccessfulSyncAt: Int64(now.timeIntervalSince1970),
          rateLimitAttempt: 0,
          olderCursor: state.olderCursor ?? capped.last?.id
        ),
        retentionCutoff: retentionCutoff(for: configuration, now: now)
      )
      redditSyncLogger.notice(
        "Reddit refresh completed parsed=\(stories.count, privacy: .public) stored=\(capped.count, privacy: .public) inserted=\(report.inserted, privacy: .public) updated=\(report.updated, privacy: .public) ignored=\(report.ignored, privacy: .public) deleted=\(report.deleted, privacy: .public)"
      )
      return .synced(report)
    } catch let error as FeedClientError {
      let syncError = mappedError(error, state: state, now: now)
      redditSyncLogger.error(
        "Reddit refresh failed category=\(self.syncErrorCategory(syncError), privacy: .public)")
      throw syncError
    } catch let error as RSSParserError {
      redditSyncLogger.error("Reddit refresh failed category=malformed-feed")
      throw SyncError.malformedFeed(errorDescription(of: error))
    } catch let error as URLError {
      let syncError = transportError(urlError: error)
      redditSyncLogger.error(
        "Reddit refresh failed category=\(self.syncErrorCategory(syncError), privacy: .public)")
      throw syncError
    } catch is CancellationError {
      redditSyncLogger.notice("Reddit refresh cancelled")
      throw SyncError.cancelled
    }
  }

  public func loadOlder(
    configuration: FeedConfiguration,
    now: Date = Date()
  ) async throws -> OlderSyncOutcome {
    let feedKey = FeedSourceRecord.builtInRedditID()
    let state =
      try repository.loadSyncState(feedKey: feedKey)
      ?? SyncState(feedKey: feedKey)
    if state.hasReachedEnd {
      redditSyncLogger.notice("Reddit pagination skipped because the end was reached")
      return .exhausted
    }
    if let retryNotBefore = state.retryNotBeforeDate, retryNotBefore > now {
      redditSyncLogger.notice("Reddit pagination skipped because retry is deferred")
      return .skipped(nextAllowedAt: retryNotBefore)
    }
    if isSyncing {
      redditSyncLogger.notice("Reddit pagination skipped because a Reddit sync is active")
      return .skipped(nextAllowedAt: now)
    }
    let cursor: String?
    if let olderCursor = state.olderCursor {
      cursor = olderCursor
    } else {
      cursor = try repository.oldestStoryID(sourceId: FeedSourceRecord.builtInRedditID())
    }
    guard let cursor else {
      redditSyncLogger.notice("Reddit pagination reached the end because no cursor is available")
      return .exhausted
    }

    redditSyncLogger.notice("Reddit pagination started")
    isSyncing = true
    defer { isSyncing = false }

    do {
      let data = try await feedClient.fetch(configuration: configuration, after: cursor)
      let stories = try parse(data, sourceId: FeedSourceRecord.builtInRedditID())
      let capped = Array(stories.prefix(policy.maximumStories))
      let hasReachedEnd = capped.isEmpty || capped.last?.id == cursor
      let report = try repository.applySync(
        stories: capped,
        syncStateUpdate: SyncStateUpdate(
          feedKey: feedKey,
          lastSuccessfulSyncAt: Int64(now.timeIntervalSince1970),
          rateLimitAttempt: 0,
          olderCursor: capped.last?.id ?? cursor,
          hasReachedEnd: hasReachedEnd
        ),
        retentionCutoff: retentionCutoff(for: configuration, now: now)
      )
      redditSyncLogger.notice(
        "Reddit pagination completed parsed=\(stories.count, privacy: .public) stored=\(capped.count, privacy: .public) inserted=\(report.inserted, privacy: .public) updated=\(report.updated, privacy: .public) deleted=\(report.deleted, privacy: .public) exhausted=\(hasReachedEnd, privacy: .public)"
      )
      return hasReachedEnd ? .exhausted : .loaded(report)
    } catch let error as FeedClientError {
      let syncError = mappedError(error, state: state, now: now)
      redditSyncLogger.error(
        "Reddit pagination failed category=\(self.syncErrorCategory(syncError), privacy: .public)")
      throw syncError
    } catch let error as RSSParserError {
      redditSyncLogger.error("Reddit pagination failed category=malformed-feed")
      throw SyncError.malformedFeed(errorDescription(of: error))
    } catch let error as URLError {
      let syncError = transportError(urlError: error)
      redditSyncLogger.error(
        "Reddit pagination failed category=\(self.syncErrorCategory(syncError), privacy: .public)")
      throw syncError
    } catch is CancellationError {
      redditSyncLogger.notice("Reddit pagination cancelled")
      throw SyncError.cancelled
    }
  }

  public func hasReachedEnd(configuration: FeedConfiguration) throws -> Bool {
    let feedKey = FeedSourceRecord.builtInRedditID()
    return try repository.loadSyncState(feedKey: feedKey)?.hasReachedEnd ?? false
  }

  private func syncErrorCategory(_ error: SyncError) -> String {
    switch error {
    case .rateLimited: return "rate-limited"
    case .invalidCredentials: return "invalid-credentials"
    case .offline: return "offline"
    case .timedOut: return "timed-out"
    case .serverFailure: return "server-failure"
    case .malformedFeed: return "malformed-feed"
    case .networkFailure: return "network-failure"
    case .cancelled: return "cancelled"
    }
  }

  private func retentionCutoff(for configuration: FeedConfiguration, now: Date) -> Int64 {
    switch configuration.source {
    case .subscribed, .privateListing:
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
    let feedKey = FeedSourceRecord.builtInRedditID()
    return try repository.loadSyncState(feedKey: feedKey)?.retryNotBeforeDate
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

  private func parse(_ data: Data, sourceId: String) throws -> [Story] {
    let raw = try parser.parse(data)
    return raw.map { story in
      Story(
        id: story.id,
        title: story.title,
        contentBody: story.contentBody,
        author: story.author,
        subreddit: story.subreddit,
        publishedAt: story.publishedAt,
        link: story.link,
        isRead: story.isRead,
        sourceId: sourceId
      )
    }
  }

  private func errorDescription(of error: RSSParserError) -> String? {
    if case .invalidXML(let description) = error {
      return description
    }
    return nil
  }
}
