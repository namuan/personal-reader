import PersonalReaderCore
import SwiftUI

struct ReaderView: View {
  @Environment(\.openURL) private var openURL

  let story: Story
  let sourceTitle: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(story.title)
          .font(.title2.weight(.bold))
          .textSelection(.enabled)

        Text(metaLine)
          .font(.footnote)
          .foregroundStyle(.secondary)

        Divider()

        if story.contentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContentUnavailableView(
            "No text content",
            systemImage: "doc.text.magnifyingglass",
            description: Text(
              "This feed entry does not include a readable body. Open the original post instead.")
          )
        } else {
          RichTextView(html: story.contentBody)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let url = story.originalURL, url.scheme == "http" || url.scheme == "https" {
          Button {
            openURL(url)
          } label: {
            Label(openOriginalLabel(for: url), systemImage: "safari")
          }
          .padding(.top, 8)
        }
      }
      .padding()
    }
    .navigationBarTitleDisplayMode(.inline)
  }

  private func openOriginalLabel(for url: URL) -> String {
    if sourceTitle == nil { return "Open on Reddit" }
    return "Open on \(url.host ?? "the original site")"
  }

  private var metaLine: String {
    var parts = ["r/\(story.subreddit)"]
    if !story.author.isEmpty {
      parts.append("u/\(story.author)")
    }
    parts.append(story.publishedDate.formatted(date: .long, time: .shortened))
    return parts.joined(separator: " · ")
  }
}
