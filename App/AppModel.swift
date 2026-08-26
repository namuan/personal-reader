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
    case partial(succeeded: Int, attempted: Int)
  }

  private(set) var phase: Phase = .loading
  private(set) var stories: [Story] = []
  private(set) var unreadCount = 0
  private(set) var lastSyncDate: Date?
  private(set) var syncStatus: SyncStatus = .idle
  private(set) var isLoadingOlderStories = false
  private(set) var hasMoreStories = true
  private(set) var feedSources: [FeedSourceRecord] = []
  private(set) var sourcesNeedingAttention: [String: String] = [:]
  var scope: LibraryScope = .all {
    didSet {
      if scope != oldValue {
        persistScope()
        restartObservation()
      }
    }
  }

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

  var currentFeedTitle: String {
    switch scope {
    case .all:
      return redditTitle()
    case .reddit:
      return redditTitle()
    case .source(let id):
      return feedSources.first(where: { $0.id == id })?.title ?? "Feed"
    }
  }

  var hasConfiguredSubscribedFeed: Bool {
    true
  }

  var canChangeFeed: Bool {
    if case .syncing = syncStatus { return false }
    return true
  }

  private let environment: AppEnvironment
  var environmentIfAvailable: AppEnvironment { environment }
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
    scope = preferences.scope
    loadFeedSources()
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

    let report = await environment.librarySyncService.refreshDueSources(
      reddit: true,
      force: force
    )
    loadFeedSources()
    loadSyncState()
    applyLibraryReport(report, isBackground: isBackground)
  }

  func markRead(_ story: Story) {
    guard !story.isRead else { return }
    _ = try? environment.repository.markRead(id: story.id)
  }

  func loadOlderStories() async {
    guard !isLoadingOlderStories, hasMoreStories,
      let configuration = environment.configuration()
    else { return }
    isLoadingOlderStories = true
    syncStatus = .syncing
    defer { isLoadingOlderStories = false }

    do {
      let outcome = try await environment.librarySyncService.loadOlderReddit(
        configuration: configuration
      )
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
      applyReddit(error: error)
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

  enum FeedConnectionOutcome: Equatable {
    case connected(title: String, entryCount: Int)
    case failed(String)
  }

  func testConnection(
    username: String,
    token: String,
    feedMode: FeedMode,
    privateListing: RedditPrivateListing
  ) async -> ConnectionOutcome {
    let effectiveToken = token.isEmpty ? (environment.tokenStore.load() ?? "") : token
    let source = Self.feedSource(
      mode: feedMode,
      privateListing: privateListing
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

  func testFeed(url: String) async -> FeedConnectionOutcome {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .failed("Enter a feed URL.")
    }
    guard let urlValue = URL(string: trimmed), urlValue.scheme?.lowercased() == "https" else {
      return .failed("Feed URL must start with https://")
    }
    do {
      let feed = try await environment.rssSyncService.testSync(url: urlValue)
      return .connected(title: feed.title, entryCount: feed.entries.count)
    } catch let error as SyndicationClientError {
      return .failed(Self.feedTestMessage(for: error))
    } catch let error as RSSParserError {
      return .failed("The feed response was not valid XML or RSS.")
    } catch is CancellationError {
      return .failed("The test was cancelled.")
    } catch {
      return .failed("Could not reach the feed. Check the URL and your network.")
    }
  }

  func saveSetup(
    username: String,
    token: String,
    feedMode: FeedMode,
    privateListing: RedditPrivateListing
  ) -> SetupOutcome {
    let source = Self.feedSource(
      mode: feedMode,
      privateListing: privateListing
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
      preferences.feedMode = feedMode
      preferences.privateListing = privateListing
      preferences.setupComplete = true
      environment.preferences.preferences = preferences

      loadFeedSources()
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
    feedMode: FeedMode,
    privateListing: RedditPrivateListing
  ) -> SetupOutcome {
    let previousFeedKey = environment.configuration()?.feedKey
    let source = Self.feedSource(
      mode: feedMode,
      privateListing: privateListing
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
      preferences.feedMode = feedMode
      preferences.privateListing = privateListing
      environment.preferences.preferences = preferences
      if previousFeedKey != configuration.feedKey {
        resetRedditFeed()
      }
      loadSyncState()
      Task { await refresh(force: true) }
      return .saved
    } catch {
      return .failed(Self.validationMessage(for: error))
    }
  }

  func selectPrivateListing(_ listing: RedditPrivateListing) {
    guard canChangeFeed else { return }
    var preferences = environment.savedPreferences
    guard preferences.feedMode != .privateListing || preferences.privateListing != listing else {
      return
    }
    preferences.feedMode = .privateListing
    preferences.privateListing = listing
    environment.preferences.preferences = preferences
    resetRedditFeed()
    Task { await refresh(force: true) }
  }

  func selectSubscribedFeed() {
    guard canChangeFeed else { return }
    var preferences = environment.savedPreferences
    guard preferences.feedMode != .subscribed else { return }
    preferences.feedMode = .subscribed
    environment.preferences.preferences = preferences
    resetRedditFeed()
    Task { await refresh(force: true) }
  }

  func selectScope(_ newScope: LibraryScope) {
    scope = newScope
  }

  func addFeed(
    url: String,
    title: String?,
    refreshInterval: RefreshInterval
  ) -> SetupOutcome {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .failed("Enter a feed URL.") }
    guard let urlValue = URL(string: trimmed), urlValue.scheme?.lowercased() == "https" else {
      return .failed("Feed URL must start with https://")
    }
    do {
      let nextOrder = (try? environment.sourceStore.nextSortOrder()) ?? 0
      let displayTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
      let resolvedTitle =
        (displayTitle?.isEmpty == false ? displayTitle! : urlValue.host ?? trimmed)
      let source = FeedSourceRecord(
        kind: .rss,
        title: resolvedTitle,
        url: trimmed,
        isEnabled: true,
        refreshInterval: refreshInterval,
        sortOrder: nextOrder
      )
      try environment.sourceStore.save(source)
      loadFeedSources()
      Task { await refresh(force: false, isBackground: false) }
      return .saved
    } catch {
      return .failed("Could not save the feed.")
    }
  }

  func updateFeed(
    id: String,
    title: String?,
    refreshInterval: RefreshInterval,
    isEnabled: Bool
  ) -> SetupOutcome {
    guard let existing = try? environment.sourceStore.fetch(id: id) else {
      return .failed("Feed not found.")
    }
    var updated = existing
    updated.refreshInterval = refreshInterval
    updated.isEnabled = isEnabled
    if let title {
      let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        updated.title = trimmed
      }
    }
    updated.updatedAt = Int64(Date().timeIntervalSince1970)
    do {
      try environment.sourceStore.save(updated)
      loadFeedSources()
      restartObservation()
      return .saved
    } catch {
      return .failed("Could not update the feed.")
    }
  }

  func deleteFeed(id: String) {
    do {
      try environment.repository.deleteSource(sourceId: id)
      loadFeedSources()
      restartObservation()
      if case .source(let scopedId) = scope, scopedId == id {
        scope = .all
      }
    } catch {
      syncStatus = .failed("Could not delete the feed.")
    }
  }

  func refreshFeed(id: String) async {
    let result = await environment.librarySyncService.refreshSource(
      id: id,
      force: true
    )
    loadFeedSources()
    loadSyncState()
    if case .failure(let error) = result.outcome {
      switch error {
      case .notDue(let next):
        syncStatus = .throttled(next)
      case .rateLimited(let next):
        syncStatus = .throttled(next)
      case .invalidCredentials:
        syncStatus = .failed("Feed credentials rejected.")
      case .offline:
        syncStatus = .offline
      case .timedOut:
        syncStatus = .failed("Feed request timed out.")
      case .serverFailure:
        syncStatus = .failed("Feed server is having trouble.")
      case .malformedFeed(let message):
        syncStatus = .failed(message ?? "Feed could not be parsed.")
      case .networkFailure:
        syncStatus = .offline
      case .cancelled:
        break
      case .insecureScheme, .alreadySyncing:
        break
      }
    } else if case .syncing = syncStatus {
      syncStatus = .idle
    }
  }

  func clearLocalData() {
    do {
      try environment.repository.deleteAllData(preservingFeedSources: true)
    } catch {
      syncStatus = .failed("Could not clear downloaded stories.")
      return
    }
    loadSyncState()
    restartObservation()
  }

  func clearAllData() {
    environment.tokenStore.delete()
    environment.preferences.clear()
    do {
      try environment.repository.deleteAllData(preservingFeedSources: false)
    } catch {
      syncStatus = .failed("Could not clear library data.")
    }
    observationCancellable?.cancel()
    observationCancellable = nil
    stories = []
    unreadCount = 0
    lastSyncDate = nil
    isLoadingOlderStories = false
    hasMoreStories = true
    syncStatus = .idle
    showUnreadOnly = false
    scope = .all
    loadFeedSources()
    phase = .setup
  }

  private func applyLibraryReport(_ report: LibraryRefreshReport, isBackground: Bool) {
    if isBackground {
      if report.succeededCount < report.totalAttempted, report.totalAttempted > 0 {
        sourcesNeedingAttention = report.sources.reduce(into: [:]) { acc, result in
          if case .failure(let error) = result.outcome {
            acc[result.sourceId] = Self.message(forRSSError: error)
          }
        }
      } else {
        sourcesNeedingAttention = [:]
      }
      if report.succeededCount > 0 {
        syncStatus = .idle
      } else if report.totalAttempted > 0 {
        syncStatus = .failed("Refresh failed. Open the app to see details.")
      }
      return
    }
    var aggregated: [String: String] = [:]
    if case .failure(let error) = report.reddit {
      aggregated[FeedSourceRecord.builtInRedditID()] = Self.message(forSyncError: error)
    }
    for result in report.sources {
      if case .failure(let error) = result.outcome {
        aggregated[result.sourceId] = Self.message(forRSSError: error)
      }
    }
    sourcesNeedingAttention = aggregated

    if report.succeededCount == 0, report.totalAttempted > 0 {
      if let firstFailure = aggregated.values.first {
        syncStatus = .failed(firstFailure)
      } else {
        syncStatus = .failed("Refresh failed.")
      }
    } else if report.totalAttempted == 0 {
      syncStatus = .idle
    } else if report.succeededCount < report.totalAttempted {
      syncStatus = .partial(succeeded: report.succeededCount, attempted: report.totalAttempted)
    } else {
      syncStatus = .idle
    }
  }

  private func applyReddit(error: SyncError) {
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

  nonisolated static func message(forSyncError error: SyncError) -> String {
    switch error {
    case .rateLimited(let retryAt):
      return
        "Reddit is rate limiting. Next try \(retryAt.formatted(.relative(presentation: .named)))."
    case .invalidCredentials:
      return "Reddit rejected the feed credentials."
    case .offline:
      return "Offline."
    case .timedOut:
      return "The feed request timed out."
    case .serverFailure:
      return "Reddit is having trouble right now."
    case .malformedFeed:
      return "The feed response could not be parsed."
    case .networkFailure:
      return "Network error."
    case .cancelled:
      return "Cancelled."
    }
  }

  nonisolated static func message(forRSSError error: RSSSyncError) -> String {
    switch error {
    case .rateLimited(let retryAt):
      return "Rate limited. Next try \(retryAt.formatted(.relative(presentation: .named)))."
    case .invalidCredentials:
      return "The feed rejected the request."
    case .offline:
      return "Offline."
    case .timedOut:
      return "The feed request timed out."
    case .serverFailure:
      return "The feed server is having trouble."
    case .malformedFeed(let message):
      return message ?? "Feed could not be parsed."
    case .networkFailure:
      return "Network error."
    case .cancelled:
      return "Cancelled."
    case .insecureScheme:
      return "Feed URL must use HTTPS."
    case .alreadySyncing:
      return "Already syncing."
    case .notDue:
      return "Refresh not yet due."
    }
  }

  nonisolated static func feedTestMessage(for error: SyndicationClientError) -> String {
    switch error {
    case .insecureScheme, .insecureRedirect:
      return "Feed URL must start with https://"
    case .invalidCredentials:
      return "The feed rejected the request."
    case .rateLimited:
      return "The feed is rate limiting requests. Try again later."
    case .serverError:
      return "The feed server is having trouble right now."
    case .invalidResponse:
      return "The response from the feed was not recognized."
    case .offline:
      return "Offline."
    case .timedOut:
      return "The feed request timed out."
    case .cancelled:
      return "Cancelled."
    case .unexpectedStatus(let status):
      return "Unexpected response (HTTP \(status))."
    case .transportFailure:
      return "Network error."
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
    case .invalidURL:
      return "These settings do not form a valid feed URL."
    case .missingUserAgent:
      return "A user agent is required."
    }
  }

  nonisolated private static func feedSource(
    mode: FeedMode,
    privateListing: RedditPrivateListing
  ) -> FeedSource {
    mode == .subscribed
      ? .subscribed
      : .privateListing(privateListing)
  }

  private func resetRedditFeed() {
    do {
      try environment.repository.deleteSourceStories(sourceId: FeedSourceRecord.builtInRedditID())
      try environment.repository.deletePublished(
        before: Int64.max, sourceId: FeedSourceRecord.builtInRedditID()
      )
    } catch {
      syncStatus = .failed("Could not reset the Reddit feed.")
      return
    }
    stories = stories.filter { $0.sourceId != FeedSourceRecord.builtInRedditID() }
    unreadCount = stories.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
    lastSyncDate = nil
    isLoadingOlderStories = false
    hasMoreStories = true
    showUnreadOnly = false
    restartObservation()
  }

  private func persistScope() {
    var preferences = environment.savedPreferences
    preferences.scope = scope
    environment.preferences.preferences = preferences
  }

  private func redditTitle() -> String {
    let preferences = environment.savedPreferences
    guard preferences.feedMode == .privateListing else { return "Stories" }
    return preferences.privateListing.title
  }

  private func loadFeedSources() {
    feedSources = (try? environment.sourceStore.fetchAll()) ?? []
  }

  private func loadSyncState() {
    guard let configuration = environment.configuration() else { return }
    let feedKey = StoryRepository.feedKey(for: FeedSourceRecord.builtInRedditID())
    let state = try? environment.repository.loadSyncState(feedKey: feedKey)
    lastSyncDate = state?.lastSuccessfulSyncDate
    hasMoreStories = state?.hasReachedEnd != true
  }

  private func enabledSourceIds() -> Set<String> {
    Set(feedSources.filter(\.isEnabled).map(\.id))
  }

  private func filteredStoriesForScope(_ all: [Story]) -> [Story] {
    switch scope {
    case .all:
      return all
    case .reddit:
      return all.filter { $0.sourceId == FeedSourceRecord.builtInRedditID() }
    case .source(let id):
      return all.filter { $0.sourceId == id }
    }
  }

  private func startObservation() {
    observationCancellable?.cancel()
    let repository = environment.repository
    let enabledIds = enabledSourceIds()
    observationCancellable = repository.observeEnabledStories(
      enabledSourceIds: enabledIds,
      onError: { _ in },
      onChange: { [weak self] updatedStories in
        Task { @MainActor in
          self?.apply(stories: updatedStories)
        }
      }
    )
    do {
      let initial = try repository.fetchStoriesFromEnabledSources(
        enabledSourceIds: enabledIds
      )
      apply(stories: initial)
    } catch {}
  }

  private func restartObservation() {
    guard phase == .ready else { return }
    startObservation()
  }

  private func apply(stories updatedStories: [Story]) {
    let scoped = filteredStoriesForScope(updatedStories)
    stories = scoped
    unreadCount = scoped.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
  }
}
