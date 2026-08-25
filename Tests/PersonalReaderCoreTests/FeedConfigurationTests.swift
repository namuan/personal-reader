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
