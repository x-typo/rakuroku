import SwiftUI

struct MediaListView: View {

    let type: MediaType

    @Environment(AuthStore.self) private var authStore

    @State private var entries: [MediaListEntry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var searchQuery = ""
    @State private var selectedFilter: String
    @State private var showFilter = false
    @State private var hasLoadedOnce = false

    private var filters: [String] {
        type == .anime
            ? ["All", "Watching", "Completed", "Dropped", "Planning"]
            : ["All", "Reading", "Completed", "Dropped", "Planning"]
    }

    init(type: MediaType) {
        self.type = type
        self._selectedFilter = State(initialValue: type == .anime ? "Watching" : "Reading")
    }

    private var filteredEntries: [MediaListEntry] {
        var result = entries
        if selectedFilter != "All" {
            let statusMap: [String: [MediaListStatus]] = [
                "Watching": [.current], "Reading": [.current],
                "Completed": [.completed],
                "Dropped": [.dropped], "Planning": [.planning],
            ]
            if let statuses = statusMap[selectedFilter] {
                result = result.filter { statuses.contains($0.status) }
            }
        }
        if !searchQuery.isEmpty {
            result = result.filter { $0.media.title.matches(searchQuery) }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedFilter)
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .onTapGesture { showFilter = true }

            SearchBarView(text: $searchQuery)
                .padding(.bottom, 8)

            if loading {
                ContentLoadingView()
            } else if let error {
                ContentErrorView(message: error) { Task { await loadData() } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEntries) { entry in
                            MediaCardView(entry: entry, type: type)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .refreshable { await loadData() }
            }
        }
        .background(Theme.background)
        .task { await loadData() }
        .onAppear {
            if hasLoadedOnce { Task { await loadData() } }
        }
        .sheet(isPresented: $showFilter) {
            let title = type == .anime ? "Anime List" : "Manga List"
            FilterSheet(title: title, filters: filters, selectedFilter: $selectedFilter)
        }
    }

    private func loadData() async {
        if !hasLoadedOnce { loading = true }
        error = nil
        do {
            entries = try await AniListClient.shared.fetchMediaList(type: type, username: authStore.username, accessToken: authStore.accessToken)
            hasLoadedOnce = true
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// Tab wrappers
struct AnimeListView: View {
    var body: some View { MediaListView(type: .anime) }
}
