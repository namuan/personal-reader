import GRDB
import XCTest

@testable import PersonalReaderCore

final class StoryRepositoryPersistenceTests: XCTestCase {
  private var databaseURL: URL!

  override func setUpWithError() throws {
    databaseURL = FileManager.default.temporaryDirectory
      .appending(path: "repo-tests-\(UUID().uuidString).sqlite")
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: databaseURL)
  }

  func testMigratesFromPreviousSchemaVersion() throws {
    var previousMigrator = DatabaseMigrator()
    previousMigrator.registerMigration("createStories") { database in
      try database.create(table: "stories") { table in
        table.column("id", .text).primaryKey()
        table.column("title", .text).notNull()
        table.column("content_body", .text).notNull()
        table.column("author", .text).notNull()
        table.column("subreddit", .text).notNull()
        table.column("published_at", .integer).notNull()
        table.column("link", .text).notNull().defaults(to: "")
        table.column("is_read", .boolean).notNull().defaults(to: false)
      }
      try database.execute(
        sql: "INSERT INTO stories VALUES ('t3_old0001', 'Old', '<p>b</p>', 'a', 's', 100, '', 1)"
      )
    }
    let queue = try DatabaseQueue(path: databaseURL.path)
    try previousMigrator.migrate(queue)

    let repository = try StoryRepository(databaseURL: databaseURL)
    let stories = try repository.fetchStories()

    XCTAssertEqual(stories.map(\.id), ["t3_old0001"])
    XCTAssertTrue(try XCTUnwrap(stories.first).isRead)
    XCTAssertNil(try repository.loadSyncState(feedKey: "any"))
  }

  func testApplySyncIsAtomicAndPreservesReadState() throws {
    let repository = try StoryRepository.inMemory()
    try repository.save([makeStory(id: "t3_keep01", publishedAt: 500)])
    try repository.markRead(id: "t3_keep01")
    try repository.save([makeStory(id: "t3_stale", publishedAt: 10)])

    let report = try repository.applySync(
      stories: [
        makeStory(id: "t3_keep01", publishedAt: 600),
        makeStory(id: "t3_new001", publishedAt: 700),
      ],
      syncStateUpdate: SyncStateUpdate(
        feedKey: "feed-a", lastSuccessfulSyncAt: 900, rateLimitAttempt: 0),
      retentionCutoff: 100
    )

    XCTAssertEqual(report.inserted, 1)
    XCTAssertEqual(report.updated, 1)
    XCTAssertEqual(report.deleted, 1)

    let kept = try XCTUnwrap(repository.fetchStory(id: "t3_keep01"))
    XCTAssertTrue(kept.isRead)
    XCTAssertEqual(kept.publishedAt, 600)
    XCTAssertNil(try repository.fetchStory(id: "t3_stale"))

    let state = try XCTUnwrap(repository.loadSyncState(feedKey: "feed-a"))
    XCTAssertEqual(state.lastSuccessfulSyncAt, 900)
    XCTAssertNil(state.retryNotBefore)
    XCTAssertEqual(state.rateLimitAttempt, 0)
  }

  func testRateLimitStatePersists() throws {
    let repository = try StoryRepository(databaseURL: databaseURL)
    _ = try repository.recordRateLimit(feedKey: "feed-a", retryNotBefore: 1234, attempt: 2)

    let reopened = try StoryRepository(databaseURL: databaseURL)
    let state = try XCTUnwrap(reopened.loadSyncState(feedKey: "feed-a"))

    XCTAssertEqual(state.retryNotBefore, 1234)
    XCTAssertEqual(state.rateLimitAttempt, 2)
  }

  func testUnreadQueries() throws {
    let repository = try StoryRepository.inMemory()
    try repository.save([
      makeStory(id: "a", publishedAt: 100),
      makeStory(id: "b", publishedAt: 200),
      makeStory(id: "c", publishedAt: 300),
    ])
    try repository.markRead(id: "b")

    XCTAssertEqual(try repository.fetchUnreadStories().map(\.id), ["c", "a"])
    XCTAssertEqual(try repository.fetchUnreadCount(), 2)
    XCTAssertEqual(try repository.fetchStories().count, 3)
  }

  func testMarkReadReturnsFalseForMissingStory() throws {
    let repository = try StoryRepository.inMemory()
    XCTAssertFalse(try repository.markRead(id: "missing"))
  }

  func testDeleteAllDataClearsStoriesAndSyncState() throws {
    let repository = try StoryRepository.inMemory()
    try repository.save([makeStory(id: "a", publishedAt: 1)])
    _ = try repository.recordRateLimit(feedKey: "feed-a", retryNotBefore: 5, attempt: 1)

    try repository.deleteAllData()

    XCTAssertTrue(try repository.fetchStories().isEmpty)
    XCTAssertNil(try repository.loadSyncState(feedKey: "feed-a"))
  }

  private func makeStory(id: String, publishedAt: Int64) -> Story {
    Story(
      id: id,
      title: "Title",
      contentBody: "<p>Body</p>",
      author: "author",
      subreddit: "shortstories",
      publishedAt: publishedAt
    )
  }
}
