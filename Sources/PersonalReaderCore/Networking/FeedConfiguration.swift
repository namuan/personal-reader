import Foundation

public enum FeedMode: String, CaseIterable, Codable, Equatable, Sendable {
  case subscribed
  case privateListing
}

public enum RedditPrivateListing: String, CaseIterable, Codable, Equatable, Sendable {
  case saved
  case upvoted
  case downvoted
  case hidden
  case submitted
  case comments

  func path(username: String) -> String {
    switch self {
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
  case subscribed
  case privateListing(RedditPrivateListing)

  public var mode: FeedMode {
    switch self {
    case .subscribed:
      return .subscribed
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
    self.username = username
    self.token = token
    self.source = source
    self.userAgent = userAgent
  }

  public var privateListing: RedditPrivateListing? {
    guard case .privateListing(let listing) = source else { return nil }
    return listing
  }

  public var feedKey: String {
    let usernameKey = username.lowercased()
    switch source {
    case .subscribed:
      return "u/\(usernameKey)/subscribed"
    case .privateListing(let listing):
      return "u/\(usernameKey)/listing/\(listing.rawValue)"
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
    case .subscribed:
      components.path = "/.rss"
    case .privateListing(let listing):
      components.path = listing.path(username: username)
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
}

public enum FeedConfigurationError: Error, Equatable {
  case invalidURL
  case missingToken
  case missingUserAgent
  case missingUsername
}
