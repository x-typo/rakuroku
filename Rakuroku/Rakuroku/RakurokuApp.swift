import Combine
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

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = SceneDelegate.self
        }
        return configuration
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
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        ReleaseNotificationResponseDelivery.deliverOnMain(
            route: {
                let targetSceneID = Self.notificationSceneID(for: response)
                ReleaseNotificationResponseIngress.receiveOnMain(
                    response,
                    source: .notificationCenter,
                    targetSceneID: targetSceneID
                )
            },
            completion: { completionHandler() }
        )
    }

    @MainActor
    private static func notificationSceneID(
        for response: UNNotificationResponse
    ) -> UUID? {
        if let targetSceneID = (response.targetScene?.delegate as? SceneDelegate)?
            .notificationSceneID {
            return targetSceneID
        }

        let connectedSceneDelegates = UIApplication.shared.connectedScenes.compactMap {
            $0.delegate as? SceneDelegate
        }
        let foregroundSceneDelegates: [SceneDelegate] = UIApplication.shared.connectedScenes.compactMap {
            guard $0.activationState == .foregroundActive
                    || $0.activationState == .foregroundInactive else {
                return nil
            }
            return $0.delegate as? SceneDelegate
        }
        if foregroundSceneDelegates.count == 1 {
            return foregroundSceneDelegates[0].notificationSceneID
        }
        if connectedSceneDelegates.count == 1 {
            return connectedSceneDelegates[0].notificationSceneID
        }
        return nil
    }
}

enum ReleaseNotificationResponseDelivery {
    nonisolated static func deliverOnMain(
        route: @escaping @MainActor () -> Void,
        completion: @escaping @MainActor () -> Void
    ) {
        Task { @MainActor in
            route()
            completion()
        }
    }
}

@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    @Published private(set) var notificationSceneID = UUID()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let response = connectionOptions.notificationResponse else { return }
        ReleaseNotificationResponseIngress.receiveOnMain(
            response,
            source: .sceneConnection,
            targetSceneID: notificationSceneID
        )
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        ReleaseNotificationSceneLifecycleCoordinator.update(
            router: ReleaseNotificationRouter.shared,
            sceneID: notificationSceneID,
            isActive: true
        )
    }

    func sceneWillResignActive(_ scene: UIScene) {
        ReleaseNotificationSceneLifecycleCoordinator.update(
            router: ReleaseNotificationRouter.shared,
            sceneID: notificationSceneID,
            isActive: false
        )
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ReleaseNotificationSceneLifecycleCoordinator.disconnect(
            router: ReleaseNotificationRouter.shared,
            sceneID: notificationSceneID
        )
    }
}

enum ReleaseNotificationResponseSource: String {
    case notificationCenter
    case sceneConnection
}

enum ReleaseNotificationResponseIngress {
    @MainActor
    static func receiveOnMain(
        _ response: UNNotificationResponse,
        source: ReleaseNotificationResponseSource,
        targetSceneID: UUID?
    ) {
        let request = response.notification.request
        ReleaseNotificationRouteDiagnostics.responseReceived(
            source: source,
            isManaged: request.identifier.hasPrefix(ReleaseNotificationRequest.identifierPrefix),
            isDefaultAction: response.actionIdentifier == UNNotificationDefaultActionIdentifier
        )
        ReleaseNotificationResponseHandler.handle(
            identifier: request.identifier,
            actionIdentifier: response.actionIdentifier,
            userInfo: request.content.userInfo,
            targetSceneID: targetSceneID,
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
        targetSceneID: UUID? = nil,
        router: ReleaseNotificationRouter
    ) -> Bool {
        guard let tap = ReleaseNotificationTapValidation.parse(
            identifier: identifier,
            actionIdentifier: actionIdentifier,
            userInfo: userInfo
        ) else {
            ReleaseNotificationRouteDiagnostics.responseRejected()
            return false
        }
        ReleaseNotificationRouteDiagnostics.responseAccepted(mediaID: tap.mediaID)
        router.accept(
            notificationIdentifier: identifier,
            mediaID: tap.mediaID,
            ownerUsername: tap.ownerUsername,
            targetSceneID: targetSceneID
        )
        return true
    }
}

@MainActor
enum ReleaseNotificationSceneLifecycleCoordinator {
    static func update(
        router: ReleaseNotificationRouter,
        sceneID: UUID,
        isActive: Bool
    ) {
        router.register(sceneID: sceneID, isActive: isActive)
    }

    static func disconnect(
        router: ReleaseNotificationRouter,
        sceneID: UUID
    ) {
        router.disconnect(sceneID: sceneID)
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
    let id: UUID
    let tab: ContentTab
    let detailDestination: ReleaseNotificationDetailDestination
}

@MainActor @Observable
final class ContentNavigationState {
    var selectedTab = ContentTab.home
    var homePath = NavigationPath()
    var animePath = NavigationPath()
    var mangaPath = NavigationPath()
    var schedulePath = NavigationPath()
    var profilePath = NavigationPath()

    @discardableResult
    func apply(_ outcome: ReleaseNotificationRouteCoordinator.Outcome) -> ReleaseNotificationNavigation? {
        guard case let .navigate(navigation) = outcome else { return nil }
        selectedTab = navigation.tab
        var path = NavigationPath()
        path.append(navigation.detailDestination)
        animePath = path
        ReleaseNotificationRouteDiagnostics.navigationPresented(
            mediaID: navigation.detailDestination.mediaId,
            pathCount: animePath.count
        )
        return navigation
    }
}

@MainActor
enum ReleaseNotificationPresentationCoordinator {
    @discardableResult
    static func present(
        outcome: ReleaseNotificationRouteCoordinator.Outcome,
        sceneID: UUID,
        state: ContentNavigationState,
        router: ReleaseNotificationRouter
    ) -> Bool {
        guard case let .navigate(navigation) = outcome,
              router.claimedDestination(for: sceneID)?.id == navigation.id,
              state.apply(outcome)?.id == navigation.id else {
            return false
        }
        return router.acknowledge(destinationID: navigation.id, for: sceneID)
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
            ReleaseNotificationRouteDiagnostics.navigationDeferred(mediaID: destination.mediaID)
            return .deferred
        }
        guard router.claim(destinationID: destination.id, for: sceneID) else {
            return .none
        }
        guard ReleaseNotificationTapValidation.belongsToOwner(
            ReleaseNotificationTap(
                mediaID: destination.mediaID,
                ownerUsername: destination.ownerUsername
            ),
            username: ownerUsername
        ) else {
            guard router.acknowledge(
                destinationID: destination.id,
                for: sceneID
            ) else {
                return .none
            }
            ReleaseNotificationRouteDiagnostics.navigationRejected(mediaID: destination.mediaID)
            return .rejected
        }
        ReleaseNotificationRouteDiagnostics.navigationAccepted(mediaID: destination.mediaID)
        return .navigate(
            ReleaseNotificationNavigation(
                id: destination.id,
                tab: .anime,
                detailDestination: ReleaseNotificationDetailDestination(
                    id: destination.id,
                    mediaId: destination.mediaID
                )
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
    @EnvironmentObject private var notificationScene: SceneDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var ready = false
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
                for: notificationScene.notificationSceneID
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
            let outcome = ReleaseNotificationRouteCoordinator.consume(
                router: releaseNotificationRouter,
                sceneID: notificationScene.notificationSceneID,
                isReady: ready,
                isIdentityResolved: authStore.isMediaLibraryIdentityResolved,
                isActive: scenePhase == .active,
                ownerUsername: authStore.mediaLibrarySession.id.username
            )
            ReleaseNotificationPresentationCoordinator.present(
                outcome: outcome,
                sceneID: notificationScene.notificationSceneID,
                state: navigationState,
                router: releaseNotificationRouter
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
                sceneID: notificationScene.notificationSceneID,
                isReady: request.isReady,
                isIdentityResolved: request.isIdentityResolved,
                isActive: request.isActive,
                ownerUsername: authStore.mediaLibrarySession.id.username
            )
            ReleaseNotificationPresentationCoordinator.present(
                outcome: outcome,
                sceneID: notificationScene.notificationSceneID,
                state: navigationState,
                router: releaseNotificationRouter
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
                .navigationDestination(for: ReleaseNotificationDetailDestination.self) { dest in
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

struct ReleaseNotificationDetailDestination: Hashable {
    let id: UUID
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
