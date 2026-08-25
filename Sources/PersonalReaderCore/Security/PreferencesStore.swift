import Foundation

public struct UserPreferences: Equatable, Sendable {
  public var username: String
  public var subreddits: [String]
  public var feedMode: FeedMode
  public var privateListing: RedditPrivateListing
  public var frontPageSort: RedditFrontPageSort
  public var setupComplete: Bool

  public init(
    username: String = "",
    subreddits: [String] = [],
    feedMode: FeedMode = .subreddits,
    privateListing: RedditPrivateListing = .frontPage,
    frontPageSort: RedditFrontPageSort = .best,
    setupComplete: Bool = false
  ) {
    self.username = username
    self.subreddits = subreddits
    self.feedMode = feedMode
    self.privateListing = privateListing
    self.frontPageSort = frontPageSort
    self.setupComplete = setupComplete
  }
}

public struct PreferencesStore: Sendable {
  private nonisolated(unsafe) let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var preferences: UserPreferences {
    get {
      UserPreferences(
        username: defaults.string(forKey: Keys.username) ?? "",
        subreddits: defaults.stringArray(forKey: Keys.subreddits) ?? [],
        feedMode: defaults.string(forKey: Keys.feedMode).flatMap(FeedMode.init(rawValue:))
          ?? .subreddits,
        privateListing: defaults.string(forKey: Keys.privateListing).flatMap(
          RedditPrivateListing.init(rawValue:)) ?? .frontPage,
        frontPageSort: defaults.string(forKey: Keys.frontPageSort).flatMap(
          RedditFrontPageSort.init(rawValue:)) ?? .best,
        setupComplete: defaults.bool(forKey: Keys.setupComplete)
      )
    }
    nonmutating set {
      defaults.set(newValue.username, forKey: Keys.username)
      defaults.set(newValue.subreddits, forKey: Keys.subreddits)
      defaults.set(newValue.feedMode.rawValue, forKey: Keys.feedMode)
      defaults.set(newValue.privateListing.rawValue, forKey: Keys.privateListing)
      defaults.set(newValue.frontPageSort.rawValue, forKey: Keys.frontPageSort)
      defaults.set(newValue.setupComplete, forKey: Keys.setupComplete)
    }
  }

  public func clear() {
    for key in [
      Keys.username,
      Keys.subreddits,
      Keys.feedMode,
      Keys.privateListing,
      Keys.frontPageSort,
      Keys.setupComplete,
    ] {
      defaults.removeObject(forKey: key)
    }
  }

  private enum Keys {
    static let username = "PersonalReader.username"
    static let subreddits = "PersonalReader.subreddits"
    static let feedMode = "PersonalReader.feedMode"
    static let privateListing = "PersonalReader.privateListing"
    static let frontPageSort = "PersonalReader.frontPageSort"
    static let setupComplete = "PersonalReader.setupComplete"
  }
}
