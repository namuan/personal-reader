# Feature ideas for Personal Reader

## Best next additions

Start with local bookmarks, reading progress, and reversible read actions. These make daily reading better without adding accounts, servers, or new data sources.

This brainstorm builds on the current code, including RSS and Atom subscriptions, feed management, OPML import, JSON feed import and export, local search, and image viewing. Those features are not new proposals.

Effort labels are relative estimates, not delivery commitments. Small means a focused addition; medium means new persistent state or several screens; large means a new integration or substantial architecture work.

## Make everyday reading easier

### Local bookmarks and a read-later queue

Keep stories worth revisiting, independently of Reddit's Saved listing. Add a bookmark action and a dedicated queue with manual ordering.

First version: bookmark and unbookmark stories locally. Preserve bookmarked content when switching Reddit listings or cleaning downloaded data, unless the user explicitly deletes it.

Effort: medium. Priority: first.

### Resume unfinished stories

Remember your place in long posts. Show a Continue reading section and restore the reading position after relaunch.

First version: store a position and last-opened date per story. Keep unfinished stories separate from completed ones.

Effort: medium. Priority: first.

### Reversible read actions

Recover from accidentally dismissing a story or marking the whole list as read. Let users decide when a story counts as read.

First version: add Mark unread, Undo for bulk actions, and a choice between automatic and manual completion. Make bulk actions explicit about their scope during search.

Effort: small to medium. Priority: first.

### Reader appearance controls

Tune the reader for long sessions without changing system-wide settings.

First version: font size, serif or sans-serif text, line spacing, and a warm background option. Preserve Dynamic Type and contrast accessibility.

Effort: small to medium.

### Reading time and length filters

Choose something that fits the time available. Show estimated reading time on cards and filter for short or long reads.

First version: estimate from downloaded text. Label estimates for truncated feed entries so a short summary does not imply a short article.

Effort: small.

### Next and previous story navigation

Move through a reading session without returning to the list after every article.

First version: add reader navigation buttons that follow the current filter and sort. Keep the session order stable as stories become read.

Effort: small to medium.

### Compact list and local sorting

Make large libraries easier to scan. Offer compact headlines alongside the existing preview cards.

First version: newest first, oldest first, and shortest read. Remember display preferences per feed without changing Reddit's server-side sort.

Effort: small.

### Read aloud

Listen to downloaded stories while walking or doing chores.

First version: system speech with pause, resume, speed control, and saved playback position. Use downloaded voices for offline listening.

Effort: medium; background playback and lock-screen controls add scope.

## Organise a growing library

### Feed folders and favourites

Group subscriptions into topics such as Engineering, Fiction, and News. Pin frequently read feeds above the rest.

First version: one folder per feed, manual reordering, and unread counts per folder. Later preserve folder structure during OPML transfer.

Effort: medium.

### Saved searches and smart collections

Turn repeated searches into reusable views. Examples include Swift posts, unread fiction, and bookmarked articles from a particular source.

First version: save a text query with source and read-state filters. Add SQLite full-text indexing if library size makes the existing search slow.

Effort: medium.

### Mute rules

Reduce repetitive or unwanted stories without unsubscribing from a useful feed.

First version: local rules for title keywords, authors, and domains. Include a Hidden by rules view and explain which rule matched.

Effort: medium.

### Duplicate grouping

Avoid reading the same link several times when it appears in Reddit and multiple RSS feeds.

First version: group exact canonical-URL matches while retaining each source attribution. Keep discussion links and per-source state accessible.

Effort: medium. Avoid merging stories solely because their titles are similar.

### Highlights and private notes

Keep useful passages and your own thoughts beside a story.

First version: select text to save a quote with an optional note. Store the quoted text so it survives later article changes.

Effort: medium to large. Build on durable bookmarks first.

### Reading history

Find something you remember reading but forgot to save.

First version: a chronological history of opened and completed stories, with search and a Clear history action.

Effort: medium. Explain when original content has been removed from the cache.

### Snooze a story

Set aside an interesting article until the weekend without leaving it in today's unread list.

First version: Later today, Tomorrow, and Next weekend. Resurface stories locally when their snooze expires; notifications remain optional.

Effort: medium.

## Improve capture and offline access

### RSS-only setup

Use Personal Reader without a Reddit account or token. The current startup and refresh paths require Reddit configuration even though general feeds are supported.

First version: offer Start with RSS during setup. Sync enabled RSS sources independently and allow Reddit to be connected later.

Effort: medium. High value if the app becomes a general-purpose reader.

### Website feed discovery

Subscribe using a website address rather than hunting for its RSS URL.

First version: inspect a public page for RSS or Atom discovery links, preview the available feeds, and let the user choose.

Effort: medium. Keep HTTPS validation and avoid importing credential-bearing URLs without a warning.

### Save from the share sheet

Capture articles from Safari and other apps into the read-later queue.

First version: an iOS share extension that stores a URL and title in a shared app container. Add content downloading separately.

Effort: large. A saved link alone is not an offline-readable article.

### Download full article text

Read articles whose feeds only contain a short excerpt.

First version: a user-triggered Fetch article action for public pages. Extract and sanitise readable content while keeping the original feed text as a fallback.

Effort: large. Do not bypass paywalls or login requirements; show which version of the content is being read.

### Prepare for offline reading

Make it clear what will work on a train or flight, including images rather than just text.

First version: download a chosen queue with progress, cancellation, a storage limit, and a Wi-Fi-only option. Show text-only and fully-downloaded states separately.

Effort: large. Treat remote images as potential tracking requests and make downloading them a user choice.

### Portable library backup

Protect bookmarks, notes, reading positions, and read history when replacing a phone or reinstalling the app.

First version: versioned export and restore with a preview. Extend the existing feed-only export rather than creating a second subscription format.

Effort: medium to large. Exclude Reddit tokens, redact credential-bearing URLs, and warn that private story content is sensitive. Consider encrypted archives.

### OPML export

Move subscriptions to other readers using a standard format. OPML import already exists; the current export uses the app's JSON format.

First version: export public RSS and Atom subscriptions as OPML. Exclude private Reddit URLs and other credentials.

Effort: small.

## Give users more control

### Storage and retention controls

See how much space the library uses and remove expendable downloads without losing saved work.

First version: show text and media usage, then offer Clear read downloads and per-feed retention choices. Protect bookmarks and notes by default.

Effort: medium. Make the settings description match the actual cleanup policy.

### Feed health and recovery

Understand why a subscription stopped updating without exposing secrets in diagnostics.

First version: extend existing feed error displays with last success, next allowed attempt, and a suggested recovery action. Add a redacted diagnostic export.

Effort: small to medium. Respect rate limits even when the user retries manually.

### Privacy lock and hidden previews

Keep private listings out of sight when lending someone your phone.

First version: optional Face ID or device-passcode unlock, plus an obscured app-switcher snapshot. Hide sensitive widget and notification content by default.

Effort: medium. An app lock is not a substitute for protecting exported files.

### Quiet daily reading sessions

Reduce the pressure of an endless unread queue. Offer a finite selection, such as 5 stories or roughly 15 minutes of reading.

First version: select from downloaded unread stories, balancing sources and reading length. End with a clear session-complete screen, not another infinite feed.

Effort: medium. No engagement scoring, streak pressure, or server-side profiling needed.

### Widgets and Shortcuts

Jump straight into a useful action without navigating the app.

First version: a Continue reading widget and Shortcuts for opening the queue or saving a URL. Make private titles opt-in.

Effort: medium to large. Show cached data honestly; iOS background refresh cannot guarantee exact update times.

## Explore later

### iPad layout and keyboard navigation

Use a sidebar, story list, and reader together on larger screens. Add keyboard commands for navigation, search, and read-state changes.

Effort: medium to large. Worth prioritising if reading on iPad is a regular use case.

### Optional cross-device sync

Keep bookmarks, notes, reading positions, and read state consistent across personal devices.

First version: opt-in CloudKit sync for user-created state, not the entire feed cache. Resolve conflicts and deletions explicitly; keep Reddit tokens device-local.

Effort: large. This expands the original local-only scope and introduces iCloud and signing requirements.

### On-device summaries and topic suggestions

Help decide whether a long article deserves a full read. Suggest tags or produce a short summary without sending private posts to a service.

First version: an explicit Summarise action on supported devices. Label generated text, retain the original, and handle incomplete feed content.

Effort: large. Check device, model, and operating-system support before committing; do not make core reading depend on AI.

## Suggested delivery order

1. Add reversible read actions and local bookmarks, including rules that protect saved content.
2. Add reading positions, reading-time estimates, and reader appearance controls.
3. Add folders, saved searches, and mute rules when the subscription list grows.
4. Add backup and restore before users accumulate substantial notes or saved articles.
5. Add RSS-only setup and feed discovery if broader feed reading becomes a goal.
6. Tackle share-sheet capture and full offline downloads as a separate expansion.

## Keep out unless the product goal changes

Avoid features that turn a quiet, private reader into a full social client:

- posting, voting, replying, and messaging require a separately approved authenticated integration; private RSS is not a write API
- full comment threads need a permitted data source; reading a private Comments listing is not the same as downloading discussions
- public profiles, leaderboards, advertising, and analytics conflict with the app's personal, tracking-free purpose
- cloud AI processing of private listings should never happen silently
- scheduled digests must not promise exact fresh-content delivery through best-effort iOS background refresh
