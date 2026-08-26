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

public struct SourceSyncReport: Equatable, Sendable {
  public let sourceId: String
  public let inserted: Int
  public let updated: Int
  public let ignored: Int
  public let deleted: Int

  public init(
    sourceId: String,
    inserted: Int,
    updated: Int,
    ignored: Int,
    deleted: Int
  ) {
    self.sourceId = sourceId
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
  public let etag: String?
  public let lastModified: String?

  public init(
    feedKey: String,
    lastSuccessfulSyncAt: Int64,
    rateLimitAttempt: Int,
    olderCursor: String? = nil,
    hasReachedEnd: Bool? = nil,
    etag: String? = nil,
    lastModified: String? = nil
  ) {
    self.feedKey = feedKey
    self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    self.rateLimitAttempt = rateLimitAttempt
    self.olderCursor = olderCursor
    self.hasReachedEnd = hasReachedEnd
    self.etag = etag
    self.lastModified = lastModified
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

  public func makeFeedSourceStore() -> FeedSourceStore {
    FeedSourceStore(databaseQueue: databaseQueue)
  }

  @discardableResult
  public func applySync(
    stories: [Story],
    syncStateUpdate: SyncStateUpdate,
    retentionCutoff: Int64
  ) throws -> SyncReport {
    try databaseQueue.write { database in
      let report = try ingest(stories, in: database)
      let sourceId = Self.sourceId(for: syncStateUpdate.feedKey)
      _ = try Self.upsertState(database, update: syncStateUpdate)
      let deletedCount =
        try Story
        .filter(Story.Columns.publishedAt < retentionCutoff)
        .filter(Story.Columns.sourceId == sourceId)
        .deleteAll(database)
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

  public func fetchStories(
    sourceId: String? = nil,
    limit: Int? = nil
  ) throws -> [Story] {
    try databaseQueue.read { database in
      var request = Story.order(Story.Columns.publishedAt.desc)
      if let sourceId {
        request = request.filter(Story.Columns.sourceId == sourceId)
      }
      if let limit {
        return try request.limit(limit).fetchAll(database)
      }
      return try request.fetchAll(database)
    }
  }

  public func fetchStoriesFromEnabledSources(
    enabledSourceIds: Set<String>,
    limit: Int? = nil
  ) throws -> [Story] {
    try databaseQueue.read { database in
      var request = Story.order(Story.Columns.publishedAt.desc)
      if !enabledSourceIds.isEmpty {
        request = request.filter(enabledSourceIds.contains(Story.Columns.sourceId))
      }
      if let limit {
        return try request.limit(limit).fetchAll(database)
      }
      return try request.fetchAll(database)
    }
  }

  public func fetchUnreadStories(
    sourceId: String? = nil,
    limit: Int? = nil
  ) throws -> [Story] {
    try databaseQueue.read { database in
      var request =
        Story
        .filter(Story.Columns.isRead == false)
        .order(Story.Columns.publishedAt.desc)
      if let sourceId {
        request = request.filter(Story.Columns.sourceId == sourceId)
      }
      if let limit {
        return try request.limit(limit).fetchAll(database)
      }
      return try request.fetchAll(database)
    }
  }

  public func fetchUnreadCount(sourceId: String? = nil) throws -> Int {
    try databaseQueue.read { database in
      var request = Story.filter(Story.Columns.isRead == false)
      if let sourceId {
        request = request.filter(Story.Columns.sourceId == sourceId)
      }
      return try request.fetchCount(database)
    }
  }

  public func oldestStoryID(sourceId: String) throws -> String? {
    try databaseQueue.read { database in
      try Story
        .filter(Story.Columns.sourceId == sourceId)
        .order(Story.Columns.publishedAt.asc, Story.Columns.id.asc)
        .fetchOne(database)?.id
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
  public func markRead(ids: [String], isRead: Bool = true) throws -> Int {
    guard !ids.isEmpty else { return 0 }
    return try databaseQueue.write { database in
      try Story
        .filter(ids.contains(Story.Columns.id))
        .filter(Story.Columns.isRead == !isRead)
        .updateAll(database, Story.Columns.isRead.set(to: isRead))
    }
  }

  @discardableResult
  public func deletePublished(before timestamp: Int64, sourceId: String? = nil) throws -> Int {
    try databaseQueue.write { database in
      var request = Story.filter(Story.Columns.publishedAt < timestamp)
      if let sourceId {
        request = request.filter(Story.Columns.sourceId == sourceId)
      }
      return try request.deleteAll(database)
    }
  }

  @discardableResult
  public func deleteSourceStories(sourceId: String) throws -> Int {
    try databaseQueue.write { database in
      try Story
        .filter(Story.Columns.sourceId == sourceId)
        .deleteAll(database)
    }
  }

  @discardableResult
  public func capStoriesPerSource(sourceId: String, maximum: Int) throws -> Int {
    try databaseQueue.write { database in
      let total =
        try Story
        .filter(Story.Columns.sourceId == sourceId)
        .fetchCount(database)
      guard total > maximum else { return 0 }
      let oldestIds =
        try Story
        .filter(Story.Columns.sourceId == sourceId)
        .order(Story.Columns.publishedAt.asc, Story.Columns.id.asc)
        .limit(total - maximum)
        .fetchAll(database)
        .map(\.id)
      guard !oldestIds.isEmpty else { return 0 }
      let placeholders = String(repeating: "?,", count: oldestIds.count).dropLast()
      let sql =
        "DELETE FROM stories WHERE source_id = ? AND id IN (\(placeholders))"
      var arguments: [DatabaseValueConvertible] = [sourceId]
      arguments.append(contentsOf: oldestIds)
      try database.execute(sql: sql, arguments: StatementArguments(arguments))
      return database.changesCount
    }
  }

  public func deleteAllData() throws {
    try databaseQueue.write { database in
      _ = try Story.deleteAll(database)
      _ = try SyncState.deleteAll(database)
      _ = try FeedSourceRecord.deleteAll(database)
    }
  }

  public func deleteAllData(preservingFeedSources: Bool) throws {
    try databaseQueue.write { database in
      _ = try Story.deleteAll(database)
      _ = try SyncState.deleteAll(database)
      if !preservingFeedSources {
        _ = try FeedSourceRecord.deleteAll(database)
      }
    }
  }

  public func deleteSource(sourceId: String) throws {
    try databaseQueue.write { database in
      _ =
        try Story
        .filter(Story.Columns.sourceId == sourceId)
        .deleteAll(database)
      try SyncState
        .filter(SyncState.Columns.feedKey == Self.feedKey(for: sourceId))
        .deleteAll(database)
      try FeedSourceRecord.deleteOne(database, key: sourceId)
    }
  }

  @MainActor
  public func observeStories(
    sourceId: String? = nil,
    onError: @escaping @Sendable (Error) -> Void,
    onChange: @escaping @Sendable ([Story]) -> Void
  ) -> AnyDatabaseCancellable {
    let observation = ValueObservation.tracking { database -> [Story] in
      var request = Story.order(Story.Columns.publishedAt.desc)
      if let sourceId {
        request = request.filter(Story.Columns.sourceId == sourceId)
      }
      return try request.fetchAll(database)
    }
    return observation.start(in: databaseQueue, onError: onError, onChange: onChange)
  }

  @MainActor
  public func observeEnabledStories(
    enabledSourceIds: Set<String>,
    onError: @escaping @Sendable (Error) -> Void,
    onChange: @escaping @Sendable ([Story]) -> Void
  ) -> AnyDatabaseCancellable {
    let observation = ValueObservation.tracking { database -> [Story] in
      var request = Story.order(Story.Columns.publishedAt.desc)
      if !enabledSourceIds.isEmpty {
        request = request.filter(enabledSourceIds.contains(Story.Columns.sourceId))
      }
      return try request.fetchAll(database)
    }
    return observation.start(in: databaseQueue, onError: onError, onChange: onChange)
  }

  public static func feedKey(for sourceId: String) -> String {
    "source/\(sourceId)"
  }

  private static func upsertState(
    _ database: Database,
    update: SyncStateUpdate
  ) throws -> SyncState {
    var state =
      try SyncState.fetchOne(database, key: update.feedKey)
      ?? SyncState(feedKey: update.feedKey)
    state.lastSuccessfulSyncAt = update.lastSuccessfulSyncAt
    state.retryNotBefore = nil
    state.rateLimitAttempt = update.rateLimitAttempt
    if let olderCursor = update.olderCursor {
      state.olderCursor = olderCursor
    }
    if let hasReachedEnd = update.hasReachedEnd {
      state.hasReachedEnd = hasReachedEnd
    }
    if let etag = update.etag {
      state.etag = etag
    } else if state.lastSuccessfulSyncAt == nil {
      state.etag = nil
    }
    if let lastModified = update.lastModified {
      state.lastModified = lastModified
    } else if state.lastSuccessfulSyncAt == nil {
      state.lastModified = nil
    }
    state.lastError = nil
    state.lastErrorAt = nil
    try state.save(database)
    return state
  }

  public func recordSourceError(
    sourceId: String,
    error: String,
    at timestamp: Int64
  ) throws {
    let feedKey = Self.feedKey(for: sourceId)
    try databaseQueue.write { database in
      var state = try SyncState.fetchOne(database, key: feedKey) ?? SyncState(feedKey: feedKey)
      state.lastError = error
      state.lastErrorAt = timestamp
      try state.save(database)
    }
  }

  public func recordSourceSuccess(sourceId: String, at timestamp: Int64) throws {
    let feedKey = Self.feedKey(for: sourceId)
    try databaseQueue.write { database in
      var state = try SyncState.fetchOne(database, key: feedKey) ?? SyncState(feedKey: feedKey)
      state.lastError = nil
      state.lastErrorAt = nil
      state.lastSuccessfulSyncAt = timestamp
      try state.save(database)
    }
  }

  public func saveFeedSourceRecord(_ source: FeedSourceRecord) throws {
    try databaseQueue.write { database in
      try source.save(database)
    }
  }

  public func fetchFeedSourceRecord(id: String) throws -> FeedSourceRecord? {
    try databaseQueue.read { database in
      try FeedSourceRecord.fetchOne(database, key: id)
    }
  }

  public func fetchAllFeedSources() throws -> [FeedSourceRecord] {
    try databaseQueue.read { database in
      try FeedSourceRecord
        .order(FeedSourceRecord.Columns.sortOrder.asc, FeedSourceRecord.Columns.createdAt.asc)
        .fetchAll(database)
    }
  }

  public static func sourceId(for feedKey: String) -> String {
    if feedKey.hasPrefix("source/") {
      return String(feedKey.dropFirst("source/".count))
    }
    return FeedSourceRecord.builtInRedditID()
  }

  public static func makeMigrator() -> DatabaseMigrator {
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
    migrator.registerMigration("addFeedSources") { database in
      try database.create(table: FeedSourceRecord.databaseTableName) { table in
        table.column("id", .text).primaryKey()
        table.column("kind", .text).notNull()
        table.column("title", .text).notNull()
        table.column("url", .text).notNull().defaults(to: "")
        table.column("is_enabled", .boolean).notNull().defaults(to: true)
        table.column(
          "refresh_interval_seconds",
          .integer
        ).notNull().defaults(to: RefreshInterval.default.rawValue)
        table.column("sort_order", .integer).notNull().defaults(to: 0)
        table.column("created_at", .integer).notNull().defaults(to: 0)
        table.column("updated_at", .integer).notNull().defaults(to: 0)
      }
      try database.alter(table: SyncState.databaseTableName) { table in
        table.add(column: "etag", .text)
        table.add(column: "last_modified", .text)
        table.add(column: "last_error", .text)
        table.add(column: "last_error_at", .integer)
      }
    }
    migrator.registerMigration("addStorySourceId") { database in
      try database.alter(table: Story.databaseTableName) { table in
        table.add(column: "source_id", .text).notNull().defaults(
          to: FeedSourceRecord.builtInRedditID())
      }
      try database.create(
        indexOn: Story.databaseTableName, columns: ["source_id", "published_at"]
      )
      try FeedSourceRecord(
        id: FeedSourceRecord.builtInRedditID(),
        kind: .reddit,
        title: "Reddit",
        url: "https://www.reddit.com/.rss",
        isEnabled: true,
        refreshInterval: .thirtyMinutes,
        sortOrder: -1
      ).save(database)
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
      && link == other.link
      && sourceId == other.sourceId
  }
}
