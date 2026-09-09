import Foundation

public struct WebsiteFetchResponse: Sendable, Equatable {
  public let data: Data
  public let finalURL: URL

  public init(data: Data, finalURL: URL) {
    self.data = data
    self.finalURL = finalURL
  }
}

public protocol WebsiteFetching: Sendable {
  func fetch(url: URL) async throws -> WebsiteFetchResponse
}

public struct WebsiteClient: WebsiteFetching, Sendable {
  private let session: URLSession
  private let responseSizeLimit: Int

  public init(session: URLSession = .shared, responseSizeLimit: Int = 2_000_000) {
    self.session = session
    self.responseSizeLimit = responseSizeLimit
  }

  public func fetch(url: URL) async throws -> WebsiteFetchResponse {
    guard url.scheme?.lowercased() == "https" else {
      throw WebsiteFetchError.insecureScheme
    }
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 30
    request.setValue("text/html, application/xhtml+xml;q=0.9", forHTTPHeaderField: "Accept")
    request.setValue(SyndicationFeedClient.userAgent, forHTTPHeaderField: "User-Agent")

    do {
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw WebsiteFetchError.invalidResponse
      }
      guard (200...299).contains(httpResponse.statusCode) else {
        throw WebsiteFetchError.unexpectedStatus(httpResponse.statusCode)
      }
      guard data.count <= responseSizeLimit else {
        throw WebsiteFetchError.responseTooLarge
      }
      let finalURL = httpResponse.url ?? url
      guard finalURL.scheme?.lowercased() == "https" else {
        throw WebsiteFetchError.insecureRedirect
      }
      return WebsiteFetchResponse(data: data, finalURL: finalURL)
    } catch let error as WebsiteFetchError {
      throw error
    } catch is CancellationError {
      throw WebsiteFetchError.cancelled
    } catch let urlError as URLError {
      switch urlError.code {
      case .timedOut, .cannotFindHost:
        throw WebsiteFetchError.timedOut
      case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost,
        .cannotConnectToHost, .dnsLookupFailed:
        throw WebsiteFetchError.offline
      case .cancelled:
        throw WebsiteFetchError.cancelled
      default:
        throw WebsiteFetchError.transportFailure(code: urlError.errorCode)
      }
    }
  }
}

public enum WebsiteFetchError: Error, Equatable, Sendable {
  case insecureScheme
  case insecureRedirect
  case invalidResponse
  case responseTooLarge
  case unexpectedStatus(Int)
  case offline
  case timedOut
  case transportFailure(code: Int)
  case cancelled
}

public struct FeedDiscoverySample: Sendable, Equatable, Identifiable {
  public let title: String
  public let link: String

  public var id: String { link.isEmpty ? title : link }

  public init(title: String, link: String) {
    self.title = title
    self.link = link
  }
}

public struct DiscoveredFeed: Sendable, Equatable, Identifiable {
  public let url: URL
  public let title: String
  public let entryCount: Int
  public let samples: [FeedDiscoverySample]

  public var id: URL { url }

  public init(url: URL, title: String, entryCount: Int, samples: [FeedDiscoverySample]) {
    self.url = url
    self.title = title
    self.entryCount = entryCount
    self.samples = samples
  }
}

public struct WebsiteFeedDiscoveryService: Sendable {
  private let websiteClient: any WebsiteFetching
  private let feedClient: any SyndicationFeedFetching
  private let parser: SyndicationParser
  private let maximumCandidates: Int

  public init(
    websiteClient: any WebsiteFetching,
    feedClient: any SyndicationFeedFetching,
    parser: SyndicationParser = SyndicationParser(),
    maximumCandidates: Int = 20
  ) {
    self.websiteClient = websiteClient
    self.feedClient = feedClient
    self.parser = parser
    self.maximumCandidates = maximumCandidates
  }

  public func discover(from websiteURL: URL) async throws -> [DiscoveredFeed] {
    guard websiteURL.scheme?.lowercased() == "https" else {
      throw WebsiteFetchError.insecureScheme
    }
    let response = try await websiteClient.fetch(url: websiteURL)
    let candidates = FeedLinkExtractor.extract(from: response.data, baseURL: response.finalURL)
    let limitedCandidates = Array(candidates.prefix(maximumCandidates))
    return await withTaskGroup(of: DiscoveredFeed?.self, returning: [DiscoveredFeed].self) {
      group in
      for candidate in limitedCandidates {
        group.addTask {
          await preview(url: candidate)
        }
      }
      var results: [DiscoveredFeed] = []
      for await candidate in group {
        if let candidate {
          results.append(candidate)
        }
      }
      let positions = Dictionary(
        uniqueKeysWithValues: limitedCandidates.enumerated().map { ($1, $0) })
      return results.sorted { positions[$0.url, default: .max] < positions[$1.url, default: .max] }
    }
  }

  private func preview(url: URL) async -> DiscoveredFeed? {
    do {
      let response = try await feedClient.fetch(url: url, etag: nil, lastModified: nil)
      guard !response.isNotModified else { return nil }
      let feed = try parser.parse(response.data)
      let title = feed.title.trimmingCharacters(in: .whitespacesAndNewlines)
      return DiscoveredFeed(
        url: url,
        title: title.isEmpty ? url.host ?? "Feed" : title,
        entryCount: feed.entries.count,
        samples: feed.entries.prefix(3).map { FeedDiscoverySample(title: $0.title, link: $0.link) }
      )
    } catch {
      return nil
    }
  }
}

public enum FeedLinkExtractor {
  public static func extract(from data: Data, baseURL: URL) -> [URL] {
    guard let html = String(data: data, encoding: .utf8) else { return [] }
    let documentBaseURL = documentBaseURL(in: html, fallback: baseURL)
    var urls: [URL] = []
    var seen = Set<URL>()

    for attributes in tags(named: "link", in: html) {
      guard isSyndicationLink(attributes), let href = attributes["href"],
        let url = secureURL(href, relativeTo: documentBaseURL)
      else { continue }
      append(url, to: &urls, seen: &seen)
    }

    for (attributes, text) in anchors(in: html) {
      guard let href = attributes["href"], isLikelyFeedLink(href: href, text: text),
        let url = secureURL(href, relativeTo: documentBaseURL)
      else { continue }
      append(url, to: &urls, seen: &seen)
    }

    for path in ["/feed", "/rss", "/atom.xml", "/feed.xml", "/rss.xml", "/feed/", "/rss/"] {
      guard let url = URL(string: path, relativeTo: documentBaseURL)?.absoluteURL else { continue }
      append(url, to: &urls, seen: &seen)
    }
    return urls
  }

  private static func documentBaseURL(in html: String, fallback: URL) -> URL {
    guard let attributes = tags(named: "base", in: html).first,
      let href = attributes["href"], let url = secureURL(href, relativeTo: fallback)
    else { return fallback }
    return url
  }

  private static func isSyndicationLink(_ attributes: [String: String]) -> Bool {
    let relation = attributes["rel", default: ""].lowercased()
    let type = attributes["type", default: ""].lowercased()
    let hasAlternate = relation.split(separator: " ").contains("alternate")
    let isSyndicationType = [
      "application/rss+xml", "application/atom+xml", "application/xml", "text/xml",
    ]
    .contains(type)
    return hasAlternate && isSyndicationType
  }

  private static func isLikelyFeedLink(href: String, text: String) -> Bool {
    let value = "\(href) \(text)".lowercased()
    return ["rss", "atom", "feed", "subscribe"].contains { value.contains($0) }
  }

  private static func secureURL(_ string: String, relativeTo baseURL: URL) -> URL? {
    guard let url = URL(string: string, relativeTo: baseURL)?.absoluteURL,
      url.scheme?.lowercased() == "https"
    else { return nil }
    return url
  }

  private static func append(_ url: URL, to urls: inout [URL], seen: inout Set<URL>) {
    guard seen.insert(url).inserted else { return }
    urls.append(url)
  }

  private static func tags(named name: String, in html: String) -> [[String: String]] {
    matches("<\\s*\(name)\\b([^>]*)>", in: html).compactMap { match in
      guard match.count == 2 else { return nil }
      return attributes(match[1])
    }
  }

  private static func anchors(in html: String) -> [([String: String], String)] {
    matches(
      "<\\s*a\\b([^>]*)>(.*?)</\\s*a\\s*>", in: html,
      options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    .compactMap { match in
      guard match.count == 3 else { return nil }
      return (
        attributes(match[1]),
        match[2].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      )
    }
  }

  private static func attributes(_ input: String) -> [String: String] {
    var values: [String: String] = [:]
    for match in matches(
      "([^\\s=/>]+)\\s*=\\s*(?:\\\"([^\\\"]*)\\\"|'([^']*)'|([^\\s>]+))", in: input)
    {
      guard match.count == 5 else { continue }
      let key = match[1].lowercased()
      values[key] = [match[2], match[3], match[4]].first(where: { !$0.isEmpty }) ?? ""
    }
    return values
  }

  private static func matches(
    _ pattern: String,
    in input: String,
    options: NSRegularExpression.Options = [.caseInsensitive]
  ) -> [[String]] {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
      return []
    }
    let range = NSRange(input.startIndex..., in: input)
    return expression.matches(in: input, range: range).map { result in
      (0..<result.numberOfRanges).map { index in
        guard let range = Range(result.range(at: index), in: input) else { return "" }
        return String(input[range])
      }
    }
  }
}
