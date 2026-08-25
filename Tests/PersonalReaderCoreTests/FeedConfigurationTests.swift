import XCTest

@testable import PersonalReaderCore

final class FeedConfigurationTests: XCTestCase {
  func testBuildsPrivateMultiSubredditURL() throws {
    let configuration = try FeedConfiguration(
      username: "reader",
      token: "ABCDEFGHIJKLMNOPQRST",
      subreddits: ["r/shortstories", "writingprompts"],
      userAgent: "ios:PersonalStoryReader:v1.0.0 (by /u/reader)"
    )

    XCTAssertEqual(
      try configuration.feedURL.absoluteString,
      "https://www.reddit.com/r/shortstories+writingprompts/.rss?feed=ABCDEFGHIJKLMNOPQRST&user=reader"
    )
  }

  func testBuildsOlderPageURL() throws {
    let configuration = try FeedConfiguration(
      username: "reader",
      token: "PRIVATE_TOKEN",
      privateListing: .frontPage,
      frontPageSort: .hot,
      userAgent: "PersonalReader"
    )
    let components = try XCTUnwrap(
      URLComponents(url: configuration.feedURL(after: "t3_abc123"), resolvingAgainstBaseURL: false)
    )

    XCTAssertEqual(components.path, "/hot/.rss")
    XCTAssertEqual(components.queryItems?.first { $0.name == "after" }?.value, "t3_abc123")
    XCTAssertEqual(components.queryItems?.first { $0.name == "feed" }?.value, "PRIVATE_TOKEN")
    XCTAssertEqual(components.queryItems?.first { $0.name == "user" }?.value, "reader")
  }

  func testBuildsPrivateListingURLs() throws {
    let expectedPaths: [RedditPrivateListing: String] = [
      .frontPage: "/.rss",
      .saved: "/user/reader/saved/.rss",
      .upvoted: "/user/reader/upvoted/.rss",
      .downvoted: "/user/reader/downvoted/.rss",
      .hidden: "/user/reader/hidden/.rss",
      .submitted: "/user/reader/submitted/.rss",
      .comments: "/user/reader/comments/.rss",
    ]

    for listing in RedditPrivateListing.allCases {
      let configuration = try FeedConfiguration(
        username: "reader",
        token: "PRIVATE_TOKEN",
        privateListing: listing,
        userAgent: "PersonalReader"
      )
      let components = try XCTUnwrap(
        URLComponents(url: configuration.feedURL, resolvingAgainstBaseURL: false))

      XCTAssertEqual(components.path, expectedPaths[listing])
      XCTAssertEqual(components.host, "www.reddit.com")
      XCTAssertEqual(components.queryItems?.first { $0.name == "feed" }?.value, "PRIVATE_TOKEN")
      XCTAssertEqual(components.queryItems?.first { $0.name == "user" }?.value, "reader")
    }
  }

  func testBuildsEveryFrontPageSortURL() throws {
    let expectedPaths: [RedditFrontPageSort: String] = [
      .best: "/.rss",
      .hot: "/hot/.rss",
      .new: "/new/.rss",
      .rising: "/rising/.rss",
    ]

    for sort in RedditFrontPageSort.allCases {
      let configuration = try FeedConfiguration(
        username: "reader",
        token: "PRIVATE_TOKEN",
        privateListing: .frontPage,
        frontPageSort: sort,
        userAgent: "PersonalReader"
      )
      let components = try XCTUnwrap(
        URLComponents(url: configuration.feedURL, resolvingAgainstBaseURL: false))

      XCTAssertEqual(components.path, expectedPaths[sort])
      XCTAssertEqual(configuration.feedKey, "u/reader/listing/frontPage/\(sort.rawValue)")
    }
  }

  func testPrivateListingDoesNotRequireSubreddits() throws {
    let configuration = try FeedConfiguration(
      username: "reader",
      token: "token",
      privateListing: .frontPage,
      userAgent: "PersonalReader"
    )

    XCTAssertEqual(configuration.subreddits, [])
    XCTAssertEqual(configuration.source, .privateListing(.frontPage, .best))
  }

  func testRejectsInvalidSubreddit() {
    XCTAssertThrowsError(
      try FeedConfiguration(
        username: "reader",
        token: "token",
        subreddits: ["not/a/subreddit"],
        userAgent: "PersonalReader"
      )
    )
  }
}
