import SwiftUI

struct AnimeListView: View {

    @Environment(AuthStore.self) private var authStore

    @State private var entries: [MediaListEntry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var searchQuery = ""
    @State private var selectedFilter = "Watching"
    @State private var showFilter = false
    @State private var hasLoadedOnce = false

    private let filters = ["All", "Watching", "Completed", "Dropped", "Planning"]

    private var filteredEntries: [MediaListEntry] {
        var result = entries
        if selectedFilter != "All" {
            let statusMap: [String: [MediaListStatus]] = [
                "Watching": [.current], "Completed": [.completed],
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
            // Header
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

            if loading {
                ContentLoadingView()
            } else if let error {
                ContentErrorView(message: error) { Task { await loadData() } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEntries) { entry in
                            MediaCardView(entry: entry, type: .anime)
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
            // Re-fetch on tab re-focus (like RN's useFocusEffect) to pick up progress changes
            if hasLoadedOnce { Task { await loadData() } }
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet(title: "Anime List", filters: filters, selectedFilter: $selectedFilter)
        }
    }

    private func loadData() async {
        if !hasLoadedOnce { loading = true }
        error = nil
        do {
            entries = try await AniListClient.shared.fetchMediaList(type: .anime, accessToken: authStore.accessToken)
            hasLoadedOnce = true
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
