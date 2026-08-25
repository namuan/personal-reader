import PersonalReaderCore
import SwiftUI

struct ReaderView: View {
  @Environment(AppModel.self) private var model: AppModel
  @Environment(\.openURL) private var openURL

  let story: Story

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
            Label("Open original on Reddit", systemImage: "safari")
          }
          .padding(.top, 8)
        }
      }
      .padding()
    }
    .navigationBarTitleDisplayMode(.inline)
    .task(id: story.id) {
      model.markRead(story)
    }
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
