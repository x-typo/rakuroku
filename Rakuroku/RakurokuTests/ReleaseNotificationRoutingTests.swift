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
        guard let queuedDestination = router.pendingDestination(for: sceneID) else {
            Issue.record("The accepted response did not queue a destination")
            return
        }
        let outcome = consume(router: router, sceneID: sceneID)
        #expect(outcome == .navigate(
            ReleaseNotificationNavigation(
                id: queuedDestination.id,
                tab: .anime,
                detailDestination: ReleaseNotificationDetailDestination(
                    id: queuedDestination.id,
                    mediaId: 42
                )
            )
        ))
        #expect(router.pendingDestination(for: sceneID) == queuedDestination)

        let navigationState = ContentNavigationState()
        navigationState.apply(outcome)

        #expect(navigationState.selectedTab == .anime)
        #expect(navigationState.pendingNotificationNavigation == ReleaseNotificationNavigation(
            id: queuedDestination.id,
            tab: .anime,
            detailDestination: ReleaseNotificationDetailDestination(
                id: queuedDestination.id,
                mediaId: 42
            )
        ))
        #expect(navigationState.animePath.isEmpty)

        #expect(!ReleaseNotificationPresentationCoordinator.present(
            navigationID: queuedDestination.id,
            sceneID: sceneID,
            state: navigationState,
            router: router,
            canPresent: { false }
        ))

        #expect(navigationState.pendingNotificationNavigation?.id == queuedDestination.id)
        #expect(router.pendingDestination(for: sceneID) == queuedDestination)

        #expect(ReleaseNotificationPresentationCoordinator.present(
            navigationID: queuedDestination.id,
            sceneID: sceneID,
            state: navigationState,
            router: router,
            canPresent: { true }
        ))

        #expect(navigationState.pendingNotificationNavigation == nil)
        #expect(navigationState.animePath.count == 1)
        #expect(router.pendingDestination(for: sceneID) == nil)

        #expect(!ReleaseNotificationPresentationCoordinator.present(
            navigationID: queuedDestination.id,
            sceneID: sceneID,
            state: navigationState,
            router: router,
            canPresent: { true }
        ))

        #expect(navigationState.animePath.count == 1)
    }

    @Test("A warm tap produces the Anime detail navigation exactly once")
    func warmTapRoutesExactlyOnce() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(
            notificationIdentifier: "warm-42",
            mediaID: 42,
            ownerUsername: "Owner"
        )
        guard let queuedDestination = router.pendingDestination(for: sceneID) else {
            Issue.record("The tap did not queue a destination")
            return
        }

        let outcome = consume(router: router, sceneID: sceneID)

        #expect(outcome == .navigate(ReleaseNotificationNavigation(
            id: queuedDestination.id,
            tab: .anime,
            detailDestination: ReleaseNotificationDetailDestination(
                id: queuedDestination.id,
                mediaId: 42
            )
        )))
        #expect(router.pendingDestination(for: sceneID) == queuedDestination)
        #expect(router.acknowledge(
            destinationID: queuedDestination.id,
            for: sceneID
        ))
        #expect(consume(router: router, sceneID: sceneID) == .none)
    }

    @Test("Scene activation routes a cold tap queued before registration")
    func sceneActivationRoutesColdTap() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        let navigationState = ContentNavigationState()
        router.accept(
            notificationIdentifier: "cold-42",
            mediaID: 42,
            ownerUsername: "Owner"
        )

        #expect(consume(router: router, sceneID: sceneID) == .none)

        let outcome = ReleaseNotificationRouteCoordinator.registerAndConsume(
            router: router,
            sceneID: sceneID,
            isReady: true,
            isIdentityResolved: true,
            isActive: true,
            ownerUsername: "owner"
        )
        guard case let .navigate(navigation) = outcome else {
            Issue.record("Scene activation did not route the queued destination")
            return
        }
        #expect(outcome == .navigate(
            ReleaseNotificationNavigation(
                id: navigation.id,
                tab: .anime,
                detailDestination: ReleaseNotificationDetailDestination(
                    id: navigation.id,
                    mediaId: 42
                )
            )
        ))
        #expect(router.claimedDestination(for: sceneID)?.id == navigation.id)

        navigationState.apply(outcome)
        #expect(navigationState.selectedTab == .anime)
        #expect(navigationState.pendingNotificationNavigation?.id == navigation.id)
    }

    @Test("Unresolved identity defers without consuming the tap")
    func unresolvedIdentityDefers() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(
            notificationIdentifier: "unresolved-42",
            mediaID: 42,
            ownerUsername: "Owner"
        )

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
                detailDestination: ReleaseNotificationDetailDestination(
                    id: queuedDestination.id,
                    mediaId: 42
                )
            )
        ))
    }

    @Test("An inactive scene defers without consuming the tap")
    func inactiveSceneDefers() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(
            notificationIdentifier: "inactive-42",
            mediaID: 42,
            ownerUsername: "Owner"
        )

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
                detailDestination: ReleaseNotificationDetailDestination(
                    id: queuedDestination.id,
                    mediaId: 42
                )
            )
        ))
    }

    @Test("A tap for another owner is rejected and consumed")
    func wrongOwnerIsRejected() {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(
            notificationIdentifier: "wrong-owner-42",
            mediaID: 42,
            ownerUsername: "Other"
        )

        #expect(consume(router: router, sceneID: sceneID) == .rejected)
        #expect(router.pendingDestination(for: sceneID) == nil)
        #expect(consume(router: router, sceneID: sceneID) == .none)
    }

    @Test("Consecutive same-media taps keep distinct path identities")
    func sameMediaTapHasUniquePresentationIdentity() throws {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        let navigationState = ContentNavigationState()
        router.register(sceneID: sceneID, isActive: true)

        router.accept(
            notificationIdentifier: "same-media-first",
            mediaID: 42,
            ownerUsername: "Owner"
        )
        let firstDestination = try #require(router.pendingDestination(for: sceneID))
        navigationState.apply(consume(router: router, sceneID: sceneID))
        #expect(ReleaseNotificationPresentationCoordinator.present(
            navigationID: firstDestination.id,
            sceneID: sceneID,
            state: navigationState,
            router: router,
            canPresent: { true }
        ))

        router.accept(
            notificationIdentifier: "same-media-second",
            mediaID: 42,
            ownerUsername: "Owner"
        )
        let secondDestination = try #require(router.pendingDestination(for: sceneID))
        #expect(secondDestination.id != firstDestination.id)
        navigationState.apply(consume(router: router, sceneID: sceneID))
        #expect(ReleaseNotificationPresentationCoordinator.present(
            navigationID: secondDestination.id,
            sceneID: sceneID,
            state: navigationState,
            router: router,
            canPresent: { true }
        ))

        #expect(navigationState.pendingNotificationNavigation == nil)
        #expect(navigationState.animePath.count == 1)
        #expect(router.pendingDestination(for: sceneID) == nil)
    }

    @Test("Duplicate ingress for one system response queues one destination")
    func duplicateIngressIsIdempotent() throws {
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
        let firstDestination = try #require(router.pendingDestination(for: sceneID))

        #expect(ReleaseNotificationResponseHandler.handle(
            identifier: request.identifier,
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: request.content.userInfo,
            router: router
        ))
        #expect(router.pendingDestination(for: sceneID) == firstDestination)

        #expect(router.claim(destinationID: firstDestination.id, for: sceneID))
        #expect(router.acknowledge(
            destinationID: firstDestination.id,
            for: sceneID
        ))
        #expect(ReleaseNotificationResponseHandler.handle(
            identifier: request.identifier,
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: request.content.userInfo,
            router: router
        ))
        #expect(router.pendingDestination(for: sceneID) == nil)
    }

    @Test("One active scene reserves a tap until presentation")
    func oneSceneReservesDestination() throws {
        let router = ReleaseNotificationRouter()
        let firstScene = UUID()
        let secondScene = UUID()
        router.register(sceneID: firstScene, isActive: true)
        router.register(sceneID: secondScene, isActive: true)
        router.accept(
            notificationIdentifier: "multi-scene",
            mediaID: 42,
            ownerUsername: "Owner"
        )
        let destination = try #require(router.pendingDestination(for: firstScene))
        #expect(router.pendingDestination(for: secondScene) == destination)

        #expect(consume(router: router, sceneID: firstScene) == .navigate(
            ReleaseNotificationNavigation(
                id: destination.id,
                tab: .anime,
                detailDestination: ReleaseNotificationDetailDestination(
                    id: destination.id,
                    mediaId: 42
                )
            )
        ))
        #expect(router.claimedDestination(for: firstScene) == destination)
        #expect(router.pendingDestination(for: secondScene) == nil)
        #expect(consume(router: router, sceneID: secondScene) == .none)
    }

    @Test("Scene-targeted ingress is visible only to its destination scene")
    func targetedSceneOwnsDestination() throws {
        let router = ReleaseNotificationRouter()
        let firstScene = UUID()
        let targetScene = UUID()
        router.register(sceneID: firstScene, isActive: true)
        router.register(sceneID: targetScene, isActive: true)

        router.accept(
            notificationIdentifier: "targeted-scene",
            mediaID: 42,
            ownerUsername: "Owner"
        )
        let unboundDestination = try #require(router.pendingDestination(for: firstScene))

        #expect(!router.accept(
            notificationIdentifier: "targeted-scene",
            mediaID: 42,
            ownerUsername: "Owner",
            targetSceneID: targetScene
        ))
        #expect(router.pendingDestination(for: firstScene) == nil)
        #expect(router.pendingDestination(for: targetScene)?.id == unboundDestination.id)
        #expect(consume(router: router, sceneID: firstScene) == .none)
        #expect(consume(router: router, sceneID: targetScene) == .navigate(
            ReleaseNotificationNavigation(
                id: unboundDestination.id,
                tab: .anime,
                detailDestination: ReleaseNotificationDetailDestination(
                    id: unboundDestination.id,
                    mediaId: 42
                )
            )
        ))
    }

    @Test("A canceled or hidden presentation retains the claimed tap")
    func blockedPresentationRetainsClaim() throws {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        let navigationState = ContentNavigationState()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(
            notificationIdentifier: "blocked-presentation",
            mediaID: 42,
            ownerUsername: "Owner"
        )
        let destination = try #require(router.pendingDestination(for: sceneID))
        navigationState.apply(consume(router: router, sceneID: sceneID))

        #expect(!ReleaseNotificationPresentationCoordinator.present(
            navigationID: destination.id,
            sceneID: sceneID,
            state: navigationState,
            router: router,
            canPresent: { false }
        ))
        #expect(navigationState.animePath.isEmpty)
        #expect(navigationState.pendingNotificationNavigation?.id == destination.id)
        #expect(router.claimedDestination(for: sceneID) == destination)
    }

    @Test("A stale presentation cannot replace or acknowledge a newer tap")
    func newerDestinationWinsPresentationRace() throws {
        let router = ReleaseNotificationRouter()
        let sceneID = UUID()
        let navigationState = ContentNavigationState()
        router.register(sceneID: sceneID, isActive: true)
        router.accept(
            notificationIdentifier: "race-first",
            mediaID: 41,
            ownerUsername: "Owner"
        )
        let firstDestination = try #require(router.pendingDestination(for: sceneID))
        navigationState.apply(consume(router: router, sceneID: sceneID))

        router.accept(
            notificationIdentifier: "race-second",
            mediaID: 42,
            ownerUsername: "Owner"
        )
        let secondDestination = try #require(router.pendingDestination(for: sceneID))
        #expect(!ReleaseNotificationPresentationCoordinator.present(
            navigationID: firstDestination.id,
            sceneID: sceneID,
            state: navigationState,
            router: router,
            canPresent: { true }
        ))
        #expect(navigationState.animePath.isEmpty)
        #expect(router.pendingDestination(for: sceneID) == secondDestination)

        navigationState.apply(consume(router: router, sceneID: sceneID))
        #expect(ReleaseNotificationPresentationCoordinator.present(
            navigationID: secondDestination.id,
            sceneID: sceneID,
            state: navigationState,
            router: router,
            canPresent: { true }
        ))
        #expect(navigationState.animePath.count == 1)
        #expect(router.pendingDestination(for: sceneID) == nil)
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
