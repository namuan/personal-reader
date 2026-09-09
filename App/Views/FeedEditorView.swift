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
  @State private var discoveredFeeds: [DiscoveredFeed] = []
  @State private var discoveryError: String?
  @State private var isDiscovering = false
  @State private var selectedDiscoveredFeedURL: URL?
  @State private var discoveryID = UUID()
  @State private var discoveryTask: Task<Void, Never>?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("https://example.com", text: $url, axis: .vertical)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .disabled(isEditingExisting)
        } header: {
          Text(isEditingExisting ? "Feed URL" : "Website or feed URL")
        } footer: {
          Text(
            isEditingExisting
              ? "Use the public Atom or RSS URL of the site. HTTPS is required."
              : "Enter a public HTTPS website to find its feeds, or paste a feed URL directly."
          )
        }

        if !isEditingExisting {
          discoverySection
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
      .onDisappear {
        discoveryTask?.cancel()
      }
    }
  }

  private var isEditingExisting: Bool {
    if case .edit = mode { return true }
    return false
  }

  private var isSavePlausible: Bool {
    !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  @ViewBuilder
  private var discoverySection: some View {
    Section {
      Button {
        discoverFeeds()
      } label: {
        Label("Find feeds", systemImage: "magnifyingglass")
      }
      .disabled(isDiscovering || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

      if isDiscovering {
        HStack(spacing: 8) {
          ProgressView()
          Text("Looking for feeds…")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      if let discoveryError {
        Label(discoveryError, systemImage: "exclamationmark.triangle")
          .font(.footnote)
          .foregroundStyle(.orange)
      }

      if !isDiscovering, discoveryError == nil, !discoveredFeeds.isEmpty {
        ForEach(discoveredFeeds) { feed in
          Button {
            selectDiscoveredFeed(feed)
          } label: {
            DiscoveredFeedRow(
              feed: feed,
              isSelected: selectedDiscoveredFeedURL == feed.url
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(feed.title), \(feed.entryCount) entries")
          .accessibilityAddTraits(selectedDiscoveredFeedURL == feed.url ? .isSelected : [])
        }
      }
    } header: {
      Text("Find feeds")
    } footer: {
      if !isDiscovering, discoveryError == nil, discoveredFeeds.isEmpty {
        Text("No feeds found yet. You can still test and add a feed URL directly.")
      }
    }
  }

  private func loadInitialValues() {
    if case .edit(let source) = mode {
      url = source.url
      title = source.title
      refreshInterval = source.refreshInterval
      isEnabled = source.isEnabled
    }
  }

  private func discoverFeeds() {
    discoveryTask?.cancel()
    let requestID = UUID()
    discoveryID = requestID
    isDiscovering = true
    discoveryError = nil
    discoveredFeeds = []
    selectedDiscoveredFeedURL = nil
    discoveryTask = Task {
      let outcome = await model.discoverFeeds(from: url)
      guard !Task.isCancelled, discoveryID == requestID else { return }
      isDiscovering = false
      switch outcome {
      case .found(let feeds):
        discoveredFeeds = feeds
        if feeds.isEmpty {
          discoveryError = "No public RSS or Atom feeds were found on that website."
        }
      case .failed(let message):
        discoveryError = message
      }
      discoveryTask = nil
    }
  }

  private func selectDiscoveredFeed(_ feed: DiscoveredFeed) {
    selectedDiscoveredFeedURL = feed.url
    url = feed.url.absoluteString
    title = feed.title
    testOutcome = nil
    saveError = nil
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

private struct DiscoveredFeedRow: View {
  let feed: DiscoveredFeed
  let isSelected: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 4) {
        Text(feed.title)
          .font(.headline)
          .foregroundStyle(.primary)
        Text(feed.url.host ?? feed.url.absoluteString)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("\(feed.entryCount) entries")
          .font(.caption2)
          .foregroundStyle(.secondary)
        ForEach(feed.samples) { sample in
          Text(sample.title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
    .padding(.vertical, 4)
  }
}
