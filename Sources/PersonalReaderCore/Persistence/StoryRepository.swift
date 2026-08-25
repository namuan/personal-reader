import Foundation
import GRDB

public struct StorySaveReport: Equatable, Sendable {
  public let inserted: Int
  public let updated: Int
  public let ignored: Int

  public init(inserted: Int, updated: Int, ignored: Int) {
    self.inserted = inserted
    self.updated = updated
    self.ignored = ignored
  }
}

public struct SyncReport: Equatable, Sendable {
  public let inserted: Int
  public let updated: Int
  public let ignored: Int
  public let deleted: Int

  public init(inserted: Int, updated: Int, ignored: Int, deleted: Int) {
    self.inserted = inserted
    self.updated = updated
    self.ignored = ignored
    self.deleted = deleted
  }
}

public struct SyncStateUpdate: Equatable, Sendable {
  public let feedKey: String
  public let lastSuccessfulSyncAt: Int64
  public let rateLimitAttempt: Int
  public let olderCursor: String?
  public let hasReachedEnd: Bool?

  public init(
    feedKey: String,
    lastSuccessfulSyncAt: Int64,
    rateLimitAttempt: Int,
    olderCursor: String? = nil,
    hasReachedEnd: Bool? = nil
  ) {
    self.feedKey = feedKey
    self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    self.rateLimitAttempt = rateLimitAttempt
    self.olderCursor = olderCursor
    self.hasReachedEnd = hasReachedEnd
  }
}

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

  @discardableResult
  public func applySync(
    stories: [Story],
    syncStateUpdate: SyncStateUpdate,
    retentionCutoff: Int64
  ) throws -> SyncReport {
    try databaseQueue.write { database in
      let report = try ingest(stories, in: database)
      var state =
        try SyncState.fetchOne(database, key: syncStateUpdate.feedKey)
        ?? SyncState(
          feedKey: syncStateUpdate.feedKey
        )
      state.lastSuccessfulSyncAt = syncStateUpdate.lastSuccessfulSyncAt
      state.retryNotBefore = nil
      state.rateLimitAttempt = syncStateUpdate.rateLimitAttempt
      if let olderCursor = syncStateUpdate.olderCursor {
        state.olderCursor = olderCursor
      }
      if let hasReachedEnd = syncStateUpdate.hasReachedEnd {
        state.hasReachedEnd = hasReachedEnd
      }
      try state.save(database)
      let deletedCount = try Story.filter(Story.Columns.publishedAt < retentionCutoff).deleteAll(
        database)
      return SyncReport(
        inserted: report.inserted,
        updated: report.updated,
        ignored: report.ignored,
        deleted: deletedCount
      )
    }
  }

  @discardableResult
  public func recordRateLimit(feedKey: String, retryNotBefore: Int64, attempt: Int) throws
    -> SyncState
  {
    try databaseQueue.write { database in
      var state = try SyncState.fetchOne(database, key: feedKey) ?? SyncState(feedKey: feedKey)
      state.retryNotBefore = retryNotBefore
      state.rateLimitAttempt = attempt
      try state.save(database)
      return state
    }
  }

  public func loadSyncState(feedKey: String) throws -> SyncState? {
    try databaseQueue.read { database in
      try SyncState.fetchOne(database, key: feedKey)
    }
  }

  @discardableResult
  public func save(_ stories: [Story]) throws -> StorySaveReport {
    try databaseQueue.write { database in
      try ingest(stories, in: database)
    }
  }

  private func ingest(_ stories: [Story], in database: Database) throws -> StorySaveReport {
    var inserted = 0
    var updated = 0
    var ignored = 0
    for incoming in stories {
      guard let existing = try Story.fetchOne(database, key: incoming.id) else {
        try incoming.insert(database)
        inserted += 1
        continue
      }
      if existing.contentEquals(incoming) {
        ignored += 1
      } else {
        var changed = incoming
        changed.isRead = existing.isRead
        try changed.update(database)
        updated += 1
      }
    }
    return StorySaveReport(inserted: inserted, updated: updated, ignored: ignored)
  }

  public func fetchStories(limit: Int? = nil) throws -> [Story] {
    try databaseQueue.read { database in
      if let limit {
        return try Story.order(Story.Columns.publishedAt.desc).limit(limit).fetchAll(database)
      }
      return try Story.order(Story.Columns.publishedAt.desc).fetchAll(database)
    }
  }

  public func fetchUnreadStories(limit: Int? = nil) throws -> [Story] {
    try databaseQueue.read { database in
      let request =
        Story
        .filter(Story.Columns.isRead == false)
        .order(Story.Columns.publishedAt.desc)
      if let limit {
        return try request.limit(limit).fetchAll(database)
      }
      return try request.fetchAll(database)
    }
  }

  public func fetchUnreadCount() throws -> Int {
    try databaseQueue.read { database in
      try Story.filter(Story.Columns.isRead == false).fetchCount(database)
    }
  }

  public func oldestStoryID() throws -> String? {
    try databaseQueue.read { database in
      try Story.order(Story.Columns.publishedAt.asc, Story.Columns.id.asc).fetchOne(database)?.id
    }
  }

  public func fetchStory(id: String) throws -> Story? {
    try databaseQueue.read { database in
      try Story.fetchOne(database, key: id)
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
      try Story.filter(Story.Columns.publishedAt < timestamp).deleteAll(database)
    }
  }

  public func deleteAllData() throws {
    try databaseQueue.write { database in
      _ = try Story.deleteAll(database)
      _ = try SyncState.deleteAll(database)
    }
  }

  @MainActor
  public func observeStories(
    limit: Int? = nil,
    onError: @escaping @Sendable (Error) -> Void,
    onChange: @escaping @Sendable ([Story]) -> Void
  ) -> AnyDatabaseCancellable {
    let observation = ValueObservation.tracking { database in
      if let limit {
        return try Story.order(Story.Columns.publishedAt.desc).limit(limit).fetchAll(database)
      }
      return try Story.order(Story.Columns.publishedAt.desc).fetchAll(database)
    }
    return observation.start(in: databaseQueue, onError: onError, onChange: onChange)
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
        table.column("link", .text).notNull().defaults(to: "")
        table.column("is_read", .boolean).notNull().defaults(to: false)
      }
      try database.create(indexOn: Story.databaseTableName, columns: ["published_at"])
      try database.create(indexOn: Story.databaseTableName, columns: ["subreddit"])
    }
    migrator.registerMigration("addSyncState") { database in
      try database.create(table: SyncState.databaseTableName) { table in
        table.column("feed_key", .text).primaryKey()
        table.column("last_successful_sync_at", .integer)
        table.column("retry_not_before", .integer)
        table.column("rate_limit_attempt", .integer).notNull().defaults(to: 0)
      }
    }
    migrator.registerMigration("addPaginationState") { database in
      try database.alter(table: SyncState.databaseTableName) { table in
        table.add(column: "older_cursor", .text)
        table.add(column: "has_reached_end", .boolean).notNull().defaults(to: false)
      }
    }
    return migrator
  }
}

extension Story {
  fileprivate func contentEquals(_ other: Story) -> Bool {
    title == other.title
      && contentBody == other.contentBody
      && author == other.author
      && subreddit == other.subreddit
      && publishedAt == other.publishedAt
  }
}
