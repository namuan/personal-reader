import Foundation
import PersonalReaderCore

struct AppEnvironment: Sendable {
  let repository: StoryRepository
  let syncService: StorySyncService
  let feedClient: any FeedFetching
  let parser: any StoryParsing
  let tokenStore: KeychainTokenStore
  let preferences: PreferencesStore

  static func live() throws -> AppEnvironment {
    let databaseURL = try DatabaseLocation.defaultURL()
    let repository = try StoryRepository(databaseURL: databaseURL)

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
    sessionConfiguration.urlCache = nil
    let client = RedditFeedClient(session: URLSession(configuration: sessionConfiguration))
    let parser = RedditRSSParser()

    let syncService = StorySyncService(
      feedClient: client,
      parser: parser,
      repository: repository,
      policy: .standard
    )

    return AppEnvironment(
      repository: repository,
      syncService: syncService,
      feedClient: client,
      parser: parser,
      tokenStore: KeychainTokenStore(),
      preferences: PreferencesStore()
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
    subreddits: [String]? = nil,
    feedMode: FeedMode? = nil,
    privateListing: RedditPrivateListing? = nil,
    frontPageSort: RedditFrontPageSort? = nil
  ) -> FeedConfiguration? {
    let saved = preferences.preferences
    let effectiveUsername = username ?? saved.username
    let effectiveSubreddits = subreddits ?? saved.subreddits
    let effectiveToken = token ?? tokenStore.load()
    let effectiveMode = feedMode ?? saved.feedMode
    let effectiveListing = privateListing ?? saved.privateListing
    let effectiveFrontPageSort = frontPageSort ?? saved.frontPageSort

    guard let effectiveToken, !effectiveToken.isEmpty else { return nil }
    let source: FeedSource =
      effectiveMode == .subreddits
      ? .subreddits(effectiveSubreddits)
      : .privateListing(effectiveListing, effectiveFrontPageSort)
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
