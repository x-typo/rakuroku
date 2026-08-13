import SwiftUI

struct ProfileView: View {
    private struct LoadRequest: Hashable {
        let sessionID: MediaLibrarySession.ID
        let accessToken: String
    }

    @Environment(AuthStore.self) private var authStore
    @Environment(ReleaseNotificationStore.self) private var releaseNotificationStore
    @Environment(\.openURL) private var openURL

    @State private var user: AniListUser?
    @State private var activities: [ListActivity] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showManualTokenSheet = false
    @State private var manualTokenValue = ""

    var body: some View {
        Group {
            if !authStore.isAuthenticated {
                signedOutView
            } else {
                signedInView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .task(id: loadRequest) {
            guard let loadRequest else {
                user = nil
                activities = []
                loading = authStore.isAuthenticated
                error = nil
                return
            }
            user = nil
            activities = []
            loading = true
            error = nil
            await loadData(for: loadRequest)
        }
        .sheet(isPresented: $showManualTokenSheet) {
            manualTokenSheet
        }
    }

    @ViewBuilder
    private var signedInView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !authStore.isMediaLibraryIdentityResolved {
                    if let resolutionError = authStore.mediaLibraryIdentityResolutionError {
                        VStack(spacing: 16) {
                            Text(resolutionError)
                                .foregroundStyle(Theme.error)
                                .multilineTextAlignment(.center)
                            Button("Retry Account Verification") {
                                authStore.retryMediaLibraryIdentityResolution()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    } else {
                        ProgressView()
                            .tint(Theme.primary)
                            .padding(.bottom, 24)
                    }
                } else if loading {
                    ProgressView()
                        .tint(Theme.primary)
                        .padding(.bottom, 24)
                } else if let error {
                    VStack(spacing: 16) {
                        Text(error).foregroundStyle(Theme.error)
                        Button("Retry") {
                            guard let loadRequest else { return }
                            Task { await loadData(for: loadRequest) }
                        }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else if let user {
                    avatarSection(user)
                    statsSection(user)
                } else {
                    Text("No user data available")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 16)
                }

                notificationSection
                authSection

                if !loading, error == nil, user != nil {
                    activitySection
                }
            }
            .padding(.vertical, 32)
        }
        .refreshable {
            guard let loadRequest else { return }
            await loadData(for: loadRequest)
        }
    }

    @ViewBuilder
    private var signedOutView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "person.circle")
                    .font(.system(size: 50))
                    .foregroundStyle(Theme.textSecondary)
                Text("Sign in to see your profile")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                Button {
                    Task { await authStore.login() }
                } label: {
                    Label("Sign in with AniList", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    openManualTokenSheet()
                } label: {
                    Label("Paste Access Token", systemImage: "key")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.surfaceLight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let authError = authStore.authError {
                    Button { authStore.clearAuthError() } label: {
                        Text(authError)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.error)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Theme.error.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, 16)
                }

                notificationSection
            }
            .padding(.vertical, 32)
        }
    }

    @ViewBuilder
    private func avatarSection(_ user: AniListUser) -> some View {
        VStack(spacing: 16) {
            AsyncCoverImage(url: user.avatar?.large, width: 120, height: 120, cornerRadius: 60)
            Text(user.name)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func statsSection(_ user: AniListUser) -> some View {
        HStack(spacing: 12) {
            statCard(value: user.statistics.anime.count, label: "Anime")
            statCard(value: user.statistics.anime.episodesWatched, label: "Episodes")
            statCard(value: user.statistics.anime.minutesWatched / 60, label: "Hours")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)

        HStack(spacing: 12) {
            statCard(value: user.statistics.manga.count, label: "Manga")
            statCard(value: user.statistics.manga.chaptersRead, label: "Chapters")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func statCard(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Release Notifications",
                isOn: Binding(
                    get: { releaseNotificationStore.isEnabled },
                    set: { enabled in
                        Task { await releaseNotificationStore.setEnabled(enabled) }
                    }
                )
            )
            .font(.headline)
            .tint(Theme.primary)
            .disabled(releaseNotificationStore.isUpdatingPreference)

            Text("Only currently releasing anime on your Watching list qualify. Being behind does not stop future episode alerts.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Rakuroku schedules only each title's next episode known to AniList at its reported airing time. It does not refresh in the background, so open the app to schedule later episodes.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("iOS limits pending local alerts, so Rakuroku keeps the nearest releases when space is limited.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if releaseNotificationStore.isEnabled {
                Text("Scheduled: \(releaseNotificationStore.scheduledCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            if releaseNotificationStore.authorizationStatus == .denied {
                Text("Notifications are blocked in iOS Settings.")
                    .font(.caption)
                    .foregroundStyle(Theme.error)

                Button("Open Settings") {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                        return
                    }
                    openURL(settingsURL)
                }
                .buttonStyle(.bordered)
                .tint(Theme.primary)
            }

            if let schedulingError = releaseNotificationStore.schedulingError {
                Text(schedulingError)
                    .font(.caption)
                    .foregroundStyle(Theme.error)
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var authSection: some View {
        VStack(spacing: 10) {
            if authStore.isLoading {
                ProgressView().tint(Theme.primary)
            } else if authStore.isAuthenticated {
                Button {
                    authStore.logout()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Button {
                    Task { await authStore.login() }
                } label: {
                    Label("Sign in with AniList", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    openManualTokenSheet()
                } label: {
                    Label("Paste Access Token", systemImage: "key")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.surfaceLight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let authError = authStore.authError {
                    Button { authStore.clearAuthError() } label: {
                        VStack(spacing: 4) {
                            Text(authError)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.error)
                            Text("Tap to dismiss")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Theme.error.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            if activities.isEmpty {
                Text("No recent activities")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(activities) { activity in
                    NavigationLink(value: MediaDetailDestination(mediaId: activity.media.id)) {
                        HStack(spacing: 10) {
                            AsyncCoverImage(url: activity.media.coverImage?.medium, width: 50, height: 70)

                            Text(formatActivityStatus(activity))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(Formatters.timeAgo(activity.createdAt))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(12)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var manualTokenSheet: some View {
        VStack(spacing: 16) {
            Text("Paste AniList Token")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            Text("If browser login is blocked, paste an existing AniList OAuth access token here.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            SecureField("access_token...", text: $manualTokenValue)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if let authError = authStore.authError {
                Text(authError)
                    .font(.caption)
                    .foregroundStyle(Theme.error)
            }

            HStack(spacing: 12) {
                Button("Save") {
                    if authStore.setManualToken(manualTokenValue) {
                        showManualTokenSheet = false
                        manualTokenValue = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .disabled(manualTokenValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel") {
                    showManualTokenSheet = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func formatActivityStatus(_ activity: ListActivity) -> String {
        let title = activity.media.title.display
        let status = activity.status?.lowercased() ?? ""
        let progress = activity.progress

        if let progress {
            if status.contains("watched") { return "Watched episode \(progress) of \(title)" }
            if status.contains("read") { return "Read chapter \(progress) of \(title)" }
            return "\(status) \(progress) of \(title)"
        }
        if status.contains("completed") { return "Completed \(title)" }
        if status.contains("dropped") { return "Dropped \(title)" }
        if status.contains("paused") { return "Paused \(title)" }
        if status.contains("planning") { return "Plans to watch \(title)" }
        return "\(status) \(title)"
    }

    private var loadRequest: LoadRequest? {
        guard authStore.isMediaLibraryIdentityResolved,
              let accessToken = authStore.accessToken else {
            return nil
        }
        return LoadRequest(
            sessionID: authStore.mediaLibrarySession.id,
            accessToken: accessToken
        )
    }

    private func loadData(for request: LoadRequest) async {
        if user == nil { loading = true }
        error = nil
        let session = authStore.mediaLibrarySession
        guard session.id == request.sessionID,
              session.accessToken == request.accessToken,
              authStore.isMediaLibraryIdentityResolved else {
            return
        }
        do {
            let userData = try await AniListClient.shared.fetchAuthenticatedUser(
                accessToken: request.accessToken
            )
            guard authStore.isMediaLibraryIdentityResolved,
                  authStore.isCurrent(session) else {
                return
            }
            user = userData
            loading = false
            let loadedActivities = (try? await AniListClient.shared.fetchUserActivities(
                userId: userData.id
            )) ?? []
            guard authStore.isMediaLibraryIdentityResolved,
                  authStore.isCurrent(session) else {
                return
            }
            activities = loadedActivities
        } catch let error as AniListError where error.isAuthenticationFailure {
            guard authStore.logoutIfCurrent(
                session,
                authError: "AniList session expired. Sign in again."
            ) else {
                return
            }
            user = nil
            activities = []
            self.error = nil
            loading = false
        } catch where error.isCancellation {
        } catch {
            guard authStore.isCurrent(session) else { return }
            self.error = error.localizedDescription
            loading = false
        }
    }

    private func openManualTokenSheet() {
        authStore.clearAuthError()
        manualTokenValue = ""
        showManualTokenSheet = true
    }
}
