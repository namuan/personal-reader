import UIKit
import XCTest

@testable import PersonalReaderApp

@MainActor
final class ReaderImageLayoutTests: XCTestCase {
  func testOversizedImageIsScaledToAvailableWidth() throws {
    let image = makeImage(size: CGSize(width: 1200, height: 600))
    let source = attributedString(with: image)

    let fitted = AttributedTextView.fittedAttributedString(source, maxWidth: 300)
    let attachment = try XCTUnwrap(attachment(in: fitted))

    XCTAssertEqual(attachment.bounds.width, 300, accuracy: 0.01)
    XCTAssertEqual(attachment.bounds.height, 150, accuracy: 0.01)
  }

  func testOversizedAttachmentBoundsAreScaledToAvailableWidth() throws {
    let image = makeImage(size: CGSize(width: 120, height: 60))
    let sourceAttachment = NSTextAttachment()
    sourceAttachment.image = image
    sourceAttachment.bounds = CGRect(x: 0, y: 0, width: 1200, height: 600)
    let source = NSAttributedString(attachment: sourceAttachment)

    let fitted = AttributedTextView.fittedAttributedString(source, maxWidth: 300)
    let fittedAttachment = try XCTUnwrap(attachment(in: fitted))

    XCTAssertEqual(fittedAttachment.bounds.width, 300, accuracy: 0.01)
    XCTAssertEqual(fittedAttachment.bounds.height, 150, accuracy: 0.01)
  }

  func testSmallImageIsNotUpscaled() throws {
    let image = makeImage(size: CGSize(width: 120, height: 60))
    let source = attributedString(with: image)

    let fitted = AttributedTextView.fittedAttributedString(source, maxWidth: 300)
    let attachment = try XCTUnwrap(attachment(in: fitted))
    let fittedImage = try XCTUnwrap(attachment.image)

    XCTAssertEqual(fittedImage.size.width, 120, accuracy: 0.01)
    XCTAssertEqual(fittedImage.size.height, 60, accuracy: 0.01)
    XCTAssertEqual(attachment.bounds, .zero)
  }

  func testFittingPreservesAspectRatioAtDifferentWidths() throws {
    let image = makeImage(size: CGSize(width: 1000, height: 400))
    let source = attributedString(with: image)

    let narrow = AttributedTextView.fittedAttributedString(source, maxWidth: 250)
    let wide = AttributedTextView.fittedAttributedString(source, maxWidth: 500)

    let narrowAttachment = try XCTUnwrap(attachment(in: narrow))
    let wideAttachment = try XCTUnwrap(attachment(in: wide))

    XCTAssertEqual(narrowAttachment.bounds.size, CGSize(width: 250, height: 100))
    XCTAssertEqual(wideAttachment.bounds.size, CGSize(width: 500, height: 200))
  }

  func testInvalidWidthLeavesAttributedStringUntouched() {
    let image = makeImage(size: CGSize(width: 1000, height: 400))
    let source = attributedString(with: image)

    let fitted = AttributedTextView.fittedAttributedString(source, maxWidth: 0)

    XCTAssertTrue(fitted.isEqual(to: source))
  }

  private func attributedString(with image: UIImage) -> NSAttributedString {
    let attachment = NSTextAttachment()
    attachment.image = image
    return NSAttributedString(attachment: attachment)
  }

  private func attachment(in attributedString: NSAttributedString) -> NSTextAttachment? {
    guard attributedString.length > 0 else { return nil }
    return attributedString.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
  }

  private func makeImage(size: CGSize) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      context.cgContext.setFillColor(UIColor.black.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: size))
    }
  }
}
