import Foundation

public enum OPMLImportError: Error, Equatable, Sendable {
  case unreadable
  case invalidFormat
}

public struct OPMLImport {
  public static func looksLikeOPML(_ data: Data) -> Bool {
    guard let first = data.firstNonWhitespaceByte() else { return false }
    return first == UInt8(ascii: "<")
  }

  public static func parse(data: Data) throws -> [FeedTransferItem] {
    let collector = OutlineCollector()
    let parser = XMLParser(data: data)
    parser.delegate = collector
    guard parser.parse() else {
      throw OPMLImportError.unreadable
    }
    guard collector.rootElementName == "opml" else {
      throw OPMLImportError.invalidFormat
    }
    return collector.items
  }
}

private final class OutlineCollector: NSObject, XMLParserDelegate {
  private(set) var rootElementName: String?
  private(set) var items: [FeedTransferItem] = []

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    if rootElementName == nil {
      rootElementName = elementName
    }
    guard elementName == "outline" else { return }
    guard let xmlURL = attributeDict.first(where: { $0.key.lowercased() == "xmlurl" })?.value,
      !xmlURL.isEmpty
    else { return }
    let title = attributeDict["title"] ?? attributeDict["text"] ?? ""
    items.append(FeedTransferItem(url: xmlURL, title: title))
  }
}

extension Data {
  fileprivate func firstNonWhitespaceByte() -> UInt8? {
    var index = 0
    if count >= 3, self[0] == 0xEF, self[1] == 0xBB, self[2] == 0xBF {
      index = 3
    }
    while index < count {
      let byte = self[index]
      switch byte {
      case 0x09, 0x0A, 0x0D, 0x20:
        index += 1
      default:
        return byte
      }
    }
    return nil
  }
}
