import XCTest

@testable import PersonalReaderCore

final class FeedTransferTests: XCTestCase {
  private func makePackageData(
    feeds: [[String: Any]],
    format: String = FeedTransferPackage.formatIdentifier,
    version: Int = FeedTransferPackage.version
  ) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: ["format": format, "version": version, "feeds": feeds])
  }

  func testExportIncludesOnlyRSSFeeds() throws {
    let records = [
      FeedSourceRecord(
        kind: .rss, title: "Blog", url: "https://blog.example/feed.xml", sortOrder: 1),
      FeedSourceRecord(
        id: FeedSourceRecord.builtInRedditID(),
        kind: .reddit,
        title: "Reddit",
        url: "https://www.reddit.com/.rss",
        sortOrder: -1
      ),
    ]

    let package = FeedTransferPackage.exporting(records: records)

    XCTAssertEqual(package.format, FeedTransferPackage.formatIdentifier)
    XCTAssertEqual(package.version, FeedTransferPackage.version)
    XCTAssertEqual(package.feeds.map(\.url), ["https://blog.example/feed.xml"])
  }

  func testExportImportRoundTripPreservesFeedSettings() throws {
    let records = [
      FeedSourceRecord(
        kind: .rss,
        title: "Blog",
        url: "https://blog.example/feed.xml",
        isEnabled: false,
        refreshInterval: .sixHours,
        sortOrder: 3
      )
    ]
    let data = try JSONEncoder().encode(FeedTransferPackage.exporting(records: records))

    let items = try FeedTransferPackage.decode(from: data)
    let plan = FeedImportPlanner.plan(items: items, existingURLs: [])

    XCTAssertEqual(plan.addedCount, 1)
    XCTAssertEqual(plan.rejectedCount, 0)
    let added = try XCTUnwrap(plan.accepted.first)
    XCTAssertEqual(added.title, "Blog")
    XCTAssertEqual(added.url, "https://blog.example/feed.xml")
    XCTAssertFalse(added.isEnabled)
    XCTAssertEqual(added.refreshInterval, .sixHours)

    let record = added.makeRecord(sortOrder: 9)
    XCTAssertEqual(record.kind, .rss)
    XCTAssertEqual(record.title, "Blog")
    XCTAssertEqual(record.url, "https://blog.example/feed.xml")
    XCTAssertFalse(record.isEnabled)
    XCTAssertEqual(record.refreshInterval, .sixHours)
    XCTAssertEqual(record.sortOrder, 9)
    XCTAssertFalse(record.id.isEmpty)
  }

  func testImportRejectsDuplicatesAgainstExistingURLs() throws {
    let existing = Set(["https://Blog.Example.com/Feed.xml"])

    let plan = FeedImportPlanner.plan(
      items: [
        FeedTransferItem(url: "https://blog.example.com/Feed.xml")
      ],
      existingURLs: existing
    )

    XCTAssertEqual(plan.addedCount, 0)
    XCTAssertEqual(plan.rejected.first?.issue, .duplicate)
  }

  func testImportRejectsDuplicatesWithinFile() throws {
    let plan = FeedImportPlanner.plan(
      items: [
        FeedTransferItem(url: "https://blog.example.com/feed.xml"),
        FeedTransferItem(url: "https://blog.example.com/feed.xml"),
      ],
      existingURLs: []
    )

    XCTAssertEqual(plan.addedCount, 1)
    XCTAssertEqual(plan.rejected.first?.issue, .duplicate)
  }

  func testImportNormalizesDefaultPortAndTrailingSlash() throws {
    let plan = FeedImportPlanner.plan(
      items: [
        FeedTransferItem(url: "https://blog.example.com:443/feed.xml/"),
        FeedTransferItem(url: "https://blog.example.com/feed.xml"),
      ],
      existingURLs: []
    )

    XCTAssertEqual(plan.addedCount, 1)
    XCTAssertEqual(plan.accepted.first?.url, "https://blog.example.com/feed.xml")
    XCTAssertEqual(plan.rejected.first?.issue, .duplicate)
  }

  func testImportRejectsInvalidURLs() throws {
    let plan = FeedImportPlanner.plan(
      items: [
        FeedTransferItem(url: "not a url"),
        FeedTransferItem(url: ""),
        FeedTransferItem(url: "www.example.com/feed"),
      ],
      existingURLs: []
    )

    XCTAssertEqual(plan.addedCount, 0)
    XCTAssertEqual(plan.rejected.map(\.issue), [.invalidURL, .invalidURL, .invalidURL])
  }

  func testImportRejectsInsecureURLs() throws {
    let plan = FeedImportPlanner.plan(
      items: [
        FeedTransferItem(url: "http://blog.example.com/feed.xml")
      ],
      existingURLs: []
    )

    XCTAssertEqual(plan.addedCount, 0)
    XCTAssertEqual(plan.rejected.first?.issue, .insecureURL)
  }

  func testImportRejectsUnsupportedKind() throws {
    let plan = FeedImportPlanner.plan(
      items: [
        FeedTransferItem(kind: .reddit, url: "https://blog.example.com/feed.xml")
      ],
      existingURLs: []
    )

    XCTAssertEqual(plan.addedCount, 0)
    XCTAssertEqual(plan.rejected.first?.issue, .unsupportedKind)
  }

  func testDecodeRejectsEmptyData() {
    XCTAssertThrowsError(try FeedTransferPackage.decode(from: Data())) { error in
      XCTAssertEqual(error as? FeedTransferError, .unreadable)
    }
  }

  func testDecodeRejectsMalformedJSON() {
    XCTAssertThrowsError(
      try FeedTransferPackage.decode(from: Data("{not json".utf8))
    ) { error in
      XCTAssertEqual(error as? FeedTransferError, .unreadable)
    }
  }

  func testDecodeRejectsUnknownFormat() throws {
    let data = try makePackageData(feeds: [])
    let altered = try makePackageData(feeds: [], format: "some-other-app")

    XCTAssertThrowsError(try FeedTransferPackage.decode(from: altered)) { error in
      XCTAssertEqual(error as? FeedTransferError, .invalidFormat)
    }
    XCTAssertNoThrow(try FeedTransferPackage.decode(from: data))
  }

  func testDecodeRejectsFutureVersion() throws {
    let data = try makePackageData(feeds: [], version: FeedTransferPackage.version + 1)

    XCTAssertThrowsError(try FeedTransferPackage.decode(from: data)) { error in
      XCTAssertEqual(error as? FeedTransferError, .unsupportedVersion(2))
    }
  }

  func testDecodeDefaultsMissingFields() throws {
    let data = try makePackageData(
      feeds: [
        ["url": "https://blog.example.com/feed.xml", "kind": "rss"]
      ]
    )

    let items = try FeedTransferPackage.decode(from: data)

    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.title, "")
    XCTAssertTrue(items.first?.isEnabled ?? false)
    XCTAssertEqual(items.first?.refreshInterval, .threeHours)
    XCTAssertEqual(items.first?.sortOrder, 0)
  }
}
