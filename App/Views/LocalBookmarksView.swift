import PersonalReaderCore
import SwiftUI

struct LocalBookmarksView: View {
  @Environment(AppModel.self) private var model: AppModel

  var body: some View {
    Group {
      if model.bookmarks.isEmpty {
        ContentUnavailableView(
          "No local bookmarks",
          systemImage: "bookmark",
          description: Text("Bookmark a story to keep an offline copy in your read-later queue.")
        )
      } else {
        List {
          ForEach(model.bookmarks) { bookmark in
            StoryCardView(
              story: bookmark.story,
              sourceTitle: sourceTitle(for: bookmark.sourceId)
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .padding(.vertical, 6)
          }
          .onMove(perform: moveBookmarks)
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("Local Bookmarks")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if model.bookmarks.count > 1 {
        EditButton()
      }
    }
  }

  private func moveBookmarks(from source: IndexSet, to destination: Int) {
    var reordered = model.bookmarks
    reordered.move(fromOffsets: source, toOffset: destination)
    model.reorderBookmarks(ids: reordered.map(\.id))
  }

  private func sourceTitle(for sourceId: String) -> String? {
    if sourceId == FeedSourceRecord.builtInRedditID() { return nil }
    return model.feedSources.first(where: { $0.id == sourceId })?.title
  }
}
