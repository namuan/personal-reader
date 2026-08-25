import SwiftUI
import UIKit
import XCTest

@testable import PersonalReaderApp

final class RichTextRenderingTests: XCTestCase {
  private let body = """
    <div><p><a href="https://www.reddit.com/r/WritingPrompts/comments/1v89ci1/">original prompt</a> by <a>u/Kitty_Fuchs</a> :)</p> <p>(alchemists count, right?)</p> <p>&quot;Ceri,&quot; Master Scand began, taking a seat at the table.</p> <p>They looked up from the distillation notes they&#39;d been poring over all morning.</p></div>
    """

  @MainActor
  func testConvertsRealRedditBodyToAttributedString() throws {
    let rendered = RichTextView.styledAttributedString(from: body)

    XCTAssertGreaterThan(rendered.length, 50)
    XCTAssertTrue(rendered.string.contains("original prompt"))
    XCTAssertNotNil(rendered.attribute(.font, at: 0, effectiveRange: nil))
    XCTAssertNotNil(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil))
  }

  @MainActor
  func testExpandsTextViewToFitRenderedContent() async throws {
    let controller = UIHostingController(
      rootView: RichTextView(html: body).frame(width: 320)
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 1000))
    window.rootViewController = controller
    window.makeKeyAndVisible()

    try await Task.sleep(for: .milliseconds(300))
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()

    let textView = try XCTUnwrap(findTextView(in: controller.view))
    XCTAssertGreaterThan(textView.attributedText.length, 50)
    XCTAssertGreaterThan(textView.frame.height, 100)
    XCTAssertGreaterThanOrEqual(textView.frame.height + 1, textView.contentSize.height)
  }

  @MainActor
  func testFallsBackToPlainTextForGarbageInput() {
    let rendered = RichTextView.styledAttributedString(from: "plain words only")
    XCTAssertEqual(rendered.string, "plain words only")
  }

  @MainActor
  private func findTextView(in view: UIView) -> UITextView? {
    if let textView = view as? UITextView {
      return textView
    }
    for child in view.subviews {
      if let textView = findTextView(in: child) {
        return textView
      }
    }
    return nil
  }
}
