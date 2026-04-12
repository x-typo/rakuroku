import SwiftUI

struct MediaCardView: View {
    let entry: MediaListEntry
    let type: MediaType

    @Environment(AuthStore.self) private var authStore
    @State private var localProgress: Int
    @State private var isUpdating = false

    init(entry: MediaListEntry, type: MediaType) {
        self.entry = entry
        self.type = type
        self._localProgress = State(initialValue: entry.progress)
    }

    private var total: Int? {
        type == .anime ? entry.media.episodes : entry.media.chapters
    }

    private var progressPercent: Double {
        guard let total, total > 0 else { return 0 }
        return min(Double(localProgress) / Double(total), 1.0)
    }

    private var episodesBehind: Int {
        guard let next = entry.media.nextAiringEpisode else { return 0 }
        return max(0, next.episode - 1 - localProgress)
    }

    private var scoreText: String? {
        entry.score > 0 ? "★ \(Int(entry.score))" : nil
    }

    private var scoreColor: Color {
        if entry.score >= 8 { return Theme.success }
        if entry.score >= 5 { return Theme.warning }
        return Theme.error
    }

    private var progressText: String {
        if let total {
            return "\(localProgress)/\(total)"
        }
        return "\(localProgress)"
    }

    private var canIncrement: Bool {
        guard let total else { return true }
        return localProgress < total
    }

    private var canDecrement: Bool {
        localProgress > 0
    }

    var body: some View {
        ZStack {
            // Hidden NavigationLink suppresses List's default disclosure chevron
            // while preserving full-row tap navigation.
            NavigationLink(value: MediaDetailDestination(mediaId: entry.media.id)) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .opacity(0)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    AsyncCoverImage(url: entry.media.coverImage?.medium, width: 80, height: 130)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.media.title.display)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            Text(progressText)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)

                            if isUpdating {
                                ProgressView()
                                    .tint(Theme.primary)
                                    .scaleEffect(0.7)
                            }

                            if episodesBehind > 0 {
                                Text("\(episodesBehind) \(episodesBehind == 1 ? "episode" : "episodes") behind")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.error)
                            }
                        }

                        if let next = entry.media.nextAiringEpisode, type == .anime {
                            Text(Formatters.nextAiring(next.airingAt, episode: next.episode))
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                        }

                        if let score = scoreText {
                            Text(score)
                                .font(.subheadline)
                                .foregroundStyle(scoreColor)
                        }
                    }
                    .padding(12)

                    Spacer(minLength: 0)
                }

                if let total, total > 0 {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.primary)
                            .frame(width: geo.size.width * progressPercent)
                    }
                    .frame(height: 3)
                    .background(Theme.surfaceLight)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .onChange(of: entry.progress) { _, newValue in
            localProgress = newValue
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                handleProgressChange(delta: 1)
            } label: {
                Label("+1", systemImage: "plus.circle.fill")
            }
            .tint(Theme.primary)
            .disabled(!canIncrement || isUpdating || !authStore.isAuthenticated)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                handleProgressChange(delta: -1)
            } label: {
                Label("-1", systemImage: "minus.circle.fill")
            }
            .tint(Theme.error)
            .disabled(!canDecrement || isUpdating || !authStore.isAuthenticated)
        }
    }

    private func handleProgressChange(delta: Int) {
        guard !isUpdating else { return }
        guard let token = authStore.accessToken else { return }
        let previousProgress = localProgress
        let newProgress = localProgress + delta
        isUpdating = true
        localProgress = newProgress

        Task { @MainActor in
            do {
                try await AniListClient.shared.updateProgress(
                    mediaId: entry.media.id,
                    progress: newProgress,
                    accessToken: token
                )
            } catch {
                localProgress = previousProgress
            }
            isUpdating = false
        }
    }
}
