import Foundation
import SwiftUI
import Testing
import UserNotifications
@testable import Rakuroku

@Suite("Release notification routing")
@MainActor
struct ReleaseNotificationRoutingTests {
    @Test("A managed default action crosses payload handling into detail navigation")
    func managedResponseRoutesEndToEnd() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.register(sceneID: sceneID, isActive: true)
        let request = ReleaseNotificationRequest(
            identifier: ReleaseNotificationCandidate.identifier(
                ownerUsername: "Owner",
                mediaID: 42,
                airingAt: 2_000
            ),
            ownerUsername: "Owner",
            mediaID: 42,
            title: "Title",
            episode: 3,
            airingAt: 2_000
        ).notificationRequest()

        #expect(ReleaseNotificationResponseHandler.handle(
            identifier: request.identifier,
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: request.content.userInfo,
            router: router
        ))
        let outcome = consume(router: router, sceneID: sceneID)
        #expect(outcome == .navigate(
            ReleaseNotificationNavigation(
                tab: .anime,
                detailDestination: MediaDetailDestination(mediaId: 42)
            )
        ))

        let navigationState = ContentNavigationState()
        navigationState.apply(outcome)

        #expect(navigationState.selectedTab == .anime)
        #expect(navigationState.pendingNotificationAnimeDestination == MediaDetailDestination(mediaId: 42))
        #expect(navigationState.animePath.isEmpty)

        navigationState.presentPendingNotificationAnimeDestination()

        #expect(navigationState.pendingNotificationAnimeDestination == nil)
        #expect(navigationState.animePath.count == 1)

        navigationState.presentPendingNotificationAnimeDestination()

        #expect(navigationState.animePath.count == 1)
    }

    @Test("A warm tap produces the Anime detail navigation exactly once")
    func warmTapRoutesExactlyOnce() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(mediaID: 42, ownerUsername: "Owner")

        let outcome = consume(router: router, sceneID: sceneID)

        #expect(outcome == .navigate(ReleaseNotificationNavigation(
            tab: .anime,
            detailDestination: MediaDetailDestination(mediaId: 42)
        )))
        #expect(consume(router: router, sceneID: sceneID) == .none)
    }

    @Test("A cold tap waits for scene registration before routing")
    func coldTapWaitsForSceneRegistration() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.accept(mediaID: 42, ownerUsername: "Owner")

        #expect(consume(router: router, sceneID: sceneID) == .none)

        router.register(sceneID: sceneID, isActive: true)

        #expect(consume(router: router, sceneID: sceneID) == .navigate(
            ReleaseNotificationNavigation(
                tab: .anime,
                detailDestination: MediaDetailDestination(mediaId: 42)
            )
        ))
    }

    @Test("Unresolved identity defers without consuming the tap")
    func unresolvedIdentityDefers() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(mediaID: 42, ownerUsername: "Owner")

        #expect(consume(
            router: router,
            sceneID: sceneID,
            isIdentityResolved: false
        ) == .deferred)
        #expect(router.pendingDestination(for: sceneID)?.mediaID == 42)
        #expect(consume(router: router, sceneID: sceneID) == .navigate(
            ReleaseNotificationNavigation(
                tab: .anime,
                detailDestination: MediaDetailDestination(mediaId: 42)
            )
        ))
    }

    @Test("An inactive scene defers without consuming the tap")
    func inactiveSceneDefers() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(mediaID: 42, ownerUsername: "Owner")

        #expect(consume(
            router: router,
            sceneID: sceneID,
            isActive: false
        ) == .deferred)
        #expect(router.pendingDestination(for: sceneID)?.mediaID == 42)
        #expect(consume(router: router, sceneID: sceneID) == .navigate(
            ReleaseNotificationNavigation(
                tab: .anime,
                detailDestination: MediaDetailDestination(mediaId: 42)
            )
        ))
    }

    @Test("A tap for another owner is rejected and consumed")
    func wrongOwnerIsRejected() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(mediaID: 42, ownerUsername: "Other")

        #expect(consume(router: router, sceneID: sceneID) == .rejected)
        #expect(router.pendingDestination(for: sceneID) == nil)
        #expect(consume(router: router, sceneID: sceneID) == .none)
    }

    private func consume(
        router: ReleaseNotificationRouter,
        sceneID: UUID,
        isReady: Bool = true,
        isIdentityResolved: Bool = true,
        isActive: Bool = true,
        ownerUsername: String = "owner"
    ) -> ReleaseNotificationRouteCoordinator.Outcome {
        ReleaseNotificationRouteCoordinator.consume(
            router: router,
            sceneID: sceneID,
            isReady: isReady,
            isIdentityResolved: isIdentityResolved,
            isActive: isActive,
            ownerUsername: ownerUsername
        )
    }
}
