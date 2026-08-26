import XCTest

@testable import PersonalReaderCore

final class SyndicationParserTests: XCTestCase {
  func testParsesRSS20FeedWithItemsAndCategories() throws {
    let xml = """
      <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel>
          <title>Sample Feed</title>
          <link>https://example.com</link>
          <item>
            <title>First</title>
            <link>https://example.com/a</link>
            <guid>https://example.com/a</guid>
            <dc:creator>Alice</dc:creator>
            <category>tech</category>
            <pubDate>Wed, 02 Oct 2024 13:00:00 +0000</pubDate>
            <content:encoded><![CDATA[<p>Hello <strong>world</strong></p>]]></content:encoded>
          </item>
        </channel>
      </rss>
      """

    let feed = try SyndicationParser().parse(Data(xml.utf8))
    XCTAssertEqual(feed.title, "Sample Feed")
    XCTAssertEqual(feed.siteLink, "https://example.com")
    XCTAssertEqual(feed.entries.count, 1)
    let entry = try XCTUnwrap(feed.entries.first)
    XCTAssertEqual(entry.title, "First")
    XCTAssertEqual(entry.link, "https://example.com/a")
    XCTAssertEqual(entry.id, "https://example.com/a")
    XCTAssertEqual(entry.author, "Alice")
    XCTAssertEqual(entry.categories, ["tech"])
    XCTAssertGreaterThan(entry.publishedAt, 0)
    XCTAssertTrue(entry.content.contains("Hello"))
  }

  func testParsesAtomFeedWithIdAndContent() throws {
    let xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Atom Feed</title>
        <link href="https://example.com/atom" />
        <entry>
          <id>tag:example.com,2024:1</id>
          <title>Atom entry</title>
          <link href="https://example.com/atom/1" />
          <updated>2024-10-02T13:00:00Z</updated>
          <author><name>Bob</name></author>
          <summary>Plain summary text</summary>
          <content type="html">&lt;p&gt;Hello&lt;/p&gt;</content>
        </entry>
      </feed>
      """

    let feed = try SyndicationParser().parse(Data(xml.utf8))
    XCTAssertEqual(feed.title, "Atom Feed")
    XCTAssertEqual(feed.siteLink, "https://example.com/atom")
    XCTAssertEqual(feed.entries.count, 1)
    let entry = feed.entries[0]
    XCTAssertEqual(entry.id, "tag:example.com,2024:1")
    XCTAssertEqual(entry.title, "Atom entry")
    XCTAssertEqual(entry.link, "https://example.com/atom/1")
    XCTAssertEqual(entry.author, "Bob")
    XCTAssertTrue(entry.content.contains("Hello"))
    XCTAssertGreaterThan(entry.publishedAt, 0)
  }

  func testSanitizesScriptAndEventHandlers() throws {
    let xml = """
      <rss version="2.0">
        <channel>
          <title>Unsafe</title>
          <item>
            <title>Unsafe entry</title>
            <link>https://example.com/unsafe</link>
            <guid>unsafe</guid>
            <description><![CDATA[
              <p>safe</p>
              <script>alert(1)</script>
              <a href="javascript:alert(1)">click</a>
              <img src="https://example.com/x.png" onerror="alert(1)" />
            ]]></description>
          </item>
        </channel>
      </rss>
      """

    let feed = try SyndicationParser().parse(Data(xml.utf8))
    let entry = try XCTUnwrap(feed.entries.first)
    XCTAssertFalse(entry.content.contains("<script"))
    XCTAssertFalse(entry.content.contains("javascript:"))
    XCTAssertFalse(entry.content.contains("onerror"))
    XCTAssertTrue(entry.content.contains("safe"))
    XCTAssertTrue(entry.content.contains("click"))
  }

  func testInvalidXMLThrows() {
    XCTAssertThrowsError(try SyndicationParser().parse(Data("<rss>".utf8)))
  }

  func testEmptyFeedReturnsNoEntries() throws {
    let xml = """
      <rss version="2.0"><channel><title>Empty</title></channel></rss>
      """
    let feed = try SyndicationParser().parse(Data(xml.utf8))
    XCTAssertEqual(feed.title, "Empty")
    XCTAssertTrue(feed.entries.isEmpty)
  }

  func testFallbackTimestampUsedWhenDateMissing() throws {
    let xml = """
      <rss version="2.0">
        <channel>
          <title>No Dates</title>
          <item>
            <title>Old</title>
            <link>https://example.com/x</link>
            <guid>x</guid>
            <description>body</description>
          </item>
        </channel>
      </rss>
      """
    let fallback = Date(timeIntervalSince1970: 1_700_000_000)
    let feed = try SyndicationParser().parse(Data(xml.utf8), fallbackFetchedAt: fallback)
    XCTAssertEqual(feed.entries.first?.publishedAt, 1_700_000_000)
  }
}
