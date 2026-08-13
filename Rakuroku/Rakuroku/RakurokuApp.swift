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
        await ReleaseNotificationResponseHandler.handle(
            identifier: request.identifier,
            actionIdentifier: response.actionIdentifier,
            userInfo: request.content.userInfo,
            router: ReleaseNotificationRouter.shared
        )
    }
}

@MainActor
enum ReleaseNotificationResponseHandler {
    @discardableResult
    static func handle(
        identifier: String,
        actionIdentifier: String,
        userInfo: [AnyHashable: Any],
        router: ReleaseNotificationRouter
    ) -> Bool {
        guard let tap = ReleaseNotificationTapValidation.parse(
            identifier: identifier,
            actionIdentifier: actionIdentifier,
            userInfo: userInfo
        ) else {
            return false
        }
        router.accept(
            mediaID: tap.mediaID,
            ownerUsername: tap.ownerUsername
        )
        return true
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

enum ContentTab: Hashable {
    case home, anime, manga, schedule, profile
}

struct ReleaseNotificationNavigation: Equatable {
    let tab: ContentTab
    let detailDestination: MediaDetailDestination
}

@MainActor @Observable
final class ContentNavigationState {
    var selectedTab = ContentTab.home
    var homePath = NavigationPath()
    var animePath = NavigationPath()
    var mangaPath = NavigationPath()
    var schedulePath = NavigationPath()
    var profilePath = NavigationPath()
    private(set) var pendingNotificationAnimeDestination: MediaDetailDestination?

    func apply(_ outcome: ReleaseNotificationRouteCoordinator.Outcome) {
        guard case let .navigate(navigation) = outcome else { return }
        selectedTab = navigation.tab
        pendingNotificationAnimeDestination = navigation.detailDestination
    }

    func presentPendingNotificationAnimeDestination() {
        guard let destination = pendingNotificationAnimeDestination else { return }
        animePath = NavigationPath()
        animePath.append(destination)
        pendingNotificationAnimeDestination = nil
    }
}

@MainActor
enum ReleaseNotificationRouteCoordinator {
    enum Outcome: Equatable {
        case none
        case deferred
        case rejected
        case navigate(ReleaseNotificationNavigation)
    }

    static func consume(
        router: ReleaseNotificationRouter,
        sceneID: UUID,
        isReady: Bool,
        isIdentityResolved: Bool,
        isActive: Bool,
        ownerUsername: String
    ) -> Outcome {
        guard let destination = router.pendingDestination(for: sceneID) else {
            return .none
        }
        guard isReady, isIdentityResolved, isActive else {
            return .deferred
        }
        guard router.takePendingDestination(for: sceneID) == destination else {
            return .none
        }
        guard ReleaseNotificationTapValidation.belongsToOwner(
            ReleaseNotificationTap(
                mediaID: destination.mediaID,
                ownerUsername: destination.ownerUsername
            ),
            username: ownerUsername
        ) else {
            return .rejected
        }
        return .navigate(
            ReleaseNotificationNavigation(
                tab: .anime,
                detailDestination: MediaDetailDestination(mediaId: destination.mediaID)
            )
        )
    }
}

// Each tab gets its own NavigationStack so navigation state is independent per tab
struct ContentView: View {
    private struct ReleaseNotificationRouteRequest: Hashable {
        let isReady: Bool
        let isIdentityResolved: Bool
        let isActive: Bool
        let destination: ReleaseNotificationRouter.Destination?
    }

    @Environment(AuthStore.self) private var authStore
    @Environment(MediaLibraryStore.self) private var mediaLibraryStore
    @Environment(ReleaseNotificationStore.self) private var releaseNotificationStore
    @Environment(ReleaseNotificationRouter.self) private var releaseNotificationRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var ready = false
    @State private var notificationSceneID = UUID()
    @State private var navigationState = ContentNavigationState()

    var body: some View {
        @Bindable var navigationState = navigationState
        let synchronizationRequest = releaseNotificationSynchronizationRequest
        let presentationState = ContentPresentationState.resolve(
            isReady: ready,
            isMediaLibraryIdentityResolved: authStore.isMediaLibraryIdentityResolved
        )
        let routeRequest = ReleaseNotificationRouteRequest(
            isReady: ready,
            isIdentityResolved: authStore.isMediaLibraryIdentityResolved,
            isActive: scenePhase == .active,
            destination: releaseNotificationRouter.pendingDestination(
                for: notificationSceneID
            )
        )

        Group {
            switch presentationState {
            case .tabs:
                TabView(selection: $navigationState.selectedTab) {
                    SwiftUI.Tab("Home", systemImage: "house", value: ContentTab.home) {
                        TabNavigationWrapper(path: $navigationState.homePath) { HomeView() }
                    }

                    SwiftUI.Tab("Anime", systemImage: "tv", value: ContentTab.anime) {
                        TabNavigationWrapper(path: $navigationState.animePath) { AnimeListView() }
                            .onChange(
                                of: navigationState.pendingNotificationAnimeDestination,
                                initial: true
                            ) { _, _ in
                                navigationState.presentPendingNotificationAnimeDestination()
                            }
                    }

                    SwiftUI.Tab("Manga", systemImage: "book", value: ContentTab.manga) {
                        TabNavigationWrapper(path: $navigationState.mangaPath) { MangaListView() }
                    }

                    SwiftUI.Tab("Schedule", systemImage: "calendar", value: ContentTab.schedule) {
                        TabNavigationWrapper(path: $navigationState.schedulePath) { ScheduleView() }
                    }

                    SwiftUI.Tab("Profile", systemImage: "person", value: ContentTab.profile) {
                        TabNavigationWrapper(path: $navigationState.profilePath) { ProfileView() }
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
        .onChange(of: routeRequest, initial: true) { _, request in
            let outcome = ReleaseNotificationRouteCoordinator.consume(
                router: releaseNotificationRouter,
                sceneID: notificationSceneID,
                isReady: request.isReady,
                isIdentityResolved: request.isIdentityResolved,
                isActive: request.isActive,
                ownerUsername: authStore.mediaLibrarySession.id.username
            )
            navigationState.apply(outcome)
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
