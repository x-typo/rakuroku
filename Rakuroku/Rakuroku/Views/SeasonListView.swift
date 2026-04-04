import SwiftUI

struct SeasonListView: View {
    let season: Season
    let year: Int
    let label: String

    @Environment(AuthStore.self) private var authStore

    @State private var media: [SeasonalMedia] = []
    @State private var userStatusMap: [Int: MediaListStatus] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var hasNextPage = true
    @State private var loadingMore = false
    @State private var currentPage = 1

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

            if loading {
                ContentLoadingView()
            } else if let error {
                ContentErrorView(message: error) { Task { await loadData() } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(media) { item in
                            seasonMediaRow(item)
                        }

                        if loadingMore {
                            ProgressView().tint(Theme.primary).padding()
                        }

                        if hasNextPage && !loadingMore {
                            Color.clear.frame(height: 1)
                                .onAppear { Task { await loadMore() } }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .refreshable { await loadData() }
            }
        }
        .background(Theme.background)
        .task { await loadData() }
    }

    @ViewBuilder
    private func seasonMediaRow(_ item: SeasonalMedia) -> some View {
        let userStatus = userStatusMap[item.id]

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
        do {
            async let seasonData = AniListClient.shared.fetchSeasonalAnime(season: season, year: year, page: 1, perPage: 25)
            async let animeList = AniListClient.shared.fetchMediaList(type: .anime, username: authStore.username)
            let (s, list) = try await (seasonData, animeList)
            media = s.media
            hasNextPage = s.hasNextPage
            userStatusMap = Dictionary(uniqueKeysWithValues: list.map { ($0.media.id, $0.status) })
        } catch where error.isCancellation {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func loadMore() async {
        guard !loadingMore, hasNextPage else { return }
        loadingMore = true
        let nextPage = currentPage + 1
        do {
            let result = try await AniListClient.shared.fetchSeasonalAnime(season: season, year: year, page: nextPage, perPage: 25)
            media.append(contentsOf: result.media)
            hasNextPage = result.hasNextPage
            currentPage = nextPage
        } catch {
            hasNextPage = false
        }
        loadingMore = false
    }
}
