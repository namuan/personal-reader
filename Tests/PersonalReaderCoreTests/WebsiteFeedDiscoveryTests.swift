import Foundation
import Testing

@testable import PersonalReaderCore

struct WebsiteFeedDiscoveryTests {
  @Test func extractsStandardLinksAnchorsAndConventionalPaths() {
    let html = """
      <html><head>
      <base href="https://example.com/news/">
      <link rel="alternate" type="application/rss+xml" href="feed.xml">
      <link rel="alternate" type="application/atom+xml" href="https://feeds.example.com/atom.xml">
      <link rel="alternate" type="text/html" href="/not-a-feed">
      </head><body>
      <a href="/updates/rss">Subscribe</a>
      <a href="javascript:alert(1)">RSS</a>
      </body></html>
      """

    let urls = FeedLinkExtractor.extract(
      from: Data(html.utf8),
      baseURL: URL(string: "https://example.com")!
    )

    #expect(urls.contains(URL(string: "https://example.com/news/feed.xml")!))
    #expect(urls.contains(URL(string: "https://feeds.example.com/atom.xml")!))
    #expect(urls.contains(URL(string: "https://example.com/updates/rss")!))
    #expect(!urls.contains(URL(string: "https://example.com/not-a-feed")!))
    #expect(urls.allSatisfy { $0.scheme == "https" })
  }

  @Test func deduplicatesAndRejectsInsecureURLs() {
    let html = """
      <link rel="alternate" type="application/rss+xml" href="/feed.xml">
      <link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml">
      <link rel="alternate" type="application/atom+xml" href="http://example.com/atom.xml">
      """

    let urls = FeedLinkExtractor.extract(
      from: Data(html.utf8),
      baseURL: URL(string: "https://example.com")!
    )

    #expect(urls.filter { $0 == URL(string: "https://example.com/feed.xml")! }.count == 1)
    #expect(!urls.contains(URL(string: "http://example.com/atom.xml")!))
  }

  @Test func previewsValidFeedsAndSkipsInvalidCandidates() async throws {
    let websiteURL = URL(string: "https://example.com")!
    let validURL = URL(string: "https://example.com/feed.xml")!
    let invalidURL = URL(string: "https://example.com/rss")!
    let html = """
      <link rel="alternate" type="application/rss+xml" href="/feed.xml">
      <link rel="alternate" type="application/rss+xml" href="/rss">
      """
    let validFeed = """
      <rss version="2.0"><channel><title>Example Feed</title>
      <item><title>First</title><guid>first</guid></item>
      <item><title>Second</title><guid>second</guid></item>
      <item><title>Third</title><guid>third</guid></item>
      <item><title>Fourth</title><guid>fourth</guid></item>
      </channel></rss>
      """
    let service = WebsiteFeedDiscoveryService(
      websiteClient: StubWebsiteClient(
        response: WebsiteFetchResponse(data: Data(html.utf8), finalURL: websiteURL)),
      feedClient: StubFeedClient(responses: [
        validURL: .success(
          SyndicationFetchResponse(
            statusCode: 200, data: Data(validFeed.utf8), etag: nil, lastModified: nil)),
        invalidURL: .success(
          SyndicationFetchResponse(
            statusCode: 200, data: Data("not xml".utf8), etag: nil, lastModified: nil)),
      ])
    )

    let feeds = try await service.discover(from: websiteURL)

    #expect(feeds.count == 1)
    #expect(feeds[0].url == validURL)
    #expect(feeds[0].title == "Example Feed")
    #expect(feeds[0].entryCount == 4)
    #expect(feeds[0].samples.map(\.title) == ["First", "Second", "Third"])
  }

  @Test func requiresHTTPSWebsiteURLs() async {
    let service = WebsiteFeedDiscoveryService(
      websiteClient: StubWebsiteClient(
        response: WebsiteFetchResponse(data: Data(), finalURL: URL(string: "https://example.com")!)),
      feedClient: StubFeedClient(responses: [:])
    )

    await #expect(throws: WebsiteFetchError.insecureScheme) {
      try await service.discover(from: URL(string: "http://example.com")!)
    }
  }
}

private struct StubWebsiteClient: WebsiteFetching {
  let response: WebsiteFetchResponse

  func fetch(url: URL) async throws -> WebsiteFetchResponse {
    guard url.scheme == "https" else { throw WebsiteFetchError.insecureScheme }
    return response
  }
}

private struct StubFeedClient: SyndicationFeedFetching {
  let responses: [URL: Result<SyndicationFetchResponse, SyndicationClientError>]

  func fetch(
    url: URL,
    etag: String?,
    lastModified: String?
  ) async throws -> SyndicationFetchResponse {
    guard let response = responses[url] else { throw SyndicationClientError.unexpectedStatus(404) }
    return try response.get()
  }
}
