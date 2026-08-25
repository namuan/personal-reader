import PersonalReaderCore
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  @State private var username = ""
  @State private var subredditText = ""
  @State private var feedMode: FeedMode = .subreddits
  @State private var privateListing: RedditPrivateListing = .frontPage
  @State private var frontPageSort: RedditFrontPageSort = .best
  @State private var newToken = ""
  @State private var hasStoredToken = false
  @State private var connectionResult: AppModel.ConnectionOutcome?
  @State private var settingsMessage: String?
  @State private var settingsError: String?
  @State private var isTesting = false
  @State private var isConfirmingLocalDataClear = false
  @State private var isConfirmingReset = false

  var body: some View {
    NavigationStack {
      Form {
        accountSection
        tokenSection
        feedSection
        connectionSection
        dataSection
        resetSection
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .onAppear(perform: loadCurrentValues)
      .confirmationDialog(
        "Clear downloaded data?",
        isPresented: $isConfirmingLocalDataClear,
        titleVisibility: .visible
      ) {
        Button("Clear downloaded data", role: .destructive) {
          model.clearLocalData()
          connectionResult = nil
          settingsError = nil
          settingsMessage =
            "Downloaded stories and sync history cleared. Pull down to download again."
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "This removes downloaded stories and sync history from this device. Your Reddit username, feed selection, and Keychain token stay saved."
        )
      }
      .confirmationDialog(
        "Clear credentials and local data?",
        isPresented: $isConfirmingReset,
        titleVisibility: .visible
      ) {
        Button("Clear everything", role: .destructive) {
          model.clearAllData()
          dismiss()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "This removes the RSS token, your preferences, and every downloaded story. You will return to setup."
        )
      }
    }
  }

  private var accountSection: some View {
    Section("Reddit account") {
      TextField("Username", text: $username)
        .textContentType(.username)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
  }

  private var tokenSection: some View {
    Section {
      if hasStoredToken {
        LabeledContent("Token") {
          Text("Saved in Keychain")
            .foregroundStyle(.secondary)
        }
      }
      SecureField(hasStoredToken ? "Replace RSS token" : "RSS token", text: $newToken)
        .textContentType(.password)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    } header: {
      Text("Private feed token")
    } footer: {
      Text(
        "The token authenticates all private listings. It acts like a password and lives only in this device's Keychain."
      )
    }
  }

  private var feedSection: some View {
    Section("Feed source") {
      Picker("Browse", selection: $feedMode) {
        ForEach(FeedMode.allCases, id: \.self) { mode in
          Text(mode.title).tag(mode)
        }
      }

      if feedMode == .privateListing {
        Picker("Listing", selection: $privateListing) {
          ForEach(RedditPrivateListing.allCases, id: \.self) { listing in
            Label(listing.title, systemImage: listing.systemImage).tag(listing)
          }
        }

        if privateListing == .frontPage {
          Picker("Sort", selection: $frontPageSort) {
            ForEach(RedditFrontPageSort.allCases, id: \.self) { sort in
              Label(sort.title, systemImage: sort.systemImage).tag(sort)
            }
          }
        }
      } else {
        TextField(
          "Subreddits, comma separated",
          text: $subredditText,
          axis: .vertical
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
      }
    }
  }

  private var connectionSection: some View {
    Section {
      Button {
        testConnection()
      } label: {
        Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
      }
      .disabled(isTesting || !isFeedInputPlausible)

      if let result = connectionResult {
        ConnectionResultLabel(outcome: result)
      }

      Button("Save changes") { saveChanges() }
        .disabled(!isFeedInputPlausible)

      if let settingsMessage {
        Label(settingsMessage, systemImage: "checkmark.circle")
          .font(.footnote)
          .foregroundStyle(.green)
      }

      if let settingsError {
        Text(settingsError)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    }
  }

  private var dataSection: some View {
    Section("Data") {
      LabeledContent("Downloaded stories") {
        Text("\(model.stories.count)")
      }
      LabeledContent("Unread") {
        Text("\(model.unreadCount)")
      }
      LabeledContent("Last sync") {
        Text(model.lastSyncDate.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
      }
      LabeledContent("Retention") {
        Text(
          feedMode == .subreddits
            ? "Stories older than 14 days are removed"
            : "Up to 50 listing entries are kept"
        )
      }
      .accessibilityHint("Automatic cleanup keeps the library current")
      LabeledContent("Version") {
        Text(AppEnvironment.appVersion)
      }
      Button(role: .destructive) {
        isConfirmingLocalDataClear = true
      } label: {
        Label("Clear downloaded data", systemImage: "externaldrive.badge.minus")
      }
      .accessibilityHint("Keeps your feed settings and Keychain token")
    }
  }

  private var resetSection: some View {
    Section {
      Button(role: .destructive) {
        isConfirmingReset = true
      } label: {
        Label("Clear credentials and local data", systemImage: "trash")
      }
    } footer: {
      Text(
        "Privacy: the app sends requests only to reddit.com for your configured feed and opens links you choose. It contains no analytics or tracking."
      )
    }
  }

  private var isFeedInputPlausible: Bool {
    !username.trimmingCharacters(in: .whitespaces).isEmpty
      && (feedMode == .privateListing || !AppModel.parseSubreddits(subredditText).isEmpty)
  }

  private func loadCurrentValues() {
    let preferences = model.savedPreferences
    username = preferences.username
    subredditText = preferences.subreddits.joined(separator: ", ")
    feedMode = preferences.feedMode
    privateListing = preferences.privateListing
    frontPageSort = preferences.frontPageSort
    hasStoredToken = model.hasStoredToken
  }

  private func testConnection() {
    isTesting = true
    connectionResult = nil
    settingsMessage = nil
    settingsError = nil
    let testUsername = username.trimmingCharacters(in: .whitespaces)
    let testSubreddits = AppModel.parseSubreddits(subredditText)

    Task {
      let outcome = await model.testConnection(
        username: testUsername,
        token: newToken,
        subreddits: testSubreddits,
        feedMode: feedMode,
        privateListing: privateListing,
        frontPageSort: frontPageSort
      )
      connectionResult = outcome
      isTesting = false
    }
  }

  private func saveChanges() {
    settingsMessage = nil
    settingsError = nil
    let trimmedToken = newToken.trimmingCharacters(in: .whitespaces)
    let outcome = model.updateSettings(
      username: username.trimmingCharacters(in: .whitespaces),
      newToken: trimmedToken.isEmpty ? nil : trimmedToken,
      subredditText: subredditText,
      feedMode: feedMode,
      privateListing: privateListing,
      frontPageSort: frontPageSort
    )
    if case .failed(let message) = outcome {
      settingsError = message
    } else {
      newToken = ""
      hasStoredToken = true
      connectionResult = nil
      settingsMessage = "Settings saved. Refreshing the selected feed…"
    }
  }
}
