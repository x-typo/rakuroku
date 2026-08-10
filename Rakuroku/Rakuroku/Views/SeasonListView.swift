import SwiftUI

struct SeasonListView: View {
    let season: Season
    let year: Int
    let label: String

    @Environment(AuthStore.self) private var authStore
    @Environment(MediaLibraryStore.self) private var mediaLibraryStore

    @State private var media: [SeasonalMedia] = []
    @State private var loading = true
    @State private var error: String?
    @State private var hasNextPage = true
    @State private var loadingMore = false
    @State private var currentPage = 1
    @State private var loadMoreError: String?

    private var personalizationWarning: String? {
        let libraryState = mediaLibraryStore.state(for: .anime)
        if case .failed(let message) = libraryState.phase {
            return libraryState.hasUsableData
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

            if loading {
                ContentLoadingView()
            } else if let error {
                ContentErrorView(message: error) { Task { await refreshData() } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(media) { item in
                            seasonMediaRow(item)
                        }

                        if loadingMore {
                            ProgressView().tint(Theme.primary).padding()
                        }

                        if let loadMoreError {
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

                        if hasNextPage && !loadingMore && loadMoreError == nil {
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
        let userStatus = libraryState.hasUsableData
            ? mediaLibraryStore.status(mediaID: item.id, type: .anime)
            : nil

        NavigationLink(value: MediaDetailDestination(mediaId: item.id)) {
            HStack(spacing: 0) {
                AsyncCoverImage(url: item.coverImage?.medium, width: 80, height: 120)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.display)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)

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
    }

    private func loadData() async {
        if media.isEmpty { loading = true }
        error = nil
        currentPage = 1
        loadMoreError = nil
        do {
            let result = try await AniListClient.shared.fetchSeasonalAnime(
                season: season,
                year: year,
                page: 1,
                perPage: 25
            )
            try Task.checkCancellation()
            media = result.media
            hasNextPage = result.hasNextPage
            loading = false
        } catch where error.isCancellation {
            return
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
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
        guard !loadingMore, hasNextPage else { return }
        loadingMore = true
        loadMoreError = nil
        let nextPage = currentPage + 1
        do {
            let result = try await AniListClient.shared.fetchSeasonalAnime(season: season, year: year, page: nextPage, perPage: 25)
            try Task.checkCancellation()
            let existingIds = Set(media.map(\.id))
            let newItems = result.media.filter { !existingIds.contains($0.id) }
            media.append(contentsOf: newItems)
            hasNextPage = result.hasNextPage
            currentPage = nextPage
        } catch where error.isCancellation {
        } catch {
            loadMoreError = error.localizedDescription
        }
        loadingMore = false
    }
}
