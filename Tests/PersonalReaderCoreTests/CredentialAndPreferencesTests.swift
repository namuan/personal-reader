import XCTest

@testable import PersonalReaderCore

final class CredentialAndPreferencesTests: XCTestCase {
  func testInMemoryTokenStoreRoundTrip() throws {
    let store = InMemoryTokenStore()
    XCTAssertNil(store.load())

    try store.save("secret-token")
    XCTAssertEqual(store.load(), "secret-token")

    store.delete()
    XCTAssertNil(store.load())
  }

  func testKeychainTokenStoreReplacesExistingValue() throws {
    let service = "test.PersonalReader.\(UUID().uuidString)"
    let store = KeychainTokenStore(service: service, account: "rss-token")
    defer { store.delete() }

    try store.save("first")
    XCTAssertEqual(store.load(), "first")

    try store.save("second")
    XCTAssertEqual(store.load(), "second")

    store.delete()
    XCTAssertNil(store.load())
  }

  func testPreferencesRoundTrip() {
    let suiteName = "test.Preferences.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PreferencesStore(defaults: defaults)
    XCTAssertTrue(store.preferences.username.isEmpty)

    var preferences = UserPreferences(
      username: "reader",
      subreddits: ["a", "b"],
      feedMode: .privateListing,
      privateListing: .frontPage,
      frontPageSort: .rising,
      setupComplete: true
    )
    store.preferences = preferences

    let reloaded = PreferencesStore(defaults: defaults)
    XCTAssertEqual(reloaded.preferences, preferences)

    preferences.setupComplete = false
    reloaded.preferences = preferences
    XCTAssertEqual(PreferencesStore(defaults: defaults).preferences, preferences)
  }

  func testPreferencesClearRemovesEverything() {
    let suiteName = "test.Preferences.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PreferencesStore(defaults: defaults)
    store.preferences = UserPreferences(username: "reader", subreddits: ["a"], setupComplete: true)

    store.clear()

    XCTAssertEqual(store.preferences, UserPreferences())
  }
}
