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
                List {
                    if filteredEntries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: searchQuery.isEmpty ? "tray" : "magnifyingglass")
                                .font(.title)
                                .foregroundStyle(Theme.textSecondary)
                                .accessibilityHidden(true)
                            Text(searchQuery.isEmpty ? "No items in \(selectedFilter)" : "No matching titles")
                                .foregroundStyle(Theme.textSecondary)
                            if !searchQuery.isEmpty {
                                Button("Clear Search") { searchQuery = "" }
                                    .buttonStyle(.bordered)
                                    .tint(Theme.primary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredEntries) { entry in
                            MediaCardView(entry: entry, type: type)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await loadData() }
            }
        }
        .background(Theme.background)
        .task { await loadData() }
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
        } catch where error.isCancellation {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct AnimeListView: View {
    var body: some View { MediaListView(type: .anime) }
}
