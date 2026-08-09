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

struct ContentWarningView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(message)
                .multilineTextAlignment(.leading)
        }
        .font(.caption)
        .foregroundStyle(Theme.warning)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}
