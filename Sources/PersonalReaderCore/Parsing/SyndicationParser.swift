import Foundation

public struct SyndicationEntry: Sendable, Equatable {
  public let id: String
  public let title: String
  public let summary: String
  public let content: String
  public let author: String
  public let link: String
  public let publishedAt: Int64
  public let categories: [String]
}

public struct SyndicationFeed: Sendable, Equatable {
  public let title: String
  public let siteLink: String
  public let entries: [SyndicationEntry]
}

public struct SyndicationParser: Sendable {
  private let sanitizer: HTMLSanitizer

  public init(sanitizer: HTMLSanitizer = HTMLSanitizer()) {
    self.sanitizer = sanitizer
  }

  public func parse(_ data: Data, fallbackFetchedAt: Date = Date()) throws -> SyndicationFeed {
    let delegate = SyndicationParserDelegate(
      sanitizer: sanitizer,
      fallbackFetchedAt: fallbackFetchedAt
    )
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = false
    parser.shouldReportNamespacePrefixes = true
    guard parser.parse() else {
      throw RSSParserError.invalidXML(parser.parserError?.localizedDescription)
    }
    return delegate.feed
  }
}

private final class SyndicationParserDelegate: NSObject, XMLParserDelegate {
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
  private let fallbackTimestamp: Int64

  private var feedTitleBuffer = ""
  private var feedLinkBuffer = ""

  private var insideChannel = false
  private var insideFeedRoot = false

  private var insideItem = false
  private var currentElementName: String?
  private var currentValueBuffer = ""
  private var itemLinkHref: String?
  private var itemAlternateLinkHref: String?
  private var itemCategoryTerms: [String] = []
  private var itemCategoryTexts: [String] = []
  private var itemFields: [String: String] = [:]

  private var entries: [SyndicationEntry] = []

  init(sanitizer: HTMLSanitizer, fallbackFetchedAt: Date) {
    self.sanitizer = sanitizer
    self.fallbackTimestamp = Int64(fallbackFetchedAt.timeIntervalSince1970)
  }

  var feed: SyndicationFeed {
    SyndicationFeed(title: feedTitleBuffer, siteLink: feedLinkBuffer, entries: entries)
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    let element = Self.localName(qName ?? elementName)

    if element == "item" || element == "entry" {
      insideItem = true
      currentElementName = nil
      currentValueBuffer = ""
      itemLinkHref = nil
      itemAlternateLinkHref = nil
      itemCategoryTerms = []
      itemCategoryTexts = []
      itemFields = [:]
      return
    }

    if insideItem {
      switch element {
      case "category":
        if let term = attributeDict["term"], !term.isEmpty {
          itemCategoryTerms.append(term)
        }
      case "link":
        if let href = attributeDict["href"] {
          if attributeDict["rel"] == "alternate" {
            if itemAlternateLinkHref == nil {
              itemAlternateLinkHref = href
            }
          } else if itemLinkHref == nil {
            itemLinkHref = href
          }
        }
      default:
        break
      }
      currentElementName = element
      currentValueBuffer = ""
      return
    }

    switch element {
    case "channel":
      insideChannel = true
      currentElementName = nil
      currentValueBuffer = ""
    case "feed":
      insideFeedRoot = true
      currentElementName = nil
      currentValueBuffer = ""
    case _ where insideChannel || insideFeedRoot:
      switch element {
      case "title":
        currentElementName = "title"
        currentValueBuffer = ""
      case "link":
        if let href = attributeDict["href"] {
          if feedLinkBuffer.isEmpty {
            feedLinkBuffer = href
          }
          currentElementName = nil
        } else {
          currentElementName = "link"
          currentValueBuffer = ""
        }
      default:
        currentElementName = nil
        currentValueBuffer = ""
      }
    default:
      currentElementName = nil
      currentValueBuffer = ""
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard currentElementName != nil else { return }
    currentValueBuffer += string
  }

  func parser(_ parser: XMLParser, foundCDATA cdataBlock: Data) {
    guard currentElementName != nil,
      let string = String(data: cdataBlock, encoding: .utf8)
    else { return }
    currentValueBuffer += string
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let element = Self.localName(qName ?? elementName)
    let value = currentValueBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

    if insideItem {
      if element == "item" || element == "entry" {
        insideItem = false
        if let entry = makeEntry() {
          entries.append(entry)
        }
        itemLinkHref = nil
        itemAlternateLinkHref = nil
        itemCategoryTerms = []
        itemCategoryTexts = []
        itemFields = [:]
        currentElementName = nil
        currentValueBuffer = ""
        return
      }

      if let openName = currentElementName, openName == element {
        if itemFields[element] == nil {
          itemFields[element] = value
        }
        if element == "category", !value.isEmpty, !itemCategoryTexts.contains(value) {
          itemCategoryTexts.append(value)
        }
        currentElementName = nil
        currentValueBuffer = ""
      }
      return
    }

    if insideChannel || insideFeedRoot {
      if element == "channel" {
        insideChannel = false
      } else if element == "feed" {
        insideFeedRoot = false
      }
      if let openName = currentElementName, openName == element {
        if element == "title", feedTitleBuffer.isEmpty, !value.isEmpty {
          feedTitleBuffer = value
        } else if element == "link", feedLinkBuffer.isEmpty, !value.isEmpty {
          feedLinkBuffer = value
        }
        currentElementName = nil
        currentValueBuffer = ""
      }
    }
  }

  private func makeEntry() -> SyndicationEntry? {
    let title = itemFields["title"] ?? ""
    guard !title.isEmpty else { return nil }
    let author = normalizedAuthor(
      firstNonEmpty(
        itemFields["creator"],
        itemFields["name"],
        itemFields["author"]
      ))
    let content =
      firstNonEmpty(
        itemFields["encoded"],
        itemFields["content"],
        itemFields["summary"],
        itemFields["description"]
      ) ?? ""
    let publishedAt = parseDate(
      firstNonEmpty(
        itemFields["pubdate"],
        itemFields["published"],
        itemFields["updated"],
        itemFields["date"]
      ))
    let link = firstNonEmpty(itemAlternateLinkHref, itemLinkHref, itemFields["link"])
    let idCandidate = firstNonEmpty(itemFields["guid"], itemFields["id"], link) ?? UUID().uuidString
    let categories = uniqueCategories()
    return SyndicationEntry(
      id: idCandidate,
      title: title,
      summary: "",
      content: sanitizer.sanitize(content),
      author: author,
      link: link ?? "",
      publishedAt: publishedAt == 0 ? fallbackTimestamp : publishedAt,
      categories: categories
    )
  }

  private func uniqueCategories() -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for value in itemCategoryTerms + itemCategoryTexts {
      if seen.insert(value).inserted {
        ordered.append(value)
      }
    }
    return ordered
  }

  private func firstNonEmpty(_ candidates: String?...) -> String? {
    for candidate in candidates {
      if let candidate, !candidate.isEmpty {
        return candidate
      }
    }
    return nil
  }

  private func normalizedAuthor(_ value: String?) -> String {
    guard var author = value, !author.isEmpty else { return "" }
    for prefix in ["/u/", "u/", "/user/", "user/", "mailto:"] {
      if author.lowercased().hasPrefix(prefix) {
        author = String(author.dropFirst(prefix.count))
        break
      }
    }
    if let paren = author.firstIndex(of: "(") {
      author = String(author[..<paren])
    }
    return author.trimmingCharacters(in: .whitespacesAndNewlines)
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

  private static func localName(_ name: String) -> String {
    guard let colon = name.firstIndex(of: ":") else {
      return name.lowercased()
    }
    return String(name[name.index(after: colon)...]).lowercased()
  }
}
