import Foundation

public enum FeedTransferError: Error, Equatable, Sendable {
  case unreadable
  case invalidFormat
  case unsupportedVersion(Int)
}

public struct FeedTransferItem: Codable, Equatable, Sendable, Identifiable {
  public var id: String { url }

  public var kind: FeedSourceKind
  public var url: String
  public var title: String
  public var isEnabled: Bool
  public var refreshIntervalSeconds: Int64
  public var sortOrder: Int

  public init(
    kind: FeedSourceKind = .rss,
    url: String,
    title: String = "",
    isEnabled: Bool = true,
    refreshIntervalSeconds: Int64 = RefreshInterval.default.rawValue,
    sortOrder: Int = 0
  ) {
    self.kind = kind
    self.url = url
    self.title = title
    self.isEnabled = isEnabled
    self.refreshIntervalSeconds = refreshIntervalSeconds
    self.sortOrder = sortOrder
  }

  public init(record: FeedSourceRecord) {
    self.init(
      kind: record.kind,
      url: record.url,
      title: record.title,
      isEnabled: record.isEnabled,
      refreshIntervalSeconds: record.refreshIntervalSeconds,
      sortOrder: record.sortOrder
    )
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    kind = try container.decodeIfPresent(FeedSourceKind.self, forKey: .kind) ?? .rss
    url = try container.decode(String.self, forKey: .url)
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    refreshIntervalSeconds =
      try container.decodeIfPresent(Int64.self, forKey: .refreshIntervalSeconds)
      ?? RefreshInterval.default.rawValue
    sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
  }

  public var refreshInterval: RefreshInterval {
    RefreshInterval(rawValue: refreshIntervalSeconds) ?? .default
  }

  public func makeRecord(sortOrder: Int) -> FeedSourceRecord {
    FeedSourceRecord(
      kind: kind,
      title: title.isEmpty ? (URL(string: url)?.host ?? url) : title,
      url: url,
      isEnabled: isEnabled,
      refreshInterval: refreshInterval,
      sortOrder: sortOrder
    )
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case url
    case title
    case isEnabled = "is_enabled"
    case refreshIntervalSeconds = "refresh_interval_seconds"
    case sortOrder = "sort_order"
  }
}

public struct FeedTransferPackage: Codable, Equatable, Sendable {
  public static let formatIdentifier = "personal-reader-feeds"
  public static let version = 1

  public var format: String
  public var version: Int
  public var feeds: [FeedTransferItem]

  public init(format: String, version: Int, feeds: [FeedTransferItem]) {
    self.format = format
    self.version = version
    self.feeds = feeds
  }

  public static func exporting(records: [FeedSourceRecord]) -> FeedTransferPackage {
    FeedTransferPackage(
      format: formatIdentifier,
      version: version,
      feeds: records.filter { $0.kind == .rss }.map(FeedTransferItem.init(record:))
    )
  }

  public static func decode(from data: Data) throws -> [FeedTransferItem] {
    guard !data.isEmpty else { throw FeedTransferError.unreadable }
    let package: FeedTransferPackage
    do {
      package = try JSONDecoder().decode(FeedTransferPackage.self, from: data)
    } catch {
      throw FeedTransferError.unreadable
    }
    guard package.format == formatIdentifier else { throw FeedTransferError.invalidFormat }
    guard package.version <= version else {
      throw FeedTransferError.unsupportedVersion(package.version)
    }
    return package.feeds
  }
}

public enum FeedImportIssue: Equatable, Sendable {
  case unsupportedKind
  case invalidURL
  case insecureURL
  case duplicate

  public var message: String {
    switch self {
    case .unsupportedKind: return "Not an RSS feed"
    case .invalidURL: return "Not a valid URL"
    case .insecureURL: return "Must use https://"
    case .duplicate: return "Already in your library"
    }
  }
}

public struct FeedImportRejection: Equatable, Sendable, Identifiable {
  public var id: String { item.url }
  public let item: FeedTransferItem
  public let issue: FeedImportIssue

  public init(item: FeedTransferItem, issue: FeedImportIssue) {
    self.item = item
    self.issue = issue
  }
}

public struct FeedImportPlan: Equatable, Sendable {
  public let accepted: [FeedTransferItem]
  public let rejected: [FeedImportRejection]

  public init(accepted: [FeedTransferItem], rejected: [FeedImportRejection]) {
    self.accepted = accepted
    self.rejected = rejected
  }

  public var addedCount: Int { accepted.count }
  public var rejectedCount: Int { rejected.count }
}

public struct FeedImportPlanner {
  public static func plan(
    items: [FeedTransferItem],
    existingURLs: Set<String>
  ) -> FeedImportPlan {
    var accepted: [FeedTransferItem] = []
    var rejected: [FeedImportRejection] = []
    var seen = Set<String>()
    let existing = Set(existingURLs.map { normalize($0) })

    for item in items {
      guard item.kind == .rss else {
        rejected.append(FeedImportRejection(item: item, issue: .unsupportedKind))
        continue
      }
      guard let normalizedURL = normalize(item.url) else {
        rejected.append(FeedImportRejection(item: item, issue: .invalidURL))
        continue
      }
      guard normalizedURL.hasPrefix("https://") else {
        rejected.append(FeedImportRejection(item: item, issue: .insecureURL))
        continue
      }
      if existing.contains(normalizedURL) || seen.contains(normalizedURL) {
        rejected.append(FeedImportRejection(item: item, issue: .duplicate))
        continue
      }
      seen.insert(normalizedURL)
      var acceptedItem = item
      acceptedItem.url = normalizedURL
      accepted.append(acceptedItem)
    }
    return FeedImportPlan(accepted: accepted, rejected: rejected)
  }

  static func normalize(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard
      let components = URLComponents(string: trimmed),
      let scheme = components.scheme?.lowercased(),
      let host = components.host?.lowercased(),
      !host.isEmpty
    else { return nil }
    let port = components.port.map { $0 == 80 || $0 == 443 ? "" : ":\($0)" } ?? ""
    var path = components.path
    if path == "/" {
      path = ""
    } else if path.hasSuffix("/") {
      path = String(path.dropLast())
    }
    let query = components.query.map { "?\($0)" } ?? ""
    return "\(scheme)://\(host)\(port)\(path)\(query)"
  }
}
