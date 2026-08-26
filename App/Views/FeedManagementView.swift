import PersonalReaderCore
import SwiftUI

struct FeedManagementView: View {
  @Environment(AppModel.self) private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  @State private var editingFeed: FeedSourceRecord?
  @State private var isAdding = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          if model.feedSources.isEmpty {
            Text(
              "You haven't added any RSS or Atom feeds yet. Add one to start mixing it with your Reddit private stories."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          } else {
            ForEach(model.feedSources) { source in
              Button {
                editingFeed = source
              } label: {
                FeedSourceRow(
                  source: source, errorMessage: model.sourcesNeedingAttention[source.id])
              }
              .buttonStyle(.plain)
              .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                  model.deleteFeed(id: source.id)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
            }
          }
        } header: {
          Text("RSS feeds")
        } footer: {
          Text(
            "Personal Reader will fetch each enabled feed on its own schedule and merge the entries with your Reddit private stories."
          )
        }

        Section {
          Button {
            isAdding = true
          } label: {
            Label("Add RSS feed", systemImage: "plus")
          }
        }
      }
      .navigationTitle("RSS feeds")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $editingFeed) { source in
        FeedEditorView(mode: .edit(source))
      }
      .sheet(isPresented: $isAdding) {
        FeedEditorView(mode: .add)
      }
    }
  }
}

private struct FeedSourceRow: View {
  let source: FeedSourceRecord
  let errorMessage: String?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: source.isEnabled ? "dot.radiowaves.left.and.right" : "pause.circle")
        .foregroundStyle(source.isEnabled ? Color.accentColor : .secondary)
        .imageScale(.large)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 4) {
        Text(source.title)
          .font(.headline)
        Text(source.host)
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack(spacing: 8) {
          Label(source.refreshInterval.title, systemImage: "clock")
          if !source.isEnabled {
            Label("Paused", systemImage: "pause")
              .foregroundStyle(.secondary)
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)

        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.orange)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
  }
}
