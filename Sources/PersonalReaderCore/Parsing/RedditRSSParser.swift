import Foundation

public protocol StoryParsing: Sendable {
  func parse(_ data: Data) throws -> [Story]
}

public struct RedditRSSParser: StoryParsing, Sendable {
  private let sanitizer: HTMLSanitizer

  public init(sanitizer: HTMLSanitizer = HTMLSanitizer()) {
    self.sanitizer = sanitizer
  }

  public func parse(_ data: Data) throws -> [Story] {
    let delegate = RSSParserDelegate(sanitizer: sanitizer)
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = false
    parser.shouldReportNamespacePrefixes = true

    guard parser.parse() else {
      throw RSSParserError.invalidXML(parser.parserError?.localizedDescription)
    }
    return delegate.stories
  }
}

public enum RSSParserError: Error, Equatable {
  case invalidXML(String?)
}

private final class RSSParserDelegate: NSObject, XMLParserDelegate {
  private static let rfc822Formatters: [DateFormatter] = [
    makeFormatter("EEE, dd MMM yyyy HH:mm:ss Z"),
    makeFormatter("EEE, dd MMM yyyy HH:mm:ss zzz"),
    makeFormatter("EEE, dd MMM yyyy HH:mm Z"),
  ]
  private static nonisolated(unsafe) let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  private static nonisolated(unsafe) let iso8601NoFractionFormatter = ISO8601DateFormatter()

  private static func makeFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter
  }

  private let sanitizer: HTMLSanitizer
  private var currentItemValues: [String: String] = [:]
  private var currentElementName: String?
  private var currentValueBuffer = ""
  private var insideItem = false
  private var categoryTerm: String?
  private var linkHref: String?
  private var alternateLinkHref: String?

  private(set) var stories: [Story] = []

  init(sanitizer: HTMLSanitizer) {
    self.sanitizer = sanitizer
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    let element = Self.localName(qName ?? elementName)
    switch element {
    case "item", "entry":
      insideItem = true
      currentItemValues = [:]
      currentElementName = nil
      currentValueBuffer = ""
      categoryTerm = nil
      linkHref = nil
      alternateLinkHref = nil
    case _ where insideItem:
      switch element {
      case "category":
        if let term = attributeDict["term"], categoryTerm == nil {
          categoryTerm = term
        }
      case "link":
        if let href = attributeDict["href"] {
          if attributeDict["rel"] == "alternate" {
            if alternateLinkHref == nil {
              alternateLinkHref = href
            }
          } else if linkHref == nil {
            linkHref = href
          }
        }
      default:
        break
      }
      currentElementName = element
      currentValueBuffer = ""
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard insideItem, currentElementName != nil else { return }
    currentValueBuffer += string
  }

  func parser(_ parser: XMLParser, foundCDATA cdataBlock: Data) {
    guard insideItem, currentElementName != nil,
      let string = String(data: cdataBlock, encoding: .utf8)
    else {
      return
    }
    currentValueBuffer += string
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let element = Self.localName(qName ?? elementName)

    if insideItem, let openElement = currentElementName, openElement == element {
      if currentItemValues[element] == nil {
        currentItemValues[element] = currentValueBuffer.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
      }
      currentElementName = nil
      currentValueBuffer = ""
      return
    }

    if element == "item" || element == "entry", insideItem {
      insideItem = false
      currentElementName = nil
      if let story = makeStory(from: currentItemValues) {
        stories.append(story)
      }
      currentItemValues = [:]
      categoryTerm = nil
      linkHref = nil
      alternateLinkHref = nil
    }
  }

  private static func localName(_ name: String) -> String {
    guard let colon = name.firstIndex(of: ":") else {
      return name.lowercased()
    }
    return String(name[name.index(after: colon)...]).lowercased()
  }

  private func makeStory(from values: [String: String]) -> Story? {
    let title = values["title"] ?? ""
    guard !title.isEmpty else { return nil }

    let link = firstNonEmpty(alternateLinkHref, linkHref, values["link"])
    let guid = firstNonEmpty(values["guid"], values["id"])
    guard let id = redditID(guid: guid, link: link) else { return nil }

    let author = normalizedAuthor(
      firstNonEmpty(values["creator"], values["name"], values["author"])
    )
    let category = firstNonEmpty(categoryTerm, values["category"])
    let subreddit = normalizedSubreddit(category: category, link: link)
    let publishedAt = parseDate(
      firstNonEmpty(values["pubdate"], values["date"], values["published"], values["updated"])
    )
    let rawContent =
      firstNonEmpty(
        values["encoded"], values["content"], values["summary"], values["description"]
      ) ?? ""

    return Story(
      id: id,
      title: title,
      contentBody: sanitizer.sanitize(rawContent),
      author: author,
      subreddit: subreddit,
      publishedAt: publishedAt,
      link: link ?? "",
      sourceId: FeedSourceRecord.builtInRedditID()
    )
  }

  private func firstNonEmpty(_ candidates: String?...) -> String? {
    for candidate in candidates {
      if let candidate, !candidate.isEmpty {
        return candidate
      }
    }
    return nil
  }

  private func redditID(guid: String?, link: String?) -> String? {
    if let guid, isStableRedditID(guid) {
      return guid
    }
    for candidate in [guid, link] {
      guard let candidate, !candidate.isEmpty else { continue }
      if let id = idFromRedditPath(candidate) {
        return id
      }
    }
    if let guid, !guid.isEmpty {
      return guid
    }
    return nil
  }

  private func isStableRedditID(_ candidate: String) -> Bool {
    candidate.range(of: "^t[1-6]_[A-Za-z0-9]+$", options: .regularExpression) != nil
  }

  private func idFromRedditPath(_ candidate: String) -> String? {
    let components = candidate.split(separator: "/").map(String.init)
    guard let commentsIndex = components.firstIndex(of: "comments") else {
      return nil
    }
    let idIndex = components.index(after: commentsIndex)
    guard components.indices.contains(idIndex), !components[idIndex].isEmpty else {
      return nil
    }
    return "t3_\(components[idIndex])"
  }

  private func normalizedAuthor(_ value: String?) -> String {
    guard var author = value, !author.isEmpty else { return "" }
    for prefix in ["/u/", "u/", "/user/", "user/"] {
      if author.lowercased().hasPrefix(prefix) {
        author = String(author.dropFirst(prefix.count))
        break
      }
    }
    return author.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func normalizedSubreddit(category: String?, link: String?) -> String {
    if let category, !category.isEmpty {
      var name = category
      for prefix in ["/r/", "r/"] {
        if name.lowercased().hasPrefix(prefix) {
          name = String(name.dropFirst(prefix.count))
          break
        }
      }
      if let slash = name.firstIndex(of: "/") {
        name = String(name[..<slash])
      }
      return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard let link else { return "" }
    let components = link.split(separator: "/").map(String.init)
    guard let subredditIndex = components.firstIndex(of: "r") else {
      return ""
    }
    let nameIndex = components.index(after: subredditIndex)
    guard components.indices.contains(nameIndex) else {
      return ""
    }
    return components[nameIndex]
  }

  private func parseDate(_ string: String?) -> Int64 {
    guard let string, !string.isEmpty else { return 0 }
    for formatter in Self.rfc822Formatters {
      if let date = formatter.date(from: string) {
        return Int64(date.timeIntervalSince1970)
      }
    }
    if let date = Self.iso8601Formatter.date(from: string) {
      return Int64(date.timeIntervalSince1970)
    }
    if let date = Self.iso8601NoFractionFormatter.date(from: string) {
      return Int64(date.timeIntervalSince1970)
    }
    return 0
  }
}
