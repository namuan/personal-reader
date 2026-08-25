import Foundation

public protocol FeedFetching: Sendable {
  func fetch(configuration: FeedConfiguration) async throws -> Data
}

public struct RedditFeedClient: FeedFetching, Sendable {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func fetch(configuration: FeedConfiguration) async throws -> Data {
    var request = URLRequest(url: try configuration.feedURL)
    request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(
      "application/rss+xml, application/xml, text/xml",
      forHTTPHeaderField: "Accept"
    )

    let (data, response) = try await session.data(for: request)

    guard let response = response as? HTTPURLResponse else {
      throw FeedClientError.invalidResponse
    }
    if response.statusCode == 429 {
      throw FeedClientError.rateLimited(
        retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
      )
    }
    guard (200..<300).contains(response.statusCode) else {
      throw FeedClientError.httpStatus(response.statusCode)
    }

    return data
  }
}

public enum FeedClientError: Error, Equatable {
  case httpStatus(Int)
  case invalidResponse
  case rateLimited(retryAfter: TimeInterval?)
}
