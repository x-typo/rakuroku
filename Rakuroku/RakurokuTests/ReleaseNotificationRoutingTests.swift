import Foundation
import SwiftUI
import Testing
import UserNotifications
@testable import Rakuroku

@Suite("Release notification routing")
@MainActor
struct ReleaseNotificationRoutingTests {
    @Test("A managed default action crosses payload handling into detail navigation")
    func managedResponseRoutesEndToEnd() async {
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
        guard let queuedDestination = router.pendingDestination(for: sceneID) else {
            Issue.record("The accepted response did not queue a destination")
            return
        }
        let outcome = consume(router: router, sceneID: sceneID)
        #expect(outcome == .navigate(
            ReleaseNotificationNavigation(
                id: queuedDestination.id,
                tab: .anime,
                detailDestination: MediaDetailDestination(mediaId: 42)
            )
        ))

        let navigationState = ContentNavigationState()
        navigationState.apply(outcome)

        #expect(navigationState.selectedTab == .anime)
        #expect(navigationState.pendingNotificationNavigation == ReleaseNotificationNavigation(
            id: queuedDestination.id,
            tab: .anime,
            detailDestination: MediaDetailDestination(mediaId: 42)
        ))
        #expect(navigationState.animePath.isEmpty)

        await ReleaseNotificationPresentationCoordinator.present(
            navigationID: queuedDestination.id,
            state: navigationState
        )

        #expect(navigationState.pendingNotificationNavigation == nil)
        #expect(navigationState.animePath.count == 1)

        await ReleaseNotificationPresentationCoordinator.present(
            navigationID: queuedDestination.id,
            state: navigationState
        )

        #expect(navigationState.animePath.count == 1)
    }

    @Test("A warm tap produces the Anime detail navigation exactly once")
    func warmTapRoutesExactlyOnce() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(mediaID: 42, ownerUsername: "Owner")
        guard let queuedDestination = router.pendingDestination(for: sceneID) else {
            Issue.record("The tap did not queue a destination")
            return
        }

        let outcome = consume(router: router, sceneID: sceneID)

        #expect(outcome == .navigate(ReleaseNotificationNavigation(
            id: queuedDestination.id,
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
        guard let queuedDestination = router.pendingDestination(for: sceneID) else {
            Issue.record("Scene activation did not expose the queued destination")
            return
        }

        #expect(consume(router: router, sceneID: sceneID) == .navigate(
            ReleaseNotificationNavigation(
                id: queuedDestination.id,
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
        guard let queuedDestination = router.pendingDestination(for: sceneID) else {
            Issue.record("The deferred destination was lost")
            return
        }
        #expect(consume(router: router, sceneID: sceneID) == .navigate(
            ReleaseNotificationNavigation(
                id: queuedDestination.id,
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
        guard let queuedDestination = router.pendingDestination(for: sceneID) else {
            Issue.record("The deferred destination was lost")
            return
        }
        #expect(consume(router: router, sceneID: sceneID) == .navigate(
            ReleaseNotificationNavigation(
                id: queuedDestination.id,
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

    @Test("A newer same-media tap cannot be cleared by an older presentation task")
    func sameMediaTapHasUniquePresentationIdentity() async {
        let navigationState = ContentNavigationState()
        let firstID = UUID()
        let secondID = UUID()
        let destination = MediaDetailDestination(mediaId: 42)

        navigationState.apply(.navigate(ReleaseNotificationNavigation(
            id: firstID,
            tab: .anime,
            detailDestination: destination
        )))
        navigationState.apply(.navigate(ReleaseNotificationNavigation(
            id: secondID,
            tab: .anime,
            detailDestination: destination
        )))

        await ReleaseNotificationPresentationCoordinator.present(
            navigationID: firstID,
            state: navigationState
        )

        #expect(navigationState.pendingNotificationNavigation?.id == secondID)
        #expect(navigationState.animePath.isEmpty)

        await ReleaseNotificationPresentationCoordinator.present(
            navigationID: secondID,
            state: navigationState
        )

        #expect(navigationState.pendingNotificationNavigation == nil)
        #expect(navigationState.animePath.count == 1)
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
