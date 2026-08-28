import PersonalReaderCore
import SwiftUI
import UniformTypeIdentifiers

struct FeedExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }

  var data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

struct FeedManagementView: View {
  @Environment(AppModel.self) private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  @State private var editingFeed: FeedSourceRecord?
  @State private var isAdding = false
  @State private var exportDocument: FeedExportDocument?
  @State private var isExporting = false
  @State private var isImporting = false
  @State private var pendingImportPlan: FeedImportPlan?
  @State private var isConfirmingImport = false
  @State private var importMessage: String?
  @State private var transferError: String?

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

        if importMessage != nil || transferError != nil {
          Section {
            if let importMessage {
              Label(importMessage, systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.green)
            }
            if let transferError {
              Label(transferError, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
            }
          }
        }
      }
      .navigationTitle("RSS feeds")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Menu {
            Button {
              prepareExport()
            } label: {
              Label("Export feeds", systemImage: "square.and.arrow.up")
            }
            .disabled(exportableFeeds.isEmpty)

            Button {
              isImporting = true
            } label: {
              Label("Import feeds", systemImage: "square.and.arrow.down")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .accessibilityLabel("Feed import and export")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .fileExporter(
        isPresented: $isExporting,
        document: exportDocument,
        contentType: .json,
        defaultFilename: "personal-reader-feeds"
      ) { result in
        if case .failure = result {
          transferError = "Could not export feeds."
        }
      }
      .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: [.json],
        allowsMultipleSelection: false
      ) { result in
        handleImportSelection(result)
      }
      .confirmationDialog(
        "Import feeds?",
        isPresented: $isConfirmingImport,
        titleVisibility: .visible
      ) {
        Button("Import \(pendingImportPlan?.addedCount ?? 0) feeds") {
          commitImport()
        }
        Button("Cancel", role: .cancel) {
          pendingImportPlan = nil
        }
      } message: {
        if let plan = pendingImportPlan {
          Text(
            plan.rejectedCount > 0
              ? "Adds \(plan.addedCount) new feed(s). \(plan.rejectedCount) duplicate or invalid entries will be skipped."
              : "Adds \(plan.addedCount) new feed(s) to your library."
          )
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

  private var exportableFeeds: [FeedSourceRecord] {
    model.feedSources.filter { $0.kind == .rss }
  }

  private func prepareExport() {
    do {
      exportDocument = FeedExportDocument(data: try model.makeFeedExportData())
      isExporting = true
    } catch {
      transferError = "Could not export feeds."
    }
  }

  private func handleImportSelection(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      do {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
          if isAccessing {
            url.stopAccessingSecurityScopedResource()
          }
        }
        let data = try Data(contentsOf: url)
        let plan = try model.planFeedImport(data: data)
        if plan.addedCount == 0 {
          transferError =
            "No new feeds to import. The file contains only duplicates or invalid entries."
          pendingImportPlan = nil
        } else {
          transferError = nil
          importMessage = nil
          pendingImportPlan = plan
          isConfirmingImport = true
        }
      } catch {
        transferError = AppModel.transferMessage(for: error)
      }
    case .failure:
      transferError = "Could not read the selected file."
    }
  }

  private func commitImport() {
    guard let plan = pendingImportPlan else { return }
    pendingImportPlan = nil
    switch model.commitFeedImport(plan: plan) {
    case .imported(let added, let skipped):
      importMessage =
        skipped > 0
        ? "Imported \(added) feed(s). \(skipped) skipped."
        : "Imported \(added) feed(s)."
    case .failed(let message):
      transferError = message
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
