import SwiftUI
import UIKit

struct RichTextView: View {
  let html: String

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var attributedText: NSAttributedString?
  @State private var presentedImage: PresentedImage?

  var body: some View {
    Group {
      if let attributedText {
        AttributedTextView(
          attributedText: attributedText,
          onImageTap: { image in
            presentedImage = PresentedImage(image: image)
          }
        )
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
    .fullScreenCover(item: $presentedImage) { item in
      FullScreenImageView(image: item.image)
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

  private struct PresentedImage: Identifiable {
    let id = UUID()
    let image: UIImage
  }
}

struct AttributedTextView: UIViewRepresentable {
  let attributedText: NSAttributedString
  var onImageTap: (UIImage) -> Void = { _ in }

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

    let imageTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    imageTap.cancelsTouchesInView = false
    textView.addGestureRecognizer(imageTap)
    context.coordinator.textView = textView

    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.onImageTap = onImageTap

    let availableWidth = textView.bounds.width
    let renderedText =
      availableWidth > 0
      ? Self.fittedAttributedString(attributedText, maxWidth: availableWidth)
      : attributedText

    if !textView.attributedText.isEqual(to: renderedText) {
      textView.attributedText = renderedText
      textView.invalidateIntrinsicContentSize()
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: UITextView,
    context: Context
  ) -> CGSize? {
    guard let width = proposal.width, width > 0 else { return nil }

    let renderedText = Self.fittedAttributedString(attributedText, maxWidth: width)
    if !uiView.attributedText.isEqual(to: renderedText) {
      uiView.attributedText = renderedText
    }

    let fitted = uiView.sizeThatFits(
      CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    )
    return CGSize(width: width, height: max(fitted.height, 1))
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(openURL: openURL, onImageTap: onImageTap)
  }

  static func fittedAttributedString(
    _ source: NSAttributedString,
    maxWidth: CGFloat
  ) -> NSAttributedString {
    guard maxWidth > 0, source.length > 0 else { return source }

    let mutable = NSMutableAttributedString(attributedString: source)
    let fullRange = NSRange(location: 0, length: mutable.length)

    mutable.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
      guard let attachment = value as? NSTextAttachment,
        let image = attachment.image,
        image.size.width > 0,
        image.size.height > 0,
        image.size.width > maxWidth
      else {
        return
      }

      let scale = maxWidth / image.size.width
      let fittedSize = CGSize(
        width: maxWidth,
        height: image.size.height * scale
      )

      let fittedAttachment = NSTextAttachment()
      fittedAttachment.image = image
      fittedAttachment.bounds = CGRect(origin: .zero, size: fittedSize)
      mutable.addAttribute(.attachment, value: fittedAttachment, range: range)
    }

    return mutable
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    let openURL: OpenURLAction
    var onImageTap: (UIImage) -> Void
    weak var textView: UITextView?

    init(openURL: OpenURLAction, onImageTap: @escaping (UIImage) -> Void) {
      self.openURL = openURL
      self.onImageTap = onImageTap
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended,
        let textView,
        textView.attributedText.length > 0
      else {
        return
      }

      var location = recognizer.location(in: textView)
      location.x -= textView.textContainerInset.left
      location.y -= textView.textContainerInset.top

      let layoutManager = textView.layoutManager
      let textContainer = textView.textContainer
      let glyphIndex = layoutManager.glyphIndex(
        for: location,
        in: textContainer,
        fractionOfDistanceThroughGlyph: nil
      )
      guard glyphIndex < layoutManager.numberOfGlyphs else { return }

      let glyphRect = layoutManager.boundingRect(
        forGlyphRange: NSRange(location: glyphIndex, length: 1),
        in: textContainer
      )
      guard glyphRect.insetBy(dx: -8, dy: -8).contains(location) else { return }

      let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
      guard characterIndex < textView.attributedText.length,
        let attachment = textView.attributedText.attribute(
          .attachment,
          at: characterIndex,
          effectiveRange: nil
        ) as? NSTextAttachment,
        let image = attachment.image
      else {
        return
      }

      onImageTap(image)
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

private struct FullScreenImageView: View {
  let image: UIImage

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()

        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityLabel("Story image")
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .tint(.white)
        }
      }
      .toolbarBackground(.black, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
  }
}
