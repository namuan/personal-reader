import XCTest

@testable import PersonalReaderCore

final class HTMLSanitizerTests: XCTestCase {
  private let sanitizer = HTMLSanitizer()

  func testRemovesScriptWithContent() {
    XCTAssertEqual(
      sanitizer.sanitize("<p>safe</p><script>alert('x')</script><p>after</p>"),
      "<p>safe</p><p>after</p>"
    )
  }

  func testRemovesUnclosedScriptToTheEnd() {
    XCTAssertEqual(sanitizer.sanitize("<p>safe</p><script>alert('x')"), "<p>safe</p>")
  }

  func testRemovesStyleIframeObjectEmbed() {
    XCTAssertEqual(
      sanitizer.sanitize("<style>*{}</style><iframe src=\"x\"></iframe><object></object><embed>"),
      ""
    )
  }

  func testRemovesSVGAndMathWithContent() {
    XCTAssertEqual(
      sanitizer.sanitize("<svg><circle/></svg><math></math><b>ok</b>"),
      "<b>ok</b>"
    )
  }

  func testStripsEventAttributes() {
    XCTAssertEqual(
      sanitizer.sanitize("<img src=\"https://x/i.png\" onerror=\"alert(1)\">"),
      "<img src=\"https://x/i.png\">"
    )
    XCTAssertEqual(
      sanitizer.sanitize("<p onclick=\"x()\" onMouseOver=\"y()\">t</p>"),
      "<p>t</p>"
    )
  }

  func testDropsJavaScriptHrefsAndSrcs() {
    XCTAssertEqual(sanitizer.sanitize("<a href=\"javascript:alert(1)\">x</a>"), "<a>x</a>")
    XCTAssertEqual(sanitizer.sanitize("<img src=\"JaVaScRiPt:alert(1)\">"), "<img>")
    XCTAssertEqual(sanitizer.sanitize("<a href=\"data:text/html,<b>x</b>\">x</a>"), "<a>x</a>")
  }

  func testKeepsHTTPSLinksAndImages() {
    XCTAssertEqual(
      sanitizer.sanitize("<a href=\"https://example.com/a?b=1&amp;c=2\" title=\"t\">link</a>"),
      "<a href=\"https://example.com/a?b=1&amp;c=2\" title=\"t\">link</a>"
    )
    XCTAssertEqual(
      sanitizer.sanitize("<img alt=\"pic\" src=\"http://cdn.example.com/i.png\" width=\"5\">"),
      "<img alt=\"pic\" src=\"http://cdn.example.com/i.png\">"
    )
  }

  func testDropsUnknownTagsButKeepsChildren() {
    XCTAssertEqual(
      sanitizer.sanitize("<form action=\"/x\"><input value=\"v\"><button>go</button></form>text"),
      "gotext"
    )
  }

  func testRemovesCommentsAndDeclarations() {
    XCTAssertEqual(
      sanitizer.sanitize("<!-- secret --><!DOCTYPE html><p>a</p>"),
      "<p>a</p>"
    )
  }

  func testEscapesBareAngleBracketsInText() {
    XCTAssertEqual(sanitizer.sanitize("2 < 3 > 1"), "2 &lt; 3 &gt; 1")
  }

  func testPreservesWellFormedEntitiesInText() {
    XCTAssertEqual(
      sanitizer.sanitize("A&nbsp;B &amp; C &#8212; D &unknown"),
      "A&nbsp;B &amp; C &#8212; D &amp;unknown")
  }

  func testClosesUnclosedElementsAtEnd() {
    XCTAssertEqual(
      sanitizer.sanitize("<blockquote><p>quoted"),
      "<blockquote><p>quoted</p></blockquote>"
    )
  }

  func testHandlesAttributeValuesContainingGreaterThanSigns() {
    XCTAssertEqual(
      sanitizer.sanitize("<img src=\"https://x/i.png?a=b>c\" onerror=\"a>b\" alt=\"ok\">"),
      "<img src=\"https://x/i.png?a=b>c\" alt=\"ok\">"
    )
  }

  func testSelfClosingTagsDoNotPushStack() {
    XCTAssertEqual(sanitizer.sanitize("<hr/><br />end"), "<hr><br>end")
  }

  func testVeryLongStoryCompletesQuickly() {
    let chunk =
      #"<p>Hello <strong>world</strong>, this is a reasonably long paragraph with <a href="https://example.com/x">a link</a> and some <em>emphasis</em>.</p>"#
    let html = String(repeating: chunk, count: 2000)
    let start = Date()
    _ = sanitizer.sanitize(html)
    XCTAssertLessThan(Date().timeIntervalSince(start), 5.0)
  }
}
