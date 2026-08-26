import XCTest

@testable import PersonalReaderCore

final class LibrarySyncServiceTests: XCTestCase {
  private var repository: StoryRepository!
  private var sourceStore: FeedSourceStore!

  override func setUpWithError() throws {
    repository = try StoryRepository.inMemory()
    sourceStore = try FeedSourceStore.inMemory()
  }

  func testRefreshesRedditAndAllEnabledRSSFeeds() async throws {
    let redditService = StubRedditService()
    redditService.outcome = .success(
      SyncOutcome.synced(
        SyncReport(inserted: 1, updated: 0, ignored: 0, deleted: 0)
      ))
    let rssService = StubRSSService()
    let source = FeedSourceRecord(
      kind: .rss,
      title: "RSS Feed",
      url: "https://example.com/rss.xml",
      refreshInterval: .thirtyMinutes
    )
    try sourceStore.save(source)
    rssService.responses[source.id] = .success(
      RSSSyncOutcome(
        report: SyncReport(inserted: 2, updated: 0, ignored: 0, deleted: 0),
        etag: nil,
        lastModified: nil,
        nextEligibleAt: Date()
      )
    )

    let configuration = try FeedConfiguration(
      username: "reader",
      token: "token",
      source: .subscribed,
      userAgent: "ua"
    )
    let library = LibrarySyncService(
      redditService: redditService,
      rssService: rssService,
      sourceStore: sourceStore,
      repository: repository,
      redditConfigurationProvider: { configuration }
    )

    let report = await library.refreshDueSources(now: Date(timeIntervalSince1970: 100))
    XCTAssertEqual(report.succeededCount, 2)
    XCTAssertEqual(report.totalAttempted, 2)
    XCTAssertNotNil(report.reddit)
  }

  func testPartialFailureCountsSuccessfulSourcesOnly() async throws {
    let sourceA = FeedSourceRecord(kind: .rss, title: "A", url: "https://a.example/rss")
    let sourceB = FeedSourceRecord(kind: .rss, title: "B", url: "https://b.example/rss")
    try sourceStore.save(sourceA)
    try sourceStore.save(sourceB)

    let redditService = StubRedditService()
    redditService.outcome = .success(
      SyncOutcome.synced(
        SyncReport(inserted: 0, updated: 0, ignored: 0, deleted: 0)
      ))
    let rssService = StubRSSService()
    rssService.responses[sourceA.id] = .success(
      RSSSyncOutcome(
        report: SyncReport(inserted: 1, updated: 0, ignored: 0, deleted: 0),
        etag: nil,
        lastModified: nil,
        nextEligibleAt: Date()
      )
    )
    rssService.responses[sourceB.id] = .failure(.offline)

    let configuration = try FeedConfiguration(
      username: "reader",
      token: "token",
      source: .subscribed,
      userAgent: "ua"
    )
    let library = LibrarySyncService(
      redditService: redditService,
      rssService: rssService,
      sourceStore: sourceStore,
      repository: repository,
      redditConfigurationProvider: { configuration }
    )

    let report = await library.refreshDueSources()
    XCTAssertEqual(report.succeededCount, 2)
    XCTAssertEqual(report.totalAttempted, 3)
  }

  func testRedditSkipsWhenNoConfiguration() async throws {
    let redditService = StubRedditService()
    let rssService = StubRSSService()
    let library = LibrarySyncService(
      redditService: redditService,
      rssService: rssService,
      sourceStore: sourceStore,
      repository: repository,
      redditConfigurationProvider: { nil }
    )

    let report = await library.refreshDueSources()
    XCTAssertNil(report.reddit)
    XCTAssertEqual(report.totalAttempted, 0)
  }

  func testNextScheduledDateUsesEarliestSourceDue() async throws {
    let redditService = StubRedditService()
    let rssService = StubRSSService()
    let sourceA = FeedSourceRecord(
      kind: .rss,
      title: "A",
      url: "https://a.example/rss",
      refreshInterval: .oneHour
    )
    try sourceStore.save(sourceA)
    try repository.recordSourceSuccess(sourceId: sourceA.id, at: 1_000)
    try repository.recordSourceSuccess(
      sourceId: FeedSourceRecord.builtInRedditID(),
      at: 900
    )

    let library = LibrarySyncService(
      redditService: redditService,
      rssService: rssService,
      sourceStore: sourceStore,
      repository: repository,
      redditConfigurationProvider: { nil }
    )

    let next = await library.nextScheduledRefreshDate(now: Date(timeIntervalSince1970: 0))
    XCTAssertEqual(next?.timeIntervalSince1970, 900 + 1800)
  }
}

private final class StubRedditService: RedditSyncing, @unchecked Sendable {
  var outcome: Result<SyncOutcome, Error> = .success(
    .synced(SyncReport(inserted: 0, updated: 0, ignored: 0, deleted: 0))
  )
  var loadOlderOutcome: Result<OlderSyncOutcome, Error> = .success(.exhausted)

  func sync(
    configuration: FeedConfiguration,
    force: Bool,
    now: Date
  ) async throws -> SyncOutcome {
    try outcome.get()
  }

  func loadOlder(configuration: FeedConfiguration, now: Date) async throws -> OlderSyncOutcome {
    try loadOlderOutcome.get()
  }

  func hasReachedEnd(configuration: FeedConfiguration) async throws -> Bool { false }
}

private final class StubRSSService: RSSSyncing, @unchecked Sendable {
  var responses: [String: Result<RSSSyncOutcome, RSSSyncError>] = [:]

  func sync(source: FeedSourceRecord, force: Bool, now: Date) async throws -> RSSSyncOutcome {
    switch responses[source.id] {
    case .success(let outcome): return outcome
    case .failure(let error): throw error
    case .none: throw RSSSyncError.malformedFeed("No response configured")
    }
  }
}
