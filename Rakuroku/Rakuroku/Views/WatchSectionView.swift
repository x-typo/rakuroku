import SafariServices
import SwiftUI

struct SafariDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct WatchSectionView: View {
    let media: MediaDetails
    let userEntry: UserMediaEntry?

    @Environment(AuthStore.self) private var authStore
    @Environment(AnimeKaiStore.self) private var animeKaiStore

    @State private var watchLoading = false
    @State private var watchError: String?
    @State private var watchCandidates: [AnimeKaiResolver.Candidate] = []
    @State private var showCandidateSheet = false
    @State private var showOverrideSheet = false
    @State private var overrideInput = ""
    @State private var overrideInputError: String?
    @State private var safariDestination: SafariDestination?
    @State private var discussionUrl: URL?

    private var currentProgress: Int { userEntry?.progress ?? 0 }
    private var nextEp: Int { currentProgress + 1 }
    private var allWatched: Bool { media.episodes.map { currentProgress >= $0 } ?? false }
    private var canWatch: Bool { authStore.isAuthenticated && userEntry != nil && !allWatched }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canWatch {
                Button {
                    Task { await handleWatch() }
                } label: {
                    HStack(spacing: 8) {
                        if watchLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text("Watch episode \(nextEp)")
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(watchLoading)

                HStack(spacing: 8) {
                    Button {
                        if let url = URL(string: "https://animekai.to/home") {
                            safariDestination = SafariDestination(url: url)
                        }
                    } label: {
                        Text("AnimeKai")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Button {
                        overrideInput = animeKaiStore.getWatchPath(mediaId: media.id) ?? ""
                        overrideInputError = nil
                        showOverrideSheet = true
                    } label: {
                        Text(animeKaiStore.hasOverride(mediaId: media.id) ? "Edit Override" : "Override Link")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Button {
                        if let url = discussionUrl {
                            safariDestination = SafariDestination(url: url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.fill")
                                .font(.caption2)
                            Text("Discuss")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(discussionUrl != nil ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(discussionUrl != nil ? 1 : 0.4)
                    }
                    .disabled(discussionUrl == nil)

                    if animeKaiStore.hasOverride(mediaId: media.id) {
                        Button {
                            animeKaiStore.clearOverride(mediaId: media.id)
                        } label: {
                            Text("Clear")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.error)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            } else if allWatched {
                Text("All episodes watched.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else if !authStore.isAuthenticated || userEntry == nil {
                Text("Add to your list to watch episodes.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let watchError {
                Text(watchError)
                    .font(.caption)
                    .foregroundStyle(Theme.error)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .task(id: currentProgress) {
            guard canWatch else {
                discussionUrl = nil
                return
            }
            let episode: Int
            if currentProgress > 0 {
                episode = currentProgress
            } else if let nextEp = media.nextAiringEpisode, nextEp.episode > 1 {
                episode = nextEp.episode - 1
            } else {
                discussionUrl = nil
                return
            }
            discussionUrl = await RedditDiscussion.findUrl(
                anilistId: media.id,
                episode: episode,
                airingAt: Int(Date().timeIntervalSince1970)
            )
        }
        .sheet(isPresented: $showCandidateSheet) { candidateSheet }
        .sheet(isPresented: $showOverrideSheet) { overrideSheet }
        .fullScreenCover(item: $safariDestination) { dest in
            SafariView(url: dest.url)
                .ignoresSafeArea()
                .onAppear { AppDelegate.allowLandscape = true }
                .onDisappear {
                    AppDelegate.allowLandscape = false
                    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                    scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                }
        }
    }

    // MARK: - Actions

    private func handleWatch() async {
        guard let entry = userEntry else { return }
        let nextEp = entry.progress + 1
        watchLoading = true
        watchError = nil

        let result = await animeKaiStore.resolve(mediaId: media.id, title: media.title.display)

        if let path = result.watchPath,
           let url = AnimeKaiResolver.buildEpisodeURL(watchPath: path, episode: nextEp) {
            safariDestination = SafariDestination(url: url)
        } else if !result.candidates.isEmpty {
            watchCandidates = result.candidates
            showCandidateSheet = true
        } else {
            watchError = "Couldn't find this show on AnimeKai."
        }

        watchLoading = false
    }

    // MARK: - Sheets

    @ViewBuilder
    private var candidateSheet: some View {
        VStack(spacing: 12) {
            Text("Choose AnimeKai Link")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 16)

            Text("Multiple results found. Pick the correct one.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(watchCandidates) { candidate in
                        Button {
                            animeKaiStore.setOverride(mediaId: media.id, watchPath: candidate.watchPath)
                            showCandidateSheet = false
                            if let url = AnimeKaiResolver.buildEpisodeURL(watchPath: candidate.watchPath, episode: nextEp) {
                                safariDestination = SafariDestination(url: url)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title ?? candidate.watchPath.replacingOccurrences(of: "/watch/", with: ""))
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                Text(candidate.watchPath)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            Button {
                showCandidateSheet = false
                overrideInput = ""
                overrideInputError = nil
                showOverrideSheet = true
            } label: {
                Text("Paste Link Instead")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.primary)
            }
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var overrideSheet: some View {
        VStack(spacing: 16) {
            Text("AnimeKai Link Override")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            Text("Paste an AnimeKai URL, /watch path, or slug.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            TextField("https://animekai.to/watch/...", text: $overrideInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if let overrideInputError {
                Text(overrideInputError)
                    .font(.caption)
                    .foregroundStyle(Theme.error)
            }

            HStack(spacing: 12) {
                Button("Save") {
                    if let normalized = AnimeKaiResolver.normalizeWatchPathInput(overrideInput) {
                        animeKaiStore.setOverride(mediaId: media.id, watchPath: normalized)
                        showOverrideSheet = false
                        overrideInputError = nil
                    } else {
                        overrideInputError = "Invalid AnimeKai link."
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .disabled(overrideInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel") {
                    showOverrideSheet = false
                }
                .buttonStyle(.bordered)
            }

            if animeKaiStore.hasOverride(mediaId: media.id) {
                Button(role: .destructive) {
                    animeKaiStore.clearOverride(mediaId: media.id)
                    showOverrideSheet = false
                } label: {
                    Text("Clear Override")
                        .foregroundStyle(Theme.error)
                }
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Safari View

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(Theme.primary)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
