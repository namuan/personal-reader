import SwiftUI

struct ConnectionResultLabel: View {
  let outcome: AppModel.ConnectionOutcome

  var body: some View {
    switch outcome {
    case .connected(let count) where count > 0:
      Label(
        "Connected. \(count) recent \(count == 1 ? "story" : "stories") found.",
        systemImage: "checkmark.circle"
      )
      .font(.footnote)
      .foregroundStyle(Color.green)
    case .connected:
      Label(
        "Connected, but the selected feed returned no entries. Choose another feed source or check that the account has recent activity.",
        systemImage: "exclamationmark.triangle"
      )
      .font(.footnote)
      .foregroundStyle(Color.orange)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.footnote)
        .foregroundStyle(Color.orange)
    }
  }
}
