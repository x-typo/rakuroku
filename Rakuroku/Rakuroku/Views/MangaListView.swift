import SwiftUI

struct MangaListView: View {

    @Environment(AuthStore.self) private var authStore

    @State private var entries: [MediaListEntry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var searchQuery = ""
    @State private var selectedFilter = "Reading"
    @State private var showFilter = false
    @State private var hasLoadedOnce = false

    private let filters = ["All", "Reading", "Completed", "Dropped", "Planning"]

    private var filteredEntries: [MediaListEntry] {
        var result = entries
        if selectedFilter != "All" {
            let statusMap: [String: [MediaListStatus]] = [
                "Reading": [.current], "Completed": [.completed],
                "Dropped": [.dropped], "Planning": [.planning],
            ]
            if let statuses = statusMap[selectedFilter] {
                result = result.filter { statuses.contains($0.status) }
            }
        }
        if !searchQuery.isEmpty {
            result = result.filter { $0.media.title.matches(searchQuery) }
        }
        return result
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

            if loading {
                ContentLoadingView()
            } else if let error {
                ContentErrorView(message: error) { Task { await loadData() } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEntries) { entry in
                            MediaCardView(entry: entry, type: .manga)
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
            FilterSheet(title: "Manga List", filters: filters, selectedFilter: $selectedFilter)
        }
    }

    private func loadData() async {
        if !hasLoadedOnce { loading = true }
        error = nil
        do {
            entries = try await AniListClient.shared.fetchMediaList(type: .manga, accessToken: authStore.accessToken)
            hasLoadedOnce = true
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
