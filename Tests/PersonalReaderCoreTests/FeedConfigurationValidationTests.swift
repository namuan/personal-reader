import Testing

@testable import PersonalReaderCore

struct FeedConfigurationValidationTests {
  @Test func rejectsEmptyUsername() {
    #expect(
      throws: FeedConfigurationError.missingUsername
    ) {
      _ = try FeedConfiguration(
        username: "", token: "t", source: .subscribed, userAgent: "ua"
      )
    }
  }

  @Test func rejectsEmptyToken() {
    #expect(
      throws: FeedConfigurationError.missingToken
    ) {
      _ = try FeedConfiguration(
        username: "u", token: "", source: .subscribed, userAgent: "ua"
      )
    }
  }

  @Test func rejectsInvalidUserAgent() {
    #expect(
      throws: FeedConfigurationError.missingUserAgent
    ) {
      _ = try FeedConfiguration(
        username: "u", token: "t", source: .subscribed, userAgent: ""
      )
    }
  }

  @Test func feedKeyIsStableAcrossTokens() throws {
    let first = try FeedConfiguration(
      username: "Reader",
      token: "secret-token",
      source: .subscribed,
      userAgent: "ua"
    )
    let second = try FeedConfiguration(
      username: "reader",
      token: "different",
      source: .subscribed,
      userAgent: "ua"
    )

    #expect(first.feedKey == second.feedKey)
    #expect(!first.feedKey.contains("secret-token"))
  }

  @Test func privateListingFeedKeysAreDistinctAndExcludeToken() throws {
    let saved = try FeedConfiguration(
      username: "Reader",
      token: "secret-token",
      source: .privateListing(.saved),
      userAgent: "ua"
    )
    let upvoted = try FeedConfiguration(
      username: "reader",
      token: "another-token",
      source: .privateListing(.upvoted),
      userAgent: "ua"
    )

    #expect(saved.feedKey != upvoted.feedKey)
    #expect(saved.feedKey == "u/reader/listing/saved")
    #expect(!saved.feedKey.contains("secret-token"))
  }

  @Test func feedURLContainsPrivateQueryItemsInOrder() throws {
    let configuration = try FeedConfiguration(
      username: "reader",
      token: "ABCDEFGHIJKLMNOPQRST",
      source: .subscribed,
      userAgent: "ios:PersonalStoryReader:v1.0.0 (by /u/reader)"
    )

    let url = try configuration.feedURL
    #expect(url.absoluteString.hasPrefix("https://www.reddit.com/.rss?"))
    #expect(url.absoluteString.contains("feed=ABCDEFGHIJKLMNOPQRST"))
    #expect(url.absoluteString.contains("user=reader"))
  }
}
