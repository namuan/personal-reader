import Testing

@testable import PersonalReaderCore

struct FeedConfigurationValidationTests {
  @Test func rejectsEmptyUsername() {
    #expect(
      throws: FeedConfigurationError.missingUsername
    ) {
      _ = try FeedConfiguration(username: "", token: "t", subreddits: ["a"], userAgent: "ua")
    }
  }

  @Test func rejectsEmptyToken() {
    #expect(
      throws: FeedConfigurationError.missingToken
    ) {
      _ = try FeedConfiguration(username: "u", token: "", subreddits: ["a"], userAgent: "ua")
    }
  }

  @Test func rejectsMissingSubreddits() {
    #expect(
      throws: FeedConfigurationError.missingSubreddits
    ) {
      _ = try FeedConfiguration(username: "u", token: "t", subreddits: [], userAgent: "ua")
    }
  }

  @Test func rejectsInvalidUserAgent() {
    #expect(
      throws: FeedConfigurationError.missingUserAgent
    ) {
      _ = try FeedConfiguration(username: "u", token: "t", subreddits: ["a"], userAgent: "")
    }
  }

  @Test func feedKeyIsStableAcrossOrderAndCase() throws {
    let first = try FeedConfiguration(
      username: "Reader", token: "secret-token", subreddits: ["WritingPrompts", "shortstories"],
      userAgent: "ua"
    )
    let second = try FeedConfiguration(
      username: "reader", token: "different", subreddits: ["ShortStories", "writingprompts"],
      userAgent: "ua"
    )

    #expect(first.feedKey == second.feedKey)
    #expect(!first.feedKey.contains("secret-token"))
  }

  @Test func privateListingFeedKeysAreDistinctAndExcludeToken() throws {
    let frontPage = try FeedConfiguration(
      username: "Reader",
      token: "secret-token",
      privateListing: .frontPage,
      userAgent: "ua"
    )
    let saved = try FeedConfiguration(
      username: "reader",
      token: "another-token",
      privateListing: .saved,
      userAgent: "ua"
    )

    #expect(frontPage.feedKey != saved.feedKey)
    #expect(frontPage.feedKey == "u/reader/listing/frontPage/best")
    #expect(!frontPage.feedKey.contains("secret-token"))
  }

  @Test func feedURLContainsPrivateQueryItemsInOrder() throws {
    let configuration = try FeedConfiguration(
      username: "reader",
      token: "ABCDEFGHIJKLMNOPQRST",
      subreddits: ["shortstories"],
      userAgent: "ios:PersonalStoryReader:v1.0.0 (by /u/reader)"
    )

    let url = try configuration.feedURL
    #expect(url.absoluteString.hasPrefix("https://www.reddit.com/r/shortstories/.rss?"))
    #expect(url.absoluteString.contains("feed=ABCDEFGHIJKLMNOPQRST"))
    #expect(url.absoluteString.contains("user=reader"))
  }
}
