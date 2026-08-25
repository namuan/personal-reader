import PersonalReaderCore

extension FeedMode {
  var title: String {
    switch self {
    case .subreddits:
      return "Subreddits"
    case .privateListing:
      return "Private listing"
    }
  }
}

extension RedditFrontPageSort {
  var title: String {
    rawValue.capitalized
  }

  var systemImage: String {
    switch self {
    case .best:
      return "sparkles"
    case .hot:
      return "flame"
    case .new:
      return "clock"
    case .rising:
      return "chart.line.uptrend.xyaxis"
    }
  }
}

extension RedditPrivateListing {
  var title: String {
    switch self {
    case .frontPage:
      return "Front page"
    case .saved:
      return "Saved"
    case .upvoted:
      return "Upvoted"
    case .downvoted:
      return "Downvoted"
    case .hidden:
      return "Hidden"
    case .submitted:
      return "Submitted"
    case .comments:
      return "Comments"
    }
  }

  var systemImage: String {
    switch self {
    case .frontPage:
      return "house"
    case .saved:
      return "bookmark"
    case .upvoted:
      return "arrow.up.circle"
    case .downvoted:
      return "arrow.down.circle"
    case .hidden:
      return "eye.slash"
    case .submitted:
      return "square.and.pencil"
    case .comments:
      return "bubble.left.and.bubble.right"
    }
  }
}
