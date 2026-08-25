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
