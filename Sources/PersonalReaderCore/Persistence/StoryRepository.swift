import Foundation
import GRDB

public struct StoryRepository: Sendable {
  private let databaseQueue: DatabaseQueue

  public init(databaseURL: URL) throws {
    let databaseQueue = try DatabaseQueue(path: databaseURL.path)
    try Self.makeMigrator().migrate(databaseQueue)
    self.databaseQueue = databaseQueue
  }

  private init(databaseQueue: DatabaseQueue) throws {
    try Self.makeMigrator().migrate(databaseQueue)
    self.databaseQueue = databaseQueue
  }

  public static func inMemory() throws -> StoryRepository {
    try StoryRepository(databaseQueue: DatabaseQueue())
  }

  public func save(_ stories: [Story]) throws {
    try databaseQueue.write { database in
      for incomingStory in stories {
        var story = incomingStory
        if let existingStory = try Story.fetchOne(database, key: story.id) {
          story.isRead = existingStory.isRead
        }
        try story.save(database)
      }
    }
  }

  public func fetchStories(limit: Int = 50) throws -> [Story] {
    try databaseQueue.read { database in
      try Story
        .order(Story.Columns.publishedAt.desc)
        .limit(limit)
        .fetchAll(database)
    }
  }

  @discardableResult
  public func markRead(id: String, isRead: Bool = true) throws -> Bool {
    try databaseQueue.write { database in
      try database.execute(
        sql: "UPDATE stories SET is_read = ? WHERE id = ?",
        arguments: [isRead, id]
      )
      return database.changesCount > 0
    }
  }

  @discardableResult
  public func deletePublished(before timestamp: Int64) throws -> Int {
    try databaseQueue.write { database in
      try Story
        .filter(Story.Columns.publishedAt < timestamp)
        .deleteAll(database)
    }
  }

  @MainActor
  public func observeStories(
    limit: Int = 50,
    onError: @escaping @Sendable (Error) -> Void,
    onChange: @escaping @Sendable ([Story]) -> Void
  ) -> AnyDatabaseCancellable {
    let observation = ValueObservation.tracking { database in
      try Story
        .order(Story.Columns.publishedAt.desc)
        .limit(limit)
        .fetchAll(database)
    }
    return observation.start(
      in: databaseQueue,
      onError: onError,
      onChange: onChange
    )
  }

  private static func makeMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("createStories") { database in
      try database.create(table: Story.databaseTableName) { table in
        table.column("id", .text).primaryKey()
        table.column("title", .text).notNull()
        table.column("content_body", .text).notNull()
        table.column("author", .text).notNull()
        table.column("subreddit", .text).notNull()
        table.column("published_at", .integer).notNull()
        table.column("is_read", .boolean).notNull().defaults(to: false)
      }
      try database.create(
        indexOn: Story.databaseTableName,
        columns: ["published_at"]
      )
      try database.create(
        indexOn: Story.databaseTableName,
        columns: ["subreddit"]
      )
    }
    return migrator
  }
}
