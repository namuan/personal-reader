# Personal Reader — implementation and personal-device deployment plan

## 1. Goal

Build a private, read-only iPhone application that downloads text-focused Reddit posts from an authenticated private RSS feed, stores them locally, supports offline reading and read/unread tracking, and can be installed on the owner's personal iPhone.

The first release targets iOS 17 or later and uses Swift 6, SwiftUI, Swift Package Manager, GRDB, URLSession, XMLParser, Keychain, and BGTaskScheduler.

## 2. Release scope

### Included in version 1

- First-run setup for Reddit username, private RSS token, selected subreddits, and descriptive User-Agent.
- Secure token storage in Keychain.
- Downloading and parsing Reddit RSS 2.0 feeds.
- Offline-first story list backed by GRDB/SQLite.
- Story detail reading view with sanitized HTML rendering.
- Read/unread state and unread filtering.
- Pull-to-refresh and visible sync status.
- A minimum 30-minute automatic-sync interval.
- Exponential backoff after HTTP 429 responses.
- A 50-story ingestion cap per feed request.
- Automatic removal of posts older than 14 days.
- Settings for updating credentials and subreddits.
- Light mode, dark mode, Dynamic Type, VoiceOver labels, and reduced-motion support.
- Installation and signing on the owner's iPhone.

### Excluded from version 1

- Posting, voting, commenting, messaging, or Reddit OAuth.
- Multiple Reddit accounts.
- Comments and media galleries.
- Push notifications.
- Cross-device sync.
- Public App Store release.
- Analytics, advertising, or third-party tracking.

## 3. Delivery constraints and decisions

- Swift Package Manager remains the dependency and core-module build system.
- `PersonalReaderCore` contains models, persistence, parsing, networking, and synchronization logic.
- A thin Xcode iOS application target is required for the app bundle, resources, entitlements, code signing, and installation. It will consume `PersonalReaderCore` as a local Swift package. Command-line SwiftPM alone cannot produce and sign an iOS application bundle.
- GRDB 7.x is the only database layer. The resolved version is pinned in `Package.resolved`.
- The deployment target is iOS 17 to allow Observation, modern SwiftUI navigation, and current background-task APIs.
- The interface uses a calm, editorial, reading-first design built from native SwiftUI controls and semantic colors and typography.
- The private RSS endpoint must be validated before significant UI work. If Reddit no longer provides or permits the private feed, development stops until an approved data source is selected; the app must not bypass access controls.

## 4. Current implementation status

The repository already contains:

- `Package.swift` with the `PersonalReaderCore` library and GRDB dependency.
- GRDB `Story` model, migration, repository queries, read-state preservation, cleanup, and `ValueObservation` support.
- Private-feed URL configuration and subreddit validation.
- URLSession feed client with custom headers and explicit HTTP 429 handling.
- RSS 2.0 parser for `item`, `title`, `guid`, `link`, `dc:creator`, `category`, `pubDate`, `description`, and `content:encoded`.
- Initial unsafe-HTML removal.
- Sync actor with throttling, a 50-item cap, cleanup, and exponential backoff.
- Seven passing unit tests.
- A Makefile for resolving, building, formatting, linting, testing, and opening the package.

The repository does not yet contain the signed iOS host application, secure settings, durable sync state, production UI, background-task integration, app assets, or device validation.

## 5. Target architecture

```text
PersonalReaderApp
├── SwiftUI application and scenes
├── AppEnvironment dependency composition
├── @MainActor @Observable application state
├── Story list, reader, setup, and settings views
├── Keychain credential store
├── Background task registration
└── Local PersonalReaderCore package
    ├── Models
    ├── Networking
    ├── Parsing and sanitization
    ├── GRDB persistence and observations
    └── Sync orchestration
```

Runtime flow:

```text
Keychain and app settings
        ↓
FeedConfiguration
        ↓
URLSession with redacted diagnostics
        ↓
RSS 2.0 parser and HTML sanitizer
        ↓
GRDB transaction and cleanup
        ↓
ValueObservation
        ↓
@MainActor application state
        ↓
SwiftUI list and reader views
```

## 6. Data and security design

### GRDB tables

`stories`:

- `id TEXT PRIMARY KEY`
- `title TEXT NOT NULL`
- `content_body TEXT NOT NULL`
- `author TEXT NOT NULL`
- `subreddit TEXT NOT NULL`
- `published_at INTEGER NOT NULL`
- `is_read INTEGER NOT NULL DEFAULT 0`
- Indexes on `published_at` and `subreddit`.

`sync_state` migration:

- `feed_key TEXT PRIMARY KEY`
- `last_successful_sync_at INTEGER`
- `retry_not_before INTEGER`
- `rate_limit_attempt INTEGER NOT NULL DEFAULT 0`

Sync metadata must be durable so relaunching the application cannot bypass throttling or 429 backoff.

### Credentials and preferences

- Store the RSS token in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so approved background refresh can access it after the first device unlock.
- Store username, subreddits, and non-secret UI preferences in UserDefaults.
- Never put a live token in source files, `Config.plist`, test fixtures, screenshots, logs, analytics, crash messages, or Git history.
- Redact `feed` and `user` query values from all diagnostics.
- Provide a “Clear credentials and local data” action.

### Network policy

- Build URLs with URLComponents using `/r/{SUB_A}+{SUB_B}/.rss` and private-feed query items.
- Validate whether `/new/.rss` is supported by the live private feed before selecting it as the production route.
- Set `User-Agent: ios:PersonalStoryReader:{version} (by /u/{username})`.
- Accept RSS/XML content types.
- Let URLSession set the `Host` header.
- Disable response caching for tokenized feed requests and never print full request URLs.
- Treat 200–299 as success, 401/403 as invalid credentials or unavailable feed, 429 as rate limiting, and other status codes as recoverable sync errors.
- Respect `Retry-After` when present; otherwise use 1, 2, 4, 8, 16, and 30-minute delays capped at 30 minutes.

## 7. Implementation phases

### Phase 1 — Validate the live feed

Tasks:

- Obtain a fresh private RSS token without adding it to the repository.
- Test the exact feed URL outside the app with the intended User-Agent.
- Save a redacted representative RSS response as a test fixture.
- Confirm item names, namespace behavior, post identifiers, subreddit category, date format, HTML structure, ordering, and maximum item count.
- Confirm behavior for invalid credentials and rapid repeat requests.

Exit criteria:

- A real redacted fixture parses into expected stories.
- The selected endpoint and ordering are documented.
- No credential appears in source control or terminal output captured by tests.

### Phase 2 — Create the iOS host and signing baseline

Tasks:

- Add a minimal `PersonalReaderApp.xcodeproj` with an iOS SwiftUI application target.
- Set iOS 17 as the deployment target and Swift 6 as the language mode.
- Add `PersonalReaderCore` as a local package dependency.
- Choose a unique reverse-DNS bundle identifier.
- Add development and release build configurations.
- Select the owner's Apple development team and automatic signing.
- Add app icon, accent color, launch presentation, display name, version, and build number.
- Build and launch an empty signed shell on the physical iPhone immediately.

Exit criteria:

- The app compiles for simulator and physical device.
- The package is linked through SwiftPM.
- The signed shell launches on the owner's iPhone.

### Phase 3 — Complete persistence and durable sync state

Tasks:

- Place the SQLite database in Application Support and exclude it from iCloud backup if appropriate for reproducible feed data.
- Add the `sync_state` migration and repository APIs.
- Make feed upserts preserve `is_read`.
- Define transactions so story ingestion, sync-state updates, and cleanup are consistent.
- Add queries for all stories, unread stories, unread count, and story by ID.
- Add deletion APIs for settings reset.
- Ensure `ValueObservation` cancellation follows view/application lifetimes.

Exit criteria:

- Migration tests pass from an empty and previous-version database.
- Relaunch preserves stories, read state, last sync, and rate-limit state.
- Cleanup removes only expired rows.

### Phase 4 — Implement secure setup and settings

Tasks:

- Add a small Keychain credential store with save, load, replace, and delete operations.
- Add a preferences store for username, subreddits, and setup completion.
- Build first-run setup with validation and a “Test connection” action.
- Require at least one valid subreddit and a non-empty token and username.
- Construct the User-Agent from app version and username rather than asking the user to type it.
- Build settings for editing subreddits, replacing the token, testing the connection, viewing the last sync, and clearing all data.
- Ensure secret text fields do not expose the token through normal UI or screenshots after setup.

Exit criteria:

- Credentials survive relaunch and are absent from UserDefaults and the database.
- Invalid settings produce specific, actionable errors.
- Clearing data removes Keychain credentials, preferences, sync state, and stories.

### Phase 5 — Harden networking, parsing, and sanitization

Tasks:

- Add an injectable URLSession/URLProtocol test seam.
- Add typed errors for offline, timeout, invalid credentials, rate limiting, malformed feeds, and server failures.
- Parse all observed live-feed variants without assuming one namespace spelling.
- Handle missing optional author, category, content, and date fields safely.
- Prefer `content:encoded`, then `description` as fallback.
- Derive `t3_` IDs from Reddit links where needed and reject entries without stable IDs.
- Replace the initial sanitizer with a tested allowlist-oriented sanitizer or a non-executing native HTML conversion path.
- Remove scripts, styles, iframes, event attributes, and JavaScript URLs.
- Add fixture tests for HTML entities, CDATA, Unicode, malformed entries, very long stories, and empty feeds.

Exit criteria:

- Parser and client tests cover success and every user-visible error category.
- No fixture can execute active content.
- One malformed item does not discard the rest of a valid feed.

### Phase 6 — Finish synchronization orchestration

Tasks:

- Move throttle and backoff state from actor memory into `sync_state`.
- Prevent concurrent syncs from pull-to-refresh, launch, foregrounding, and background refresh.
- Make cancellation propagate through URLSession and parsing work.
- Sync on first valid setup, foreground entry when eligible, manual refresh when eligible, and approved background refresh.
- Keep manual refresh subject to active 429 backoff; expose when retry becomes available.
- Store at most 50 entries from a request and remove entries older than 14 days.
- Report inserted, updated, ignored, and deleted counts for diagnostics without exposing credentials.

Exit criteria:

- Concurrent triggers produce one network request.
- Relaunch cannot bypass the minimum interval or rate-limit backoff.
- Airplane mode leaves cached stories readable and reports a non-destructive error.

### Phase 7 — Build SwiftUI state and navigation

Tasks:

- Add a dependency-composition root that creates the database, repositories, clients, parser, credential store, and sync service once.
- Use `@MainActor @Observable` state for UI-facing application and screen state.
- Keep URLSession, XML parsing, and GRDB work outside the main actor.
- Use `NavigationStack` with typed destinations.
- Model setup, ready, refreshing, empty, offline-with-cache, and blocking-error states explicitly.
- Use `.task` and `.refreshable` so work is cancelled with view lifetime.

Exit criteria:

- UI state transitions have unit tests.
- No database or network operation blocks scrolling or navigation.
- Relaunch routes correctly to setup or the story list.

### Phase 8 — Build the reading experience

Screens:

1. Setup
   - Brief explanation of private feeds and token handling.
   - Username, token, and subreddit fields.
   - Test connection and save actions.

2. Story list
   - Editorial, reading-first rows with title, subreddit, author, date, and unread marker.
   - All/unread filter.
   - Pull-to-refresh, last-sync status, offline indication, empty state, and settings access.
   - Stable story IDs and native list behavior.

3. Story detail
   - Title, metadata, sanitized body, and optional “Open original” action.
   - Mark read when the story is intentionally opened.
   - Comfortable line length, selectable text, Dynamic Type, and link handling.

4. Settings
   - Feed configuration, connection test, data retention summary, last sync, app version, and destructive reset.

Implementation requirements:

- Use semantic typography and colors, SF Symbols, and native controls.
- Support light/dark appearance and all Dynamic Type sizes.
- Do not rely on color alone for unread status.
- Respect reduced motion and increased contrast.
- Provide VoiceOver labels, values, and logical focus order.
- Use String Catalogs even if version 1 ships only in English.

Exit criteria:

- Every state is usable on the smallest supported iPhone and at accessibility text sizes.
- Cached content is fully navigable without a network connection.
- VoiceOver can complete setup, refresh, select a story, and return to the list.

### Phase 9 — Integrate safe HTML rendering and links

Tasks:

- Render sanitized HTML through a native attributed-text path where possible.
- Keep rendering JavaScript-free.
- If WKWebView is required for feed compatibility, disable JavaScript, block arbitrary navigation, use a non-persistent data store, size it without scroll conflicts, and open approved external links through the system browser.
- Apply app typography and light/dark colors without modifying stored source content.
- Cache converted presentation content only if profiling shows a measurable need.

Exit criteria:

- Long stories scroll smoothly.
- HTML cannot execute scripts or navigate silently.
- Links require explicit user action and open outside the private feed request context.

### Phase 10 — Add background refresh

Tasks:

- Register a unique `BGAppRefreshTask` identifier before application launch completes.
- Add the identifier to `BGTaskSchedulerPermittedIdentifiers`.
- Enable the Background fetch capability only if background refresh remains in scope after device testing.
- Schedule the next eligible refresh after successful setup and after each task completes.
- Respect the durable 30-minute throttle and backoff state.
- Set an expiration handler that cancels in-flight work.
- Mark every background task complete with the correct success value.
- Treat scheduling as opportunistic because iOS does not guarantee a 30-minute cadence.

Exit criteria:

- Background tasks can be triggered through Xcode diagnostics on the physical device.
- Expiration cancels cleanly.
- The app remains correct when iOS never grants background execution.

### Phase 11 — Privacy, resilience, and release hardening

Tasks:

- Add and audit `PrivacyInfo.xcprivacy`, including required-reason API declarations used by the app and dependencies.
- Verify that the app collects no analytics and transmits data only to the configured Reddit endpoint and user-opened links.
- Add a short in-app privacy explanation.
- Audit logs and error descriptions for URL-query secrets.
- Test database corruption handling and provide a local-data reset path.
- Handle unavailable Keychain, low storage, loss of network, app termination during sync, and feed schema changes.
- Run static analysis and build with warnings treated as failures where practical.
- Check licenses and notices for GRDB and any later dependency.

Exit criteria:

- No token appears in logs, backups intended for feed cache, screenshots, or persisted non-Keychain storage.
- There are no build warnings, crashes, or high-priority accessibility findings.
- Dependency licenses and privacy manifests are accounted for.

### Phase 12 — Test the release candidate

Automated checks:

- `make check` passes.
- Unit tests cover configuration, Keychain behavior through an abstraction, parser fixtures, sanitizer rules, migrations, repository queries, throttling, backoff, cancellation, and state transitions.
- URLProtocol integration tests cover HTTP 200, 401, 403, 429 with and without Retry-After, 500, timeout, and offline responses.
- UI tests cover first-run setup, cached launch, refresh, unread filtering, opening a story, settings changes, and full reset.

Physical-device checks:

- Fresh install and upgrade from the previous database schema.
- Wi-Fi, cellular, airplane mode, and intermittent connectivity.
- App backgrounding, termination, relaunch, and device restart.
- Light/dark mode, portrait/landscape, smallest/largest Dynamic Type, VoiceOver, reduce motion, and increased contrast.
- Invalid and replaced RSS tokens.
- Real 14-day cleanup using controlled fixture timestamps.
- Memory and responsiveness with 50 long stories.
- Instruments pass for leaks, hangs, excessive main-thread work, and repeated view updates.

Exit criteria:

- All automated tests pass.
- No release-blocking issue remains from the physical-device checklist.
- A backup/export of the live token is not required to recover; the user can replace it in settings.

## 8. Personal iPhone deployment

### Prerequisites

- A Mac with a current Xcode version that supports the phone's iOS version.
- The owner's Apple ID added under Xcode Settings > Accounts.
- An iPhone running iOS 17 or later.
- Developer Mode enabled on the iPhone under Settings > Privacy & Security.
- A USB connection for initial setup, with the Mac and iPhone trusted.
- A unique bundle identifier.

### Free Personal Team installation

1. Open `PersonalReaderApp.xcodeproj` in Xcode.
2. Select the application target, then Signing & Capabilities.
3. Enable automatic signing and select the owner's Personal Team.
4. Confirm the unique bundle identifier and resolve any provisioning issue shown by Xcode.
5. Select the connected iPhone as the run destination.
6. Build and run with the Debug configuration.
7. Approve the developer identity on the phone if iOS requests it.
8. Complete setup in the app and verify an offline relaunch.

A free Personal Team is suitable for personal testing but its provisioning commonly expires after about seven days. The app must then be rebuilt and installed again from Xcode.

### Paid Apple Developer installation

For a longer-lived personal installation, use a paid Apple Developer Program team and install a signed development or Ad Hoc build. TestFlight is also available with a paid membership, but it adds App Store Connect setup, beta review requirements, and 90-day build expiry. It is optional for a single personal phone.

### Release archive check

Before calling the application deployable:

1. Select Any iOS Device as the destination.
2. Archive the Release configuration.
3. Run Xcode's validation for signing, entitlements, icons, privacy manifests, and bundle metadata.
4. Install the chosen development, Ad Hoc, or TestFlight build.
5. Perform the physical-device smoke test against the release build rather than only Debug.

## 9. Makefile workflow

```sh
make resolve
make format
make check
make release
make open
```

`make check` is the local quality gate and must pass before each device build. Xcode remains responsible for compiling the iOS host target, signing, archiving, and installation.

## 10. Definition of done

The application is complete for personal deployment when:

- A fresh user can enter valid settings and download stories without editing source code.
- The token is stored only in Keychain and is redacted from diagnostics.
- Stories remain readable offline after force-quitting and relaunching the app.
- Read/unread state survives refresh and relaunch.
- Manual and background sync honor throttling and persisted 429 backoff.
- The feed parser is verified against a current redacted Reddit response.
- The app is usable with VoiceOver and accessibility text sizes in light and dark mode.
- `make check`, integration tests, UI tests, release archive validation, and the physical-device checklist pass.
- A signed Release build is installed and successfully exercised on the owner's personal iPhone.
- The owner understands whether the selected signing method requires a weekly reinstall, annual renewal, or TestFlight renewal.
