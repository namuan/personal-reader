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
  private struct Item {
    var values: [String: String] = [:]

    mutating func append(_ text: String, to element: String) {
      values[element, default: ""].append(text)
    }
  }

  private let sanitizer: HTMLSanitizer
  private var currentElement: String?
  private var currentItem: Item?

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
    let element = qName ?? elementName
    if element == "item" {
      currentItem = Item()
    }
    currentElement = element
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    append(string)
  }

  func parser(_ parser: XMLParser, foundCDATA cdataBlock: Data) {
    guard let string = String(data: cdataBlock, encoding: .utf8) else {
      return
    }
    append(string)
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let element = qName ?? elementName
    if element == "item", let item = currentItem, let story = makeStory(from: item) {
      stories.append(story)
      currentItem = nil
    }
    currentElement = nil
  }

  private func append(_ string: String) {
    guard let currentElement, currentItem != nil else {
      return
    }
    currentItem?.append(string, to: currentElement)
  }

  private func makeStory(from item: Item) -> Story? {
    let title = normalized(item.values["title"])
    let link = normalized(item.values["link"])
    let guid = normalized(item.values["guid"])
    let rawContent = item.values["content:encoded"] ?? item.values["description"] ?? ""

    guard !title.isEmpty else {
      return nil
    }
    guard let id = redditID(guid: guid, link: link), !id.isEmpty else {
      return nil
    }

    let author = normalized(item.values["dc:creator"] ?? item.values["author"])
      .replacingOccurrences(of: "u/", with: "", options: [.anchored, .caseInsensitive])
    let category = normalized(item.values["category"])
    let subreddit = normalizedSubreddit(category: category, link: link)
    let publishedAt = parseDate(normalized(item.values["pubDate"]))

    return Story(
      id: id,
      title: title,
      contentBody: sanitizer.sanitize(rawContent),
      author: author,
      subreddit: subreddit,
      publishedAt: publishedAt
    )
  }

  private func redditID(guid: String, link: String) -> String? {
    if guid.hasPrefix("t3_") {
      return guid
    }

    for candidate in [guid, link] {
      let components = candidate.split(separator: "/").map(String.init)
      guard let commentsIndex = components.firstIndex(of: "comments") else {
        continue
      }
      let idIndex = components.index(after: commentsIndex)
      guard components.indices.contains(idIndex) else {
        continue
      }
      return "t3_\(components[idIndex])"
    }

    return guid.isEmpty ? nil : guid
  }

  private func normalizedSubreddit(category: String, link: String) -> String {
    if !category.isEmpty {
      return
        category
        .replacingOccurrences(of: "/r/", with: "", options: [.anchored, .caseInsensitive])
        .replacingOccurrences(of: "r/", with: "", options: [.anchored, .caseInsensitive])
    }

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

  private func parseDate(_ string: String) -> Int64 {
    let formats = [
      "EEE, dd MMM yyyy HH:mm:ss Z",
      "EEE, dd MMM yyyy HH:mm:ss zzz",
    ]

    for format in formats {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = format
      if let date = formatter.date(from: string) {
        return Int64(date.timeIntervalSince1970)
      }
    }
    return 0
  }

  private func normalized(_ value: String?) -> String {
    value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }
}
