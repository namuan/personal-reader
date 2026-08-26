import GRDB
import XCTest

@testable import PersonalReaderCore

final class StorySourceIsolationTests: XCTestCase {
  func testMigratesLegacySchemaAndSeedsBuiltInRedditSource() throws {
    let databaseURL = FileManager.default.temporaryDirectory
      .appending(path: "source-tests-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    var legacyMigrator = DatabaseMigrator()
    legacyMigrator.registerMigration("createStories") { database in
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
        sql: "INSERT INTO stories VALUES ('t3_old', 'Old', '<p>x</p>', 'a', 's', 100, '', 1)"
      )
    }
    let queue = try DatabaseQueue(path: databaseURL.path)
    try legacyMigrator.migrate(queue)

    let repository = try StoryRepository(databaseURL: databaseURL)
    let sources = try repository.fetchAllFeedSources()

    XCTAssertEqual(sources.count, 1)
    XCTAssertEqual(sources.first?.id, FeedSourceRecord.builtInRedditID())
    XCTAssertEqual(sources.first?.kind, .reddit)

    let legacyStory = try XCTUnwrap(repository.fetchStory(id: "t3_old"))
    XCTAssertEqual(legacyStory.sourceId, FeedSourceRecord.builtInRedditID())
    XCTAssertTrue(legacyStory.isRead)
  }

  func testSwitchingRedditListingOnlyDeletesRedditStories() throws {
    let repository = try StoryRepository.inMemory()
    let rssA = FeedSourceRecord(kind: .rss, title: "A", url: "https://a.example/rss")
    let rssB = FeedSourceRecord(kind: .rss, title: "B", url: "https://b.example/rss")
    try repository.saveFeedSourceRecord(rssA)
    try repository.saveFeedSourceRecord(rssB)

    try repository.save([
      Story(
        id: "t3_reddit", title: "R", contentBody: "<p>r</p>",
        author: "a", subreddit: "s", publishedAt: 200,
        sourceId: FeedSourceRecord.builtInRedditID()
      ),
      Story(
        id: rssA.id + ":1", title: "A1", contentBody: "<p>a</p>",
        author: "a", subreddit: "a", publishedAt: 300,
        sourceId: rssA.id
      ),
      Story(
        id: rssB.id + ":1", title: "B1", contentBody: "<p>b</p>",
        author: "b", subreddit: "b", publishedAt: 400,
        sourceId: rssB.id
      ),
    ])

    _ = try repository.deleteSourceStories(sourceId: FeedSourceRecord.builtInRedditID())

    XCTAssertNil(try repository.fetchStory(id: "t3_reddit"))
    XCTAssertNotNil(try repository.fetchStory(id: rssA.id + ":1"))
    XCTAssertNotNil(try repository.fetchStory(id: rssB.id + ":1"))
  }

  func testCapStoriesPerSourceRemovesOldestBeyondLimit() throws {
    let repository = try StoryRepository.inMemory()
    let source = FeedSourceRecord(kind: .rss, title: "Cap", url: "https://cap.example/rss")
    try repository.saveFeedSourceRecord(source)
    try repository.save(
      (1...10).map { index in
        Story(
          id: source.id + ":story-\(index)",
          title: "Story \(index)",
          contentBody: "<p>\(index)</p>",
          author: "author",
          subreddit: "feed",
          publishedAt: Int64(index),
          sourceId: source.id
        )
      })

    let removed = try repository.capStoriesPerSource(sourceId: source.id, maximum: 4)
    XCTAssertEqual(removed, 6)
    let kept = try repository.fetchStories(sourceId: source.id)
    XCTAssertEqual(kept.map(\.publishedAt), [10, 9, 8, 7])
  }

  func testObservingEnabledSourcesExcludesDisabledFeeds() throws {
    let repository = try StoryRepository.inMemory()
    let enabled = FeedSourceRecord(
      kind: .rss, title: "On", url: "https://on.example/rss", isEnabled: true)
    let disabled = FeedSourceRecord(
      kind: .rss, title: "Off", url: "https://off.example/rss", isEnabled: false)
    try repository.saveFeedSourceRecord(enabled)
    try repository.saveFeedSourceRecord(disabled)
    try repository.save([
      Story(
        id: enabled.id + ":x", title: "On", contentBody: "",
        author: "a", subreddit: "feed", publishedAt: 100,
        sourceId: enabled.id
      ),
      Story(
        id: disabled.id + ":x", title: "Off", contentBody: "",
        author: "a", subreddit: "feed", publishedAt: 200,
        sourceId: disabled.id
      ),
    ])

    let ids = Set([FeedSourceRecord.builtInRedditID(), enabled.id])
    let enabledStories = try repository.fetchStoriesFromEnabledSources(enabledSourceIds: ids)
    XCTAssertTrue(enabledStories.contains(where: { $0.sourceId == enabled.id }))
    XCTAssertFalse(enabledStories.contains(where: { $0.sourceId == disabled.id }))
  }

  func testDeletingSourceRemovesItsStoriesAndSyncState() throws {
    let repository = try StoryRepository.inMemory()
    let source = FeedSourceRecord(kind: .rss, title: "Temp", url: "https://temp.example/rss")
    try repository.saveFeedSourceRecord(source)
    try repository.save([
      Story(
        id: source.id + ":x", title: "X", contentBody: "",
        author: "a", subreddit: "feed", publishedAt: 100,
        sourceId: source.id
      )
    ])
    _ = try repository.recordSourceError(
      sourceId: source.id,
      error: "boom",
      at: 1000
    )

    try repository.deleteSource(sourceId: source.id)

    XCTAssertNil(try repository.fetchStory(id: source.id + ":x"))
    XCTAssertNil(try repository.loadSyncState(feedKey: StoryRepository.feedKey(for: source.id)))
    XCTAssertNil(try repository.fetchFeedSourceRecord(id: source.id))
  }

  func testFetchAllFeedSourcesExcludesNothing() throws {
    let repository = try StoryRepository.inMemory()
    let sources = try repository.fetchAllFeedSources()
    XCTAssertEqual(sources.count, 1)
    XCTAssertEqual(sources.first?.id, FeedSourceRecord.builtInRedditID())
  }
}
