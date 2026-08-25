import Foundation

public struct HTMLSanitizer: Sendable {
  public init() {}

  public func sanitize(_ html: String) -> String {
    let elementPattern = #"(?is)<(script|style|iframe)\b[^>]*>.*?</\1\s*>"#
    let eventAttributePattern = #"(?i)\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#
    let javascriptURLPattern = #"(?i)(href|src)\s*=\s*(["'])\s*javascript:[^"']*\2"#

    return
      html
      .replacingOccurrences(of: elementPattern, with: "", options: .regularExpression)
      .replacingOccurrences(of: eventAttributePattern, with: "", options: .regularExpression)
      .replacingOccurrences(
        of: javascriptURLPattern,
        with: "$1=\"\"",
        options: .regularExpression
      )
  }
}
