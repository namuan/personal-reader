import Foundation
import OSLog

private let rssSyncLogger = Logger(
  subsystem: "com.github.namuan.personalreader", category: "rss-sync"
)

public struct RSSSyncOutcome: Equatable, Sendable {
  public let report: SyncReport
  public let etag: String?
  public let lastModified: String?
  public let nextEligibleAt: Date
}

public enum RSSSyncError: Error, Equatable, Sendable {
  case rateLimited(retryAt: Date)
  case invalidCredentials
  case offline
  case timedOut
  case serverFailure(statusCode: Int)
  case malformedFeed(String?)
  case networkFailure
  case cancelled
  case insecureScheme
  case alreadySyncing
  case notDue(nextEligibleAt: Date)
}

public actor RSSFeedSyncService: RSSSyncing {
  private let client: any SyndicationFeedFetching
  private let parser: SyndicationParser
  private let repository: StoryRepository
  private let maximumStories: Int
  private var isSyncing: [String: Bool] = [:]

  public init(
    client: any SyndicationFeedFetching,
    parser: SyndicationParser = SyndicationParser(),
    repository: StoryRepository,
    maximumStories: Int = 100
  ) {
    self.client = client
    self.parser = parser
    self.repository = repository
    self.maximumStories = maximumStories
  }

  public func sync(
    source: FeedSourceRecord,
    force: Bool = false,
    now: Date = Date()
  ) async throws -> RSSSyncOutcome {
    let feedKey = StoryRepository.feedKey(for: source.id)
    let state =
      try repository.loadSyncState(feedKey: feedKey) ?? SyncState(feedKey: feedKey)
    let minimumInterval: TimeInterval = source.refreshInterval.seconds
    if let nextEligible = nextEligibleDate(
      state: state, now: now, force: force, minimumInterval: minimumInterval
    ), nextEligible > now {
      rssSyncLogger.debug(
        "RSS refresh skipped source=\(source.id, privacy: .public) reason=not-due")
      throw RSSSyncError.notDue(nextEligibleAt: nextEligible)
    }
    if isSyncing[source.id] == true {
      rssSyncLogger.notice(
        "RSS refresh skipped source=\(source.id, privacy: .public) reason=already-syncing")
      throw RSSSyncError.alreadySyncing
    }
    rssSyncLogger.notice(
      "RSS refresh started source=\(source.id, privacy: .public) force=\(force, privacy: .public)"
    )
    isSyncing[source.id] = true
    defer { isSyncing[source.id] = false }

    guard let url = URL(string: source.url) else {
      rssSyncLogger.error(
        "RSS refresh failed source=\(source.id, privacy: .public) category=malformed-feed")
      throw RSSSyncError.malformedFeed("Invalid feed URL")
    }
    do {
      let response = try await client.fetch(
        url: url,
        etag: state.etag,
        lastModified: state.lastModified
      )
      if response.isNotModified {
        let timestamp = Int64(now.timeIntervalSince1970)
        try repository.recordSourceSuccess(sourceId: source.id, at: timestamp)
        rssSyncLogger.notice(
          "RSS refresh completed source=\(source.id, privacy: .public) notModified=true")
        return RSSSyncOutcome(
          report: SyncReport(inserted: 0, updated: 0, ignored: 0, deleted: 0),
          etag: response.etag ?? state.etag,
          lastModified: response.lastModified ?? state.lastModified,
          nextEligibleAt: now.addingTimeInterval(minimumInterval)
        )
      }
      let feed = try parser.parse(response.data, fallbackFetchedAt: now)
      let stories = makeStories(
        from: feed, source: source, fallbackTimestamp: Int64(now.timeIntervalSince1970))
      let capped = Array(stories.prefix(maximumStories))
      let report = try repository.applySync(
        stories: capped,
        syncStateUpdate: SyncStateUpdate(
          feedKey: feedKey,
          lastSuccessfulSyncAt: Int64(now.timeIntervalSince1970),
          rateLimitAttempt: 0,
          etag: response.etag,
          lastModified: response.lastModified
        ),
        retentionCutoff: .min
      )
      let removedCount = try repository.capStoriesPerSource(
        sourceId: source.id, maximum: maximumStories)
      try repository.recordSourceSuccess(sourceId: source.id, at: Int64(now.timeIntervalSince1970))
      rssSyncLogger.notice(
        "RSS refresh completed source=\(source.id, privacy: .public) parsed=\(stories.count, privacy: .public) stored=\(capped.count, privacy: .public) inserted=\(report.inserted, privacy: .public) updated=\(report.updated, privacy: .public) ignored=\(report.ignored, privacy: .public) retainedRemoved=\(removedCount, privacy: .public)"
      )
      return RSSSyncOutcome(
        report: report,
        etag: response.etag,
        lastModified: response.lastModified,
        nextEligibleAt: now.addingTimeInterval(minimumInterval)
      )
    } catch let error as SyndicationClientError {
      let mapped = mapError(error, source: source, state: state, now: now)
      rssSyncLogger.error(
        "RSS refresh failed source=\(source.id, privacy: .public) category=\(self.rssErrorCategory(mapped), privacy: .public)"
      )
      try repository.recordSourceError(
        sourceId: source.id,
        error: describe(error),
        at: Int64(now.timeIntervalSince1970)
      )
      throw mapped
    } catch let error as RSSParserError {
      rssSyncLogger.error(
        "RSS refresh failed source=\(source.id, privacy: .public) category=malformed-feed")
      try repository.recordSourceError(
        sourceId: source.id,
        error: "Feed could not be parsed",
        at: Int64(now.timeIntervalSince1970)
      )
      throw RSSSyncError.malformedFeed(errorDescription(of: error))
    } catch let error as URLError {
      let mapped = mapTransportError(error)
      rssSyncLogger.error(
        "RSS refresh failed source=\(source.id, privacy: .public) category=\(self.rssErrorCategory(mapped), privacy: .public)"
      )
      try repository.recordSourceError(
        sourceId: source.id,
        error: "Network error",
        at: Int64(now.timeIntervalSince1970)
      )
      throw mapped
    } catch is CancellationError {
      rssSyncLogger.notice("RSS refresh cancelled source=\(source.id, privacy: .public)")
      throw RSSSyncError.cancelled
    } catch let error as RSSSyncError {
      rssSyncLogger.error(
        "RSS refresh failed source=\(source.id, privacy: .public) category=\(self.rssErrorCategory(error), privacy: .public)"
      )
      throw error
    } catch {
      rssSyncLogger.error(
        "RSS refresh failed source=\(source.id, privacy: .public) category=unknown")
      try repository.recordSourceError(
        sourceId: source.id,
        error: "Unknown error",
        at: Int64(now.timeIntervalSince1970)
      )
      throw RSSSyncError.networkFailure
    }
  }

  public func testSync(url: URL) async throws -> SyndicationFeed {
    let response = try await client.fetch(url: url, etag: nil, lastModified: nil)
    return try parser.parse(response.data, fallbackFetchedAt: Date())
  }

  private func makeStories(
    from feed: SyndicationFeed,
    source: FeedSourceRecord,
    fallbackTimestamp: Int64
  ) -> [Story] {
    feed.entries.compactMap { entry in
      guard !entry.title.isEmpty else { return nil }
      let idSource = entry.id.isEmpty ? entry.link : entry.id
      guard !idSource.isEmpty else { return nil }
      let storyId = source.id + ":" + Self.deterministicID(from: idSource)
      let subreddit = entry.categories.first.map(Self.normalizeCategory) ?? source.title
      let publishedAt = entry.publishedAt == 0 ? fallbackTimestamp : entry.publishedAt
      return Story(
        id: storyId,
        title: entry.title,
        contentBody: entry.content,
        author: entry.author,
        subreddit: subreddit,
        publishedAt: publishedAt,
        link: entry.link,
        isRead: false,
        sourceId: source.id
      )
    }
  }

  private static func deterministicID(from string: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in string.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }

  private static func normalizeCategory(_ value: String) -> String {
    var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["/r/", "r/", "/category/", "category/"] {
      if trimmed.lowercased().hasPrefix(prefix) {
        trimmed = String(trimmed.dropFirst(prefix.count))
        break
      }
    }
    if let slash = trimmed.firstIndex(of: "/") {
      trimmed = String(trimmed[..<slash])
    }
    return trimmed.isEmpty ? "feed" : trimmed
  }

  private func nextEligibleDate(
    state: SyncState,
    now: Date,
    force: Bool,
    minimumInterval: TimeInterval
  ) -> Date? {
    var candidates: [Date] = []
    if let retryNotBefore = state.retryNotBeforeDate {
      candidates.append(retryNotBefore)
    }
    if !force, let lastSuccess = state.lastSuccessfulSyncDate {
      candidates.append(lastSuccess.addingTimeInterval(minimumInterval))
    }
    return candidates.max()
  }

  private func rssErrorCategory(_ error: RSSSyncError) -> String {
    switch error {
    case .rateLimited: return "rate-limited"
    case .invalidCredentials: return "invalid-credentials"
    case .offline: return "offline"
    case .timedOut: return "timed-out"
    case .serverFailure: return "server-failure"
    case .malformedFeed: return "malformed-feed"
    case .networkFailure: return "network-failure"
    case .cancelled: return "cancelled"
    case .insecureScheme: return "insecure-scheme"
    case .alreadySyncing: return "already-syncing"
    case .notDue: return "not-due"
    }
  }

  private func mapError(
    _ error: SyndicationClientError,
    source: FeedSourceRecord,
    state: SyncState,
    now: Date
  ) -> RSSSyncError {
    switch error {
    case .rateLimited(let retryAfter):
      let delay = max(retryAfter ?? 0, 60)
      let retryAt = now.addingTimeInterval(delay)
      _ = try? repository.recordRateLimit(
        feedKey: StoryRepository.feedKey(for: source.id),
        retryNotBefore: Int64(retryAt.timeIntervalSince1970),
        attempt: state.rateLimitAttempt + 1
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
    case .insecureScheme, .insecureRedirect:
      return .malformedFeed("Feed URL must use HTTPS")
    case .invalidResponse, .unexpectedStatus:
      return .networkFailure
    case .transportFailure:
      return .networkFailure
    }
  }

  private func mapTransportError(_ error: URLError) -> RSSSyncError {
    switch error.code {
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

  private func describe(_ error: SyndicationClientError) -> String {
    switch error {
    case .insecureScheme, .insecureRedirect: return "Insecure feed URL"
    case .invalidResponse: return "Invalid response"
    case .invalidCredentials: return "Authentication required"
    case .rateLimited: return "Rate limited"
    case .serverError: return "Server error"
    case .offline: return "Offline"
    case .timedOut: return "Timed out"
    case .cancelled: return "Cancelled"
    case .unexpectedStatus(let status): return "HTTP \(status)"
    case .transportFailure(let code): return "Network error (\(code))"
    }
  }

  private func errorDescription(of error: RSSParserError) -> String? {
    if case .invalidXML(let description) = error { return description }
    return nil
  }
}
