import PersonalReaderCore
import XCTest

@testable import PersonalReaderApp

@MainActor
final class StorySearchTests: XCTestCase {
  func testSearchMatchesTitleContentAuthorSubredditAndSourceName() async throws {
    let source = FeedSourceRecord(
      id: "rss-source",
      kind: .rss,
      title: "Weekly Reading",
      url: "https://example.com/feed"
    )
    let model = makeModel(
      stories: [
        makeStory(id: "title", title: "A Mountain Journey"),
        makeStory(id: "content", contentBody: "<p>Freshly roasted coffee</p>"),
        makeStory(id: "author", author: "Ada Lovelace"),
        makeStory(id: "subreddit", subreddit: "SwiftUI"),
        makeStory(id: "source", sourceID: source.id),
      ],
      sources: [source]
    )
    await waitForObservation()

    model.searchQuery = "mountain"
    await waitForSearchDebounce()
    XCTAssertEqual(model.filteredStories.map(\.id), ["title"])

    model.searchQuery = "coffee"
    await waitForSearchDebounce()
    XCTAssertEqual(model.filteredStories.map(\.id), ["content"])

    model.searchQuery = "ada"
    await waitForSearchDebounce()
    XCTAssertEqual(model.filteredStories.map(\.id), ["author"])

    model.searchQuery = "swiftui"
    await waitForSearchDebounce()
    XCTAssertEqual(model.filteredStories.map(\.id), ["subreddit"])

    model.searchQuery = "weekly reading"
    await waitForSearchDebounce()
    XCTAssertEqual(model.filteredStories.map(\.id), ["source"])
  }

  func testSearchIsCaseAndDiacriticInsensitive() async throws {
    let model = makeModel(stories: [makeStory(id: "cafe", title: "Café Notes")])
    await waitForObservation()

    model.searchQuery = "CAFE"
    await waitForSearchDebounce()

    XCTAssertEqual(model.filteredStories.map(\.id), ["cafe"])
  }

  func testSearchAppliesAfterDebouncingInput() async throws {
    let model = makeModel(stories: [makeStory(id: "match", title: "Needle")])
    await waitForObservation()

    model.searchQuery = "needle"

    XCTAssertFalse(model.hasActiveSearch)
    await waitForSearchDebounce()
    XCTAssertTrue(model.hasActiveSearch)
    XCTAssertEqual(model.filteredStories.map(\.id), ["match"])
  }

  func testWhitespaceOnlySearchReturnsTheNormalList() async throws {
    let model = makeModel(stories: [makeStory(id: "first"), makeStory(id: "second")])
    await waitForObservation()

    model.searchQuery = "   \n"

    XCTAssertFalse(model.hasActiveSearch)
    XCTAssertEqual(model.filteredStories.map(\.id), model.stories.map(\.id))
  }

  func testSearchCombinesWithTheCurrentScopeAndUnreadFilter() async throws {
    let source = FeedSourceRecord(
      id: "rss-source",
      kind: .rss,
      title: "RSS",
      url: "https://example.com/feed"
    )
    var readStory = makeStory(id: "read", title: "Needle", sourceID: source.id)
    readStory.isRead = true
    let model = makeModel(
      stories: [
        makeStory(id: "reddit", title: "Needle"),
        readStory,
        makeStory(id: "unread", title: "Needle", sourceID: source.id),
      ],
      sources: [source]
    )
    model.scope = .source(source.id)
    model.startObservation()
    await waitForObservation()

    model.searchQuery = "needle"
    await waitForSearchDebounce()

    XCTAssertEqual(model.filteredStories.map(\.id), ["unread"])
  }

  func testObservedStoriesAreIncludedWhenTheyMatchAnActiveSearch() async throws {
    let repository = try StoryRepository.inMemory()
    let environment = TestEnvironment.make(repository: repository)
    let model = AppModel(environment: environment)
    model.startObservation()
    model.searchQuery = "arrival"

    try repository.save([makeStory(id: "arrival", title: "New Arrival")])
    await waitForObservation()

    XCTAssertEqual(model.filteredStories.map(\.id), ["arrival"])
  }

  private func makeModel(
    stories: [Story],
    sources: [FeedSourceRecord] = []
  ) -> AppModel {
    let repository = try! StoryRepository.inMemory()
    let sourceStore = repository.makeFeedSourceStore()
    for source in sources {
      try! sourceStore.save(source)
    }
    try! repository.save(stories)
    let model = AppModel(environment: TestEnvironment.make(repository: repository))
    model.startObservation()
    return model
  }

  private func makeStory(
    id: String,
    title: String? = nil,
    contentBody: String = "<p>Body</p>",
    author: String = "author",
    subreddit: String = "test",
    sourceID: String = FeedSourceRecord.builtInRedditID()
  ) -> Story {
    Story(
      id: id,
      title: title ?? "Story \(id)",
      contentBody: contentBody,
      author: author,
      subreddit: subreddit,
      publishedAt: 100,
      sourceId: sourceID
    )
  }

  private func waitForSearchDebounce() async {
    try? await Task.sleep(for: .milliseconds(300))
    await Task.yield()
  }

  private func waitForObservation() async {
    for _ in 0..<50 {
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(20))
      await Task.yield()
    }
  }
}
