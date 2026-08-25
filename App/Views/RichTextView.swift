import SwiftUI
import UIKit

struct RichTextView: View {
  let html: String

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var attributedText: NSAttributedString?

  var body: some View {
    Group {
      if let attributedText {
        AttributedTextView(attributedText: attributedText)
      } else {
        HStack(spacing: 10) {
          ProgressView()
          Text("Preparing story…")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing story content")
      }
    }
    .task(id: RenderRequest(html: html, dynamicTypeSize: dynamicTypeSize)) {
      attributedText = nil
      await Task.yield()
      guard !Task.isCancelled else { return }
      attributedText = Self.styledAttributedString(from: html)
    }
  }

  static func styledAttributedString(from html: String) -> NSAttributedString {
    guard let data = html.data(using: .utf8),
      let imported = try? NSAttributedString(
        data: data,
        options: [
          .documentType: NSAttributedString.DocumentType.html,
          .characterEncoding: String.Encoding.utf8.rawValue,
        ],
        documentAttributes: nil
      )
    else {
      return NSAttributedString(string: html)
    }

    let mutable = NSMutableAttributedString(attributedString: imported)
    let fullRange = NSRange(location: 0, length: mutable.length)
    let baseFont = UIFont.preferredFont(forTextStyle: .body)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 4
    paragraphStyle.paragraphSpacing = 10

    mutable.beginEditing()
    mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
      var targetFont = baseFont
      if let existingFont = value as? UIFont,
        existingFont.fontDescriptor.symbolicTraits.contains(.traitBold),
        let bolded = baseFont.fontDescriptor.withSymbolicTraits(.traitBold)
      {
        targetFont = UIFont(descriptor: bolded, size: baseFont.pointSize)
      }
      if range.length > 0 {
        mutable.addAttribute(.font, value: targetFont, range: range)
        mutable.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
      }
    }
    mutable.endEditing()
    return mutable
  }

  private struct RenderRequest: Hashable {
    let html: String
    let dynamicTypeSize: DynamicTypeSize
  }
}

private struct AttributedTextView: UIViewRepresentable {
  let attributedText: NSAttributedString

  @Environment(\.openURL) private var openURL

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.isScrollEnabled = false
    textView.backgroundColor = .clear
    textView.textContainerInset = .zero
    textView.textContainer.lineFragmentPadding = 0
    textView.adjustsFontForContentSizeCategory = true
    textView.delegate = context.coordinator
    textView.accessibilityLabel = "Story content"
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    if !textView.attributedText.isEqual(to: attributedText) {
      textView.attributedText = attributedText
      textView.invalidateIntrinsicContentSize()
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: UITextView,
    context: Context
  ) -> CGSize? {
    guard let width = proposal.width, width > 0 else { return nil }
    let fitted = uiView.sizeThatFits(
      CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    )
    return CGSize(width: width, height: max(fitted.height, 1))
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(openURL: openURL)
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    let openURL: OpenURLAction

    init(openURL: OpenURLAction) {
      self.openURL = openURL
    }

    func textView(
      _ textView: UITextView,
      shouldInteractWith url: URL,
      in characterRange: NSRange
    ) -> Bool {
      switch url.scheme?.lowercased() {
      case "http", "https", "mailto":
        openURL(url)
        return false
      default:
        return false
      }
    }
  }
}
