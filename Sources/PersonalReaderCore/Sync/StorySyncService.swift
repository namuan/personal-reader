import Foundation

public struct SyncPolicy: Equatable, Sendable {
  public let minimumInterval: TimeInterval
  public let maximumStories: Int
  public let retentionInterval: TimeInterval

  public init(
    minimumInterval: TimeInterval = 30 * 60,
    maximumStories: Int = 50,
    retentionInterval: TimeInterval = 14 * 24 * 60 * 60
  ) {
    self.minimumInterval = minimumInterval
    self.maximumStories = maximumStories
    self.retentionInterval = retentionInterval
  }
}

public enum SyncResult: Equatable, Sendable {
  case skipped(nextAllowedAt: Date)
  case synchronized(storedCount: Int, deletedCount: Int)
}

public actor StorySyncService {
  private let feedClient: any FeedFetching
  private let parser: any StoryParsing
  private let repository: StoryRepository
  private let policy: SyncPolicy

  private var lastSuccessfulSyncAt: Date?
  private var nextAllowedSyncAt: Date?
  private var rateLimitAttempt = 0

  public init(
    feedClient: any FeedFetching,
    parser: any StoryParsing,
    repository: StoryRepository,
    policy: SyncPolicy = SyncPolicy()
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
  ) async throws -> SyncResult {
    if let nextAllowedSyncAt, now < nextAllowedSyncAt {
      return .skipped(nextAllowedAt: nextAllowedSyncAt)
    }
    if !force, let lastSuccessfulSyncAt {
      let nextSyncAt = lastSuccessfulSyncAt.addingTimeInterval(policy.minimumInterval)
      if now < nextSyncAt {
        return .skipped(nextAllowedAt: nextSyncAt)
      }
    }

    do {
      let data = try await feedClient.fetch(configuration: configuration)
      let stories = Array(try parser.parse(data).prefix(policy.maximumStories))
      try repository.save(stories)
      let cutoff = Int64(now.addingTimeInterval(-policy.retentionInterval).timeIntervalSince1970)
      let deletedCount = try repository.deletePublished(before: cutoff)

      lastSuccessfulSyncAt = now
      nextAllowedSyncAt = nil
      rateLimitAttempt = 0

      return .synchronized(
        storedCount: stories.count,
        deletedCount: deletedCount
      )
    } catch let FeedClientError.rateLimited(retryAfter) {
      rateLimitAttempt += 1
      let exponentialDelay = min(
        pow(2, Double(rateLimitAttempt - 1)) * 60,
        policy.minimumInterval
      )
      let delay = max(retryAfter ?? 0, exponentialDelay)
      nextAllowedSyncAt = now.addingTimeInterval(delay)
      throw FeedClientError.rateLimited(retryAfter: delay)
    }
  }
}
