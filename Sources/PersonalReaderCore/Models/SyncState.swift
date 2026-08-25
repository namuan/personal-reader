import Foundation
import GRDB

public struct SyncState: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "sync_state"

  public let feedKey: String
  public var lastSuccessfulSyncAt: Int64?
  public var retryNotBefore: Int64?
  public var rateLimitAttempt: Int
  public var olderCursor: String?
  public var hasReachedEnd: Bool

  public init(
    feedKey: String,
    lastSuccessfulSyncAt: Int64? = nil,
    retryNotBefore: Int64? = nil,
    rateLimitAttempt: Int = 0,
    olderCursor: String? = nil,
    hasReachedEnd: Bool = false
  ) {
    self.feedKey = feedKey
    self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    self.retryNotBefore = retryNotBefore
    self.rateLimitAttempt = rateLimitAttempt
    self.olderCursor = olderCursor
    self.hasReachedEnd = hasReachedEnd
  }

  public var lastSuccessfulSyncDate: Date? {
    lastSuccessfulSyncAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
  }

  public var retryNotBeforeDate: Date? {
    retryNotBefore.map { Date(timeIntervalSince1970: TimeInterval($0)) }
  }

  enum CodingKeys: String, CodingKey {
    case feedKey = "feed_key"
    case lastSuccessfulSyncAt = "last_successful_sync_at"
    case retryNotBefore = "retry_not_before"
    case rateLimitAttempt = "rate_limit_attempt"
    case olderCursor = "older_cursor"
    case hasReachedEnd = "has_reached_end"
  }

  public enum Columns: String, ColumnExpression {
    case feedKey = "feed_key"
    case lastSuccessfulSyncAt = "last_successful_sync_at"
    case retryNotBefore = "retry_not_before"
    case rateLimitAttempt = "rate_limit_attempt"
    case olderCursor = "older_cursor"
    case hasReachedEnd = "has_reached_end"
  }
}
