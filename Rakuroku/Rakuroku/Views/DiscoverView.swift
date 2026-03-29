import SwiftUI

struct DiscoverView: View {


    @State private var currentSeasonAnime: [SeasonalMedia] = []
    @State private var nextSeasonAnime: [SeasonalMedia] = []
    @State private var searchResults: [SeasonalMedia] = []
    @State private var loading = true
    @State private var error: String?
    @State private var searchQuery = ""
    @State private var searching = false
    @State private var loadingMore = false
    @State private var hasNextPage = false
    @State private var currentPage = 1
    @State private var searchTask: Task<Void, Never>?

    private let seasonInfo = Formatters.currentSeason()
    private var nextSeasonInfo: (season: Season, year: Int) {
        Formatters.nextSeason(after: seasonInfo)
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(text: $searchQuery)
                .padding(.top, 16)

            if !searchQuery.isEmpty {
                searchResultsView
            } else if loading {
                ContentLoadingView()
            } else if let error {
                ContentErrorView(message: error) { Task { await loadData() } }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        seasonSection(
                            label: "Current Season",
                            season: seasonInfo.season,
                            year: seasonInfo.year,
                            data: currentSeasonAnime
                        )

                        seasonSection(
                            label: "Upcoming Season",
                            season: nextSeasonInfo.season,
                            year: nextSeasonInfo.year,
                            data: nextSeasonAnime
                        )
                    }
                    .padding(.bottom, 24)
                }
                .refreshable { await loadData() }
            }
        }
        .background(Theme.background)
        .task { await loadData() }
        .onChange(of: searchQuery) { _, newValue in
            searchTask?.cancel()
            if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResults = []
                searching = false
                return
            }
            searching = true
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await performSearch(newValue)
            }
        }
    }

    @ViewBuilder
    private func seasonSection(label: String, season: Season, year: Int, data: [SeasonalMedia]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: SeasonListDestination(season: season, year: year, label: label)) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(label)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(Formatters.seasonName(season.rawValue)) \(year)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 16)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(data) { item in
                        mediaCard(item)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func mediaCard(_ item: SeasonalMedia) -> some View {
        NavigationLink(value: MediaDetailDestination(mediaId: item.id)) {
            VStack(alignment: .leading, spacing: 0) {
                AsyncCoverImage(url: item.coverImage?.large, width: 120, height: 170, cornerRadius: 8)

                Text(item.title.display)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .padding(.top, 8)

                if let studio = Formatters.mainStudioName(item.studios) {
                    Text(studio)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }

                if let score = item.averageScore {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.primary)
                        Text("\(score)%")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var searchResultsView: some View {
        if searching && searchResults.isEmpty {
            Spacer()
            ProgressView().tint(Theme.primary)
            Spacer()
        } else if searchResults.isEmpty {
            Spacer()
            Text("No results found")
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(searchResults) { item in
                        NavigationLink(value: MediaDetailDestination(mediaId: item.id)) {
                            HStack(spacing: 12) {
                                AsyncCoverImage(url: item.coverImage?.medium, width: 70, height: 100, cornerRadius: 6)

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
                                                Image(systemName: "chart.bar.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(Theme.primary)
                                                Text("\(score)%")
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.textSecondary)
                                            }
                                        }
                                        if let format = item.format {
                                            Text(Formatters.formatType(format))
                                                .font(.caption)
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    if loadingMore {
                        ProgressView().tint(Theme.primary).padding()
                    }

                    if hasNextPage && !loadingMore {
                        Color.clear.frame(height: 1)
                            .onAppear { Task { await loadMoreSearch() } }
                    }
                }
            }
        }
    }

    private func loadData() async {
        if currentSeasonAnime.isEmpty { loading = true }
        error = nil
        do {
            async let current = AniListClient.shared.fetchSeasonalAnime(
                season: seasonInfo.season, year: seasonInfo.year, page: 1, perPage: 20, sort: "POPULARITY_DESC"
            )
            async let next = AniListClient.shared.fetchSeasonalAnime(
                season: nextSeasonInfo.season, year: nextSeasonInfo.year, page: 1, perPage: 20, sort: "POPULARITY_DESC"
            )
            let (c, n) = try await (current, next)
            currentSeasonAnime = c.media
            nextSeasonAnime = n.media
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func performSearch(_ query: String) async {
        currentPage = 1
        do {
            let result = try await AniListClient.shared.searchMedia(query: query, page: 1, perPage: 25)
            searchResults = result.media
            hasNextPage = result.hasNextPage
        } catch {}
        searching = false
    }

    private func loadMoreSearch() async {
        guard !loadingMore, hasNextPage, !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        loadingMore = true
        let nextPage = currentPage + 1
        do {
            let result = try await AniListClient.shared.searchMedia(query: searchQuery, page: nextPage, perPage: 25)
            searchResults.append(contentsOf: result.media)
            hasNextPage = result.hasNextPage
            currentPage = nextPage
        } catch {}
        loadingMore = false
    }
}
