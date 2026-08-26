import PersonalReaderCore
import XCTest

@testable import PersonalReaderApp

@MainActor
final class SeenStoryTrackingTests: XCTestCase {
  func testScrollingDownMarksPassedStoriesOnly() throws {
    let model = makeModel(stories: [
      makeStory(id: "s1", publishedAt: 300),
      makeStory(id: "s2", publishedAt: 200),
      makeStory(id: "s3", publishedAt: 100),
    ])

    model.recordVisibleStories(["s1"])
    XCTAssertEqual(try model.environmentIfAvailable.repository.fetchUnreadCount(), 3)

    model.recordVisibleStories(["s3"])
    model.flushSeenStories()

    XCTAssertTrue(try model.environmentIfAvailable.repository.fetchStory(id: "s1")!.isRead)
    XCTAssertTrue(try model.environmentIfAvailable.repository.fetchStory(id: "s2")!.isRead)
    XCTAssertFalse(try model.environmentIfAvailable.repository.fetchStory(id: "s3")!.isRead)
  }

  func testInitialVisibleStoriesAreNotMarked() throws {
    let model = makeModel(stories: [
      makeStory(id: "s1", publishedAt: 300),
      makeStory(id: "s2", publishedAt: 200),
    ])

    model.recordVisibleStories(["s1", "s2"])
    model.flushSeenStories()

    XCTAssertEqual(try model.environmentIfAvailable.repository.fetchUnreadCount(), 2)
  }

  func testScrollingUpDoesNotMarkStories() throws {
    let model = makeModel(stories: [
      makeStory(id: "s1", publishedAt: 300),
      makeStory(id: "s2", publishedAt: 200),
      makeStory(id: "s3", publishedAt: 100),
    ])

    model.recordVisibleStories(["s3"])
    model.recordVisibleStories(["s1"])
    model.recordVisibleStories(["s3"])
    model.flushSeenStories()

    XCTAssertEqual(try model.environmentIfAvailable.repository.fetchUnreadCount(), 3)
  }

  func testSeenStoriesRemainVisibleUntilSessionReset() async throws {
    let model = makeModel(stories: [
      makeStory(id: "s1", publishedAt: 300),
      makeStory(id: "s2", publishedAt: 200),
      makeStory(id: "s3", publishedAt: 100),
    ])

    model.recordVisibleStories(["s1"])
    model.recordVisibleStories(["s3"])
    model.flushSeenStories()
    await waitForObservation()

    XCTAssertEqual(Set(model.filteredStories.map(\.id)), ["s1", "s2", "s3"])

    model.displaySessionDidReset()

    XCTAssertEqual(model.filteredStories.map(\.id), ["s3"])
  }

  func testDisplaySessionResetRestoresUnreadFilter() async throws {
    let model = makeModel(stories: [
      makeStory(id: "s1", publishedAt: 300),
      makeStory(id: "s2", publishedAt: 200),
    ])

    model.recordVisibleStories(["s1"])
    model.recordVisibleStories(["s2"])
    model.flushSeenStories()
    model.displaySessionDidReset()
    await waitForObservation()

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
