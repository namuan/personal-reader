import XCTest

@testable import PersonalReaderCore

final class RedditRSSParserFixtureTests: XCTestCase {
  private let parser = RedditRSSParser()

  func testParsesAtomEntriesFromLiveRedditFeedShape() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
        <category term="multi" label="r/multi"/>
        <updated>2026-08-25T06:12:30+00:00</updated>
        <id>/r/shortstories+writingprompts/.rss</id>
        <link rel="self" href="https://www.reddit.com/r/shortstories+writingprompts/.rss" type="application/atom+xml"/>
        <entry>
          <author><name>/u/storyteller</name><uri>https://www.reddit.com/user/storyteller</uri></author>
          <category term="WritingPrompts" label="r/WritingPrompts"/>
          <content type="html">&lt;div class="md"&gt;&lt;p&gt;A &lt;em&gt;prompt&lt;/em&gt; body &lt;script&gt;alert(1)&lt;/script&gt;&lt;/p&gt;&lt;/div&gt;</content>
          <id>t3_1vx75er</id>
          <link href="https://www.reddit.com/r/WritingPrompts/comments/1vx75er/pi_after_your_old_master/" />
          <updated>2026-08-24T16:09:56+00:00</updated>
          <published>2026-08-24T16:09:56+00:00</published>
          <title>[PI] An apprenticeship story</title>
        </entry>
        <entry>
          <author><name>/u/second_author</name></author>
          <category term="shortstories" label="r/shortstories"/>
          <summary type="html">&lt;p&gt;Summary body&lt;/p&gt;</summary>
          <id>t1_hk3k55f</id>
          <link href="https://www.reddit.com/r/shortstories/comments/1vx75ab/sp_hold_your_peace/" />
          <updated>2026-08-24T15:00:00+00:00</updated>
          <title>[SP] Hold Your Peace</title>
        </entry>
      </feed>
      """

    let stories = try parser.parse(Data(xml.utf8))

    XCTAssertEqual(stories.count, 2)
    XCTAssertEqual(stories[0].id, "t3_1vx75er")
    XCTAssertEqual(stories[0].title, "[PI] An apprenticeship story")
    XCTAssertEqual(stories[0].author, "storyteller")
    XCTAssertEqual(stories[0].subreddit, "WritingPrompts")
    XCTAssertEqual(
      stories[0].link,
      "https://www.reddit.com/r/WritingPrompts/comments/1vx75er/pi_after_your_old_master/"
    )
    XCTAssertEqual(
      stories[0].publishedAt,
      Int64(iso8601Epoch("2026-08-24T16:09:56+00:00"))
    )
    XCTAssertEqual(stories[0].contentBody, "<div><p>A <em>prompt</em> body </p></div>")
    XCTAssertEqual(stories[1].id, "t1_hk3k55f")
    XCTAssertEqual(stories[1].contentBody, "<p>Summary body</p>")
    XCTAssertEqual(stories[1].subreddit, "shortstories")
  }

  private func iso8601Epoch(_ string: String) -> Double {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: string)!.timeIntervalSince1970
  }

  func testParsesNamespacedItemWithCDATAContent() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel>
          <item>
            <title>A story &amp; its ending</title>
            <link>https://www.reddit.com/r/shortstories/comments/abc123/a_story/</link>
            <guid isPermaLink="false">https://www.reddit.com/r/shortstories/comments/abc123/a_story/</guid>
            <dc:creator>u/storyteller</dc:creator>
            <category>r/shortstories</category>
            <pubDate>Sat, 24 Aug 2024 12:30:00 +0000</pubDate>
            <content:encoded><![CDATA[<p>Hello&nbsp;world.</p><script>alert('no')</script>]]></content:encoded>
          </item>
        </channel>
      </rss>
      """

    let stories = try parser.parse(Data(xml.utf8))

    XCTAssertEqual(stories.count, 1)
    XCTAssertEqual(stories[0].id, "t3_abc123")
    XCTAssertEqual(stories[0].title, "A story & its ending")
    XCTAssertEqual(stories[0].author, "storyteller")
    XCTAssertEqual(stories[0].subreddit, "shortstories")
    XCTAssertEqual(stories[0].contentBody, "<p>Hello&nbsp;world.</p>")
    XCTAssertEqual(stories[0].publishedAt, 1_724_502_600)
  }

  func testAcceptsAlternateNamespacePrefixSpellings() throws {
    let xml = """
      <?xml version="1.0"?>
      <rss version="2.0" xmlns:a="http://purl.org/dc/elements/1.1/" xmlns:b="http://purl.org/rss/1.0/modules/content/">
        <channel><item>
          <title>T</title>
          <guid>t3_xyz789</guid>
          <a:creator>/u/author</a:creator>
          <b:encoded><![CDATA[<p>body</p>]]></b:encoded>
        </item></channel>
      </rss>
      """

    let stories = try parser.parse(Data(xml.utf8))

    XCTAssertEqual(stories.count, 1)
    XCTAssertEqual(stories[0].author, "author")
    XCTAssertEqual(stories[0].contentBody, "<p>body</p>")
  }

  func testFallsBackToDescriptionWhenEncodedMissing() throws {
    let xml = """
      <rss version="2.0"><channel><item>
        <title>Fallback</title>
        <guid>t3_desc001</guid>
        <description><![CDATA[<p>plain body</p>]]></description>
      </item></channel></rss>
      """

    let stories = try parser.parse(Data(xml.utf8))

    XCTAssertEqual(stories[0].contentBody, "<p>plain body</p>")
  }

  func testDerivesSubredditFromLinkWhenCategoryMissing() throws {
    let xml = """
      <rss version="2.0"><channel><item>
        <title>No category</title>
        <link>https://reddit.com/r/writingprompts/comments/def456/prompt/</link>
      </item></channel></rss>
      """

    let stories = try parser.parse(Data(xml.utf8))

    XCTAssertEqual(stories[0].subreddit, "writingprompts")
    XCTAssertEqual(stories[0].id, "t3_def456")
    XCTAssertEqual(stories[0].publishedAt, 0)
  }

  func testRejectsItemsWithoutStableIDsButKeepsOthers() throws {
    let xml = """
      <rss version="2.0"><channel>
        <item><title>Has id</title><guid>t3_ok00001</guid></item>
        <item><title>No id anywhere</title></item>
        <item><title>Also has id</title><guid>t3_ok00002</guid></item>
      </channel></rss>
      """

    let stories = try parser.parse(Data(xml.utf8))

    XCTAssertEqual(stories.map(\.id), ["t3_ok00001", "t3_ok00002"])
  }

  func testParsesISO8601Dates() throws {
    let xml = """
      <rss version="2.0"><channel><item>
        <title>ISO date</title>
        <guid>t3_iso0001</guid>
        <pubDate>2024-08-24T12:30:00+00:00</pubDate>
      </item></channel></rss>
      """

    let stories = try parser.parse(Data(xml.utf8))

    XCTAssertEqual(stories[0].publishedAt, 1_724_502_600)
  }

  func testEmptyFeedReturnsNoStories() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"><channel><title>nothing here</title></channel></rss>
      """

    XCTAssertEqual(try parser.parse(Data(xml.utf8)), [])
  }

  func testRejectsMalformedXML() {
    XCTAssertThrowsError(try parser.parse(Data("<rss>".utf8)))
  }

  func testHandlesVeryLongStoryContent() throws {
    let longParagraph = String(repeating: "word ", count: 20_000)
    let xml = """
      <rss version="2.0"><channel><item>
        <title>Long story</title>
        <guid>t3_long001</guid>
        <content:encoded><![CDATA[<p>\(longParagraph)</p>]]></content:encoded>
      </item></channel></rss>
      """

    let stories = try parser.parse(Data(xml.utf8))

    XCTAssertGreaterThan(stories[0].contentBody.count, 90_000)
    XCTAssertFalse(stories[0].contentBody.contains("<script"))
  }

  func testHandlesHTMLEntitiesAndUnicodeInTitles() throws {
    let xml = """
      <rss version="2.0"><channel><item>
        <title>Café — a “quoted” title &amp; more</title>
        <guid>t3_uni0001</guid>
      </item></channel></rss>
      """

    let stories = try parser.parse(Data(xml.utf8))

    XCTAssertEqual(stories[0].title, "Café — a “quoted” title & more")
  }

  private func makeStory(id: String, publishedAt: Int64) -> Story {
    Story(
      id: id,
      title: "Title",
      contentBody: "<p>Body</p>",
      author: "author",
      subreddit: "shortstories",
      publishedAt: publishedAt,
      sourceId: FeedSourceRecord.builtInRedditID()
    )
  }
}
