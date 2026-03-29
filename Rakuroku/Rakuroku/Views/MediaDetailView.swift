import SwiftUI

struct MediaDetailView: View {
    let mediaId: Int

    @Environment(AuthStore.self) private var authStore

    @State private var media: MediaDetails?
    @State private var userEntry: UserMediaEntry?
    @State private var loading = true
    @State private var error: String?

    // Modals
    @State private var showScoreModal = false
    @State private var showStatusModal = false
    @State private var showProgressModal = false
    @State private var updatingScore = false
    @State private var updatingStatus = false
    @State private var updatingProgress = false

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.primary)
            } else if let error {
                VStack(spacing: 16) {
                    Text(error).foregroundStyle(Theme.error)
                    Button("Retry") { Task { await loadData() } }
                        .buttonStyle(.borderedProminent).tint(Theme.primary)
                }
            } else if let media {
                mediaContent(media)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .task { await loadData() }
    }

    @ViewBuilder
    private func mediaContent(_ media: MediaDetails) -> some View {
        let title = media.title.display
        let studio = Formatters.mainStudio(media.studios)
        let userStatus = userEntry?.status
        let canEditScore = authStore.isAuthenticated && userEntry != nil

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Banner
                if let banner = media.bannerImage, let url = URL(string: banner) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(Theme.surface)
                        }
                    }
                    .frame(height: 180)
                    .clipped()
                } else {
                    Rectangle().fill(Theme.surface).frame(height: 80)
                }

                // Header: cover + title + status
                HStack(alignment: .top, spacing: 16) {
                    AsyncCoverImage(url: media.coverImage?.large, width: 120, height: 180, cornerRadius: 8)
                        .shadow(radius: 8)
                        .offset(y: -40)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(3)

                        if authStore.isAuthenticated, userEntry == nil {
                            Button("Add") { showStatusModal = true }
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Theme.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        if let status = userStatus,
                           let label = Formatters.statusLabel(status),
                           let color = Formatters.statusColor(status) {
                            Button { if canEditScore { showStatusModal = true } } label: {
                                Text(label)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(color)
                            }
                            .disabled(!canEditScore)
                        }

                        if let next = media.nextAiringEpisode {
                            Text(Formatters.nextAiring(next.airingAt, episode: next.episode))
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)

                // Stats row
                statsRow(media)

                // Action buttons (score, progress)
                if canEditScore {
                    actionButtons(media)
                }

                // Genres
                if let genres = media.genres, !genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(genres, id: \.self) { genre in
                                Text(genre)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Theme.surfaceLight)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 12)
                }

                // Description
                if let desc = media.description {
                    Text(Formatters.stripHtml(desc))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }

                // Info grid
                infoGrid(media, studio: studio)

                // Relations
                if let relations = media.relations?.edges, !relations.isEmpty {
                    relationsSection(relations)
                }

                // Share button
                Button {
                    let url = "https://anilist.co/\(media.type?.rawValue.lowercased() ?? "anime")/\(media.id)"
                    let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.windows.first?.rootViewController {
                        root.present(av, animated: true)
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .refreshable { await loadData() }
        .sheet(isPresented: $showScoreModal) { scoreSheet }
        .sheet(isPresented: $showStatusModal) { statusSheet(media) }
        .sheet(isPresented: $showProgressModal) { progressSheet(media) }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func statsRow(_ media: MediaDetails) -> some View {
        HStack(spacing: 16) {
            if let score = media.averageScore {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill").foregroundStyle(Theme.primary)
                    Text("\(score)%").foregroundStyle(Theme.textPrimary)
                }
                .font(.subheadline)
            }
            if let pop = media.popularity {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(Theme.error)
                    Text("\(pop)").foregroundStyle(Theme.textPrimary)
                }
                .font(.subheadline)
            }
            if let eps = media.episodes {
                Text("\(eps) episodes")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let chaps = media.chapters {
                Text("\(chaps) chapters")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func actionButtons(_ media: MediaDetails) -> some View {
        HStack(spacing: 12) {
            Button { showScoreModal = true } label: {
                let score = userEntry?.score ?? 0
                Label(score > 0 ? String(format: "%.0f ★", score) : "Rate", systemImage: "star")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button { showProgressModal = true } label: {
                let progress = userEntry?.progress ?? 0
                let total = media.type == .anime ? media.episodes : media.chapters
                let text = total.map { "\(progress)/\($0)" } ?? "\(progress)"
                Label(text, systemImage: "number")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func infoGrid(_ media: MediaDetails, studio: Studio?) -> some View {
        let rows: [(String, String)] = [
            ("Format", Formatters.formatType(media.format)),
            ("Status", Formatters.formatStatus(media.status)),
            ("Season", Formatters.seasonText(media.season, year: media.seasonYear)),
            ("Start", Formatters.formatFuzzyDate(media.startDate)),
            ("End", Formatters.formatFuzzyDate(media.endDate)),
            ("Source", Formatters.formatSource(media.source)),
            ("Duration", media.duration.map { "\($0) min/ep" } ?? ""),
        ].filter { !$0.1.isEmpty }

        VStack(alignment: .leading, spacing: 8) {
            if let studio {
                HStack {
                    Text("Studio")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    NavigationLink(value: StudioDestination(studioId: studio.id, studioName: studio.name)) {
                        Text(studio.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.primary)
                    }
                }
            }

            ForEach(rows, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func relationsSection(_ relations: [MediaRelationEdge]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Relations")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(relations.enumerated()), id: \.offset) { _, edge in
                        NavigationLink(value: MediaDetailDestination(mediaId: edge.node.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncCoverImage(url: edge.node.coverImage?.large, width: 100, height: 140, cornerRadius: 6)
                                Text(Formatters.formatRelationType(edge.relationType))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.primary)
                                Text(edge.node.title.display)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                            }
                            .frame(width: 100)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 24)
    }

    // MARK: - Sheets

    @ViewBuilder
    private var scoreSheet: some View {
        VStack(spacing: 16) {
            Text("Rate").font(.title3.bold()).foregroundStyle(Theme.textPrimary)
            ForEach([10, 9, 8, 7, 6, 5, 4, 3, 2, 1], id: \.self) { score in
                Button {
                    Task { await handleScoreUpdate(Double(score)) }
                } label: {
                    HStack {
                        Text("\(score)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if Int(userEntry?.score ?? 0) == score {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.primary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            if updatingScore { ProgressView().tint(Theme.primary) }
        }
        .padding(.vertical, 16)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func statusSheet(_ media: MediaDetails) -> some View {
        VStack(spacing: 8) {
            Text("Status").font(.title3.bold()).foregroundStyle(Theme.textPrimary).padding(.top, 16)
            ForEach(MediaListStatus.allCases, id: \.self) { status in
                Button {
                    if userEntry != nil {
                        Task { await handleStatusUpdate(status) }
                    } else {
                        Task { await handleAddToList(status) }
                    }
                } label: {
                    HStack {
                        Text(Formatters.statusLabel(status, type: media.type) ?? status.rawValue)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if userEntry?.status == status {
                            Image(systemName: "checkmark").foregroundStyle(Theme.primary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            if userEntry != nil {
                Button(role: .destructive) {
                    Task { await handleDeleteEntry() }
                } label: {
                    Text("Remove from List")
                        .foregroundStyle(Theme.error)
                        .padding(.vertical, 12)
                }
            }
            if updatingStatus { ProgressView().tint(Theme.primary) }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func progressSheet(_ media: MediaDetails) -> some View {
        VStack(spacing: 24) {
            Text("Progress").font(.title3.bold()).foregroundStyle(Theme.textPrimary)

            let progress = userEntry?.progress ?? 0
            let total = media.type == .anime ? media.episodes : media.chapters

            Text(total.map { "\(progress) / \($0)" } ?? "\(progress)")
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 24) {
                Button {
                    Task { await handleProgressUpdate(delta: -1) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.error)
                }
                .disabled(progress <= 0 || updatingProgress)

                Button {
                    Task { await handleProgressUpdate(delta: 1) }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.primary)
                }
                .disabled(total.map { progress >= $0 } ?? false || updatingProgress)
            }

            if updatingProgress { ProgressView().tint(Theme.primary) }
        }
        .padding(24)
        .presentationDetents([.height(250)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Actions

    private func loadData() async {
        if media == nil { loading = true }
        error = nil
        do {
            async let details = AniListClient.shared.fetchMediaDetails(id: mediaId)
            async let entry = AniListClient.shared.fetchUserMediaEntry(mediaId: mediaId)
            let (d, e) = try await (details, entry)
            media = d
            userEntry = e
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func handleScoreUpdate(_ score: Double) async {
        guard let token = authStore.accessToken, let entry = userEntry else { return }
        updatingScore = true
        do {
            try await AniListClient.shared.updateScore(mediaId: mediaId, score: score, accessToken: token)
            userEntry = UserMediaEntry(id: entry.id, status: entry.status, score: score, progress: entry.progress)
            showScoreModal = false
        } catch {}
        updatingScore = false
    }

    private func handleStatusUpdate(_ status: MediaListStatus) async {
        guard let token = authStore.accessToken, let entry = userEntry else { return }
        updatingStatus = true
        do {
            try await AniListClient.shared.updateStatus(mediaId: mediaId, status: status, accessToken: token)
            var newScore = entry.score
            if status == .dropped {
                try await AniListClient.shared.updateScore(mediaId: mediaId, score: 1, accessToken: token)
                newScore = 1
            }
            userEntry = UserMediaEntry(id: entry.id, status: status, score: newScore, progress: entry.progress)
            showStatusModal = false
        } catch {}
        updatingStatus = false
    }

    private func handleDeleteEntry() async {
        guard let token = authStore.accessToken, let entry = userEntry else { return }
        updatingStatus = true
        do {
            try await AniListClient.shared.deleteMediaListEntry(entryId: entry.id, accessToken: token)
            userEntry = nil
            showStatusModal = false
        } catch {}
        updatingStatus = false
    }

    private func handleAddToList(_ status: MediaListStatus) async {
        guard let token = authStore.accessToken else { return }
        updatingStatus = true
        do {
            let entry = try await AniListClient.shared.addToList(mediaId: mediaId, status: status, accessToken: token)
            userEntry = entry
            showStatusModal = false
        } catch {}
        updatingStatus = false
    }

    private func handleProgressUpdate(delta: Int) async {
        guard let token = authStore.accessToken, let entry = userEntry else { return }
        let total = media?.type == .anime ? media?.episodes : media?.chapters
        let newProgress = max(0, entry.progress + delta)
        if let total, newProgress > total { return }

        updatingProgress = true
        do {
            try await AniListClient.shared.updateProgress(mediaId: mediaId, progress: newProgress, accessToken: token)
            userEntry = UserMediaEntry(id: entry.id, status: entry.status, score: entry.score, progress: newProgress)
        } catch {}
        updatingProgress = false
    }
}
