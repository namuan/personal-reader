import Foundation

public enum FeedMode: String, CaseIterable, Codable, Equatable, Sendable {
  case subreddits
  case privateListing
}

public enum RedditFrontPageSort: String, CaseIterable, Codable, Equatable, Sendable {
  case best
  case hot
  case new
  case rising

  func path() -> String {
    switch self {
    case .best:
      return "/.rss"
    case .hot:
      return "/hot/.rss"
    case .new:
      return "/new/.rss"
    case .rising:
      return "/rising/.rss"
    }
  }
}

public enum RedditPrivateListing: String, CaseIterable, Codable, Equatable, Sendable {
  case frontPage
  case saved
  case upvoted
  case downvoted
  case hidden
  case submitted
  case comments

  func path(username: String, frontPageSort: RedditFrontPageSort) -> String {
    switch self {
    case .frontPage:
      return frontPageSort.path()
    case .saved:
      return "/user/\(username)/saved/.rss"
    case .upvoted:
      return "/user/\(username)/upvoted/.rss"
    case .downvoted:
      return "/user/\(username)/downvoted/.rss"
    case .hidden:
      return "/user/\(username)/hidden/.rss"
    case .submitted:
      return "/user/\(username)/submitted/.rss"
    case .comments:
      return "/user/\(username)/comments/.rss"
    }
  }
}

public enum FeedSource: Equatable, Sendable {
  case subreddits([String])
  case privateListing(RedditPrivateListing, RedditFrontPageSort)

  public var mode: FeedMode {
    switch self {
    case .subreddits:
      return .subreddits
    case .privateListing:
      return .privateListing
    }
  }
}

public struct FeedConfiguration: Equatable, Sendable {
  public let username: String
  public let token: String
  public let source: FeedSource
  public let userAgent: String

  public init(
    username: String,
    token: String,
    subreddits: [String],
    userAgent: String
  ) throws {
    try self.init(
      username: username,
      token: token,
      source: .subreddits(subreddits),
      userAgent: userAgent
    )
  }

  public init(
    username: String,
    token: String,
    privateListing: RedditPrivateListing,
    frontPageSort: RedditFrontPageSort = .best,
    userAgent: String
  ) throws {
    try self.init(
      username: username,
      token: token,
      source: .privateListing(privateListing, frontPageSort),
      userAgent: userAgent
    )
  }

  public init(
    username: String,
    token: String,
    source: FeedSource,
    userAgent: String
  ) throws {
    guard !username.isEmpty else {
      throw FeedConfigurationError.missingUsername
    }
    guard !token.isEmpty else {
      throw FeedConfigurationError.missingToken
    }
    guard !userAgent.isEmpty else {
      throw FeedConfigurationError.missingUserAgent
    }

    switch source {
    case .subreddits(let subreddits):
      let normalizedSubreddits = subreddits.map(Self.normalize)
      guard !normalizedSubreddits.isEmpty else {
        throw FeedConfigurationError.missingSubreddits
      }
      guard normalizedSubreddits.allSatisfy(Self.isValid) else {
        throw FeedConfigurationError.invalidSubreddit
      }
      self.source = .subreddits(normalizedSubreddits)
    case .privateListing:
      self.source = source
    }

    self.username = username
    self.token = token
    self.userAgent = userAgent
  }

  public var subreddits: [String] {
    guard case .subreddits(let subreddits) = source else { return [] }
    return subreddits
  }

  public var privateListing: RedditPrivateListing? {
    guard case .privateListing(let listing, _) = source else { return nil }
    return listing
  }

  public var frontPageSort: RedditFrontPageSort? {
    guard case .privateListing(let listing, let sort) = source, listing == .frontPage else {
      return nil
    }
    return sort
  }

  public var feedKey: String {
    let usernameKey = username.lowercased()
    switch source {
    case .subreddits(let subreddits):
      let subredditKey = subreddits.map { $0.lowercased() }.sorted().joined(separator: "+")
      return "u/\(usernameKey)/r/\(subredditKey)"
    case .privateListing(let listing, let sort):
      switch listing {
      case .frontPage:
        return "u/\(usernameKey)/listing/\(listing.rawValue)/\(sort.rawValue)"
      default:
        return "u/\(usernameKey)/listing/\(listing.rawValue)"
      }
    }
  }

  public var feedURL: URL {
    get throws {
      try feedURL(after: nil)
    }
  }

  public func feedURL(after cursor: String?) throws -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.reddit.com"
    switch source {
    case .subreddits(let subreddits):
      components.percentEncodedPath = "/r/\(subreddits.joined(separator: "+"))/.rss"
    case .privateListing(let listing, let sort):
      components.path = listing.path(username: username, frontPageSort: sort)
    }
    components.queryItems = [
      URLQueryItem(name: "feed", value: token),
      URLQueryItem(name: "user", value: username),
    ]
    if let cursor, !cursor.isEmpty {
      components.queryItems?.append(URLQueryItem(name: "after", value: cursor))
    }

    guard let url = components.url else {
      throw FeedConfigurationError.invalidURL
    }
    return url
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
