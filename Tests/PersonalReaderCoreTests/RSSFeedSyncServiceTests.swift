import XCTest

@testable import PersonalReaderCore

final class RSSFeedSyncServiceTests: XCTestCase {
  private var repository: StoryRepository!

  override func setUpWithError() throws {
    repository = try StoryRepository.inMemory()
  }

  func testFirstSyncStoresRSSEntriesWithStableIDs() async throws {
    let source = FeedSourceRecord(
      kind: .rss,
      title: "Sample",
      url: "https://example.com/feed.xml",
      refreshInterval: .thirtyMinutes
    )
    try repository.saveFeedSourceRecord(source)
    let client = SyndicationClientStub(responses: [
      source.url: .success(
        statusCode: 200,
        data: Data(rssFixture().utf8)
      )
    ])
    let service = RSSFeedSyncService(client: client, repository: repository, maximumStories: 100)

    let outcome = try await service.sync(
      source: source,
      now: Date(timeIntervalSince1970: 1_000_000)
    )
    XCTAssertEqual(outcome.report.inserted, 3)

    let stories = try repository.fetchStories(sourceId: source.id)
    XCTAssertEqual(stories.count, 3)
    XCTAssertTrue(stories.allSatisfy { $0.sourceId == source.id })
    XCTAssertGreaterThan(stories.first?.publishedAt ?? 0, 0)

    let state = try XCTUnwrap(
      repository.loadSyncState(feedKey: StoryRepository.feedKey(for: source.id))
    )
    XCTAssertEqual(state.lastSuccessfulSyncAt, 1_000_000)
  }

  func testRespectsRefreshIntervalBeforeNextSync() async throws {
    let source = FeedSourceRecord(
      kind: .rss,
      title: "Hourly",
      url: "https://example.com/feed.xml",
      refreshInterval: .oneHour
    )
    try repository.saveFeedSourceRecord(source)
    let client = SyndicationClientStub(responses: [
      source.url: .success(statusCode: 200, data: Data(rssFixture().utf8))
    ])
    let service = RSSFeedSyncService(client: client, repository: repository)

    _ = try await service.sync(source: source, now: Date(timeIntervalSince1970: 100))

    do {
      _ = try await service.sync(source: source, now: Date(timeIntervalSince1970: 200))
      XCTFail("expected notDue error")
    } catch let error as RSSSyncError {
      guard case .notDue(let next) = error else {
        return XCTFail("expected notDue, got \(error)")
      }
      XCTAssertEqual(next.timeIntervalSince1970, 100 + 3600)
    }
  }

  func testForcedSyncBypassesRefreshInterval() async throws {
    let source = FeedSourceRecord(
      kind: .rss,
      title: "Hourly",
      url: "https://example.com/feed.xml",
      refreshInterval: .oneHour
    )
    try repository.saveFeedSourceRecord(source)
    let client = SyndicationClientStub(responses: [
      source.url: .success(statusCode: 200, data: Data(rssFixture().utf8))
    ])
    let service = RSSFeedSyncService(client: client, repository: repository)

    _ = try await service.sync(source: source, now: Date(timeIntervalSince1970: 100))
    let outcome = try await service.sync(
      source: source, force: true, now: Date(timeIntervalSince1970: 200))
    XCTAssertGreaterThanOrEqual(
      outcome.report.inserted + outcome.report.updated + outcome.report.ignored, 3)
  }

  func testNotModifiedIsShortCircuitWithoutWriting() async throws {
    let source = FeedSourceRecord(
      kind: .rss,
      title: "Not Modified",
      url: "https://example.com/feed.xml"
    )
    try repository.saveFeedSourceRecord(source)
    let client = SyndicationClientStub(responses: [
      source.url: .success(statusCode: 304, data: Data())
    ])
    let service = RSSFeedSyncService(client: client, repository: repository)

    let outcome = try await service.sync(
      source: source,
      now: Date(timeIntervalSince1970: 500)
    )
    XCTAssertEqual(outcome.report.inserted, 0)
    XCTAssertTrue(try repository.fetchStories(sourceId: source.id).isEmpty)
  }

  func testMalformedFeedMapsToMalformedFeedError() async throws {
    let source = FeedSourceRecord(
      kind: .rss,
      title: "Broken",
      url: "https://example.com/feed.xml"
    )
    try repository.saveFeedSourceRecord(source)
    let client = SyndicationClientStub(responses: [
      source.url: .success(statusCode: 200, data: Data("not xml".utf8))
    ])
    let service = RSSFeedSyncService(client: client, repository: repository)

    do {
      _ = try await service.sync(source: source, now: Date(timeIntervalSince1970: 100))
      XCTFail("expected malformed feed")
    } catch let error as RSSSyncError {
      guard case .malformedFeed = error else {
        return XCTFail("expected malformedFeed, got \(error)")
      }
    }
    let state = try XCTUnwrap(
      repository.loadSyncState(feedKey: StoryRepository.feedKey(for: source.id))
    )
    XCTAssertEqual(state.lastError, "Feed could not be parsed")
  }

  func testRateLimitedPersistsRetryNotBefore() async throws {
    let source = FeedSourceRecord(
      kind: .rss,
      title: "Rate Limited",
      url: "https://example.com/feed.xml"
    )
    try repository.saveFeedSourceRecord(source)
    let client = SyndicationClientStub(responses: [
      source.url: .failure(.rateLimited(retryAfter: 120))
    ])
    let service = RSSFeedSyncService(client: client, repository: repository)

    do {
      _ = try await service.sync(source: source, now: Date(timeIntervalSince1970: 100))
      XCTFail("expected rate limited")
    } catch let error as RSSSyncError {
      guard case .rateLimited(let retryAt) = error else {
        return XCTFail("expected rateLimited, got \(error)")
      }
      XCTAssertEqual(retryAt.timeIntervalSince1970, 220)
    }
    let state = try XCTUnwrap(
      repository.loadSyncState(feedKey: StoryRepository.feedKey(for: source.id))
    )
    XCTAssertEqual(state.retryNotBefore, 220)
  }

  func testCapStoriesKeepsNewestAndDoesNotTouchOtherSources() async throws {
    let rss = FeedSourceRecord(
      kind: .rss,
      title: "Big Feed",
      url: "https://example.com/big.xml",
      refreshInterval: .thirtyMinutes
    )
    try repository.saveFeedSourceRecord(rss)
    let redditID = FeedSourceRecord.builtInRedditID()
    try repository.save(
      (1...150).map { index in
        Story(
          id: rss.id + ":rss-\(index)",
          title: "RSS \(index)",
          contentBody: "<p>r\(index)</p>",
          author: "author",
          subreddit: "feed",
          publishedAt: Int64(index),
          sourceId: rss.id
        )
      }
    )
    try repository.save([
      Story(
        id: "t3_kept",
        title: "Reddit",
        contentBody: "<p>r</p>",
        author: "u",
        subreddit: "s",
        publishedAt: 999,
        sourceId: redditID
      )
    ])

    let client = SyndicationClientStub(responses: [
      rss.url: .success(statusCode: 200, data: Data(rssFixture().utf8))
    ])
    let service = RSSFeedSyncService(client: client, repository: repository, maximumStories: 10)
    _ = try await service.sync(source: rss, force: true, now: Date(timeIntervalSince1970: 0))

    let rssStories = try repository.fetchStories(sourceId: rss.id)
    XCTAssertLessThanOrEqual(rssStories.count, 10)
    XCTAssertNotNil(try repository.fetchStory(id: "t3_kept"))
  }

  private func rssFixture() -> String {
    let items = (1...3).map { index in
      """
      <item>
        <title>Story \(index)</title>
        <link>https://example.com/\(index)</link>
        <guid>https://example.com/\(index)</guid>
        <pubDate>Wed, 02 Oct 2024 13:0\(index):00 +0000</pubDate>
        <description><![CDATA[<p>body \(index)</p>]]></description>
      </item>
      """
    }.joined(separator: "\n")
    return """
      <rss version="2.0">
        <channel>
          <title>Fixture Feed</title>
          <link>https://example.com</link>
          \(items)
        </channel>
      </rss>
      """
  }
}

private struct SyndicationClientStub: SyndicationFeedFetching {
  enum Result {
    case success(statusCode: Int, data: Data, headers: [String: String] = [:])
    case failure(SyndicationClientError)
  }

  let responses: [String: Result]

  func fetch(
    url: URL,
    etag: String?,
    lastModified: String?
  ) async throws -> SyndicationFetchResponse {
    let key = url.absoluteString
    guard let result = responses[key] else {
      throw SyndicationClientError.invalidResponse
    }
    switch result {
    case .success(let status, let data, let headers):
      return SyndicationFetchResponse(
        statusCode: status,
        data: data,
        etag: headers["ETag"],
        lastModified: headers["Last-Modified"]
      )
    case .failure(let error):
      throw error
    }
  }
}
