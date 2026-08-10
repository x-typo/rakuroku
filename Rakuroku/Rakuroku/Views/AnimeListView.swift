import SwiftUI

struct MediaListView: View {

    let type: MediaType

    @Environment(AuthStore.self) private var authStore
    @Environment(MediaLibraryStore.self) private var mediaLibraryStore

    @State private var searchQuery = ""
    @State private var selectedFilter: String
    @State private var showFilter = false

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
        var result = mediaLibraryStore.entries(for: type)
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
        let libraryState = mediaLibraryStore.state(for: type)

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

            if case .failed(let message) = libraryState.phase,
               libraryState.hasUsableData {
                ContentWarningView(message: "List refresh failed. \(message)")
            }

            if !libraryState.hasUsableData,
               libraryState.phase == .idle || libraryState.phase == .loading {
                ContentLoadingView()
            } else if case .failed(let message) = libraryState.phase,
                      !libraryState.hasUsableData {
                ContentErrorView(message: message) {
                    Task { await loadData(force: true) }
                }
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
                .refreshable { await loadData(force: true) }
            }
        }
        .background(Theme.background)
        .task(id: authStore.mediaLibrarySession.id) { await loadData() }
        .sheet(isPresented: $showFilter) {
            let title = type == .anime ? "Anime List" : "Manga List"
            FilterSheet(title: title, filters: filters, selectedFilter: $selectedFilter)
        }
    }

    private func loadData(force: Bool = false) async {
        let session = authStore.mediaLibrarySession
        await mediaLibraryStore.load(type, session: session, force: force)
    }
}

struct AnimeListView: View {
    var body: some View { MediaListView(type: .anime) }
}
