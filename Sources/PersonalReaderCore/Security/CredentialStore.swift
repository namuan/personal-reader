import Foundation
import Security

public protocol TokenStoring: Sendable {
  func save(_ token: String) throws
  func load() -> String?
  func delete()
}

public struct KeychainTokenStore: TokenStoring {
  private let service: String
  private let account: String

  public init(
    service: String = "com.github.namuan.personalreader.rss-token",
    account: String = "rss-token"
  ) {
    self.service = service
    self.account = account
  }

  public func save(_ token: String) throws {
    guard let data = token.data(using: .utf8) else {
      throw CredentialError.invalidData
    }
    var query = baseQuery
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] =
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let status = SecItemUpdate(
      baseQuery as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if status == errSecItemNotFound {
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw CredentialError.keychainFailure(addStatus)
      }
    } else if status != errSecSuccess {
      throw CredentialError.keychainFailure(status)
    }
  }

  public func load() -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  public func delete() {
    SecItemDelete(baseQuery as CFDictionary)
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

public final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var token: String?

  public init() {}

  public func save(_ token: String) throws {
    lock.lock()
    defer { lock.unlock() }
    self.token = token
  }

  public func load() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return token
  }

  public func delete() {
    lock.lock()
    defer { lock.unlock() }
    token = nil
  }
}

public enum CredentialError: Error, Equatable {
  case invalidData
  case keychainFailure(OSStatus)
}
