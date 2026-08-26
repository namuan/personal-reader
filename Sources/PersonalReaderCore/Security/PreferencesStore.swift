import Foundation

public enum LibraryScope: Equatable, Sendable {
  case all
  case source(String)
  case reddit
}

public struct UserPreferences: Equatable, Sendable {
  public var username: String
  public var feedMode: FeedMode
  public var privateListing: RedditPrivateListing
  public var setupComplete: Bool
  public var scope: LibraryScope

  public init(
    username: String = "",
    feedMode: FeedMode = .subscribed,
    privateListing: RedditPrivateListing = .saved,
    setupComplete: Bool = false,
    scope: LibraryScope = .all
  ) {
    self.username = username
    self.feedMode = feedMode
    self.privateListing = privateListing
    self.setupComplete = setupComplete
    self.scope = scope
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
        feedMode: defaults.string(forKey: Keys.feedMode).flatMap(FeedMode.init(rawValue:))
          ?? .subscribed,
        privateListing: defaults.string(forKey: Keys.privateListing).flatMap(
          RedditPrivateListing.init(rawValue:)) ?? .saved,
        setupComplete: defaults.bool(forKey: Keys.setupComplete),
        scope: Self.scope(from: defaults, key: Keys.scope)
      )
    }
    nonmutating set {
      defaults.set(newValue.username, forKey: Keys.username)
      defaults.set(newValue.feedMode.rawValue, forKey: Keys.feedMode)
      defaults.set(newValue.privateListing.rawValue, forKey: Keys.privateListing)
      defaults.set(newValue.setupComplete, forKey: Keys.setupComplete)
      defaults.set(Self.encode(newValue.scope), forKey: Keys.scope)
    }
  }

  public func clear() {
    for key in [
      Keys.username,
      Keys.feedMode,
      Keys.privateListing,
      Keys.setupComplete,
      Keys.scope,
    ] {
      defaults.removeObject(forKey: key)
    }
  }

  private static func scope(from defaults: UserDefaults, key: String) -> LibraryScope {
    guard let raw = defaults.string(forKey: key) else { return .all }
    if raw == "all" { return .all }
    if raw == "reddit" { return .reddit }
    if raw.hasPrefix("source:") {
      return .source(String(raw.dropFirst("source:".count)))
    }
    return .all
  }

  private static func encode(_ scope: LibraryScope) -> String {
    switch scope {
    case .all: return "all"
    case .reddit: return "reddit"
    case .source(let id): return "source:\(id)"
    }
  }

  private enum Keys {
    static let username = "PersonalReader.username"
    static let feedMode = "PersonalReader.feedMode"
    static let privateListing = "PersonalReader.privateListing"
    static let setupComplete = "PersonalReader.setupComplete"
    static let scope = "PersonalReader.scope"
  }
}
