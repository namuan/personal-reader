import Foundation
import GRDB

public struct FeedSourceStore: Sendable {
  private let databaseQueue: DatabaseQueue

  public init(databaseURL: URL) throws {
    let databaseQueue = try DatabaseQueue(path: databaseURL.path)
    try StoryRepository.applyMigrations(to: databaseQueue)
    self.databaseQueue = databaseQueue
  }

  internal init(databaseQueue: DatabaseQueue) {
    self.databaseQueue = databaseQueue
  }

  public static func inMemory() throws -> FeedSourceStore {
    let queue = try DatabaseQueue()
    try StoryRepository.applyMigrations(to: queue)
    return FeedSourceStore(databaseQueue: queue)
  }

  public func fetchAll() throws -> [FeedSourceRecord] {
    try databaseQueue.read { database in
      try FeedSourceRecord
        .order(FeedSourceRecord.Columns.sortOrder.asc, FeedSourceRecord.Columns.createdAt.asc)
        .fetchAll(database)
    }
  }

  public func fetchEnabled() throws -> [FeedSourceRecord] {
    try databaseQueue.read { database in
      try FeedSourceRecord
        .filter(FeedSourceRecord.Columns.isEnabled == true)
        .order(FeedSourceRecord.Columns.sortOrder.asc, FeedSourceRecord.Columns.createdAt.asc)
        .fetchAll(database)
    }
  }

  public func fetch(id: String) throws -> FeedSourceRecord? {
    try databaseQueue.read { database in
      try FeedSourceRecord.fetchOne(database, key: id)
    }
  }

  public func save(_ source: FeedSourceRecord) throws {
    try databaseQueue.write { database in
      try source.save(database)
    }
  }

  public func delete(id: String) throws {
    _ = try databaseQueue.write { database in
      try FeedSourceRecord.deleteOne(database, key: id)
    }
  }

  public func setEnabled(id: String, enabled: Bool) throws {
    try databaseQueue.write { database in
      guard var source = try FeedSourceRecord.fetchOne(database, key: id) else { return }
      source.isEnabled = enabled
      source.updatedAt = Int64(Date().timeIntervalSince1970)
      try source.update(database)
    }
  }

  public func updateInterval(id: String, interval: RefreshInterval) throws {
    try databaseQueue.write { database in
      guard var source = try FeedSourceRecord.fetchOne(database, key: id) else { return }
      source.refreshInterval = interval
      source.updatedAt = Int64(Date().timeIntervalSince1970)
      try source.update(database)
    }
  }

  public func updateTitle(id: String, title: String) throws {
    try databaseQueue.write { database in
      guard var source = try FeedSourceRecord.fetchOne(database, key: id) else { return }
      source.title = title
      source.updatedAt = Int64(Date().timeIntervalSince1970)
      try source.update(database)
    }
  }

  public func nextSortOrder() throws -> Int {
    try databaseQueue.read { database in
      let maxOrder =
        try Int.fetchOne(
          database,
          sql: "SELECT COALESCE(MAX(sort_order), -1) FROM feed_sources"
        ) ?? -1
      return maxOrder + 1
    }
  }
}

extension StoryRepository {
  public static func applyMigrations(to queue: DatabaseQueue) throws {
    try makeMigrator().migrate(queue)
  }
}
