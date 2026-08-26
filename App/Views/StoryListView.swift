import PersonalReaderCore
import SwiftUI

struct StoryListView: View {
  @Environment(AppModel.self) private var model: AppModel

  @State private var isSettingsPresented = false
  @State private var topVisibleStoryID: String?

  var body: some View {
    NavigationStack {
      Group {
        if model.stories.isEmpty {
          emptyState
        } else if model.showUnreadOnly && model.unreadCount == 0 {
          caughtUpState
        } else {
          storyCards
        }
      }
      .navigationTitle(model.currentFeedTitle)
      .toolbar { toolbarContent }
      .refreshable {
        await model.refresh(force: true)
      }
      .sheet(isPresented: $isSettingsPresented) {
        SettingsView()
      }
      .safeAreaInset(edge: .bottom) {
        StatusFooterView()
          .background(.bar)
      }
    }
  }

  private var storyCards: some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        ForEach(Array(model.filteredStories.enumerated()), id: \.element.id) { index, story in
          StoryCardView(story: story, sourceTitle: sourceTitle(for: story.sourceId))
            .id(story.id)
            .onAppear {
              handleStoryAppeared(at: index)
            }
        }

        olderStoriesControl
      }
      .padding(.horizontal)
      .padding(.vertical, 12)
      .scrollTargetLayout()
    }
    .scrollPosition(id: $topVisibleStoryID)
    .onChange(of: topVisibleStoryID) { _, newID in
      guard let newID else { return }
      model.recordVisibleStories([newID])
    }
    .navigationDestination(for: Story.self) { story in
      ReaderView(story: story)
    }
  }

  private func handleStoryAppeared(at index: Int) {
    let total = model.filteredStories.count
    guard total > 0 else { return }
    let threshold = max(total - 3, 0)
    guard index >= threshold else { return }
    guard model.hasMoreStories, !model.isLoadingOlderStories else { return }
    Task { await model.loadOlderStories() }
  }

  private func sourceTitle(for sourceId: String) -> String? {
    if sourceId == FeedSourceRecord.builtInRedditID() { return nil }
    return model.feedSources.first(where: { $0.id == sourceId })?.title
  }

  @ViewBuilder
  private var olderStoriesControl: some View {
    if model.isLoadingOlderStories {
      ProgressView("Loading older stories…")
        .frame(maxWidth: .infinity)
        .padding()
    } else if model.hasMoreStories {
      Button {
        Task { await model.loadOlderStories() }
      } label: {
        Label("Load more stories", systemImage: "arrow.down.circle")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .padding(.vertical, 12)
    } else if !model.filteredStories.isEmpty {
      Label("No more stories", systemImage: "checkmark.circle")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding()
    }
  }

  private var emptyState: some View {
    ContentUnavailableView(
      model.feedSources.isEmpty ? "No feeds yet" : "No stories yet",
      systemImage: "tray",
      description: Text(
        model.feedSources.isEmpty
          ? "Add an RSS feed in Settings to fill your library."
          : "Pull down to sync your feed, or check your connection. Downloaded content stays readable offline."
      )
    )
  }

  private var caughtUpState: some View {
    ContentUnavailableView(
      "All caught up",
      systemImage: "checkmark.circle",
      description: Text("Every downloaded story has been read.")
    )
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Picker(
        "Show",
        selection: Binding(
          get: { model.showUnreadOnly },
          set: { model.showUnreadOnly = $0 }
        )
      ) {
        Text("All").tag(false)
        Text("Unread").tag(true)
      }
      .pickerStyle(.segmented)
      .accessibilityLabel("Filter stories")
      .accessibilityValue(model.showUnreadOnly ? "Unread only" : "All stories")
    }

    ToolbarItem(placement: .principal) {
      FeedHeaderView()
    }

    ToolbarItemGroup(placement: .topBarTrailing) {
      Menu {
        Button {
          model.selectSubscribedFeed()
        } label: {
          Label(
            "Subscribed",
            systemImage: model.currentFeedMode == .subscribed ? "checkmark" : "rectangle.stack"
          )
        }

        Section("Private listings") {
          ForEach(RedditPrivateListing.allCases, id: \.self) { listing in
            Button {
              model.selectPrivateListing(listing)
            } label: {
              Label(
                listing.title,
                systemImage: model.currentFeedMode == .privateListing
                  && model.currentPrivateListing == listing
                  ? "checkmark"
                  : listing.systemImage
              )
            }
          }
        }
      } label: {
        Image(systemName: "person.crop.circle")
      }
      .disabled(!model.canChangeFeed)
      .accessibilityLabel("Browse feed source")
      .accessibilityValue(model.currentFeedTitle)

      Button {
        isSettingsPresented = true
      } label: {
        Image(systemName: "gearshape")
      }
      .accessibilityLabel("Settings")
    }
  }
}

struct FeedHeaderView: View {
  @Environment(AppModel.self) private var model: AppModel

  var body: some View {
    Text(model.currentFeedTitle)
      .font(.headline)
      .lineLimit(1)
      .accessibilityLabel(model.currentFeedTitle)
  }
}

struct StoryCardView: View {
  let story: Story
  let sourceTitle: String?

  @Environment(\.openURL) private var openURL

  private let preview: String

  init(story: Story, sourceTitle: String? = nil) {
    self.story = story
    self.sourceTitle = sourceTitle
    preview = Self.plainText(from: story.contentBody)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      NavigationLink(value: story) {
        VStack(alignment: .leading, spacing: 10) {
          metadata

          Text(story.title)
            .font(story.isRead ? .headline : .headline.weight(.bold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)

          if !preview.isEmpty {
            Text(preview)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.leading)
              .lineLimit(3)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(cardAccessibilityLabel)
      .accessibilityHint("Opens the story")

      if let url = browserURL {
        Divider()

        Button {
          openURL(url)
        } label: {
          Label(openOriginalLabel, systemImage: "safari")
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(story.title) on \(hostLabel)")
      }
    }
    .padding(16)
    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(
          story.isRead ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.35),
          lineWidth: 1
        )
    }
    .shadow(color: .black.opacity(story.isRead ? 0.03 : 0.07), radius: 8, y: 3)
  }

  private var metadata: some View {
    HStack(spacing: 7) {
      Image(systemName: story.isRead ? "circle" : "circle.fill")
        .font(.system(size: 8))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      if let sourceTitle {
        Text(sourceTitle)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tint)
          .lineLimit(1)
      } else {
        Text("r/\(story.subreddit)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tint)
          .lineLimit(1)
      }

      if !story.author.isEmpty {
        Text(story.author.hasPrefix("@") ? story.author : story.author)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      Text(story.publishedDate.formatted(.relative(presentation: .named)))
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  private var browserURL: URL? {
    guard let url = story.originalURL, url.scheme == "http" || url.scheme == "https" else {
      return nil
    }
    return url
  }

  private var hostLabel: String {
    browserURL?.host ?? "the original site"
  }

  private var openOriginalLabel: String {
    if sourceTitle == nil { return "Open on Reddit" }
    return "Open on \(hostLabel)"
  }

  private var cardAccessibilityLabel: String {
    let state = story.isRead ? "Read" : "Unread"
    let source = sourceTitle ?? "r/\(story.subreddit)"
    return "\(state). \(story.title), \(source)"
  }

  private static func plainText(from html: String) -> String {
    html
      .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct StatusFooterView: View {
  @Environment(AppModel.self) private var model: AppModel

  var body: some View {
    Label(statusText, systemImage: statusIcon)
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .accessibilityLabel("Sync status: \(statusText)")
  }

  private var statusText: String {
    switch model.syncStatus {
    case .idle:
      return lastSyncDescription ?? "Up to date"
    case .syncing:
      return "Syncing…"
    case .offline:
      return "Offline — showing downloaded stories"
    case .throttled(let date):
      return "Reddit asked us to wait. Next try \(date.formatted(.relative(presentation: .named)))"
    case .partial(let succeeded, let attempted):
      return "Updated \(succeeded) of \(attempted) feeds."
    case .failed(let message):
      return message
    }
  }

  private var statusIcon: String {
    switch model.syncStatus {
    case .idle:
      return "checkmark.icloud"
    case .syncing:
      return "arrow.triangle.2.circlepath"
    case .offline:
      return "wifi.slash"
    case .throttled:
      return "clock"
    case .partial:
      return "exclamationmark.triangle"
    case .failed:
      return "exclamationmark.triangle"
    }
  }

  private var lastSyncDescription: String? {
    guard let lastSyncDate = model.lastSyncDate else { return nil }
    return "Synced \(lastSyncDate.formatted(.relative(presentation: .named)))"
  }
}
