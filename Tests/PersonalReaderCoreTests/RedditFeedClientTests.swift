import Foundation
import Testing

@testable import PersonalReaderCore

final class StubURLProtocol: URLProtocol {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
  nonisolated(unsafe) static var requestCount = 0
  nonisolated(unsafe) static var lastRequest: URLRequest?

  static func reset() {
    handler = nil
    requestCount = 0
    lastRequest = nil
  }

  static func makeClient() -> RedditFeedClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return RedditFeedClient(session: URLSession(configuration: configuration))
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    StubURLProtocol.requestCount += 1
    StubURLProtocol.lastRequest = request
    guard let handler = StubURLProtocol.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct FeedClientErrorMapping {
  private let configuration = try! FeedConfiguration(
    username: "reader",
    token: "token",
    subreddits: ["shortstories"],
    userAgent: "ios:PersonalStoryReader:v1.0.0 (by /u/reader)"
  )

  private func makeResponse(_ statusCode: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(
      url: URL(string: "https://www.reddit.com/r/shortstories/.rss")!,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: headers
    )!
  }

  @Test func successfulFetchReturnsDataWithHeaders() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in (Self.response(200), Data("<rss></rss>".utf8)) }

    let data = try await StubURLProtocol.makeClient().fetch(configuration: configuration)
    #expect(data == Data("<rss></rss>".utf8))
    #expect(StubURLProtocol.requestCount == 1)

    let sentRequest = try #require(StubURLProtocol.lastRequest)
    #expect(
      sentRequest.value(forHTTPHeaderField: "User-Agent")
        == "ios:PersonalStoryReader:v1.0.0 (by /u/reader)")
    #expect(sentRequest.value(forHTTPHeaderField: "Accept")?.contains("rss+xml") == true)
    #expect(sentRequest.value(forHTTPHeaderField: "Host") == nil)
    #expect(sentRequest.cachePolicy == .reloadIgnoringLocalCacheData)
    let url = try #require(sentRequest.url)
    #expect(url.absoluteString.contains("feed=token"))
  }

  @Test func unauthorizedMapsToInvalidCredentials() async {
    await expectError(401) { error in
      if case .invalidCredentials(let status) = error {
        #expect(status == 401)
      } else {
        Issue.record("wrong error")
      }
    }
  }

  @Test func forbiddenMapsToInvalidCredentials() async {
    await expectError(403) { error in
      if case .invalidCredentials(let status) = error {
        #expect(status == 403)
      } else {
        Issue.record("wrong error")
      }
    }
  }

  @Test func rateLimitWithoutRetryAfterMapsToRateLimited() async {
    await expectError(429) { error in
      if case .rateLimited(nil) = error {} else { Issue.record("wrong error") }
    }
  }

  @Test func rateLimitWithRetryAfterPreservesValue() async {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in (Self.response(429, headers: ["Retry-After": "120"]), Data()) }
    do {
      _ = try await StubURLProtocol.makeClient().fetch(configuration: configuration)
      Issue.record("expected failure")
    } catch let error as FeedClientError {
      if case .rateLimited(let retryAfter) = error {
        #expect(retryAfter == 120)
      } else {
        Issue.record("wrong error")
      }
    } catch {
      Issue.record("wrong error type")
    }
  }

  @Test func serverErrorMapsToServerError() async {
    await expectError(503) { error in
      if case .serverError(let status) = error {
        #expect(status == 503)
      } else {
        Issue.record("wrong error")
      }
    }
  }

  @Test func unexpectedStatusPassesThrough() async {
    await expectError(404) { error in
      if case .unexpectedStatus(let status) = error {
        #expect(status == 404)
      } else {
        Issue.record("wrong error")
      }
    }
  }

  @Test func timeoutMapsToTimedOut() async {
    await expectTransportError(URLError(.timedOut)) { error in
      if case .timedOut = error {} else { Issue.record("wrong error") }
    }
  }

  @Test func offlineMapsToOffline() async {
    await expectTransportError(URLError(.notConnectedToInternet)) { error in
      if case .offline = error {} else { Issue.record("wrong error") }
    }
  }

  @Test func cancellationMapsToCancelled() async {
    await expectTransportError(URLError(.cancelled)) { error in
      if case .cancelled = error {} else { Issue.record("wrong error") }
    }
  }

  private func expectError(
    _ statusCode: Int,
    verify: @escaping @Sendable (FeedClientError) -> Void
  ) async {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in (Self.response(statusCode), Data()) }
    do {
      _ = try await StubURLProtocol.makeClient().fetch(configuration: configuration)
      Issue.record("expected failure for \(statusCode)")
    } catch let error as FeedClientError {
      verify(error)
    } catch {
      Issue.record("wrong error type: \(error)")
    }
  }

  private func expectTransportError(
    _ underlying: URLError,
    verify: @escaping @Sendable (FeedClientError) -> Void
  ) async {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in throw underlying }
    do {
      _ = try await StubURLProtocol.makeClient().fetch(configuration: configuration)
      Issue.record("expected transport failure")
    } catch let error as FeedClientError {
      verify(error)
    } catch {
      Issue.record("wrong error type: \(error)")
    }
  }

  private static func response(_ statusCode: Int, headers: [String: String] = [:])
    -> HTTPURLResponse
  {
    HTTPURLResponse(
      url: URL(string: "https://www.reddit.com/r/shortstories/.rss")!,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: headers
    )!
  }
}
