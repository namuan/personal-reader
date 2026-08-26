import Foundation
import Testing

@testable import PersonalReaderCore

@Suite(.serialized)
struct SyndicationFeedClientTests {
  private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler:
      (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func reset() {
      handler = nil
      lastRequest = nil
    }

    static func makeClient() -> SyndicationFeedClient {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [StubURLProtocol.self]
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      return SyndicationFeedClient(session: URLSession(configuration: configuration))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

  private static let feedURL = URL(string: "https://example.com/feed.xml")!

  @Test func successReturnsDataAndCapturesETag() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in
      let response = HTTPURLResponse(
        url: Self.feedURL,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["ETag": "\"abc\"", "Last-Modified": "Wed, 02 Oct 2024 13:00:00 GMT"]
      )!
      return (response, Data("<rss/>".utf8))
    }

    let response = try await StubURLProtocol.makeClient().fetch(
      url: Self.feedURL,
      etag: nil,
      lastModified: nil
    )
    #expect(response.statusCode == 200)
    #expect(response.etag == "\"abc\"")
    #expect(response.lastModified == "Wed, 02 Oct 2024 13:00:00 GMT")
    let request = try #require(StubURLProtocol.lastRequest)
    #expect(request.value(forHTTPHeaderField: "Accept")?.contains("atom+xml") == true)
  }

  @Test func notModifiedReturns304AndPreservesETag() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in
      let response = HTTPURLResponse(
        url: Self.feedURL,
        statusCode: 304,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
      return (response, Data())
    }

    let response = try await StubURLProtocol.makeClient().fetch(
      url: Self.feedURL,
      etag: "\"old\"",
      lastModified: "old"
    )
    #expect(response.statusCode == 304)
    #expect(response.etag == "\"old\"")
    let request = try #require(StubURLProtocol.lastRequest)
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"old\"")
    #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "old")
  }

  @Test func insecureSchemeRejected() async {
    do {
      _ = try await SyndicationFeedClient().fetch(
        url: URL(string: "http://example.com/feed.xml")!,
        etag: nil,
        lastModified: nil
      )
      Issue.record("expected insecureScheme")
    } catch let error as SyndicationClientError {
      if case .insecureScheme = error {} else { Issue.record("wrong error") }
    } catch {
      Issue.record("wrong error type")
    }
  }

  @Test func rateLimitMapsToRateLimited() async {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in
      let response = HTTPURLResponse(
        url: Self.feedURL,
        statusCode: 429,
        httpVersion: "HTTP/1.1",
        headerFields: ["Retry-After": "60"]
      )!
      return (response, Data())
    }
    do {
      _ = try await StubURLProtocol.makeClient().fetch(
        url: Self.feedURL,
        etag: nil,
        lastModified: nil
      )
      Issue.record("expected rate limited")
    } catch let error as SyndicationClientError {
      if case .rateLimited(let retryAfter) = error {
        #expect(retryAfter == 60)
      } else {
        Issue.record("wrong error")
      }
    } catch {
      Issue.record("wrong error type")
    }
  }

  @Test func serverErrorMapsToServerError() async {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in
      let response = HTTPURLResponse(
        url: Self.feedURL,
        statusCode: 503,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
      return (response, Data())
    }
    do {
      _ = try await StubURLProtocol.makeClient().fetch(
        url: Self.feedURL,
        etag: nil,
        lastModified: nil
      )
      Issue.record("expected server error")
    } catch let error as SyndicationClientError {
      if case .serverError(let status) = error {
        #expect(status == 503)
      } else {
        Issue.record("wrong error")
      }
    } catch {
      Issue.record("wrong error type")
    }
  }

  @Test func offlineMapsToOffline() async {
    StubURLProtocol.reset()
    StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    do {
      _ = try await StubURLProtocol.makeClient().fetch(
        url: Self.feedURL,
        etag: nil,
        lastModified: nil
      )
      Issue.record("expected offline")
    } catch let error as SyndicationClientError {
      if case .offline = error {} else { Issue.record("wrong error") }
    } catch {
      Issue.record("wrong error type")
    }
  }
}
