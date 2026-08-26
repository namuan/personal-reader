import Foundation
import PersonalReaderCore

struct AppEnvironment: Sendable {
  let repository: StoryRepository
  let sourceStore: FeedSourceStore
  let redditSyncService: StorySyncService
  let rssSyncService: RSSFeedSyncService
  let librarySyncService: LibrarySyncService
  let feedClient: any FeedFetching
  let rssClient: SyndicationFeedClient
  let parser: any StoryParsing
  let tokenStore: KeychainTokenStore
  let preferences: PreferencesStore

  static func live() throws -> AppEnvironment {
    let databaseURL = try DatabaseLocation.defaultURL()
    let repository = try StoryRepository(databaseURL: databaseURL)
    let sourceStore = repository.makeFeedSourceStore()

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
    sessionConfiguration.urlCache = nil
    let redditClient = RedditFeedClient(session: URLSession(configuration: sessionConfiguration))
    let rssClient = SyndicationFeedClient(session: URLSession(configuration: sessionConfiguration))
    let parser = RedditRSSParser()

    let redditSyncService = StorySyncService(
      feedClient: redditClient,
      parser: parser,
      repository: repository,
      policy: .standard
    )

    let rssSyncService = RSSFeedSyncService(
      client: rssClient,
      repository: repository
    )

    let tokenStore = KeychainTokenStore()
    let preferences = PreferencesStore()

    let librarySyncService = LibrarySyncService(
      redditService: redditSyncService,
      rssService: rssSyncService,
      sourceStore: sourceStore,
      repository: repository,
      redditConfigurationProvider: { [preferences, tokenStore] in
        Self.makeRedditConfiguration(
          preferences: preferences,
          tokenStore: tokenStore
        )
      }
    )

    return AppEnvironment(
      repository: repository,
      sourceStore: sourceStore,
      redditSyncService: redditSyncService,
      rssSyncService: rssSyncService,
      librarySyncService: librarySyncService,
      feedClient: redditClient,
      rssClient: rssClient,
      parser: parser,
      tokenStore: tokenStore,
      preferences: preferences
    )
  }

  var savedPreferences: UserPreferences {
    preferences.preferences
  }

  var hasStoredToken: Bool {
    tokenStore.load()?.isEmpty == false
  }

  func configuration(
    username: String? = nil,
    token: String? = nil,
    feedMode: FeedMode? = nil,
    privateListing: RedditPrivateListing? = nil
  ) -> FeedConfiguration? {
    Self.makeRedditConfiguration(
      username: username,
      token: token,
      feedMode: feedMode,
      privateListing: privateListing,
      preferences: preferences,
      tokenStore: tokenStore
    )
  }

  static func makeRedditConfiguration(
    username: String? = nil,
    token: String? = nil,
    feedMode: FeedMode? = nil,
    privateListing: RedditPrivateListing? = nil,
    preferences: PreferencesStore,
    tokenStore: KeychainTokenStore
  ) -> FeedConfiguration? {
    let saved = preferences.preferences
    let effectiveUsername = username ?? saved.username
    let effectiveToken = token ?? tokenStore.load()
    let effectiveMode = feedMode ?? saved.feedMode
    let effectiveListing = privateListing ?? saved.privateListing

    guard let effectiveToken, !effectiveToken.isEmpty else { return nil }
    let source: FeedSource =
      effectiveMode == .subscribed
      ? .subscribed
      : .privateListing(effectiveListing)
    return try? FeedConfiguration(
      username: effectiveUsername,
      token: effectiveToken,
      source: source,
      userAgent: Self.userAgent(username: effectiveUsername)
    )
  }

  static func userAgent(username: String) -> String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "1.0"
    return "ios:PersonalReader:\(version) (by /u/\(username))"
  }

  static var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }
}
