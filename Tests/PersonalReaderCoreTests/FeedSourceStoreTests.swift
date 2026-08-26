import XCTest

@testable import PersonalReaderCore

final class FeedSourceStoreTests: XCTestCase {
  func testSavesAndReadsFeedSourcesInOrder() throws {
    let store = try FeedSourceStore.inMemory()

    let first = FeedSourceRecord(
      kind: .rss,
      title: "First",
      url: "https://example.com/first.xml",
      sortOrder: 1
    )
    let second = FeedSourceRecord(
      kind: .rss,
      title: "Second",
      url: "https://example.com/second.xml",
      sortOrder: 2
    )
    try store.save(first)
    try store.save(second)

    let fetched = try store.fetchAll()
    let customIds = fetched.filter { $0.kind == .rss }.map(\.id)
    XCTAssertEqual(customIds, [first.id, second.id])
    XCTAssertEqual(try store.fetch(id: first.id)?.title, "First")
  }

  func testFetchEnabledExcludesDisabledSources() throws {
    let store = try FeedSourceStore.inMemory()
    let enabled = FeedSourceRecord(
      kind: .rss,
      title: "Enabled",
      url: "https://example.com/a.xml",
      isEnabled: true
    )
    let disabled = FeedSourceRecord(
      kind: .rss,
      title: "Disabled",
      url: "https://example.com/b.xml",
      isEnabled: false
    )
    try store.save(enabled)
    try store.save(disabled)

    let fetched = try store.fetchEnabled().filter { $0.kind == .rss }
    XCTAssertEqual(fetched.map(\.id), [enabled.id])
  }

  func testUpdateIntervalAndEnabled() throws {
    let store = try FeedSourceStore.inMemory()
    var source = FeedSourceRecord(
      kind: .rss,
      title: "Feed",
      url: "https://example.com/feed.xml"
    )
    try store.save(source)

    try store.updateInterval(id: source.id, interval: .oneHour)
    try store.setEnabled(id: source.id, enabled: false)

    let reloaded = try XCTUnwrap(store.fetch(id: source.id))
    XCTAssertEqual(reloaded.refreshInterval, .oneHour)
    XCTAssertFalse(reloaded.isEnabled)

    source.refreshInterval = .oneHour
    source.isEnabled = false
    XCTAssertEqual(reloaded, source)
  }

  func testNextSortOrderIncrementsFromMax() throws {
    let store = try FeedSourceStore.inMemory()
    XCTAssertEqual(try store.nextSortOrder(), 0)

    try store.save(
      FeedSourceRecord(kind: .rss, title: "A", url: "https://a.example/rss", sortOrder: 0))
    XCTAssertEqual(try store.nextSortOrder(), 1)

    try store.save(
      FeedSourceRecord(kind: .rss, title: "B", url: "https://b.example/rss", sortOrder: 5))
    XCTAssertEqual(try store.nextSortOrder(), 6)
  }

  func testBuiltInRedditIDIsStable() {
    XCTAssertEqual(FeedSourceRecord.builtInRedditID(), "reddit-built-in")
  }
}
