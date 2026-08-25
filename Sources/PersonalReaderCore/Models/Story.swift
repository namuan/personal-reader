import Foundation
import GRDB

public struct Story: Codable, Equatable, Hashable, FetchableRecord, Identifiable, PersistableRecord,
  Sendable
{
  public static let databaseTableName = "stories"

  public let id: String
  public var title: String
  public var contentBody: String
  public var author: String
  public var subreddit: String
  public var publishedAt: Int64
  public var link: String
  public var isRead: Bool

  public init(
    id: String,
    title: String,
    contentBody: String,
    author: String,
    subreddit: String,
    publishedAt: Int64,
    link: String = "",
    isRead: Bool = false
  ) {
    self.id = id
    self.title = title
    self.contentBody = contentBody
    self.author = author
    self.subreddit = subreddit
    self.publishedAt = publishedAt
    self.link = link
    self.isRead = isRead
  }

  public var publishedDate: Date {
    Date(timeIntervalSince1970: TimeInterval(publishedAt))
  }

  public var originalURL: URL? {
    guard !link.isEmpty else { return nil }
    return URL(string: link)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case contentBody = "content_body"
    case author
    case subreddit
    case publishedAt = "published_at"
    case link
    case isRead = "is_read"
  }

  public enum Columns: String, ColumnExpression {
    case id
    case title
    case contentBody = "content_body"
    case author
    case subreddit
    case publishedAt = "published_at"
    case link
    case isRead = "is_read"
  }
}
