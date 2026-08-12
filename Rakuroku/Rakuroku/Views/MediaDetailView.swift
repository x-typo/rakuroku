import SwiftUI

struct MediaDetailView: View {
    private struct LoadID: Hashable {
        let mediaID: Int
        let sessionID: MediaLibrarySession.ID
    }

    private enum EntryMutation: Equatable {
        case score
        case status
        case progress
    }

    private struct ActiveEntryMutation: Equatable {
        let id = UUID()
        let kind: EntryMutation
        let loadID: LoadID
        let type: MediaType
        let media: Media

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
    }

    private struct MutationContext {
        let session: MediaLibrarySession
        let loadID: LoadID
        let accessToken: String
    }

    let mediaId: Int

    @Environment(AuthStore.self) private var authStore
    @Environment(MediaLibraryStore.self) private var mediaLibraryStore

    @State private var media: MediaDetails?
    @State private var userEntry: UserMediaEntry?
    @State private var entryLookupFailed = false
    @State private var loadedID: LoadID?
    @State private var loading = true
    @State private var error: String?

    @State private var showScoreModal = false
    @State private var showStatusModal = false
    @State private var showProgressModal = false
    @State private var entryMutation: ActiveEntryMutation?
    @State private var mutationError: String?
    @State private var showDeleteConfirmation = false

    private var mutationContext: MutationContext? {
        let session = authStore.mediaLibrarySession
        let currentLoadID = LoadID(mediaID: mediaId, sessionID: session.id)
        guard loadedID == currentLoadID,
              let accessToken = MediaLibraryMutationAuthorization.accessToken(
                  displayedSessionID: loadedID?.sessionID,
                  currentSession: session
              ) else {
            return nil
        }
        return MutationContext(
            session: session,
            loadID: currentLoadID,
            accessToken: accessToken
        )
    }

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack(spacing: 16) {
                    Text(error).foregroundStyle(Theme.error)
                    Button("Retry") { Task { await loadData() } }
                        .buttonStyle(.borderedProminent).tint(Theme.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let media {
                mediaContent(media)
            }
        }
        .background(Theme.background)
        .task(id: LoadID(mediaID: mediaId, sessionID: authStore.mediaLibrarySession.id)) {
            await loadData()
        }
    }

    @ViewBuilder
    private func mediaContent(_ media: MediaDetails) -> some View {
        let title = media.title.display
        let studio = Formatters.mainStudio(media.studios)
        let userStatus = userEntry?.status
        let canEditScore = mutationContext != nil && userEntry != nil && !entryLookupFailed

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let banner = media.bannerImage, let url = URL(string: banner) {
                    GeometryReader { geo in
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: 180)
                                    .clipped()
                            } else {
                                Rectangle().fill(Theme.surface)
                            }
                        }
                    }
                    .frame(height: 180)
                } else {
                    Rectangle().fill(Theme.surface).frame(height: 80)
                }

                HStack(alignment: .top, spacing: 16) {
                    AsyncCoverImage(url: media.coverImage?.large, width: 120, height: 180, cornerRadius: 8)
                        .shadow(radius: 8)
                        .offset(y: -40)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(3)

                        if mutationContext != nil, userEntry == nil, !entryLookupFailed {
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

                statsRow(media)

                if media.type == .anime {
                    WatchSectionView(media: media, userEntry: userEntry, entryLookupFailed: entryLookupFailed)
                }

                if canEditScore {
                    actionButtons(media)
                }

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

                if let desc = media.description {
                    Text(Formatters.stripHtml(desc))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }

                infoGrid(media, studio: studio)

                if let relations = media.relations?.edges, !relations.isEmpty {
                    relationsSection(relations)
                }

                Spacer().frame(height: 32)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await loadData() }
        .sheet(isPresented: $showScoreModal) { scoreSheet }
        .sheet(isPresented: $showStatusModal) { statusSheet(media) }
        .sheet(isPresented: $showProgressModal) { progressSheet(media) }
        .alert("AniList Error", isPresented: Binding(get: { mutationError != nil }, set: { if !$0 { mutationError = nil } })) {
            Button("OK") { mutationError = nil }
        } message: {
            Text(mutationError ?? "")
        }
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

            Spacer()

            ShareLink(item: URL(string: "https://anilist.co/\(media.type?.rawValue.lowercased() ?? "anime")/\(media.id)")!) {
                Image(systemName: "square.and.arrow.up")
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
                Group {
                    if score > 0 {
                        Text(String(format: "%.0f ★", score))
                    } else {
                        Label("Rate", systemImage: "star")
                    }
                }
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
        .disabled(entryMutation != nil || mutationContext == nil)
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
                    ForEach(relations, id: \.node.id) { edge in
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
        let currentScore = Int(userEntry?.score ?? 0)
        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        VStack(spacing: 20) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach([10, 9, 8, 7, 6, 5, 4, 3, 2, 1], id: \.self) { score in
                    Button {
                        Task { await handleScoreUpdate(Double(score)) }
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(score)")
                                .font(.title.bold())
                                .foregroundStyle(.white)
                            Text(scoreLabel(score))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(scoreGradient(score))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            if currentScore == score {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white, lineWidth: 2)
                            }
                        }
                    }
                    .disabled(entryMutation != nil || mutationContext == nil)
                }
            }
            .padding(.horizontal, 16)

            if entryMutation?.kind == .score { ProgressView().tint(Theme.primary) }
        }
        .padding(.top, 40)
        .padding(.bottom, 20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(entryMutation != nil)
    }

    private func scoreGradient(_ score: Int) -> Color {
        switch score {
        case 10: Color(red: 0.0, green: 0.7, blue: 0.3)
        case 9: Color(red: 0.1, green: 0.65, blue: 0.3)
        case 8: Color(red: 0.2, green: 0.6, blue: 0.3)
        case 7: Color(red: 0.4, green: 0.6, blue: 0.2)
        case 6: Color(red: 0.6, green: 0.6, blue: 0.1)
        case 5: Color(red: 0.7, green: 0.55, blue: 0.0)
        case 4: Color(red: 0.8, green: 0.45, blue: 0.0)
        case 3: Color(red: 0.85, green: 0.3, blue: 0.0)
        case 2: Color(red: 0.9, green: 0.2, blue: 0.0)
        case 1: Color(red: 0.85, green: 0.1, blue: 0.1)
        default: Theme.surface
        }
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 10: "Masterpiece"
        case 9: "Great"
        case 8: "Very Good"
        case 7: "Good"
        case 6: "Fine"
        case 5: "Average"
        case 4: "Bad"
        case 3: "Very Bad"
        case 2: "Horrible"
        case 1: "Appalling"
        default: ""
        }
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
                .disabled(entryMutation != nil || mutationContext == nil)
            }
            if userEntry != nil {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("Remove from List")
                        .foregroundStyle(Theme.error)
                        .padding(.vertical, 12)
                }
                .disabled(entryMutation != nil || mutationContext == nil)
            }
            if entryMutation?.kind == .status { ProgressView().tint(Theme.primary) }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(entryMutation != nil)
        .confirmationDialog(
            "Remove from List?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await handleDeleteEntry() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the title from your AniList account.")
        }
    }

    @ViewBuilder
    private func progressSheet(_ media: MediaDetails) -> some View {
        let progress = userEntry?.progress ?? 0
        let total = media.type == .anime ? media.episodes : media.chapters
        let fraction: Double = if let total, total > 0 { Double(progress) / Double(total) } else { 0 }

        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(Theme.surfaceLight, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: fraction)

                VStack(spacing: 2) {
                    Text("\(progress)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(total.map { "of \($0)" } ?? (media.type == .manga ? "chapters" : "episodes"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 150, height: 150)

            HStack(spacing: 40) {
                Button {
                    Task { await handleProgressUpdate(delta: -1) }
                } label: {
                    Image(systemName: "minus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Theme.error)
                        .clipShape(Circle())
                }
                .disabled(progress <= 0 || entryMutation != nil || mutationContext == nil)
                .opacity(progress <= 0 || entryMutation != nil || mutationContext == nil ? 0.4 : 1)
                .accessibilityLabel("Decrease progress")

                Button {
                    Task { await handleProgressUpdate(delta: 1) }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Theme.primary)
                        .clipShape(Circle())
                }
                .disabled(total.map { progress >= $0 } ?? false || entryMutation != nil || mutationContext == nil)
                .opacity(total.map { progress >= $0 } ?? false || entryMutation != nil || mutationContext == nil ? 0.4 : 1)
                .accessibilityLabel("Increase progress")
            }

            if entryMutation?.kind == .progress { ProgressView().tint(Theme.primary) }
        }
        .padding(24)
        .presentationDetents([.height(320)])
        .interactiveDismissDisabled(entryMutation != nil)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Actions

    private func loadData() async {
        let session = authStore.mediaLibrarySession
        let loadID = LoadID(mediaID: mediaId, sessionID: session.id)
        if loadedID != loadID {
            loadedID = nil
            userEntry = nil
            entryLookupFailed = false
            entryMutation = nil
            mutationError = nil
            loading = true
        } else if media == nil {
            loading = true
        }
        error = nil
        do {
            let details = try await AniListClient.shared.fetchMediaDetails(id: mediaId)
            try Task.checkCancellation()
            guard authStore.mediaLibrarySession.id == session.id else { return }
            media = details
            entryLookupFailed = false
            do {
                let entry = try await AniListClient.shared.fetchUserMediaEntry(
                    mediaId: mediaId,
                    username: session.id.username,
                    accessToken: session.accessToken
                )
                try Task.checkCancellation()
                guard authStore.mediaLibrarySession.id == session.id else { return }
                userEntry = entry
                loadedID = loadID
            } catch where error.isCancellation {
                throw error
            } catch {
                guard authStore.mediaLibrarySession.id == session.id else { return }
                userEntry = nil
                entryLookupFailed = true
                mutationError = error.localizedDescription
                loadedID = loadID
            }
        } catch where error.isCancellation {
        } catch {
            guard authStore.mediaLibrarySession.id == session.id else { return }
            self.error = error.localizedDescription
            loadedID = loadID
        }
        guard authStore.mediaLibrarySession.id == session.id else { return }
        loading = false
    }

    private func handleScoreUpdate(_ score: Double) async {
        guard let context = mutationContext,
              entryMutation == nil,
              userEntry != nil,
              let details = media,
              let type = details.type else {
            return
        }
        let mutation = mediaLibraryStore.beginMutation(
            mediaID: mediaId,
            type: type,
            sessionID: context.session.id
        )
        let activeMutation = ActiveEntryMutation(
            kind: .score,
            loadID: context.loadID,
            type: type,
            media: details.libraryMedia
        )
        entryMutation = activeMutation
        mutationError = nil
        defer { finishEntryMutation(activeMutation) }
        do {
            let updatedEntry = try await AniListClient.shared.updateScore(
                mediaId: mediaId,
                score: score,
                accessToken: context.accessToken
            )
            guard applySuccessfulMutation(updatedEntry, mutation: mutation, activeMutation: activeMutation) else { return }
            showScoreModal = false
        } catch where error.isCancellation {
        } catch {
            guard authStore.mediaLibrarySession.id == activeMutation.loadID.sessionID,
                  loadedID == activeMutation.loadID else { return }
            mutationError = error.localizedDescription
        }
    }

    private func handleStatusUpdate(_ status: MediaListStatus) async {
        guard let context = mutationContext,
              entryMutation == nil,
              userEntry != nil,
              let details = media,
              let type = details.type else {
            return
        }
        let mutation = mediaLibraryStore.beginMutation(
            mediaID: mediaId,
            type: type,
            sessionID: context.session.id
        )
        let activeMutation = ActiveEntryMutation(
            kind: .status,
            loadID: context.loadID,
            type: type,
            media: details.libraryMedia
        )
        entryMutation = activeMutation
        mutationError = nil
        defer { finishEntryMutation(activeMutation) }
        do {
            let updatedEntry = try await AniListClient.shared.updateStatus(
                mediaId: mediaId,
                status: status,
                accessToken: context.accessToken
            )
            guard applySuccessfulMutation(updatedEntry, mutation: mutation, activeMutation: activeMutation) else { return }
            showStatusModal = false
        } catch where error.isCancellation {
        } catch {
            guard authStore.mediaLibrarySession.id == activeMutation.loadID.sessionID,
                  loadedID == activeMutation.loadID else { return }
            mutationError = error.localizedDescription
        }
    }

    private func handleDeleteEntry() async {
        guard let context = mutationContext,
              entryMutation == nil,
              let entry = userEntry,
              let details = media,
              let type = details.type else {
            return
        }
        let mutation = mediaLibraryStore.beginMutation(
            mediaID: mediaId,
            type: type,
            sessionID: context.session.id
        )
        let activeMutation = ActiveEntryMutation(
            kind: .status,
            loadID: context.loadID,
            type: type,
            media: details.libraryMedia
        )
        entryMutation = activeMutation
        mutationError = nil
        defer { finishEntryMutation(activeMutation) }
        do {
            try await AniListClient.shared.deleteMediaListEntry(
                entryId: entry.id,
                accessToken: context.accessToken
            )
            guard authStore.mediaLibrarySession.id == activeMutation.loadID.sessionID else { return }
            let reconciliation = mediaLibraryStore.reconcileDeletion(
                entryID: entry.id,
                mutation: mutation
            )
            guard loadedID == activeMutation.loadID else { return }
            userEntry = MediaDetailMutationResolution.afterDeletion(
                reconciliation: reconciliation,
                canonicalEntry: mediaLibraryStore.entry(
                    mediaID: activeMutation.loadID.mediaID,
                    type: activeMutation.type
                )
            )
            guard reconciliation.shouldApplyLocally else { return }
            showStatusModal = false
        } catch where error.isCancellation {
        } catch {
            guard authStore.mediaLibrarySession.id == activeMutation.loadID.sessionID,
                  loadedID == activeMutation.loadID else { return }
            mutationError = error.localizedDescription
        }
    }

    private func handleAddToList(_ status: MediaListStatus) async {
        guard let context = mutationContext,
              entryMutation == nil,
              let details = media,
              let type = details.type else {
            return
        }
        let mutation = mediaLibraryStore.beginMutation(
            mediaID: mediaId,
            type: type,
            sessionID: context.session.id
        )
        let activeMutation = ActiveEntryMutation(
            kind: .status,
            loadID: context.loadID,
            type: type,
            media: details.libraryMedia
        )
        entryMutation = activeMutation
        mutationError = nil
        defer { finishEntryMutation(activeMutation) }
        do {
            let entry = try await AniListClient.shared.addToList(
                mediaId: mediaId,
                status: status,
                accessToken: context.accessToken
            )
            guard applySuccessfulMutation(entry, mutation: mutation, activeMutation: activeMutation) else { return }
            showStatusModal = false
        } catch where error.isCancellation {
        } catch {
            guard authStore.mediaLibrarySession.id == activeMutation.loadID.sessionID,
                  loadedID == activeMutation.loadID else { return }
            mutationError = error.localizedDescription
        }
    }

    private func handleProgressUpdate(delta: Int) async {
        guard let context = mutationContext,
              entryMutation == nil,
              let entry = userEntry,
              let details = media,
              let type = details.type else {
            return
        }
        let total = type == .anime ? details.episodes : details.chapters
        let newProgress = max(0, entry.progress + delta)
        if let total, newProgress > total { return }

        let mutation = mediaLibraryStore.beginMutation(
            mediaID: mediaId,
            type: type,
            sessionID: context.session.id
        )
        let activeMutation = ActiveEntryMutation(
            kind: .progress,
            loadID: context.loadID,
            type: type,
            media: details.libraryMedia
        )
        entryMutation = activeMutation
        mutationError = nil
        defer { finishEntryMutation(activeMutation) }
        do {
            let updatedEntry = try await AniListClient.shared.updateProgress(
                mediaId: mediaId,
                progress: newProgress,
                accessToken: context.accessToken
            )
            guard applySuccessfulMutation(updatedEntry, mutation: mutation, activeMutation: activeMutation) else { return }
        } catch where error.isCancellation {
        } catch {
            guard authStore.mediaLibrarySession.id == activeMutation.loadID.sessionID,
                  loadedID == activeMutation.loadID else { return }
            mutationError = error.localizedDescription
        }
    }

    @discardableResult
    private func applySuccessfulMutation(
        _ entry: UserMediaEntry,
        mutation: MediaLibraryMutation,
        activeMutation: ActiveEntryMutation
    ) -> Bool {
        guard authStore.mediaLibrarySession.id == activeMutation.loadID.sessionID else { return false }
        let reconciliation = mediaLibraryStore.reconcile(
            entry,
            mutation: mutation,
            media: activeMutation.media
        )
        guard loadedID == activeMutation.loadID else { return false }
        userEntry = MediaDetailMutationResolution.afterUpdate(
            entry,
            reconciliation: reconciliation,
            canonicalEntry: mediaLibraryStore.entry(
                mediaID: activeMutation.loadID.mediaID,
                type: activeMutation.type
            )
        )
        return reconciliation.shouldApplyLocally
    }

    private func finishEntryMutation(_ mutation: ActiveEntryMutation) {
        guard entryMutation?.id == mutation.id else { return }
        entryMutation = nil
    }
}

enum MediaDetailMutationResolution {
    static func afterUpdate(
        _ successfulEntry: UserMediaEntry,
        reconciliation: MediaLibraryReconciliationResult,
        canonicalEntry: MediaListEntry?
    ) -> UserMediaEntry? {
        guard !reconciliation.shouldApplyLocally else { return successfulEntry }
        return canonicalEntry.map { makeUserEntry(from: $0) }
    }

    static func afterDeletion(
        reconciliation: MediaLibraryReconciliationResult,
        canonicalEntry: MediaListEntry?
    ) -> UserMediaEntry? {
        guard !reconciliation.shouldApplyLocally else { return nil }
        return canonicalEntry.map { makeUserEntry(from: $0) }
    }

    private static func makeUserEntry(from entry: MediaListEntry) -> UserMediaEntry {
        UserMediaEntry(
            id: entry.id,
            status: entry.status,
            score: entry.score,
            progress: entry.progress,
            updatedAt: entry.updatedAt
        )
    }
}

private extension MediaDetails {
    var libraryMedia: Media {
        Media(
            id: id,
            isAdult: isAdult,
            title: title,
            coverImage: coverImage,
            episodes: episodes,
            chapters: chapters,
            format: format,
            status: status,
            averageScore: averageScore,
            nextAiringEpisode: nextAiringEpisode
        )
    }
}
