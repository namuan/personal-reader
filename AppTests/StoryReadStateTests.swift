import PersonalReaderCore
import XCTest

@testable import PersonalReaderApp

@MainActor
final class StoryReadStateTests: XCTestCase {
  func testMarkStoryReadMarksOnlyThatStory() async throws {
    let model = makeModel(stories: [
      makeStory(id: "s1", publishedAt: 300),
      makeStory(id: "s2", publishedAt: 200),
      makeStory(id: "s3", publishedAt: 100),
    ])

    model.markStoryRead(id: "s2")
    await waitForObservation()

    XCTAssertFalse(try model.environmentIfAvailable.repository.fetchStory(id: "s1")!.isRead)
    XCTAssertTrue(try model.environmentIfAvailable.repository.fetchStory(id: "s2")!.isRead)
    XCTAssertFalse(try model.environmentIfAvailable.repository.fetchStory(id: "s3")!.isRead)
    XCTAssertEqual(try model.environmentIfAvailable.repository.fetchUnreadCount(), 2)
    XCTAssertEqual(model.unreadCount, 2)
  }

  func testMarkStoryReadRemovesStoryFromUnreadFilter() async throws {
    let model = makeModel(stories: [
      makeStory(id: "s1", publishedAt: 300),
      makeStory(id: "s2", publishedAt: 200),
      makeStory(id: "s3", publishedAt: 100),
    ])

    model.showUnreadOnly = true
    model.markStoryRead(id: "s2")
    await waitForObservation()

    XCTAssertEqual(model.filteredStories.map(\.id), ["s1", "s3"])
  }

  func testMarkStoryReadIsIdempotent() async throws {
    let model = makeModel(stories: [makeStory(id: "s1", publishedAt: 300)])

    model.markStoryRead(id: "s1")
    model.markStoryRead(id: "s1")
    model.markStoryRead(id: "s1")
    await waitForObservation()

    XCTAssertTrue(try model.environmentIfAvailable.repository.fetchStory(id: "s1")!.isRead)
    XCTAssertEqual(model.unreadCount, 0)
  }

  func testMarkStoryReadKeepsStoryInAllFilter() async throws {
    let model = makeModel(stories: [makeStory(id: "s1", publishedAt: 300)])

    model.showUnreadOnly = false
    model.markStoryRead(id: "s1")
    await waitForObservation()

    XCTAssertEqual(model.filteredStories.map(\.id), ["s1"])
    XCTAssertTrue(try model.environmentIfAvailable.repository.fetchStory(id: "s1")!.isRead)
  }

  func testMarkAllStoriesReadMarksEveryUnreadStory() async throws {
    let model = makeModel(stories: [
      makeStory(id: "s1", publishedAt: 300),
      makeStory(id: "s2", publishedAt: 200),
      makeStory(id: "s3", publishedAt: 100),
    ])
    try model.environmentIfAvailable.repository.markRead(id: "s2")

    model.markAllStoriesRead()
    await waitForObservation()

    XCTAssertEqual(try model.environmentIfAvailable.repository.fetchUnreadCount(), 0)
    XCTAssertTrue(try model.environmentIfAvailable.repository.fetchStories().allSatisfy(\.isRead))
  }

  func testMarkAllStoriesReadEmptiesUnreadView() async throws {
    let model = makeModel(stories: [
      makeStory(id: "s1", publishedAt: 300),
      makeStory(id: "s2", publishedAt: 200),
    ])

    model.markAllStoriesRead()
    await waitForObservation()

    XCTAssertEqual(model.unreadCount, 0)
    XCTAssertTrue(model.filteredStories.isEmpty)
    XCTAssertEqual(model.stories.count, 2)
  }

  func testMarkAllStoriesReadSurvivesRefreshAndShowsNewStories() async throws {
    let model = makeModel(stories: [makeStory(id: "s1", publishedAt: 300)])
    model.markAllStoriesRead()
    await waitForObservation()

    var refreshed = makeStory(id: "s1", publishedAt: 300)
    refreshed.title = "Updated title"
    try model.environmentIfAvailable.repository.save([refreshed])
    try model.environmentIfAvailable.repository.save([makeStory(id: "s2", publishedAt: 400)])
    await waitForObservation()

    XCTAssertTrue(try model.environmentIfAvailable.repository.fetchStory(id: "s1")!.isRead)
    XCTAssertEqual(try model.environmentIfAvailable.repository.fetchUnreadCount(), 1)
    XCTAssertEqual(model.filteredStories.map(\.id), ["s2"])
  }

  private func waitForObservation() async {
    for _ in 0..<100 {
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(20))
      await Task.yield()
    }
  }

  private func makeModel(stories: [Story]) -> AppModel {
    let repository = try! StoryRepository.inMemory()
    try! repository.save(stories)
    let environment = TestEnvironment.make(repository: repository)
    let model = AppModel(environment: environment)
    model.startObservation()
    return model
  }

  private func makeStory(id: String, publishedAt: Int64) -> Story {
    Story(
      id: id,
      title: "Title \(id)",
      contentBody: "<p>Body</p>",
      author: "author",
      subreddit: "test",
      publishedAt: publishedAt,
      sourceId: FeedSourceRecord.builtInRedditID()
    )
  }
}