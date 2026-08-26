import Foundation
import GRDB

public enum FeedSourceKind: String, Codable, Sendable {
  case reddit
  case rss
}

public enum RefreshInterval: Int64, Codable, CaseIterable, Sendable, Identifiable {
  case thirtyMinutes = 1800
  case oneHour = 3600
  case threeHours = 10800
  case sixHours = 21600
  case twelveHours = 43200
  case oneDay = 86400

  public var id: Int64 { rawValue }

  public var seconds: TimeInterval { TimeInterval(rawValue) }

  public var title: String {
    switch self {
    case .thirtyMinutes: return "30 minutes"
    case .oneHour: return "1 hour"
    case .threeHours: return "3 hours"
    case .sixHours: return "6 hours"
    case .twelveHours: return "12 hours"
    case .oneDay: return "1 day"
    }
  }

  public static var `default`: RefreshInterval { .threeHours }
}

public struct FeedSourceRecord: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable,
  Identifiable
{
  public static let databaseTableName = "feed_sources"

  public var id: String
  public var kind: FeedSourceKind
  public var title: String
  public var url: String
  public var isEnabled: Bool
  public var refreshIntervalSeconds: Int64
  public var sortOrder: Int
  public var createdAt: Int64
  public var updatedAt: Int64

  public init(
    id: String = UUID().uuidString,
    kind: FeedSourceKind,
    title: String,
    url: String,
    isEnabled: Bool = true,
    refreshInterval: RefreshInterval = .default,
    sortOrder: Int = 0,
    createdAt: Int64 = Int64(Date().timeIntervalSince1970),
    updatedAt: Int64 = Int64(Date().timeIntervalSince1970)
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.url = url
    self.isEnabled = isEnabled
    self.refreshIntervalSeconds = refreshInterval.rawValue
    self.sortOrder = sortOrder
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var refreshInterval: RefreshInterval {
    get {
      RefreshInterval(rawValue: refreshIntervalSeconds) ?? .default
    }
    set {
      refreshIntervalSeconds = newValue.rawValue
    }
  }

  public var host: String {
    URL(string: url)?.host ?? url
  }

  public var isBuiltInReddit: Bool { kind == .reddit }

  public static func builtInRedditID() -> String { "reddit-built-in" }

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case title
    case url
    case isEnabled = "is_enabled"
    case refreshIntervalSeconds = "refresh_interval_seconds"
    case sortOrder = "sort_order"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  public enum Columns: String, ColumnExpression {
    case id
    case kind
    case title
    case url
    case isEnabled = "is_enabled"
    case refreshIntervalSeconds = "refresh_interval_seconds"
    case sortOrder = "sort_order"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}
