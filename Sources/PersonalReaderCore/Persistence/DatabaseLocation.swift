import Foundation

public enum DatabaseLocation {
  public static func defaultURL(
    subdirectory: String = "PersonalReader",
    excludingFromBackup: Bool = true
  ) throws -> URL {
    let fileManager = FileManager.default
    let appSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = appSupport.appending(path: subdirectory, directoryHint: .isDirectory)
    if !fileManager.fileExists(atPath: directory.path) {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    var isExcluded: AnyObject?
    try? (directory as NSURL).getResourceValue(&isExcluded, forKey: .isExcludedFromBackupKey)
    if excludingFromBackup, isExcluded as? Bool != true {
      try? (directory as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    }
    return directory.appending(path: "personal-reader.sqlite", directoryHint: .notDirectory)
  }
}
