import Foundation
import XCTest

@testable import PersonalReaderApp

final class WebPreviewDestinationTests: XCTestCase {
  func testAcceptsHTTPSURL() throws {
    let url = try XCTUnwrap(URL(string: "https://www.reddit.com/r/swift"))
    let destination = try XCTUnwrap(WebPreviewDestination(url: url))

    XCTAssertEqual(destination.url, url)
  }

  func testAcceptsHTTPURL() throws {
    let url = try XCTUnwrap(URL(string: "http://example.com/story"))
    let destination = try XCTUnwrap(WebPreviewDestination(url: url))

    XCTAssertEqual(destination.url, url)
  }

  func testRejectsNonWebSchemes() throws {
    let url = try XCTUnwrap(URL(string: "mailto:reader@example.com"))

    XCTAssertNil(WebPreviewDestination(url: url))
  }

  func testRejectsMissingURL() {
    XCTAssertNil(WebPreviewDestination(url: nil))
  }
}
