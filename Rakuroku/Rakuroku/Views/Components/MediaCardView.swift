import SwiftUI

struct MediaCardView: View {
    let entry: MediaListEntry
    let type: MediaType

    @Environment(AuthStore.self) private var authStore
    @State private var localProgress: Int
    @State private var isUpdating = false
    @State private var dragOffset: CGFloat = 0
    @State private var isSwiping = false
    @State private var dragAxis: Axis?

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

    var body: some View {
        ZStack {
            HStack {
                if dragOffset > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("+1")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                Spacer()
                if dragOffset < 0 {
                    HStack(spacing: 4) {
                        Text("-1")
                            .fontWeight(.semibold)
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .background(dragOffset > 0 ? Theme.primary : dragOffset < 0 ? Theme.error : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            NavigationLink(value: MediaDetailDestination(mediaId: entry.media.id)) {
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
            }
            .buttonStyle(.plain)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .offset(x: dragOffset)
        }
        .disabled(isSwiping)
        .simultaneousGesture(swipeGesture)
        .padding(.horizontal, 16)
        .onChange(of: entry.progress) { _, newValue in
            localProgress = newValue
        }
    }

    private var progressText: String {
        if let total {
            return "\(localProgress)/\(total)"
        }
        return "\(localProgress)"
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard authStore.isAuthenticated else { return }
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                guard dragAxis == .horizontal else { return }
                isSwiping = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let wasHorizontal = dragAxis == .horizontal
                defer {
                    dragAxis = nil
                    withAnimation { dragOffset = 0 }
                    Task { @MainActor in try? await Task.sleep(for: .milliseconds(300)); isSwiping = false }
                }

                guard wasHorizontal, authStore.isAuthenticated, !isUpdating else { return }

                if value.translation.width > 80 {
                    let canIncrement = total == nil || localProgress < (total ?? 0)
                    if canIncrement { handleProgressChange(delta: 1) }
                } else if value.translation.width < -80 {
                    if localProgress > 0 { handleProgressChange(delta: -1) }
                }
            }
    }

    private func handleProgressChange(delta: Int) {
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
