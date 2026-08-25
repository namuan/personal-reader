import Foundation
import GRDB
import Observation
import PersonalReaderCore

@MainActor
@Observable
final class AppModel {
  enum Phase: Equatable {
    case loading
    case setup
    case ready
  }

  enum SyncStatus: Equatable {
    case idle
    case syncing
    case offline
    case failed(String)
    case throttled(Date)
  }

  private(set) var phase: Phase = .loading
  private(set) var stories: [Story] = []
  private(set) var unreadCount = 0
  private(set) var lastSyncDate: Date?
  private(set) var syncStatus: SyncStatus = .idle
  private(set) var isLoadingOlderStories = false
  private(set) var hasMoreStories = true

  var showUnreadOnly = false {
    didSet { restartObservation() }
  }

  var filteredStories: [Story] {
    showUnreadOnly ? stories.filter { !$0.isRead } : stories
  }

  var savedPreferences: UserPreferences {
    environment.savedPreferences
  }

  var hasStoredToken: Bool {
    environment.hasStoredToken
  }

  var currentFeedMode: FeedMode {
    environment.savedPreferences.feedMode
  }

  var currentPrivateListing: RedditPrivateListing {
    environment.savedPreferences.privateListing
  }

  var currentFrontPageSort: RedditFrontPageSort {
    environment.savedPreferences.frontPageSort
  }

  var currentFeedTitle: String {
    let preferences = environment.savedPreferences
    guard preferences.feedMode == .privateListing else { return "Stories" }
    return preferences.privateListing == .frontPage
      ? preferences.frontPageSort.title
      : preferences.privateListing.title
  }

  var hasConfiguredSubreddits: Bool {
    !environment.savedPreferences.subreddits.isEmpty
  }

  var canChangeFeed: Bool {
    syncStatus != .syncing
  }

  private let environment: AppEnvironment
  private var observationCancellable: AnyDatabaseCancellable?

  init(environment: AppEnvironment) {
    self.environment = environment
  }

  func start() async {
    let preferences = environment.savedPreferences
    guard preferences.setupComplete, environment.hasStoredToken else {
      phase = .setup
      return
    }
    loadSyncState()
    startObservation()
    phase = .ready
    await refresh(force: false, isBackground: false)
  }

  func refresh(force: Bool, isBackground: Bool = false) async {
    guard let configuration = environment.configuration() else {
      syncStatus = .failed("Feed settings are incomplete. Check Settings.")
      return
    }
    if !isBackground {
      syncStatus = .syncing
    }

    do {
      let outcome = try await environment.syncService.sync(
        configuration: configuration,
        force: force
      )
      loadSyncState()
      switch outcome {
      case .synced:
        if !isBackground { syncStatus = .idle }
      case .skipped(let nextAllowedAt):
        if !isBackground {
          if nextAllowedAt > Date.now.addingTimeInterval(60) {
            syncStatus = .throttled(nextAllowedAt)
          } else {
            syncStatus = .idle
          }
        }
      }
    } catch let error as SyncError {
      apply(error: error)
    } catch {
      if !isBackground {
        syncStatus = .failed("Sync failed. Try again later.")
      }
    }
  }

  func markRead(_ story: Story) {
    guard !story.isRead else { return }
    _ = try? environment.repository.markRead(id: story.id)
  }

  func loadOlderStories() async {
    guard !isLoadingOlderStories, hasMoreStories,
      let configuration = environment.configuration()
    else {
      return
    }

    isLoadingOlderStories = true
    syncStatus = .syncing
    defer { isLoadingOlderStories = false }

    do {
      let outcome = try await environment.syncService.loadOlder(configuration: configuration)
      loadSyncState()
      switch outcome {
      case .loaded:
        syncStatus = .idle
      case .exhausted:
        hasMoreStories = false
        syncStatus = .idle
      case .skipped(let nextAllowedAt):
        syncStatus =
          nextAllowedAt > Date.now.addingTimeInterval(60)
          ? .throttled(nextAllowedAt)
          : .idle
      }
    } catch let error as SyncError {
      apply(error: error)
    } catch {
      syncStatus = .failed("Could not load older stories. Try again later.")
    }
  }

  enum SetupOutcome: Equatable {
    case saved
    case failed(String)
  }

  enum ConnectionOutcome: Equatable {
    case connected(storyCount: Int)
    case failed(String)
  }

  func testConnection(
    username: String,
    token: String,
    subreddits: [String],
    feedMode: FeedMode,
    privateListing: RedditPrivateListing,
    frontPageSort: RedditFrontPageSort
  ) async -> ConnectionOutcome {
    let effectiveToken = token.isEmpty ? (environment.tokenStore.load() ?? "") : token
    let source = Self.feedSource(
      mode: feedMode,
      subreddits: subreddits,
      privateListing: privateListing,
      frontPageSort: frontPageSort
    )
    do {
      let configuration = try FeedConfiguration(
        username: username,
        token: effectiveToken,
        source: source,
        userAgent: AppEnvironment.userAgent(username: username)
      )
      let data = try await environment.feedClient.fetch(configuration: configuration)
      let parsed = try environment.parser.parse(data)
      return .connected(storyCount: parsed.count)
    } catch let error as FeedConfigurationError {
      return .failed(Self.validationMessage(for: error))
    } catch let error as FeedClientError {
      return .failed(Self.message(for: error))
    } catch let error as RSSParserError {
      if case .invalidXML(let description) = error {
        return .failed(
          "The feed response was not valid RSS.\(description.map { " (\($0))" } ?? "")")
      }
      return .failed("The feed response could not be read.")
    } catch {
      return .failed("Connection failed. Check your network and try again.")
    }
  }

  func saveSetup(
    username: String,
    token: String,
    subredditText: String,
    feedMode: FeedMode,
    privateListing: RedditPrivateListing,
    frontPageSort: RedditFrontPageSort
  ) -> SetupOutcome {
    let subreddits = Self.parseSubreddits(subredditText)
    let source = Self.feedSource(
      mode: feedMode,
      subreddits: subreddits,
      privateListing: privateListing,
      frontPageSort: frontPageSort
    )
    do {
      let configuration = try FeedConfiguration(
        username: username,
        token: token,
        source: source,
        userAgent: AppEnvironment.userAgent(username: username)
      )
      do {
        try environment.tokenStore.save(token)
      } catch {
        return .failed("The RSS token could not be stored securely. Try again.")
      }
      var preferences = environment.savedPreferences
      preferences.username = configuration.username
      preferences.subreddits = subreddits
      preferences.feedMode = feedMode
      preferences.privateListing = privateListing
      preferences.frontPageSort = frontPageSort
      preferences.setupComplete = true
      environment.preferences.preferences = preferences

      loadSyncState()
      startObservation()
      phase = .ready
      Task { await refresh(force: true) }
      return .saved
    } catch {
      return .failed(Self.validationMessage(for: error))
    }
  }

  func updateSettings(
    username: String,
    newToken: String?,
    subredditText: String,
    feedMode: FeedMode,
    privateListing: RedditPrivateListing,
    frontPageSort: RedditFrontPageSort
  ) -> SetupOutcome {
    let previousFeedKey = environment.configuration()?.feedKey
    let subreddits = Self.parseSubreddits(subredditText)
    let source = Self.feedSource(
      mode: feedMode,
      subreddits: subreddits,
      privateListing: privateListing,
      frontPageSort: frontPageSort
    )
    let tokenToUse: String
    if let newToken, !newToken.isEmpty {
      tokenToUse = newToken
    } else if let stored = environment.tokenStore.load(), !stored.isEmpty {
      tokenToUse = stored
    } else {
      return .failed("An RSS token is required.")
    }

    do {
      let configuration = try FeedConfiguration(
        username: username,
        token: tokenToUse,
        source: source,
        userAgent: AppEnvironment.userAgent(username: username)
      )
      if let newToken, !newToken.isEmpty {
        do {
          try environment.tokenStore.save(newToken)
        } catch {
          return .failed("The RSS token could not be stored securely. Try again.")
        }
      }
      var preferences = environment.savedPreferences
      preferences.username = configuration.username
      preferences.subreddits = subreddits
      preferences.feedMode = feedMode
      preferences.privateListing = privateListing
      preferences.frontPageSort = frontPageSort
      environment.preferences.preferences = preferences
      if previousFeedKey != configuration.feedKey {
        resetDownloadedFeed()
      }
      loadSyncState()
      Task { await refresh(force: true) }
      return .saved
    } catch {
      return .failed(Self.validationMessage(for: error))
    }
  }

  func selectPrivateListing(_ listing: RedditPrivateListing) {
    guard listing != .frontPage, canChangeFeed else { return }
    var preferences = environment.savedPreferences
    guard preferences.feedMode != .privateListing || preferences.privateListing != listing else {
      return
    }
    preferences.feedMode = .privateListing
    preferences.privateListing = listing
    environment.preferences.preferences = preferences
    resetDownloadedFeed()
    Task { await refresh(force: true) }
  }

  func selectFrontPageSort(_ sort: RedditFrontPageSort) {
    guard canChangeFeed else { return }
    var preferences = environment.savedPreferences
    guard
      preferences.feedMode != .privateListing
        || preferences.privateListing != .frontPage
        || preferences.frontPageSort != sort
    else {
      return
    }
    preferences.feedMode = .privateListing
    preferences.privateListing = .frontPage
    preferences.frontPageSort = sort
    environment.preferences.preferences = preferences
    resetDownloadedFeed()
    Task { await refresh(force: true) }
  }

  func selectAdjacentFrontPageSort(direction: Int) {
    let preferences = environment.savedPreferences
    guard preferences.feedMode == .privateListing,
      preferences.privateListing == .frontPage,
      direction != 0
    else {
      return
    }
    let sorts = RedditFrontPageSort.allCases
    guard let index = sorts.firstIndex(of: preferences.frontPageSort) else { return }
    let nextIndex = (index + direction % sorts.count + sorts.count) % sorts.count
    selectFrontPageSort(sorts[nextIndex])
  }

  func selectSubreddits() {
    guard canChangeFeed else { return }
    var preferences = environment.savedPreferences
    guard !preferences.subreddits.isEmpty else {
      syncStatus = .failed("Add at least one subreddit in Settings first.")
      return
    }
    guard preferences.feedMode != .subreddits else { return }
    preferences.feedMode = .subreddits
    environment.preferences.preferences = preferences
    resetDownloadedFeed()
    Task { await refresh(force: true) }
  }

  func clearLocalData() {
    resetDownloadedFeed()
  }

  func clearAllData() {
    environment.tokenStore.delete()
    environment.preferences.clear()
    try? environment.repository.deleteAllData()
    observationCancellable?.cancel()
    observationCancellable = nil
    stories = []
    unreadCount = 0
    lastSyncDate = nil
    isLoadingOlderStories = false
    hasMoreStories = true
    syncStatus = .idle
    showUnreadOnly = false
    phase = .setup
  }

  private func apply(error: SyncError) {
    switch error {
    case .rateLimited(let retryAt):
      syncStatus = .throttled(retryAt)
    case .invalidCredentials:
      syncStatus = .failed(
        "Reddit rejected the feed credentials. Replace the RSS token in Settings.")
    case .offline:
      syncStatus = .offline
    case .timedOut:
      syncStatus = .failed("The feed request timed out. Try again later.")
    case .serverFailure:
      syncStatus = .failed("Reddit is having trouble right now. Try again later.")
    case .malformedFeed:
      syncStatus = .failed("The feed response could not be understood.")
    case .networkFailure:
      syncStatus = .offline
    case .cancelled:
      break
    }
  }

  nonisolated static func message(for error: FeedClientError) -> String {
    switch error {
    case .invalidCredentials:
      return "Reddit rejected these credentials. Check the username and RSS token."
    case .rateLimited:
      return "Reddit is rate limiting requests. Wait a few minutes and try again."
    case .serverError:
      return "Reddit is having trouble right now. Try again later."
    case .offline, .timedOut, .transportFailure:
      return "No connection. Check your network and try again."
    case .unexpectedStatus(let status):
      return "Unexpected response from Reddit (HTTP \(status))."
    case .invalidResponse:
      return "The response from Reddit was not recognized."
    case .cancelled:
      return "The request was cancelled."
    }
  }

  nonisolated static func validationMessage(for error: Error) -> String {
    guard let feedError = error as? FeedConfigurationError else {
      return "Settings could not be saved."
    }
    switch feedError {
    case .missingUsername:
      return "Enter your Reddit username."
    case .missingToken:
      return "Paste your private RSS token."
    case .missingSubreddits:
      return "Add at least one subreddit."
    case .invalidSubreddit:
      return "Subreddit names may only contain letters, numbers, and underscores."
    case .invalidURL:
      return "These settings do not form a valid feed URL."
    case .missingUserAgent:
      return "A user agent is required."
    }
  }

  nonisolated static func parseSubreddits(_ text: String) -> [String] {
    text
      .split(whereSeparator: { $0 == "," || $0.isNewline || $0 == " " })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  nonisolated private static func feedSource(
    mode: FeedMode,
    subreddits: [String],
    privateListing: RedditPrivateListing,
    frontPageSort: RedditFrontPageSort
  ) -> FeedSource {
    mode == .subreddits
      ? .subreddits(subreddits)
      : .privateListing(privateListing, frontPageSort)
  }

  private func resetDownloadedFeed() {
    try? environment.repository.deleteAllData()
    stories = []
    unreadCount = 0
    lastSyncDate = nil
    isLoadingOlderStories = false
    hasMoreStories = true
    showUnreadOnly = false
    syncStatus = .idle
  }

  private func loadSyncState() {
    guard let configuration = environment.configuration() else { return }
    let state = try? environment.repository.loadSyncState(feedKey: configuration.feedKey)
    lastSyncDate = state?.lastSuccessfulSyncDate
    hasMoreStories = state?.hasReachedEnd != true
  }

  private func startObservation() {
    observationCancellable?.cancel()
    let repository = environment.repository
    let cancellable = repository.observeStories(
      onError: { _ in },
      onChange: { [weak self] updatedStories in
        Task { @MainActor in
          self?.apply(stories: updatedStories)
        }
      }
    )
    observationCancellable = cancellable
    do {
      apply(stories: try repository.fetchStories())
    } catch {}
  }

  private func restartObservation() {
    unreadCount = stories.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
  }

  private func apply(stories updatedStories: [Story]) {
    stories = updatedStories
    unreadCount = updatedStories.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
  }
}
