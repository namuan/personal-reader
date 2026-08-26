import Foundation

public struct SyndicationFetchResponse: Sendable, Equatable {
  public let statusCode: Int
  public let data: Data
  public let etag: String?
  public let lastModified: String?

  public var isNotModified: Bool { statusCode == 304 }
}

public protocol SyndicationFeedFetching: Sendable {
  func fetch(
    url: URL,
    etag: String?,
    lastModified: String?
  ) async throws -> SyndicationFetchResponse
}

public struct SyndicationFeedClient: SyndicationFeedFetching, Sendable {
  private let session: URLSession
  private let responseSizeLimit: Int

  public init(session: URLSession = .shared, responseSizeLimit: Int = 5_000_000) {
    self.session = session
    self.responseSizeLimit = responseSizeLimit
  }

  public func fetch(
    url: URL,
    etag: String?,
    lastModified: String?
  ) async throws -> SyndicationFetchResponse {
    guard url.scheme?.lowercased() == "https" else {
      throw SyndicationClientError.insecureScheme
    }
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue(
      "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8",
      forHTTPHeaderField: "Accept"
    )
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    if let etag, !etag.isEmpty {
      request.setValue(etag, forHTTPHeaderField: "If-None-Match")
    }
    if let lastModified, !lastModified.isEmpty {
      request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
    }
    request.timeoutInterval = 30

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw SyndicationClientError.invalidResponse
      }
      switch http.statusCode {
      case 200...299:
        let finalURL = http.url ?? url
        guard finalURL.scheme?.lowercased() == "https" else {
          throw SyndicationClientError.insecureRedirect
        }
        return SyndicationFetchResponse(
          statusCode: http.statusCode,
          data: data,
          etag: http.value(forHTTPHeaderField: "ETag"),
          lastModified: http.value(forHTTPHeaderField: "Last-Modified")
        )
      case 304:
        return SyndicationFetchResponse(
          statusCode: 304,
          data: Data(),
          etag: etag,
          lastModified: lastModified
        )
      case 401, 403:
        throw SyndicationClientError.invalidCredentials(statusCode: http.statusCode)
      case 429:
        throw SyndicationClientError.rateLimited(
          retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        )
      case 500...599:
        throw SyndicationClientError.serverError(statusCode: http.statusCode)
      default:
        throw SyndicationClientError.unexpectedStatus(http.statusCode)
      }
    } catch let error as SyndicationClientError {
      throw error
    } catch is CancellationError {
      throw SyndicationClientError.cancelled
    } catch let urlError as URLError {
      switch urlError.code {
      case .timedOut, .cannotFindHost:
        throw SyndicationClientError.timedOut
      case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost,
        .cannotConnectToHost, .dnsLookupFailed:
        throw SyndicationClientError.offline
      case .cancelled:
        throw SyndicationClientError.cancelled
      default:
        throw SyndicationClientError.transportFailure(code: urlError.errorCode)
      }
    }
  }

  public static var userAgent: String {
    "ios:PersonalReader:1.0"
  }
}

public enum SyndicationClientError: Error, Equatable, Sendable {
  case insecureScheme
  case insecureRedirect
  case invalidResponse
  case invalidCredentials(statusCode: Int)
  case rateLimited(retryAfter: TimeInterval?)
  case serverError(statusCode: Int)
  case unexpectedStatus(Int)
  case offline
  case timedOut
  case transportFailure(code: Int)
  case cancelled
}
