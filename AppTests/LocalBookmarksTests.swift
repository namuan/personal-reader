import PersonalReaderCore
import XCTest

@testable import PersonalReaderApp

@MainActor
final class LocalBookmarksTests: XCTestCase {
  func testBookmarksRemainVisibleWhenTheFeedScopeChanges() async throws {
    let source = FeedSourceRecord(kind: .rss, title: "Elsewhere", url: "https://example.com/feed")
    let first = makeStory(id: "first", sourceID: FeedSourceRecord.builtInRedditID())
    let second = makeStory(id: "second", sourceID: source.id)
    let model = makeModel(stories: [first, second], sources: [source])

    model.toggleBookmark(story: first)
    model.toggleBookmark(story: second)
    await waitForObservation()
    model.selectScope(.source(source.id))
    await waitForObservation()

    XCTAssertEqual(model.bookmarks.map(\.id), ["first", "second"])
  }

  func testBookmarkReadStateSurvivesDownloadedDataCleanup() async throws {
    let story = makeStory(id: "saved", sourceID: FeedSourceRecord.builtInRedditID())
    let model = makeModel(stories: [story])

    model.toggleBookmark(story: story)
    model.markStoryRead(id: story.id)
    await waitForObservation()
    model.clearLocalData()
    await waitForObservation()

    XCTAssertTrue(model.stories.isEmpty)
    XCTAssertEqual(model.bookmarks.map(\.id), ["saved"])
    XCTAssertTrue(model.bookmarks.first?.isRead == true)
  }

  func testRemovingBookmarkRemovesOnlyTheQueueSnapshot() async throws {
    let story = makeStory(id: "saved", sourceID: FeedSourceRecord.builtInRedditID())
    let model = makeModel(stories: [story])

    model.toggleBookmark(story: story)
    await waitForObservation()
    model.toggleBookmark(story: story)
    await waitForObservation()

    XCTAssertTrue(model.bookmarks.isEmpty)
    XCTAssertEqual(try model.environmentIfAvailable.repository.fetchStory(id: story.id), story)
  }

  private func waitForObservation() async {
    for _ in 0..<30 {
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  private func makeModel(
    stories: [Story],
    sources: [FeedSourceRecord] = []
  ) -> AppModel {
    let repository = try! StoryRepository.inMemory()
    try! repository.save(stories)
    let environment = TestEnvironment.make(repository: repository)
    for source in sources {
      try! environment.sourceStore.save(source)
    }
    let model = AppModel(environment: environment)
    model.startObservation()
    return model
  }

  private func makeStory(id: String, sourceID: String) -> Story {
    Story(
      id: id,
      title: "Title \(id)",
      contentBody: "<p>Body</p>",
      author: "author",
      subreddit: "test",
      publishedAt: 100,
      sourceId: sourceID
    )
  }
}
