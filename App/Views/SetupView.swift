import PersonalReaderCore
import SwiftUI

struct SetupView: View {
  @Environment(AppModel.self) private var model: AppModel

  @State private var username = ""
  @State private var token = ""
  @State private var feedMode: FeedMode = .subscribed
  @State private var privateListing: RedditPrivateListing = .saved
  @State private var connectionResult: AppModel.ConnectionOutcome?
  @State private var saveError: String?
  @State private var isTesting = false

  var body: some View {
    Form {
      Section {
        Text(
          "Personal Reader downloads posts from the subreddits you're subscribed to or your authenticated Reddit listings. Reddit issues one personal feed token per account at reddit.com/prefs/feeds — it acts like a password, so it is stored only in this device's Keychain and is never included in backups or logs."
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
        }
      }

      if feedMode == .subscribed {
        Section {
          Text(
            "Your feed will load the latest posts from every subreddit you're subscribed to, in reverse chronological order."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
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
  }

  private func testConnection() {
    isTesting = true
    connectionResult = nil
    saveError = nil
    let testUsername = username.trimmingCharacters(in: .whitespaces)
    let testToken = token.trimmingCharacters(in: .whitespaces)

    Task {
      let outcome = await model.testConnection(
        username: testUsername,
        token: testToken,
        feedMode: feedMode,
        privateListing: privateListing
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
      feedMode: feedMode,
      privateListing: privateListing
    )
    if case .failed(let message) = outcome {
      saveError = message
    }
  }
}
