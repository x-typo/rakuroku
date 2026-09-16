import SwiftUI

struct SeasonListView: View {
    let season: Season
    let year: Int
    let label: String

    @Environment(AuthStore.self) private var authStore
    @Environment(MediaLibraryStore.self) private var mediaLibraryStore

    @State private var loadState = SeasonListStore()

    private var activeSessionID: MediaLibrarySession.ID {
        authStore.mediaLibrarySession.id
    }
    private var hasCurrentAnimeSnapshot: Bool {
        let libraryState = mediaLibraryStore.state(for: .anime)
        return MediaLibrarySnapshotValidation.isCurrent(
            hasUsableData: libraryState.hasUsableData,
            snapshotSessionID: libraryState.snapshotSessionID,
            activeSessionID: activeSessionID
        )
    }
    private var personalizationWarning: String? {
        let libraryState = mediaLibraryStore.state(for: .anime)
        if case .failed(let message) = libraryState.phase {
            return hasCurrentAnimeSnapshot
                ? "List refresh failed. \(message)"
                : "List status unavailable. \(message)"
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading) {
                Text(label)
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("\(Formatters.seasonName(season.rawValue)) \(year)")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            if let personalizationWarning {
                ContentWarningView(message: personalizationWarning)
            }

            if loadState.loading {
                ContentLoadingView()
            } else if let error = loadState.error {
                ContentErrorView(message: error) { Task { await refreshData() } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(loadState.media) { item in
                            seasonMediaRow(item)
                        }

                        if loadState.loadingMore {
                            ProgressView().tint(Theme.primary).padding()
                        }

                        if let loadMoreError = loadState.loadMoreError {
                            VStack(spacing: 8) {
                                Text(loadMoreError)
                                    .font(.caption)
                                    .foregroundStyle(Theme.error)
                                    .multilineTextAlignment(.center)
                                Button("Retry") { Task { await loadMore() } }
                                    .buttonStyle(.bordered)
                                    .tint(Theme.primary)
                            }
                            .padding()
                        }

                        if loadState.canLoadMore && loadState.loadMoreError == nil {
                            Color.clear.frame(height: 1)
                                .onAppear { Task { await loadMore() } }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .refreshable { await refreshData() }
            }
        }
        .background(Theme.background)
        .task { await loadData() }
        .task(id: authStore.mediaLibrarySession.id) { await loadLibrary() }
    }

    @ViewBuilder
    private func seasonMediaRow(_ item: SeasonalMedia) -> some View {
        let libraryState = mediaLibraryStore.state(for: .anime)
        let userStatus = hasCurrentAnimeSnapshot
            ? mediaLibraryStore.status(mediaID: item.id, type: .anime)
            : nil

        NavigationLink(value: MediaDetailDestination(mediaId: item.id)) {
            HStack(spacing: 0) {
                AsyncCoverImage(url: item.coverImage?.medium, width: 80, height: 120)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.display)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2, reservesSpace: true)

                    if let studio = Formatters.mainStudioName(item.studios) {
                        Text(studio)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    HStack(spacing: 12) {
                        if let score = item.averageScore {
                            HStack(spacing: 4) {
                                Image(systemName: "chart.bar.fill").font(.system(size: 12)).foregroundStyle(Theme.primary)
                                Text("\(score)%").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if let eps = item.episodes {
                            Text("\(eps) episodes").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }

                    if let status = userStatus,
                       let label = Formatters.statusLabel(status),
                       let color = Formatters.statusColor(status) {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color)
                            .padding(.top, 2)
                    }
                }
                .padding(12)

                Spacer()
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .opacity(MediaLibraryMembershipAppearance.opacity(
            hasUsableData: libraryState.hasUsableData,
            snapshotSessionID: libraryState.snapshotSessionID,
            activeSessionID: activeSessionID,
            status: userStatus
        ))
        .accessibilityValue(
            hasCurrentAnimeSnapshot
                ? Formatters.statusLabel(userStatus) ?? "Not in your list"
                : "List status unavailable"
        )
    }

    private func loadData() async {
        await loadState.refresh(loader: loadPage)
    }

    private func loadLibrary() async {
        let session = authStore.mediaLibrarySession
        await mediaLibraryStore.load(.anime, session: session)
    }

    private func refreshData() async {
        let session = authStore.mediaLibrarySession
        async let primaryLoad: Void = loadData()
        async let libraryLoad: Void = mediaLibraryStore.load(.anime, session: session, force: true)
        _ = await (primaryLoad, libraryLoad)
    }

    private func loadMore() async {
        await loadState.loadMore(loader: loadPage)
    }

    private func loadPage(_ page: Int) async throws -> SeasonListStore.Page {
        try await AniListClient.shared.fetchSeasonalAnime(
            season: season, year: year, page: page, perPage: 25
        )
    }
}
