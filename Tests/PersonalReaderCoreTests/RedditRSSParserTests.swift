import Foundation
import XCTest

@testable import PersonalReaderCore

final class RedditRSSParserTests: XCTestCase {
  func testParsesRSSItemAndSanitizesHTML() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel>
          <item>
            <title>A story &amp; its ending</title>
            <link>https://www.reddit.com/r/shortstories/comments/abc123/a_story/</link>
            <guid>https://www.reddit.com/r/shortstories/comments/abc123/a_story/</guid>
            <dc:creator>u/storyteller</dc:creator>
            <category>r/shortstories</category>
            <pubDate>Sat, 24 Aug 2024 12:30:00 +0000</pubDate>
            <content:encoded><![CDATA[<p>Hello&nbsp;world.</p><script>alert('no')</script>]]></content:encoded>
          </item>
        </channel>
      </rss>
      """

    let stories = try RedditRSSParser().parse(Data(xml.utf8))

    XCTAssertEqual(stories.count, 1)
    XCTAssertEqual(stories[0].id, "t3_abc123")
    XCTAssertEqual(stories[0].title, "A story & its ending")
    XCTAssertEqual(stories[0].author, "storyteller")
    XCTAssertEqual(stories[0].subreddit, "shortstories")
    XCTAssertEqual(stories[0].contentBody, "<p>Hello&nbsp;world.</p>")
    XCTAssertEqual(stories[0].publishedAt, 1_724_502_600)
  }

  func testRejectsMalformedXML() {
    XCTAssertThrowsError(try RedditRSSParser().parse(Data("<rss>".utf8)))
  }
}
