import Foundation
import PersonalReaderCore

@testable import PersonalReaderApp

enum TestEnvironment {
  static func make(repository: StoryRepository) -> AppEnvironment {
    let sourceStore = repository.makeFeedSourceStore()
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    let feedClient = RedditFeedClient(session: URLSession(configuration: sessionConfiguration))
    let rssClient = SyndicationFeedClient(session: URLSession(configuration: sessionConfiguration))
    let parser = RedditRSSParser()
    let redditSyncService = StorySyncService(
      feedClient: feedClient,
      parser: parser,
      repository: repository,
      policy: .standard
    )
    let rssSyncService = RSSFeedSyncService(client: rssClient, repository: repository)
    let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "SeenStoryTrackingTests")!)
    let tokenStore = KeychainTokenStore()
    let librarySyncService = LibrarySyncService(
      redditService: redditSyncService,
      rssService: rssSyncService,
      sourceStore: sourceStore,
      repository: repository,
      redditConfigurationProvider: {
        AppEnvironment.makeRedditConfiguration(
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
      feedClient: feedClient,
      rssClient: rssClient,
      parser: parser,
      tokenStore: tokenStore,
      preferences: preferences
    )
  }
}
