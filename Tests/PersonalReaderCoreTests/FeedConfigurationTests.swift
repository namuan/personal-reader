import XCTest

@testable import PersonalReaderCore

final class FeedConfigurationTests: XCTestCase {
  func testBuildsSubscribedFeedURL() throws {
    let configuration = try FeedConfiguration(
      username: "reader",
      token: "ABCDEFGHIJKLMNOPQRST",
      source: .subscribed,
      userAgent: "ios:PersonalStoryReader:v1.0.0 (by /u/reader)"
    )

    XCTAssertEqual(
      try configuration.feedURL.absoluteString,
      "https://www.reddit.com/.rss?feed=ABCDEFGHIJKLMNOPQRST&user=reader"
    )
  }

  func testBuildsOlderPageURL() throws {
    let configuration = try FeedConfiguration(
      username: "reader",
      token: "PRIVATE_TOKEN",
      source: .privateListing(.saved),
      userAgent: "PersonalReader"
    )
    let components = try XCTUnwrap(
      URLComponents(url: configuration.feedURL(after: "t3_abc123"), resolvingAgainstBaseURL: false)
    )

    XCTAssertEqual(components.path, "/user/reader/saved/.rss")
    XCTAssertEqual(components.queryItems?.first { $0.name == "after" }?.value, "t3_abc123")
    XCTAssertEqual(components.queryItems?.first { $0.name == "feed" }?.value, "PRIVATE_TOKEN")
    XCTAssertEqual(components.queryItems?.first { $0.name == "user" }?.value, "reader")
  }

  func testBuildsPrivateListingURLs() throws {
    let expectedPaths: [RedditPrivateListing: String] = [
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
        source: .privateListing(listing),
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

  func testPrivateListingFeedKeyIsStable() throws {
    let listing = RedditPrivateListing.saved
    let configuration = try FeedConfiguration(
      username: "reader",
      token: "PRIVATE_TOKEN",
      source: .privateListing(listing),
      userAgent: "PersonalReader"
    )
    XCTAssertEqual(configuration.feedKey, "u/reader/listing/saved")
  }

  func testSubscribedFeedKeyIsStable() throws {
    let configuration = try FeedConfiguration(
      username: "reader",
      token: "PRIVATE_TOKEN",
      source: .subscribed,
      userAgent: "PersonalReader"
    )
    XCTAssertEqual(configuration.feedKey, "u/reader/subscribed")
  }
}
