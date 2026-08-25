import PersonalReaderCore
import SwiftUI

struct SetupView: View {
  @Environment(AppModel.self) private var model: AppModel

  @State private var username = ""
  @State private var token = ""
  @State private var subredditText = ""
  @State private var feedMode: FeedMode = .subreddits
  @State private var privateListing: RedditPrivateListing = .frontPage
  @State private var frontPageSort: RedditFrontPageSort = .best
  @State private var connectionResult: AppModel.ConnectionOutcome?
  @State private var saveError: String?
  @State private var isTesting = false

  var body: some View {
    Form {
      Section {
        Text(
          "Personal Reader downloads posts from selected subreddits or your authenticated Reddit listings. Reddit issues one personal feed token per account at reddit.com/prefs/feeds — it acts like a password, so it is stored only in this device's Keychain and is never included in backups or logs."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section("Reddit account") {
        TextField("Username", text: $username, prompt: Text("e.g. readinginbed"))
          .textContentType(.username)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .accessibilityLabel("Reddit username")
      }

      Section("Private feed token") {
        SecureField("RSS token", text: $token, prompt: Text("Paste the feed token"))
          .textContentType(.password)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .accessibilityLabel("Private RSS feed token")
      }

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
        }
      }

      if feedMode == .subreddits {
        Section {
          TextField(
            "Subreddits, comma separated", text: $subredditText,
            prompt: Text("e.g. shortstories, writingprompts"), axis: .vertical
          )
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .accessibilityLabel("Subreddits, separated by commas")
        } header: {
          Text("Subreddits")
        } footer: {
          Text("Stories from these subreddits are combined into one feed.")
        }
      }

      Section {
        Button {
          testConnection()
        } label: {
          Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
        }
        .disabled(!isInputPlausible || isTesting)

        if let result = connectionResult {
          ConnectionResultLabel(outcome: result)
        }

        Button {
          save()
        } label: {
          Text("Save and start reading")
            .frame(maxWidth: .infinity)
            .bold()
        }
        .disabled(!isInputPlausible)

        if let saveError {
          Text(saveError)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
    }
    .navigationTitle("Set up your feed")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var isInputPlausible: Bool {
    !username.trimmingCharacters(in: .whitespaces).isEmpty
      && !token.trimmingCharacters(in: .whitespaces).isEmpty
      && (feedMode == .privateListing || !AppModel.parseSubreddits(subredditText).isEmpty)
  }

  private func testConnection() {
    isTesting = true
    connectionResult = nil
    saveError = nil
    let testUsername = username.trimmingCharacters(in: .whitespaces)
    let testToken = token.trimmingCharacters(in: .whitespaces)
    let testSubreddits = AppModel.parseSubreddits(subredditText)

    Task {
      let outcome = await model.testConnection(
        username: testUsername,
        token: testToken,
        subreddits: testSubreddits,
        feedMode: feedMode,
        privateListing: privateListing,
        frontPageSort: frontPageSort
      )
      connectionResult = outcome
      isTesting = false
    }
  }

  private func save() {
    saveError = nil
    let outcome = model.saveSetup(
      username: username.trimmingCharacters(in: .whitespaces),
      token: token.trimmingCharacters(in: .whitespaces),
      subredditText: subredditText,
      feedMode: feedMode,
      privateListing: privateListing,
      frontPageSort: frontPageSort
    )
    if case .failed(let message) = outcome {
      saveError = message
    }
  }
}
