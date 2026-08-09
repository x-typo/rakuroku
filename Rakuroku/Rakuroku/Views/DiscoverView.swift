import SwiftUI

struct DiscoverView: View {
    private struct SearchRequest: Hashable, Sendable {
        let query: String
        let generation: Int
    }

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
    @State private var searchError: String?
    @State private var loadMoreError: String?
    @State private var searchRequest = SearchRequest(query: "", generation: 0)

    private let seasonInfo = Formatters.currentSeason()
    private var nextSeasonInfo: (season: Season, year: Int) {
        Formatters.nextSeason(after: seasonInfo)
    }
    private var normalizedSearchQuery: String {
        normalizeSearchQuery(searchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(text: $searchQuery)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if !normalizedSearchQuery.isEmpty {
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
        .task(id: searchRequest) { await performSearch(searchRequest) }
        .onChange(of: searchQuery) { _, newValue in
            beginSearch(for: newValue)
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
        } else if let searchError, searchResults.isEmpty {
            ContentErrorView(message: searchError) { retrySearch() }
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

                    if let loadMoreError {
                        VStack(spacing: 8) {
                            Text(loadMoreError)
                                .font(.caption)
                                .foregroundStyle(Theme.error)
                                .multilineTextAlignment(.center)
                            Button("Retry") { Task { await loadMoreSearch() } }
                                .buttonStyle(.bordered)
                                .tint(Theme.primary)
                        }
                        .padding()
                    }

                    if hasNextPage && !loadingMore && loadMoreError == nil {
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
        } catch where error.isCancellation {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func beginSearch(for rawQuery: String) {
        let query = normalizeSearchQuery(rawQuery)
        searchRequest = SearchRequest(
            query: query,
            generation: searchRequest.generation &+ 1
        )
        searchResults = []
        currentPage = 1
        hasNextPage = false
        searching = !query.isEmpty
        loadingMore = false
        searchError = nil
        loadMoreError = nil
    }

    private func retrySearch() {
        guard !normalizedSearchQuery.isEmpty else { return }
        searchError = nil
        searching = true
        searchRequest = SearchRequest(
            query: normalizedSearchQuery,
            generation: searchRequest.generation &+ 1
        )
    }

    private func performSearch(_ request: SearchRequest) async {
        guard !request.query.isEmpty else { return }
        do {
            try await Task.sleep(for: .milliseconds(300))
            let result = try await AniListClient.shared.searchMedia(query: request.query, page: 1, perPage: 25)
            try Task.checkCancellation()
            guard request == searchRequest, request.query == normalizedSearchQuery else { return }
            searchResults = result.media
            hasNextPage = result.hasNextPage
            currentPage = 1
            searchError = nil
            loadMoreError = nil
            searching = false
        } catch where error.isCancellation {
        } catch {
            guard request == searchRequest, request.query == normalizedSearchQuery else { return }
            searchResults = []
            hasNextPage = false
            searchError = error.localizedDescription
            searching = false
        }
    }

    private func loadMoreSearch() async {
        let request = searchRequest
        guard !loadingMore,
              hasNextPage,
              !request.query.isEmpty,
              request.query == normalizedSearchQuery else { return }

        loadingMore = true
        loadMoreError = nil
        let nextPage = currentPage + 1
        do {
            let result = try await AniListClient.shared.searchMedia(query: request.query, page: nextPage, perPage: 25)
            try Task.checkCancellation()
            guard request == searchRequest, request.query == normalizedSearchQuery else { return }
            let existingIds = Set(searchResults.map(\.id))
            let newItems = result.media.filter { !existingIds.contains($0.id) }
            searchResults.append(contentsOf: newItems)
            hasNextPage = result.hasNextPage
            currentPage = nextPage
            loadingMore = false
        } catch where error.isCancellation {
        } catch {
            guard request == searchRequest, request.query == normalizedSearchQuery else { return }
            loadMoreError = error.localizedDescription
            loadingMore = false
        }
    }

    private func normalizeSearchQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
