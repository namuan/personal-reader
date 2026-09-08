import Foundation
import GRDB

public struct BookmarkedStory: Codable, Equatable, Hashable, FetchableRecord, Identifiable,
  PersistableRecord, Sendable
{
  public static let databaseTableName = "bookmarked_stories"

  public let id: String
  public var title: String
  public var contentBody: String
  public var author: String
  public var subreddit: String
  public var publishedAt: Int64
  public var link: String
  public var isRead: Bool
  public var sourceId: String
  public var bookmarkedAt: Int64
  public var sortOrder: Int

  public init(
    story: Story,
    bookmarkedAt: Int64 = Int64(Date().timeIntervalSince1970),
    sortOrder: Int
  ) {
    id = story.id
    title = story.title
    contentBody = story.contentBody
    author = story.author
    subreddit = story.subreddit
    publishedAt = story.publishedAt
    link = story.link
    isRead = story.isRead
    sourceId = story.sourceId
    self.bookmarkedAt = bookmarkedAt
    self.sortOrder = sortOrder
  }

  public var story: Story {
    Story(
      id: id,
      title: title,
      contentBody: contentBody,
      author: author,
      subreddit: subreddit,
      publishedAt: publishedAt,
      link: link,
      isRead: isRead,
      sourceId: sourceId
    )
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
    case sourceId = "source_id"
    case bookmarkedAt = "bookmarked_at"
    case sortOrder = "sort_order"
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
    case sourceId = "source_id"
    case bookmarkedAt = "bookmarked_at"
    case sortOrder = "sort_order"
  }
}
