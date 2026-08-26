import XCTest

@testable import PersonalReaderCore

final class StorySyncServiceTests: XCTestCase {
  private var repository: StoryRepository!

  override func setUpWithError() throws {
    repository = try StoryRepository.inMemory()
  }

  private let configuration = try! FeedConfiguration(
    username: "reader",
    token: "token",
    source: .subscribed,
    userAgent: "ua"
  )

  private func makeService(
    client: any FeedFetching,
    policy: SyncPolicy = .standard
  ) -> StorySyncService {
    StorySyncService(
      feedClient: client,
      parser: RedditRSSParser(),
      repository: repository,
      policy: policy
    )
  }

  private func feedXML(count: Int, startID: Int = 0) -> String {
    let items = (0..<count).map { index -> String in
      """
      <item>
        <title>Story \(index)</title>
        <guid>t3_\(String(format: "%07d", startID + index))</guid>
        <category>shortstories</category>
        <pubDate>Sat, 24 Aug 2024 12:\(String(format: "%02d", index % 60)):00 +0000</pubDate>
        <description><![CDATA[<p>Body \(index)</p>]]></description>
      </item>
      """
    }.joined()
    return "<rss version=\"2.0\"><channel>\(items)</channel></rss>"
  }

  func testFirstSyncStoresStoriesAndState() async throws {
    let client = FeedClientMock(data: Data(feedXML(count: 3).utf8))
    let service = makeService(client: client)

    let outcome = try await service.sync(
      configuration: configuration, now: Date(timeIntervalSince1970: 1000))

    guard case .synced(let report) = outcome else {
      return XCTFail("expected synced")
    }
    XCTAssertEqual(report.inserted, 3)
    XCTAssertEqual(try repository.fetchStories().count, 3)
    let state = try XCTUnwrap(repository.loadSyncState(feedKey: FeedSourceRecord.builtInRedditID()))
    XCTAssertEqual(state.lastSuccessfulSyncAt, 1000)
  }

  func testMinimumIntervalThrottlesNonForcedSync() async throws {
    try repository.applySync(
      stories: [],
      syncStateUpdate: SyncStateUpdate(
        feedKey: FeedSourceRecord.builtInRedditID(),
        lastSuccessfulSyncAt: 1000,
        rateLimitAttempt: 0),
      retentionCutoff: 0
    )
    let service = makeService(client: FeedClientMock(data: Data()))

    let outcome = try await service.sync(
      configuration: configuration,
      now: Date(timeIntervalSince1970: 1000 + 29 * 60)
    )

    guard case .skipped(let nextAllowedAt) = outcome else {
      return XCTFail("expected skipped")
    }
    XCTAssertEqual(nextAllowedAt.timeIntervalSince1970, 1000 + 30 * 60)
  }

  func testForceBypassesMinimumIntervalButNotBackoff() async throws {
    _ = try repository.recordRateLimit(
      feedKey: FeedSourceRecord.builtInRedditID(),
      retryNotBefore: 2000,
      attempt: 1
    )
    let service = makeService(
      client: FeedClientMock(data: Data("<rss version=\"2.0\"><channel/></rss>".utf8)))

    let throttled = try await service.sync(
      configuration: configuration,
      force: true,
      now: Date(timeIntervalSince1970: 1500)
    )
    guard case .skipped(let untilBackoffEnds) = throttled else {
      return XCTFail("expected skipped during backoff")
    }
    XCTAssertEqual(untilBackoffEnds.timeIntervalSince1970, 2000)

    let outcome = try await service.sync(
      configuration: configuration,
      force: true,
      now: Date(timeIntervalSince1970: 2001)
    )
    guard case .synced = outcome else {
      return XCTFail("expected synced after backoff window")
    }
  }

  func testRateLimitPersistsExponentialBackoffAcrossRelaunch() async throws {
    let rateLimitedClient = FeedClientMock(statusCode: 429, data: Data())
    let firstInstance = makeService(client: rateLimitedClient)

    do {
      _ = try await firstInstance.sync(
        configuration: configuration, now: Date(timeIntervalSince1970: 0))
      XCTFail("expected rate limit error")
    } catch let error as SyncError {
      guard case .rateLimited(let retryAt) = error else {
        return XCTFail("wrong error \(error)")
      }
      XCTAssertEqual(retryAt.timeIntervalSince1970, 60)
    }

    let secondInstance = makeService(client: FeedClientMock(data: Data()))
    let outcomeAt59 = try await secondInstance.sync(
      configuration: configuration,
      now: Date(timeIntervalSince1970: 59)
    )
    guard case .skipped(let until) = outcomeAt59 else {
      return XCTFail("relaunch must not bypass backoff, got \(outcomeAt59)")
    }
    XCTAssertEqual(until.timeIntervalSince1970, 60)

    let thirdInstance = makeService(client: FeedClientMock(statusCode: 429, data: Data()))
    do {
      _ = try await thirdInstance.sync(
        configuration: configuration, force: true, now: Date(timeIntervalSince1970: 61))
      XCTFail("expected second rate limit error")
    } catch let error as SyncError {
      guard case .rateLimited(let retryAt) = error else {
        return XCTFail("wrong error \(error)")
      }
      XCTAssertEqual(retryAt.timeIntervalSince1970, 61 + 120)
    }

    let state = try XCTUnwrap(repository.loadSyncState(feedKey: FeedSourceRecord.builtInRedditID()))
    XCTAssertEqual(state.rateLimitAttempt, 2)
  }

  func testRetryAfterHeaderExtendsBackoffWindow() async throws {
    let client = FeedClientMock(
      statusCode: 429,
      headers: ["Retry-After": "300"],
      data: Data()
    )
    let service = makeService(client: client)

    do {
      _ = try await service.sync(configuration: configuration, now: Date(timeIntervalSince1970: 10))
      XCTFail("expected rate limit error")
    } catch let error as SyncError {
      guard case .rateLimited(let retryAt) = error else {
        return XCTFail("wrong error \(error)")
      }
      XCTAssertEqual(retryAt.timeIntervalSince1970, 310)
    }
  }

  func testConcurrentTriggersProduceOneRequest() async throws {
    let client = CountingFetchClient(
      delayNanoseconds: 250_000_000, data: Data(feedXML(count: 2).utf8))
    let service = makeService(client: client)
    let syncConfiguration = configuration

    async let firstOutcome = service.sync(
      configuration: syncConfiguration, now: Date(timeIntervalSince1970: 0))
    async let secondOutcome = service.sync(
      configuration: syncConfiguration, now: Date(timeIntervalSince1970: 1))
    let first = try await firstOutcome
    let second = try await secondOutcome
    let results = [first, second]

    let fetchCount = await client.fetchCount
    XCTAssertEqual(fetchCount, 1)
    XCTAssertTrue(results.contains { if case .synced = $0 { return true } else { return false } })
    XCTAssertTrue(results.contains { if case .skipped = $0 { return true } else { return false } })
  }

  func testIngestionCapsAtMaximumStories() async throws {
    let client = FeedClientMock(data: Data(feedXML(count: 80).utf8))
    let service = makeService(client: client)

    let outcome = try await service.sync(
      configuration: configuration, now: Date(timeIntervalSince1970: 0))

    guard case .synced(let report) = outcome else {
      return XCTFail("expected synced")
    }
    XCTAssertEqual(report.inserted, 50)
    XCTAssertEqual(try repository.fetchStories().count, 50)
  }

  func testLoadOlderUsesThePreviousPageCursorAndPersistsItsStories() async throws {
    let firstPage = Data(feedXML(count: 2, startID: 0).utf8)
    let secondPage = Data(feedXML(count: 2, startID: 2).utf8)
    let emptyPage = Data("<rss version=\"2.0\"><channel/></rss>".utf8)
    let client = FeedClientMock(
      data: firstPage,
      dataByCursor: [
        "t3_0000001": secondPage,
        "t3_0000003": emptyPage,
      ]
    )
    let service = makeService(
      client: client,
      policy: SyncPolicy(maximumStories: 2)
    )

    _ = try await service.sync(configuration: configuration, now: Date(timeIntervalSince1970: 0))
    let older = try await service.loadOlder(
      configuration: configuration,
      now: Date(timeIntervalSince1970: 1)
    )

    guard case .loaded(let report) = older else {
      return XCTFail("expected older page")
    }
    XCTAssertEqual(report.inserted, 2)
    XCTAssertEqual(try repository.fetchStories().count, 4)

    let exhausted = try await service.loadOlder(
      configuration: configuration,
      now: Date(timeIntervalSince1970: 2)
    )
    XCTAssertEqual(exhausted, .exhausted)
    let hasReachedEnd = try await service.hasReachedEnd(configuration: configuration)
    XCTAssertTrue(hasReachedEnd)
  }

  func testCleanupKeepsOlderSubscribedEntries() async throws {
    try repository.save([
      makeStory(id: "t3_old", publishedAt: -20 * 24 * 3600),
      makeStory(id: "t3_recent", publishedAt: 150),
    ])
    let client = FeedClientMock(data: Data(feedXML(count: 1).utf8))
    let service = makeService(client: client)

    let outcome = try await service.sync(
      configuration: configuration,
      now: Date(timeIntervalSince1970: 14 * 24 * 3600 + 100)
    )

    guard case .synced(let report) = outcome else {
      return XCTFail("expected synced")
    }
    XCTAssertEqual(report.deleted, 0)
    let ids = try repository.fetchStories().map(\.id).sorted()
    XCTAssertEqual(ids, ["t3_0000000", "t3_old", "t3_recent"])
  }

  func testPrivateListingsRetainOlderEntries() async throws {
    let privateConfiguration = try FeedConfiguration(
      username: "reader",
      token: "token",
      source: .privateListing(.saved),
      userAgent: "ua"
    )
    let client = FeedClientMock(data: Data(feedXML(count: 1).utf8))
    let service = makeService(client: client)
    let twoYearsLater = Date(timeIntervalSince1970: 1_787_500_000)

    let outcome = try await service.sync(
      configuration: privateConfiguration,
      now: twoYearsLater
    )

    guard case .synced(let report) = outcome else {
      return XCTFail("expected synced")
    }
    XCTAssertEqual(report.inserted, 1)
    XCTAssertEqual(report.deleted, 0)
    XCTAssertEqual(try repository.fetchStories().count, 1)
  }

  func testMapsClientErrorsToUserVisibleCategories() async throws {
    let cases: [(client: FeedClientMock, expectedTag: String)] = [
      (FeedClientMock(statusCode: 401, data: Data()), "invalidCredentials"),
      (FeedClientMock(statusCode: 403, data: Data()), "invalidCredentials"),
      (FeedClientMock(statusCode: 500, data: Data()), "serverFailure"),
      (FeedClientMock(underlying: URLError(.notConnectedToInternet)), "offline"),
      (FeedClientMock(underlying: URLError(.timedOut)), "timedOut"),
      (FeedClientMock(data: Data("<broken".utf8)), "malformedFeed"),
    ]

    for (client, expectedTag) in cases {
      let freshRepository = try StoryRepository.inMemory()
      let service = StorySyncService(
        feedClient: client,
        parser: RedditRSSParser(),
        repository: freshRepository,
        policy: .standard
      )
      do {
        _ = try await service.sync(
          configuration: configuration, now: Date(timeIntervalSince1970: 0))
        XCTFail("expected \(expectedTag)")
      } catch let error as SyncError {
        XCTAssertEqual(Self.tag(of: error), expectedTag)
      }
    }
  }

  private static func tag(of error: SyncError) -> String {
    switch error {
    case .rateLimited: return "rateLimited"
    case .invalidCredentials: return "invalidCredentials"
    case .offline: return "offline"
    case .timedOut: return "timedOut"
    case .serverFailure: return "serverFailure"
    case .malformedFeed: return "malformedFeed"
    case .networkFailure: return "networkFailure"
    case .cancelled: return "cancelled"
    }
  }

  private func makeStory(id: String, publishedAt: Int64) -> Story {
    Story(
      id: id,
      title: "Title",
      contentBody: "<p>Body</p>",
      author: "author",
      subreddit: "shortstories",
      publishedAt: publishedAt,
      sourceId: FeedSourceRecord.builtInRedditID()
    )
  }
}

struct FeedClientMock: FeedFetching {
  var statusCode: Int = 200
  var headers: [String: String] = [:]
  var data: Data
  var dataByCursor: [String: Data] = [:]
  var underlying: URLError?

  init(
    statusCode: Int = 200,
    headers: [String: String] = [:],
    data: Data,
    dataByCursor: [String: Data] = [:]
  ) {
    self.statusCode = statusCode
    self.headers = headers
    self.data = data
    self.dataByCursor = dataByCursor
  }

  init(underlying: URLError, data: Data = Data()) {
    self.underlying = underlying
    self.data = data
  }

  func fetch(configuration: FeedConfiguration, after cursor: String?) async throws -> Data {
    if let underlying {
      throw underlying
    }
    if (200..<300).contains(statusCode) {
      if let cursor, let page = dataByCursor[cursor] {
        return page
      }
      return data
    }
    if statusCode == 429 {
      throw FeedClientError.rateLimited(
        retryAfter: headers["Retry-After"].flatMap(TimeInterval.init))
    }
    if statusCode == 401 || statusCode == 403 {
      throw FeedClientError.invalidCredentials(statusCode: statusCode)
    }
    throw FeedClientError.serverError(statusCode: statusCode)
  }
}

actor CountingFetchClient: FeedFetching {
  private(set) var fetchCount = 0
  let delayNanoseconds: UInt64
  let data: Data

  init(delayNanoseconds: UInt64, data: Data) {
    self.delayNanoseconds = delayNanoseconds
    self.data = data
  }

  func fetch(configuration: FeedConfiguration, after cursor: String?) async throws -> Data {
    fetchCount += 1
    try? await Task.sleep(nanoseconds: delayNanoseconds)
    return data
  }
}
