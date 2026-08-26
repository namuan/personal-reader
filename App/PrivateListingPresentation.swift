import PersonalReaderCore

extension FeedMode {
  var title: String {
    switch self {
    case .subscribed:
      return "Subscribed"
    case .privateListing:
      return "Private listing"
    }
  }
}

extension RedditPrivateListing {
  var title: String {
    switch self {
    case .saved: return "Saved"
    case .upvoted: return "Upvoted"
    case .downvoted: return "Downvoted"
    case .hidden: return "Hidden"
    case .submitted: return "Submitted"
    case .comments: return "Comments"
    }
  }

  var systemImage: String {
    switch self {
    case .saved: return "bookmark"
    case .upvoted: return "arrow.up.circle"
    case .downvoted: return "arrow.down.circle"
    case .hidden: return "eye.slash"
    case .submitted: return "square.and.pencil"
    case .comments: return "bubble.left.and.bubble.right"
    }
  }
}
