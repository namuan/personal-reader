import XCTest

@testable import PersonalReaderCore

final class OPMLImportTests: XCTestCase {
  private func makeOPML(_ body: String) -> Data {
    Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="1.0">
       <head>
        <title>Exported from feeeed</title>
       </head>
       <body>
      \(body)
       </body>
      </opml>
      """.utf8
    )
  }

  func testParsesFlatOutlines() throws {
    let data = makeOPML(
      """
        <outline type="rss" xmlUrl="https://www.macstories.net/feed" text="MacStories" title="MacStories"></outline>
        <outline type="rss" xmlUrl="https://simonwillison.net/atom/everything/" text="Simon Willison" title="Simon Willison"></outline>
      """
    )

    let items = try OPMLImport.parse(data: data)

    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items[0].kind, .rss)
    XCTAssertEqual(items[0].url, "https://www.macstories.net/feed")
    XCTAssertEqual(items[0].title, "MacStories")
    XCTAssertEqual(items[1].title, "Simon Willison")
    XCTAssertTrue(items[0].isEnabled)
    XCTAssertEqual(items[0].refreshInterval, .threeHours)
  }

  func testPrefersTitleOverTextAttribute() throws {
    let data = makeOPML(
      """
        <outline type="rss" xmlUrl="https://longreads.com/feed/" text="Longreads" title="Longreads - Newest"></outline>
      """
    )

    let items = try OPMLImport.parse(data: data)

    XCTAssertEqual(items.first?.title, "Longreads - Newest")
  }

  func testFallsBackToTextAttribute() throws {
    let data = makeOPML(
      """
        <outline type="rss" xmlUrl="https://lobste.rs/rss" title=""></outline>
      """
    )

    let items = try OPMLImport.parse(data: data)

    XCTAssertEqual(items.first?.title, "")
  }

  func testDecodesEscapedAttributes() throws {
    let data = makeOPML(
      """
        <outline xmlUrl="https://bigthink.com/feed/technology-innovation" text="Technology &amp; Innovation - Big Think" title="Technology &amp; Innovation - Big Think"></outline>
      """
    )

    let items = try OPMLImport.parse(data: data)

    XCTAssertEqual(items.first?.title, "Technology & Innovation - Big Think")
  }

  func testSkipsOutlinesWithoutXMLURL() throws {
    let data = makeOPML(
      """
        <outline text="Folder">
          <outline xmlUrl="https://lobste.rs/top/rss" text="Lobsters Top"></outline>
        </outline>
        <outline text="Bookmark" type="link" url="https://example.com"></outline>
      """
    )

    let items = try OPMLImport.parse(data: data)

    XCTAssertEqual(items.map(\.url), ["https://lobste.rs/top/rss"])
  }

  func testAcceptsAtomTypedOutlines() throws {
    let data = makeOPML(
      """
        <outline type="atom" xmlUrl="https://simonwillison.net/atom/everything/" text="Simon Willison"></outline>
      """
    )

    let items = try OPMLImport.parse(data: data)

    XCTAssertEqual(items.first?.url, "https://simonwillison.net/atom/everything/")
  }

  func testEmptyOPMLReturnsNoItems() throws {
    let items = try OPMLImport.parse(data: makeOPML(""))

    XCTAssertTrue(items.isEmpty)
  }

  func testRejectsNonOPMLXML() {
    let data = Data(
      """
      <?xml version="1.0"?>
      <rss version="2.0"><channel><title>Blog</title></channel></rss>
      """.utf8
    )

    XCTAssertThrowsError(try OPMLImport.parse(data: data)) { error in
      XCTAssertEqual(error as? OPMLImportError, .invalidFormat)
    }
  }

  func testRejectsMalformedXML() {
    let data = Data(
      """
      <?xml version="1.0"?>
      <opml><body><outline xmlUrl="https://example.com/feed"
      """.utf8
    )

    XCTAssertThrowsError(try OPMLImport.parse(data: data)) { error in
      XCTAssertEqual(error as? OPMLImportError, .unreadable)
    }
  }

  func testRejectsNonXMLData() {
    XCTAssertThrowsError(try OPMLImport.parse(data: Data("not xml at all".utf8))) { error in
      XCTAssertEqual(error as? OPMLImportError, .unreadable)
    }
  }

  func testLooksLikeOPMLDetectsDataFormat() {
    XCTAssertTrue(OPMLImport.looksLikeOPML(Data("<opml></opml>".utf8)))
    XCTAssertTrue(
      OPMLImport.looksLikeOPML(Data("\n  \t <?xml version=\"1.0\"?>".utf8)))
    XCTAssertTrue(
      OPMLImport.looksLikeOPML(Data([0xEF, 0xBB, 0xBF] + Array("<opml/>".utf8))))
    XCTAssertFalse(OPMLImport.looksLikeOPML(Data("{}".utf8)))
    XCTAssertFalse(OPMLImport.looksLikeOPML(Data()))
  }

  func testExampleFilePlansLikeUserImport() throws {
    let data = Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="1.0">
       <head>
        <title>Exported from feeeed</title>
       </head>
       <body>
        <outline type="rss" xmlUrl="https://www.macstories.net/feed" text="MacStories" title="MacStories"></outline>
        <outline type="rss" xmlUrl="http://www.quantamagazine.org/feed/" text="Quanta Magazine" title="Quanta Magazine"></outline>
        <outline type="rss" xmlUrl="https://simonwillison.net/atom/everything/" text="Simon Willison's Weblog" title="Simon Willison's Weblog"></outline>
        <outline type="rss" xmlUrl="http://www.producthunt.com/feed" text="Product Hunt" title="Product Hunt"></outline>
        <outline type="rss" xmlUrl="https://lobste.rs/rss" text="Lobsters" title="Lobsters"></outline>
       </body>
      </opml>
      """.utf8
    )

    let items = try OPMLImport.parse(data: data)
    let plan = FeedImportPlanner.plan(items: items, existingURLs: [])

    XCTAssertEqual(plan.addedCount, 3)
    XCTAssertEqual(plan.rejectedCount, 2)
    XCTAssertEqual(
      plan.rejected.map(\.issue),
      [.insecureURL, .insecureURL]
    )
    XCTAssertEqual(
      plan.accepted.map(\.url),
      [
        "https://www.macstories.net/feed",
        "https://simonwillison.net/atom/everything",
        "https://lobste.rs/rss",
      ])
  }

  func testOPMLImportDeduplicatesAgainstExistingLibrary() throws {
    let data = makeOPML(
      """
        <outline xmlUrl="https://lobste.rs/rss" text="Lobsters"></outline>
        <outline xmlUrl="https://www.macstories.net/feed" text="MacStories"></outline>
      """
    )

    let items = try OPMLImport.parse(data: data)
    let plan = FeedImportPlanner.plan(
      items: items,
      existingURLs: ["https://www.macstories.net/feed"]
    )

    XCTAssertEqual(plan.addedCount, 1)
    XCTAssertEqual(plan.accepted.first?.url, "https://lobste.rs/rss")
    XCTAssertEqual(plan.rejected.first?.issue, .duplicate)
  }
}
