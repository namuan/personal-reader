import Foundation

public protocol FeedFetching: Sendable {
  func fetch(configuration: FeedConfiguration, after cursor: String?) async throws -> Data
}

extension FeedFetching {
  public func fetch(configuration: FeedConfiguration) async throws -> Data {
    try await fetch(configuration: configuration, after: nil)
  }
}

public struct RedditFeedClient: FeedFetching, Sendable {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func fetch(configuration: FeedConfiguration, after cursor: String?) async throws -> Data {
    var request = URLRequest(url: try configuration.feedURL(after: cursor))
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(
      "application/rss+xml, application/xml, text/xml",
      forHTTPHeaderField: "Accept"
    )

    do {
      let (data, response) = try await session.data(for: request)

      guard let response = response as? HTTPURLResponse else {
        throw FeedClientError.invalidResponse
      }
      switch response.statusCode {
      case 200...299:
        return data
      case 401, 403:
        throw FeedClientError.invalidCredentials(statusCode: response.statusCode)
      case 429:
        throw FeedClientError.rateLimited(
          retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        )
      case 500...599:
        throw FeedClientError.serverError(statusCode: response.statusCode)
      default:
        throw FeedClientError.unexpectedStatus(response.statusCode)
      }
    } catch let error as FeedClientError {
      throw error
    } catch is CancellationError {
      throw FeedClientError.cancelled
    } catch let urlError as URLError {
      switch urlError.code {
      case .timedOut, .cannotFindHost:
        throw FeedClientError.timedOut
      case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost,
        .cannotConnectToHost, .dnsLookupFailed:
        throw FeedClientError.offline
      case .cancelled:
        throw FeedClientError.cancelled
      default:
        throw FeedClientError.transportFailure(code: urlError.errorCode)
      }
    }
  }
}

public enum FeedClientError: Error, Equatable, Sendable {
  case invalidCredentials(statusCode: Int)
  case rateLimited(retryAfter: TimeInterval?)
  case serverError(statusCode: Int)
  case unexpectedStatus(Int)
  case invalidResponse
  case offline
  case timedOut
  case transportFailure(code: Int)
  case cancelled
}
