import Foundation

public struct FeedConfiguration: Equatable, Sendable {
  public let username: String
  public let token: String
  public let subreddits: [String]
  public let userAgent: String

  public init(
    username: String,
    token: String,
    subreddits: [String],
    userAgent: String
  ) throws {
    let normalizedSubreddits = subreddits.map(Self.normalize)

    guard !username.isEmpty else {
      throw FeedConfigurationError.missingUsername
    }
    guard !token.isEmpty else {
      throw FeedConfigurationError.missingToken
    }
    guard !normalizedSubreddits.isEmpty else {
      throw FeedConfigurationError.missingSubreddits
    }
    guard normalizedSubreddits.allSatisfy(Self.isValid) else {
      throw FeedConfigurationError.invalidSubreddit
    }
    guard !userAgent.isEmpty else {
      throw FeedConfigurationError.missingUserAgent
    }

    self.username = username
    self.token = token
    self.subreddits = normalizedSubreddits
    self.userAgent = userAgent
  }

  public var feedURL: URL {
    get throws {
      var components = URLComponents()
      components.scheme = "https"
      components.host = "www.reddit.com"
      components.percentEncodedPath = "/r/\(subreddits.joined(separator: "+"))/.rss"
      components.queryItems = [
        URLQueryItem(name: "feed", value: token),
        URLQueryItem(name: "user", value: username),
      ]

      guard let url = components.url else {
        throw FeedConfigurationError.invalidURL
      }
      return url
    }
  }

  private static func normalize(_ subreddit: String) -> String {
    subreddit
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "r/", with: "", options: [.anchored, .caseInsensitive])
  }

  private static func isValid(_ subreddit: String) -> Bool {
    !subreddit.isEmpty
      && subreddit.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil
  }
}

public enum FeedConfigurationError: Error, Equatable {
  case invalidSubreddit
  case invalidURL
  case missingSubreddits
  case missingToken
  case missingUserAgent
  case missingUsername
}
