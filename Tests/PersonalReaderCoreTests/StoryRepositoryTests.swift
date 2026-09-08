import XCTest

@testable import PersonalReaderCore

final class StoryRepositoryTests: XCTestCase {
  func testSavesStoriesNewestFirst() throws {
    let repository = try StoryRepository.inMemory()
    try repository.save([
      makeStory(id: "older", publishedAt: 100),
      makeStory(id: "newer", publishedAt: 200),
    ])

    XCTAssertEqual(try repository.fetchStories().map(\.id), ["newer", "older"])
  }

  func testFeedRefreshPreservesReadState() throws {
    let repository = try StoryRepository.inMemory()
    try repository.save([makeStory(id: "story", publishedAt: 100)])
    try repository.markRead(id: "story")
    try repository.save([makeStory(id: "story", publishedAt: 200)])

    let story = try XCTUnwrap(repository.fetchStories().first)
    XCTAssertTrue(story.isRead)
    XCTAssertEqual(story.publishedAt, 200)
  }

  func testDeletesExpiredStories() throws {
    let repository = try StoryRepository.inMemory()
    try repository.save([
      makeStory(id: "expired", publishedAt: 100),
      makeStory(id: "active", publishedAt: 200),
    ])

    XCTAssertEqual(try repository.deletePublished(before: 150), 1)
    XCTAssertEqual(try repository.fetchStories().map(\.id), ["active"])
  }

  func testBookmarkPreservesAStoryAfterDownloadedDataIsRemoved() throws {
    let repository = try StoryRepository.inMemory()
    let story = makeStory(id: "saved", publishedAt: 100)
    try repository.save([story])

    XCTAssertTrue(try repository.bookmark(story, at: 500))
    XCTAssertEqual(try repository.deletePublished(before: 200), 1)

    let bookmark = try XCTUnwrap(repository.fetchBookmarks().first)
    XCTAssertEqual(bookmark.story, story)
    XCTAssertNil(try repository.fetchStory(id: story.id))
  }

  func testBookmarkingIsIdempotentAndAppendsToTheQueue() throws {
    let repository = try StoryRepository.inMemory()
    let first = makeStory(id: "first", publishedAt: 100)
    let second = makeStory(id: "second", publishedAt: 200)

    XCTAssertTrue(try repository.bookmark(first, at: 100))
    XCTAssertFalse(try repository.bookmark(first, at: 200))
    XCTAssertTrue(try repository.bookmark(second, at: 300))

    XCTAssertEqual(try repository.fetchBookmarks().map(\.id), ["first", "second"])
  }

  func testBookmarkRefreshPreservesBookmarkReadStateAndOrder() throws {
    let repository = try StoryRepository.inMemory()
    let first = makeStory(id: "first", publishedAt: 100)
    let second = makeStory(id: "second", publishedAt: 200)
    try repository.save([first, second])
    _ = try repository.bookmark(first, at: 100)
    _ = try repository.bookmark(second, at: 200)
    try repository.markRead(id: first.id)

    var refreshed = first
    refreshed.title = "Updated"
    refreshed.contentBody = "<p>Updated body</p>"
    try repository.save([refreshed])

    let bookmarks = try repository.fetchBookmarks()
    XCTAssertEqual(bookmarks.map(\.id), ["first", "second"])
    XCTAssertEqual(bookmarks.first?.title, "Updated")
    XCTAssertTrue(bookmarks.first?.isRead == true)
  }

  func testReorderingAndUnbookmarkingKeepQueueOrderStable() throws {
    let repository = try StoryRepository.inMemory()
    let stories = [
      makeStory(id: "first", publishedAt: 100),
      makeStory(id: "second", publishedAt: 200),
      makeStory(id: "third", publishedAt: 300),
    ]
    for (index, story) in stories.enumerated() {
      _ = try repository.bookmark(story, at: Int64(index))
    }

    try repository.reorderBookmarks(ids: ["third", "first", "second"])
    XCTAssertTrue(try repository.removeBookmark(id: "first"))

    XCTAssertEqual(try repository.fetchBookmarks().map(\.id), ["third", "second"])
  }

  func testClearDownloadedDataPreservesBookmarksAndClearAllDataDeletesThem() throws {
    let repository = try StoryRepository.inMemory()
    let story = makeStory(id: "saved", publishedAt: 100)
    try repository.save([story])
    _ = try repository.bookmark(story)

    try repository.deleteAllData(preservingFeedSources: true)
    XCTAssertEqual(try repository.fetchBookmarks().map(\.id), ["saved"])

    try repository.deleteAllData()
    XCTAssertTrue(try repository.fetchBookmarks().isEmpty)
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
