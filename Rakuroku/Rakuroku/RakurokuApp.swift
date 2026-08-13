import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var allowLandscape = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.allowLandscape ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier.hasPrefix(
            ReleaseNotificationRequest.identifierPrefix
        ), notification.request.content.userInfo["kind"] as? String
            == ReleaseNotificationRequest.kind else {
            return []
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        guard let tap = ReleaseNotificationTapValidation.parse(
            identifier: request.identifier,
            actionIdentifier: response.actionIdentifier,
            userInfo: request.content.userInfo
        ) else {
            return
        }

        await ReleaseNotificationRouter.shared.accept(
            mediaID: tap.mediaID,
            ownerUsername: tap.ownerUsername
        )
    }
}

struct ReleaseNotificationSynchronizationRequest: Hashable {
    let sessionID: MediaLibrarySession.ID
    let isEnabled: Bool
    let isIdentityResolved: Bool
    let candidates: [ReleaseNotificationCandidate]?
}

@MainActor
enum ReleaseNotificationSynchronizationCoordinator {
    static func synchronize(
        request: ReleaseNotificationSynchronizationRequest,
        currentSession: () -> MediaLibrarySession,
        loadAnime: (MediaLibrarySession) async -> Void,
        currentCandidates: (MediaLibrarySession.ID) -> [ReleaseNotificationCandidate]?,
        apply: ([ReleaseNotificationCandidate]?, MediaLibrarySession.ID) async -> Void
    ) async {
        guard request.isEnabled else {
            await apply(nil, request.sessionID)
            return
        }

        guard request.isIdentityResolved else {
            await apply(nil, request.sessionID)
            return
        }

        var candidates = request.candidates
        if candidates == nil {
            await apply(nil, request.sessionID)

            let session = currentSession()
            guard session.id == request.sessionID else { return }
            await loadAnime(session)
            guard currentSession().id == request.sessionID else { return }
            candidates = currentCandidates(request.sessionID)
        }

        await apply(candidates, request.sessionID)
    }

    static func refreshAfterActivation(
        isEnabled: Bool,
        canSchedule: Bool,
        isIdentityResolved: () -> Bool,
        currentSession: () -> MediaLibrarySession,
        loadAnime: (MediaLibrarySession) async -> Void,
        currentCandidates: (MediaLibrarySession.ID) -> [ReleaseNotificationCandidate]?,
        apply: ([ReleaseNotificationCandidate]?, MediaLibrarySession.ID) async -> Void
    ) async {
        guard isEnabled, canSchedule, isIdentityResolved() else { return }

        let session = currentSession()
        await loadAnime(session)
        guard isIdentityResolved(),
              currentSession().id == session.id,
              currentSession().accessToken == session.accessToken else {
            return
        }

        await apply(currentCandidates(session.id), session.id)
    }
}

@main
struct RakurokuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authStore = AuthStore()
    @State private var anikotoTVStore = AnikotoTVStore()
    @State private var mediaLibraryStore = MediaLibraryStore()
    @State private var releaseNotificationStore = ReleaseNotificationStore()
    @State private var releaseNotificationRouter = ReleaseNotificationRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authStore)
                .environment(anikotoTVStore)
                .environment(mediaLibraryStore)
                .environment(releaseNotificationStore)
                .environment(releaseNotificationRouter)
                .preferredColorScheme(.dark)
        }
    }
}

enum ContentPresentationState: Equatable {
    case loading
    case identityResolution
    case tabs

    static func resolve(
        isReady: Bool,
        isMediaLibraryIdentityResolved: Bool
    ) -> Self {
        guard isReady else { return .loading }
        guard isMediaLibraryIdentityResolved else { return .identityResolution }
        return .tabs
    }
}

// Each tab gets its own NavigationStack so navigation state is independent per tab
struct ContentView: View {
    private struct ReleaseNotificationRouteRequest: Hashable {
        let isReady: Bool
        let isActive: Bool
        let destination: ReleaseNotificationRouter.Destination?
    }

    @Environment(AuthStore.self) private var authStore
    @Environment(MediaLibraryStore.self) private var mediaLibraryStore
    @Environment(ReleaseNotificationStore.self) private var releaseNotificationStore
    @Environment(ReleaseNotificationRouter.self) private var releaseNotificationRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = Tab.home
    @State private var ready = false
    @State private var homePath = NavigationPath()
    @State private var animePath = NavigationPath()
    @State private var mangaPath = NavigationPath()
    @State private var schedulePath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var notificationSceneID = UUID()

    enum Tab: Hashable {
        case home, anime, manga, schedule, profile
    }

    var body: some View {
        let synchronizationRequest = releaseNotificationSynchronizationRequest
        let presentationState = ContentPresentationState.resolve(
            isReady: ready,
            isMediaLibraryIdentityResolved: authStore.isMediaLibraryIdentityResolved
        )
        let routeRequest = ReleaseNotificationRouteRequest(
            isReady: ready && authStore.isMediaLibraryIdentityResolved,
            isActive: scenePhase == .active,
            destination: releaseNotificationRouter.pendingDestination(
                for: notificationSceneID
            )
        )

        Group {
            switch presentationState {
            case .tabs:
                TabView(selection: $selectedTab) {
                    SwiftUI.Tab("Home", systemImage: "house", value: Tab.home) {
                        TabNavigationWrapper(path: $homePath) { HomeView() }
                    }

                    SwiftUI.Tab("Anime", systemImage: "tv", value: Tab.anime) {
                        TabNavigationWrapper(path: $animePath) { AnimeListView() }
                    }

                    SwiftUI.Tab("Manga", systemImage: "book", value: Tab.manga) {
                        TabNavigationWrapper(path: $mangaPath) { MangaListView() }
                    }

                    SwiftUI.Tab("Schedule", systemImage: "calendar", value: Tab.schedule) {
                        TabNavigationWrapper(path: $schedulePath) { ScheduleView() }
                    }

                    SwiftUI.Tab("Profile", systemImage: "person", value: Tab.profile) {
                        TabNavigationWrapper(path: $profilePath) { ProfileView() }
                    }
                }
                .tint(Theme.primary)
            case .identityResolution:
                ProfileView()
            case .loading:
                ProgressView().tint(Theme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .task(id: authStore.authenticatedViewerResolutionRequest) {
            if let request = authStore.authenticatedViewerResolutionRequest {
                let session = request.session
                defer {
                    ready = true
                }
                do {
                    let user = try await AniListClient.shared.fetchAuthenticatedUser(
                        accessToken: request.accessToken
                    )
                    _ = authStore.applyResolvedUsername(user.name, for: session)
                } catch let error as AniListError where error.isAuthenticationFailure {
                    _ = authStore.logoutIfCurrent(session)
                } catch where error.isCancellation {
                } catch {
                    _ = authStore.recordMediaLibraryIdentityResolutionFailure(
                        for: session
                    )
                }
            } else {
                ready = true
            }
        }
        .task(id: synchronizationRequest) {
            await synchronizeReleaseNotifications(for: synchronizationRequest)
        }
        .task(id: scenePhase) {
            releaseNotificationRouter.register(
                sceneID: notificationSceneID,
                isActive: scenePhase == .active
            )
            guard scenePhase == .active else { return }
            if !authStore.isMediaLibraryIdentityResolved,
               authStore.mediaLibraryIdentityResolutionError != nil {
                authStore.retryMediaLibraryIdentityResolution()
            }
            await refreshReleaseNotificationsAfterActivation()
        }
        .task(id: routeRequest) {
            guard routeRequest.isReady,
                  routeRequest.isActive,
                  let destination = routeRequest.destination,
                  releaseNotificationRouter.takePendingDestination(
                    for: notificationSceneID
                  ) == destination else {
                return
            }
            guard ReleaseNotificationTapValidation.belongsToOwner(
                ReleaseNotificationTap(
                    mediaID: destination.mediaID,
                    ownerUsername: destination.ownerUsername
                ),
                username: authStore.mediaLibrarySession.id.username
            ) else {
                return
            }
            selectedTab = .anime
            animePath = NavigationPath()
            animePath.append(MediaDetailDestination(mediaId: destination.mediaID))
        }
        .onDisappear {
            releaseNotificationRouter.register(
                sceneID: notificationSceneID,
                isActive: false
            )
        }
    }

    private var releaseNotificationSynchronizationRequest: ReleaseNotificationSynchronizationRequest {
        let sessionID = authStore.mediaLibrarySession.id
        let candidates = releaseNotificationStore.isEnabled
            && authStore.isMediaLibraryIdentityResolved
            ? mediaLibraryStore.releaseNotificationCandidates(
                activeSessionID: sessionID,
                nowEpoch: Int(Date().timeIntervalSince1970)
            )
            : nil
        return ReleaseNotificationSynchronizationRequest(
            sessionID: sessionID,
            isEnabled: releaseNotificationStore.isEnabled,
            isIdentityResolved: authStore.isMediaLibraryIdentityResolved,
            candidates: candidates
        )
    }

    private func synchronizeReleaseNotifications(
        for request: ReleaseNotificationSynchronizationRequest
    ) async {
        await ReleaseNotificationSynchronizationCoordinator.synchronize(
            request: request,
            currentSession: { authStore.mediaLibrarySession },
            loadAnime: { session in
                await mediaLibraryStore.load(.anime, session: session)
            },
            currentCandidates: { sessionID in
                mediaLibraryStore.releaseNotificationCandidates(
                    activeSessionID: sessionID,
                    nowEpoch: Int(Date().timeIntervalSince1970)
                )
            },
            apply: { candidates, sessionID in
                await releaseNotificationStore.synchronize(
                    candidates: candidates,
                    sessionID: sessionID
                )
            }
        )
    }

    private func refreshReleaseNotificationsAfterActivation() async {
        await releaseNotificationStore.refreshAuthorizationStatus()
        await ReleaseNotificationSynchronizationCoordinator.refreshAfterActivation(
            isEnabled: releaseNotificationStore.isEnabled,
            canSchedule: releaseNotificationStore.authorizationStatus.canSchedule,
            isIdentityResolved: { authStore.isMediaLibraryIdentityResolved },
            currentSession: { authStore.mediaLibrarySession },
            loadAnime: { session in
                await mediaLibraryStore.load(.anime, session: session, force: true)
            },
            currentCandidates: { sessionID in
                mediaLibraryStore.releaseNotificationCandidates(
                    activeSessionID: sessionID,
                    nowEpoch: Int(Date().timeIntervalSince1970)
                )
            },
            apply: { candidates, sessionID in
                await releaseNotificationStore.synchronize(
                    candidates: candidates,
                    sessionID: sessionID
                )
            }
        )
    }
}

/// Wraps each tab's content in its own NavigationStack with shared destinations
struct TabNavigationWrapper<Content: View>: View {
    @Binding var path: NavigationPath
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .navigationDestination(for: MediaDetailDestination.self) { dest in
                    MediaDetailView(mediaId: dest.mediaId)
                }
                .navigationDestination(for: StudioDestination.self) { dest in
                    StudioView(studioId: dest.studioId, studioName: dest.studioName)
                }
                .navigationDestination(for: SeasonListDestination.self) { dest in
                    SeasonListView(season: dest.season, year: dest.year, label: dest.label)
                }
        }
    }
}

// Navigation destinations
struct MediaDetailDestination: Hashable {
    let mediaId: Int
}

struct StudioDestination: Hashable {
    let studioId: Int
    let studioName: String
}

struct SeasonListDestination: Hashable {
    let season: Season
    let year: Int
    let label: String
}
