import SwiftUI

struct HomeSeasonLoadTracker: Sendable {
    private(set) var generation: UInt64 = 0

    mutating func begin() -> UInt64 {
        generation &+= 1
        return generation
    }

    func isCurrent(_ requestGeneration: UInt64) -> Bool {
        requestGeneration == generation
    }
}

enum HomeUpNextRefreshPolicy {
    nonisolated static func shouldReloadAfterActivation(
        scheduledRefreshEpoch: Int?,
        nowEpoch: Int
    ) -> Bool {
        guard let scheduledRefreshEpoch else { return false }
        return scheduledRefreshEpoch <= nowEpoch
    }

    static func shouldAdvanceAfterScheduledLoad(
        phase: MediaLibraryPhase
    ) -> Bool {
        if case .loaded = phase { return true }
        return false
    }
}

struct HomeView: View {
    private struct SearchRequest: Hashable, Sendable {
        let query: String
        let generation: Int
    }

    private struct UpNextRefreshRequest: Hashable, Sendable {
        let sessionID: MediaLibrarySession.ID
        let refreshEpoch: Int?
    }

    @Environment(AuthStore.self) private var authStore
    @Environment(MediaLibraryStore.self) private var mediaLibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
    @State private var upNextNowEpoch = Int(Date().timeIntervalSince1970)
    @State private var seasonLoadTracker = HomeSeasonLoadTracker()

    private let seasonInfo = Formatters.currentSeason()
    private var nextSeasonInfo: (season: Season, year: Int) {
        Formatters.nextSeason(after: seasonInfo)
    }
    private var normalizedSearchQuery: String {
        normalizeSearchQuery(searchQuery)
    }
    private var carouselMetadataLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }
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
    private var upNextItems: [MediaLibraryUpNextItem] {
        mediaLibraryStore.upNextItems(
            activeSessionID: activeSessionID,
            nowEpoch: upNextNowEpoch
        )
    }
    private var upNextRefreshRequest: UpNextRefreshRequest {
        UpNextRefreshRequest(
            sessionID: activeSessionID,
            refreshEpoch: mediaLibraryStore.nextUpNextRefreshEpoch(
                activeSessionID: activeSessionID,
                nowEpoch: upNextNowEpoch
            )
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
            SearchBarView(text: $searchQuery)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if !normalizedSearchQuery.isEmpty {
                searchResultsView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let personalizationWarning {
                            ContentWarningView(message: personalizationWarning)
                        }

                        upNextSection
                        seasonsSection
                    }
                    .padding(.bottom, 24)
                }
                .refreshable { await refreshData() }
            }
        }
        .background(Theme.background)
        .task { await loadData() }
        .task(id: authStore.mediaLibrarySession.id) { await loadLibrary() }
        .task(id: searchRequest) { await performSearch(searchRequest) }
        .task(id: upNextRefreshRequest) {
            await refreshUpNext(at: upNextRefreshRequest)
        }
        .task(id: scenePhase) { await refreshUpNextAfterActivation() }
        .onChange(of: searchQuery) { _, newValue in
            beginSearch(for: newValue)
        }
    }

    @ViewBuilder
    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Up Next")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)

            if hasCurrentAnimeSnapshot {
                if upNextItems.isEmpty {
                    Text("You're caught up for now.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(upNextItems) { item in
                                upNextCard(item)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            } else if case .failed = mediaLibraryStore.state(for: .anime).phase {
                Text("Up Next is unavailable until your list can be loaded.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.primary)
                    Text("Checking your list…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func upNextCard(_ item: MediaLibraryUpNextItem) -> some View {
        NavigationLink(value: MediaDetailDestination(mediaId: item.entry.media.id)) {
            VStack(alignment: .leading, spacing: 0) {
                AsyncCoverImage(
                    url: item.entry.media.coverImage?.large,
                    width: 120,
                    height: 170,
                    cornerRadius: 8
                )

                Text(item.entry.media.title.display)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .padding(.top, 8)

                Label("Episode \(item.nextEpisode)", systemImage: "play.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(carouselMetadataLineLimit, reservesSpace: true)
                    .padding(.top, 4)
            }
            .frame(width: 120)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.entry.media.title.display)
        .accessibilityValue("Episode \(item.nextEpisode) is ready")
    }

    @ViewBuilder
    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Seasons")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)

            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.primary)
                    Text("Loading seasons…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else if let error {
                VStack(alignment: .leading, spacing: 10) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Theme.error)
                    Button("Retry") { Task { await loadData() } }
                        .buttonStyle(.bordered)
                        .tint(Theme.primary)
                }
                .padding(.horizontal, 16)
            } else {
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

            if data.isEmpty {
                Text("No anime found for this season.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(data) { item in
                            mediaCard(item)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func mediaCard(_ item: SeasonalMedia) -> some View {
        let libraryState = mediaLibraryStore.state(for: .anime)
        let userStatus = hasCurrentAnimeSnapshot
            ? mediaLibraryStore.status(mediaID: item.id, type: .anime)
            : nil
        let studioName = Formatters.mainStudioName(item.studios)
        let statusLabel = Formatters.statusLabel(userStatus)
        let statusColor = Formatters.statusColor(userStatus)

        NavigationLink(value: MediaDetailDestination(mediaId: item.id)) {
            VStack(alignment: .leading, spacing: 0) {
                AsyncCoverImage(url: item.coverImage?.large, width: 120, height: 170, cornerRadius: 8)

                Text(item.title.display)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .padding(.top, 8)

                Text(studioName ?? " ")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(carouselMetadataLineLimit, reservesSpace: true)
                    .padding(.top, 2)
                    .accessibilityHidden(studioName == nil)

                Text(statusLabel ?? " ")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor ?? Theme.textSecondary)
                    .lineLimit(carouselMetadataLineLimit, reservesSpace: true)
                    .padding(.top, 4)
                    .accessibilityHidden(statusLabel == nil)

                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.primary)
                        .opacity(item.averageScore == nil ? 0 : 1)
                    Text(item.averageScore.map { "\($0)%" } ?? " ")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(carouselMetadataLineLimit, reservesSpace: true)
                }
                .padding(.top, 4)
                .accessibilityHidden(item.averageScore == nil)
            }
            .frame(width: 120)
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
        let requestGeneration = seasonLoadTracker.begin()

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
            try Task.checkCancellation()
            guard seasonLoadTracker.isCurrent(requestGeneration) else { return }
            currentSeasonAnime = c.media
            nextSeasonAnime = n.media
        } catch where error.isCancellation {
        } catch {
            guard seasonLoadTracker.isCurrent(requestGeneration) else { return }
            self.error = error.localizedDescription
        }
        guard seasonLoadTracker.isCurrent(requestGeneration) else { return }
        loading = false
    }

    private func loadLibrary() async {
        let session = authStore.mediaLibrarySession
        await mediaLibraryStore.load(.anime, session: session)
    }

    private func refreshData() async {
        let session = authStore.mediaLibrarySession
        async let seasonalLoad: Void = loadData()
        async let libraryLoad: Void = mediaLibraryStore.load(.anime, session: session, force: true)
        _ = await (seasonalLoad, libraryLoad)
    }

    private func refreshUpNext(at request: UpNextRefreshRequest) async {
        let session = authStore.mediaLibrarySession
        guard session.id == request.sessionID else { return }
        guard let refreshEpoch = request.refreshEpoch else { return }
        let delay = max(0, refreshEpoch - Int(Date().timeIntervalSince1970))
        do {
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }
            try Task.checkCancellation()
            guard session.id == activeSessionID else { return }
            await mediaLibraryStore.load(.anime, session: session, force: true)
            try Task.checkCancellation()
            guard session.id == activeSessionID else { return }
            guard HomeUpNextRefreshPolicy.shouldAdvanceAfterScheduledLoad(
                phase: mediaLibraryStore.state(for: .anime).phase
            ) else {
                return
            }
            upNextNowEpoch = max(refreshEpoch, Int(Date().timeIntervalSince1970))
        } catch {
            return
        }
    }

    private func refreshUpNextAfterActivation() async {
        guard scenePhase == .active else { return }
        let nowEpoch = Int(Date().timeIntervalSince1970)
        let scheduledRefreshEpoch = mediaLibraryStore.nextUpNextRefreshEpoch(
            activeSessionID: activeSessionID,
            nowEpoch: upNextNowEpoch
        )
        upNextNowEpoch = nowEpoch

        guard HomeUpNextRefreshPolicy.shouldReloadAfterActivation(
            scheduledRefreshEpoch: scheduledRefreshEpoch,
            nowEpoch: nowEpoch
        ) else {
            return
        }
        let session = authStore.mediaLibrarySession
        await mediaLibraryStore.load(.anime, session: session, force: true)
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
