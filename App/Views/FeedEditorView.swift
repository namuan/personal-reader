import PersonalReaderCore
import SwiftUI

struct FeedEditorView: View {
  enum Mode {
    case add
    case edit(FeedSourceRecord)
  }

  let mode: Mode

  @Environment(AppModel.self) private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  @State private var url = ""
  @State private var title = ""
  @State private var refreshInterval: RefreshInterval = .default
  @State private var isEnabled = true
  @State private var testOutcome: AppModel.FeedConnectionOutcome?
  @State private var saveError: String?
  @State private var isTesting = false
  @State private var isSaving = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("https://example.com/feed.xml", text: $url, axis: .vertical)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .disabled(isEditingExisting)
        } header: {
          Text("Feed URL")
        } footer: {
          Text("Use the public Atom or RSS URL of the site. HTTPS is required.")
        }

        Section {
          TextField("Display name (optional)", text: $title)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
        } header: {
          Text("Name")
        }

        Section("Refresh") {
          Picker("Refresh interval", selection: $refreshInterval) {
            ForEach(RefreshInterval.allCases) { interval in
              Text(interval.title).tag(interval)
            }
          }
          Toggle("Enabled", isOn: $isEnabled)
        }

        Section {
          Button {
            runTest()
          } label: {
            Label("Test feed", systemImage: "antenna.radiowaves.left.and.right")
          }
          .disabled(isTesting || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

          if let outcome = testOutcome {
            switch outcome {
            case .connected(let title, let count):
              Label(
                "Connected. \(count) entries from \"\(title.isEmpty ? "feed" : title)\".",
                systemImage: "checkmark.circle"
              )
              .foregroundStyle(.green)
              .font(.footnote)
            case .failed(let message):
              Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.footnote)
            }
          }

          if let saveError {
            Text(saveError)
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }

        if case .edit = mode {
          Section {
            Button(role: .destructive) {
              if case .edit(let source) = mode {
                model.deleteFeed(id: source.id)
                dismiss()
              }
            } label: {
              Label("Delete feed", systemImage: "trash")
            }
          }
        }
      }
      .navigationTitle(isEditingExisting ? "Edit feed" : "Add RSS feed")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            save()
          }
          .disabled(!isSavePlausible || isSaving)
        }
      }
      .onAppear(perform: loadInitialValues)
    }
  }

  private var isEditingExisting: Bool {
    if case .edit = mode { return true }
    return false
  }

  private var isSavePlausible: Bool {
    !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func loadInitialValues() {
    if case .edit(let source) = mode {
      url = source.url
      title = source.title
      refreshInterval = source.refreshInterval
      isEnabled = source.isEnabled
    }
  }

  private func runTest() {
    isTesting = true
    testOutcome = nil
    saveError = nil
    Task {
      let outcome = await model.testFeed(url: url)
      testOutcome = outcome
      isTesting = false
    }
  }

  private func save() {
    isSaving = true
    saveError = nil
    let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let outcome: AppModel.SetupOutcome
    switch mode {
    case .add:
      outcome = model.addFeed(
        url: trimmedURL,
        title: trimmedTitle.isEmpty ? nil : trimmedTitle,
        refreshInterval: refreshInterval
      )
    case .edit(let source):
      outcome = model.updateFeed(
        id: source.id,
        title: trimmedTitle.isEmpty ? nil : trimmedTitle,
        refreshInterval: refreshInterval,
        isEnabled: isEnabled
      )
    }
    switch outcome {
    case .saved:
      isSaving = false
      dismiss()
    case .failed(let message):
      isSaving = false
      saveError = message
    }
  }
}
