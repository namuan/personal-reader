import Foundation

public struct HTMLSanitizer: Sendable {
  private static let voidElements: Set<String> = ["br", "hr", "img"]
  private static let suppressedWithContent: Set<String> = [
    "script", "style", "iframe", "object", "embed", "template",
    "noscript", "svg", "math", "applet", "frame", "frameset",
  ]
  private static let allowedElements: Set<String> = [
    "a", "abbr", "b", "blockquote", "br", "caption", "cite", "code",
    "dd", "del", "details", "div", "dl", "dt", "em", "figcaption", "figure",
    "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "img", "ins", "kbd",
    "li", "mark", "ol", "p", "pre", "q", "s", "samp", "small", "span",
    "strike", "strong", "sub", "summary", "sup", "table", "tbody", "td",
    "tfoot", "th", "thead", "tr", "u", "ul",
  ]
  private static let allowedAttributes: [String: Set<String>] = [
    "a": ["href", "title"],
    "abbr": ["title"],
    "img": ["src", "alt"],
    "td": ["colspan", "rowspan"],
    "th": ["colspan", "rowspan"],
    "q": ["cite"],
  ]
  private static let allowedURLSchemes: Set<String> = ["http", "https", "mailto"]

  public init() {}

  public func sanitize(_ html: String) -> String {
    var output = ""
    var openElements: [String] = []
    let scalars = Array(html.unicodeScalars)
    var index = 0

    while index < scalars.count {
      guard scalars[index] == "<" else {
        let start = index
        while index < scalars.count, scalars[index] != "<" {
          index += 1
        }
        appendEscapedText(scalars, start: start, end: index, into: &output)
        continue
      }

      if index + 1 >= scalars.count {
        output.append("&lt;")
        break
      }

      let next = scalars[index + 1]
      if next == "!" {
        index = skipCommentOrDeclaration(scalars, at: index)
      } else if next == "/" {
        index = handleCloseTag(scalars, at: index, output: &output, openElements: &openElements)
      } else if next.properties.isAlphabetic {
        index = handleOpenTag(scalars, at: index, output: &output, openElements: &openElements)
      } else {
        output.append("&lt;")
        index += 1
      }
    }

    for element in openElements.reversed() {
      output.append("</\(element)>")
    }
    return output
  }

  private func skipCommentOrDeclaration(_ scalars: [Unicode.Scalar], at index: Int) -> Int {
    if index + 3 < scalars.count,
      scalars[index + 2] == "-" && scalars[index + 3] == "-"
    {
      var cursor = index + 4
      while cursor + 2 < scalars.count {
        if scalars[cursor] == "-" && scalars[cursor + 1] == "-" && scalars[cursor + 2] == ">" {
          return cursor + 3
        }
        cursor += 1
      }
      return scalars.count
    }
    var cursor = index + 2
    while cursor < scalars.count {
      if scalars[cursor] == ">" {
        return cursor + 1
      }
      cursor += 1
    }
    return scalars.count
  }

  private func handleCloseTag(
    _ scalars: [Unicode.Scalar],
    at index: Int,
    output: inout String,
    openElements: inout [String]
  ) -> Int {
    var cursor = index + 2
    var name = ""
    while cursor < scalars.count, isOpenNameScalar(scalars[cursor]) {
      name.unicodeScalars.append(scalars[cursor])
      cursor += 1
    }
    while cursor < scalars.count, scalars[cursor] != ">" {
      cursor += 1
    }
    let endIndex = cursor < scalars.count ? cursor + 1 : scalars.count

    let element = name.lowercased()
    if Self.allowedElements.contains(element),
      let position = openElements.lastIndex(of: element)
    {
      while openElements.count > position {
        output.append("</\(openElements.removeLast())>")
      }
    }
    return endIndex
  }

  private func handleOpenTag(
    _ scalars: [Unicode.Scalar],
    at index: Int,
    output: inout String,
    openElements: inout [String]
  ) -> Int {
    guard let parsed = parseTag(scalars, from: index) else {
      output.append("&lt;")
      return index + 1
    }

    let element = parsed.name.lowercased()
    if Self.suppressedWithContent.contains(element) {
      return suppressThroughCloseTag(element, scalars, from: parsed.end)
    }
    guard Self.allowedElements.contains(element) else {
      return parsed.end
    }

    output.append("<\(element)\(filteredAttributes(parsed.attributes, for: element))>")
    if !Self.voidElements.contains(element), !parsed.isSelfClosing {
      openElements.append(element)
    }
    return parsed.end
  }

  private func suppressThroughCloseTag(
    _ element: String,
    _ scalars: [Unicode.Scalar],
    from index: Int
  ) -> Int {
    var cursor = index
    while cursor < scalars.count {
      guard scalars[cursor] == "<" else {
        cursor += 1
        continue
      }
      guard cursor + 1 < scalars.count, scalars[cursor + 1] == "/" else {
        cursor += 1
        continue
      }
      var probe = cursor + 2
      var name = ""
      while probe < scalars.count, isOpenNameScalar(scalars[probe]) {
        name.unicodeScalars.append(scalars[probe])
        probe += 1
      }
      if name.lowercased() == element {
        while probe < scalars.count, scalars[probe] != ">" {
          probe += 1
        }
        return probe < scalars.count ? probe + 1 : scalars.count
      }
      cursor += 1
    }
    return scalars.count
  }

  private func parseTag(
    _ scalars: [Unicode.Scalar],
    from index: Int
  ) -> (name: String, attributes: [(String, String?)], end: Int, isSelfClosing: Bool)? {
    var cursor = index + 1
    var name = ""
    while cursor < scalars.count, isOpenNameScalar(scalars[cursor]) {
      name.unicodeScalars.append(scalars[cursor])
      cursor += 1
    }
    guard !name.isEmpty else { return nil }

    var attributes: [(String, String?)] = []
    var isSelfClosing = false

    while cursor < scalars.count {
      while cursor < scalars.count, isWhitespace(scalars[cursor]) {
        cursor += 1
      }
      guard cursor < scalars.count else { break }
      if scalars[cursor] == ">" {
        return (name, attributes, cursor + 1, isSelfClosing)
      }
      if scalars[cursor] == "/" {
        isSelfClosing = true
        cursor += 1
        continue
      }

      var attributeName = ""
      while cursor < scalars.count,
        scalars[cursor] != "=" && scalars[cursor] != ">" && scalars[cursor] != "/",
        !isWhitespace(scalars[cursor])
      {
        attributeName.unicodeScalars.append(scalars[cursor])
        cursor += 1
      }
      attributeName = attributeName.lowercased()
      guard !attributeName.isEmpty else {
        cursor += 1
        continue
      }

      var attributeValue: String?
      while cursor < scalars.count, isWhitespace(scalars[cursor]) {
        cursor += 1
      }
      if cursor < scalars.count, scalars[cursor] == "=" {
        cursor += 1
        while cursor < scalars.count, isWhitespace(scalars[cursor]) {
          cursor += 1
        }
        if cursor < scalars.count {
          let quote = scalars[cursor]
          if quote == "\"" || quote == "'" {
            cursor += 1
            var value = ""
            while cursor < scalars.count, scalars[cursor] != quote {
              value.unicodeScalars.append(scalars[cursor])
              cursor += 1
            }
            if cursor < scalars.count { cursor += 1 }
            attributeValue = value
          } else {
            var value = ""
            while cursor < scalars.count, scalars[cursor] != ">", !isWhitespace(scalars[cursor]) {
              value.unicodeScalars.append(scalars[cursor])
              cursor += 1
            }
            attributeValue = value
          }
        }
      }
      attributes.append((attributeName, attributeValue))
    }
    return (name, attributes, scalars.count, isSelfClosing)
  }

  private func filteredAttributes(
    _ attributes: [(String, String?)],
    for element: String
  ) -> String {
    let allowedNames = Self.allowedAttributes[element] ?? []
    var result = ""
    for (name, value) in attributes {
      guard allowedNames.contains(name), let value else { continue }
      if name == "href" || name == "src" || name == "cite" {
        guard let url = normalizedURL(value) else { continue }
        result += " \(name)=\"\(escapeQuotedValue(url))\""
      } else {
        result += " \(name)=\"\(escapeQuotedValue(value))\""
      }
    }
    return result
  }

  private func normalizedURL(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let separator = trimmed.firstIndex(of: ":") else { return nil }
    let scheme = String(trimmed[..<separator]).lowercased()
    return Self.allowedURLSchemes.contains(scheme) ? trimmed : nil
  }

  private func appendEscapedText(
    _ scalars: [Unicode.Scalar],
    start: Int,
    end: Int,
    into output: inout String
  ) {
    var index = start
    while index < end {
      let scalar = scalars[index]
      switch scalar {
      case "&":
        var probe = index + 1
        var candidate = ""
        while probe < end, candidate.count <= 12,
          scalars[probe].properties.isAlphabetic || scalars[probe].properties.numericType != nil
            || scalars[probe] == "#"
        {
          candidate.unicodeScalars.append(scalars[probe])
          probe += 1
        }
        if !candidate.isEmpty, probe < end, scalars[probe] == ";" {
          output.unicodeScalars.append(scalar)
          output += candidate
          output.append(";")
          index = probe + 1
        } else {
          output.append("&amp;")
          index += 1
        }
      case "<":
        output.append("&lt;")
        index += 1
      case ">":
        output.append("&gt;")
        index += 1
      default:
        output.unicodeScalars.append(scalar)
        index += 1
      }
    }
  }

  private func escapeQuotedValue(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
  }

  private func isOpenNameScalar(_ scalar: Unicode.Scalar) -> Bool {
    (scalar.value >= 97 && scalar.value <= 122)
      || (scalar.value >= 65 && scalar.value <= 90)
      || (scalar.value >= 48 && scalar.value <= 57)
      || scalar.value == 45 || scalar.value == 58
  }

  private func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value == 32 || scalar.value == 9 || scalar.value == 10 || scalar.value == 13
  }
}
