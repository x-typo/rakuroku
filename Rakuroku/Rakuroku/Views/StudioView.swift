import SwiftUI

struct StudioView: View {
    let studioId: Int
    let studioName: String

    @Environment(AuthStore.self) private var authStore

    @State private var media: [StudioMedia] = []
    @State private var userStatusMap: [Int: MediaListStatus] = [:]
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(studioName)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.vertical, 16)

            if loading {
                ContentLoadingView()
            } else if let error {
                ContentErrorView(message: error) { Task { await loadData() } }
            } else {
                Text("\(media.count) productions")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(media) { item in
                            studioMediaRow(item)
                        }
                    }
                    .padding(.bottom, 32)
                }
                .refreshable { await loadData() }
            }
        }
        .background(Theme.background)
        .task { await loadData() }
    }

    @ViewBuilder
    private func studioMediaRow(_ item: StudioMedia) -> some View {
        let title = item.title.display
        let year = Formatters.formatYear(item.startDate)
        let format = Formatters.formatType(item.format)
        let epsText = item.type == .anime ? item.episodes.map { "\($0) eps" } ?? "" : ""
        let isUnreleased = item.status == "NOT_YET_RELEASED"
        let userStatus = userStatusMap[item.id]

        NavigationLink(value: MediaDetailDestination(mediaId: item.id)) {
            HStack(spacing: 0) {
                AsyncCoverImage(url: item.coverImage?.medium, width: 80, height: 120)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)

                    Text([format, isUnreleased ? "Unreleased" : year, epsText].filter { !$0.isEmpty }.joined(separator: " \u{2022} "))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    if let score = item.averageScore, !isUnreleased {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Theme.primary)
                            Text("\(score)%").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 2)
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
        do {
            async let studioData = AniListClient.shared.fetchStudioDetails(studioId: studioId)
            async let animeList = AniListClient.shared.fetchMediaList(type: .anime, username: authStore.username)
            let (s, list) = try await (studioData, animeList)
            media = s
            userStatusMap = Dictionary(uniqueKeysWithValues: list.map { ($0.media.id, $0.status) })
        } catch where error.isCancellation {
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
