import SwiftUI

struct ContentLoadingView: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView().tint(Theme.primary)
            Spacer()
        }
    }
}

struct ContentErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack {
            Spacer()
            Text(message).foregroundStyle(Theme.error).padding()
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent).tint(Theme.primary)
            Spacer()
        }
    }
}
