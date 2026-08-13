import Foundation
import Testing
import UserNotifications
@testable import Rakuroku

@Suite("Release notifications", .timeLimit(.minutes(1)))
@MainActor
struct ReleaseNotificationStoreTests {
    @Test("Only Watching and currently releasing anime with a future positive episode qualify")
    func exactEligibility() {
        let session = makeSession()
        let entries = MediaListStatus.allCases.enumerated().map { index, status in
            makeEntry(
                entryID: index + 1,
                mediaID: 100 + index,
                status: status,
                mediaStatus: "RELEASING",
                nextAiringEpisode: airing(episode: 4, at: 1_001)
            )
        } + [
            makeEntry(entryID: 20, mediaID: 200, mediaStatus: "FINISHED", nextAiringEpisode: airing(episode: 4, at: 1_001)),
            makeEntry(entryID: 21, mediaID: 201, mediaStatus: "releasing", nextAiringEpisode: airing(episode: 4, at: 1_001)),
            makeEntry(entryID: 22, mediaID: 202, nextAiringEpisode: airing(episode: 0, at: 1_001)),
            makeEntry(entryID: 23, mediaID: 203, nextAiringEpisode: airing(episode: 4, at: 1_000)),
            makeEntry(entryID: 24, mediaID: 204, nextAiringEpisode: airing(episode: 4, at: 999)),
            makeEntry(entryID: 25, mediaID: 205, nextAiringEpisode: nil),
        ]

        let candidates = ReleaseNotificationPlan.candidates(
            entries: entries,
            hasUsableData: true,
            snapshotSessionID: session.id,
            activeSessionID: session.id,
            nowEpoch: 1_000
        )

        #expect(candidates?.map(\.mediaID) == [100])
        #expect(candidates?.first?.episode == 4)
    }

    @Test("Being behind or caught up does not change release notification eligibility")
    func progressIsIgnored() {
        let session = makeSession()
        let entries = [
            makeEntry(entryID: 1, mediaID: 101, progress: 0, nextAiringEpisode: airing(episode: 8, at: 1_001)),
            makeEntry(entryID: 2, mediaID: 102, progress: 7, nextAiringEpisode: airing(episode: 8, at: 1_001)),
            makeEntry(entryID: 3, mediaID: 103, progress: 99, nextAiringEpisode: airing(episode: 8, at: 1_001)),
        ]

        let candidates = validCandidates(entries, session: session)

        #expect(candidates.map(\.mediaID) == [101, 102, 103])
    }

    @Test("Stale or unusable snapshots return nil while a valid empty snapshot returns an empty plan")
    func snapshotValidityIsExplicit() {
        let active = makeSession(username: "active", revision: 2)
        let stale = makeSession(username: "stale", revision: 1)

        #expect(ReleaseNotificationPlan.candidates(entries: [], hasUsableData: false, snapshotSessionID: active.id, activeSessionID: active.id, nowEpoch: 1_000) == nil)
        #expect(ReleaseNotificationPlan.candidates(entries: [], hasUsableData: true, snapshotSessionID: nil, activeSessionID: active.id, nowEpoch: 1_000) == nil)
        #expect(ReleaseNotificationPlan.candidates(entries: [], hasUsableData: true, snapshotSessionID: stale.id, activeSessionID: active.id, nowEpoch: 1_000) == nil)
        #expect(ReleaseNotificationPlan.candidates(entries: [], hasUsableData: true, snapshotSessionID: active.id, activeSessionID: active.id, nowEpoch: 1_000) == [])
    }

    @Test("Candidates are deduplicated and ordered deterministically with title fallback")
    func deterministicPlanAndIdentifiers() {
        let session = makeSession(username: "  Tý User  ", revision: 8)
        let entries = [
            makeEntry(entryID: 1, mediaID: 3, title: MediaTitle(romaji: nil, english: nil, native: nil), nextAiringEpisode: airing(episode: 4, at: 1_100)),
            makeEntry(entryID: 2, mediaID: 2, title: MediaTitle(romaji: "Romaji", english: nil, native: "Native"), nextAiringEpisode: airing(episode: 3, at: 1_050)),
            makeEntry(entryID: 3, mediaID: 3, title: MediaTitle(romaji: "Later", english: "Later English", native: nil), nextAiringEpisode: airing(episode: 9, at: 1_200)),
        ]

        let candidates = validCandidates(entries, session: session)

        #expect(candidates.map(\.mediaID) == [2, 3])
        #expect(candidates.map(\.title) == ["Romaji", "Unknown"])
        #expect(candidates[1].episode == 4)
        #expect(ReleaseNotificationCandidate.identifier(ownerUsername: "  Tý User  ", mediaID: 3, airingAt: 1_100) == ReleaseNotificationCandidate.identifier(ownerUsername: "tý user", mediaID: 3, airingAt: 1_100))
        #expect(candidates[1].request(ownerUsername: session.id.username).identifier == ReleaseNotificationCandidate.identifier(ownerUsername: session.id.username, mediaID: 3, airingAt: 1_100))
        let renewedSession = makeSession(username: session.id.username, revision: 9)
        #expect(renewedSession.id.revision != session.id.revision)
        #expect(candidates[1].request(ownerUsername: renewedSession.id.username).identifier == candidates[1].request(ownerUsername: session.id.username).identifier)
    }

    @Test("UTC calendar components reconstruct the same absolute instant in Denver and Tokyo")
    func triggerUsesAbsoluteUTCInstant() throws {
        let epoch = 1_784_384_245
        let components = ReleaseNotificationTrigger.dateComponents(airingAt: epoch)
        let expected = Date(timeIntervalSince1970: TimeInterval(epoch))

        for identifier in ["America/Denver", "Asia/Tokyo"] {
            let calendar = try #require(Calendar(identifier: .gregorian).withTimeZone(identifier))
            #expect(calendar.date(from: components) == expected)
        }
    }

    @Test("The real notification request parser rejects wrong or repeating triggers")
    func notificationRequestTriggerValidation() throws {
        let model = candidate(mediaID: 7, episode: 8, airingAt: 2_000)
            .request(ownerUsername: "owner")
        let valid = model.notificationRequest()

        #expect(valid.identifier == model.identifier)
        #expect(valid.content.title == model.title)
        #expect(model.notificationBody == "Episode 8 is airing now.")
        #expect(valid.content.body == model.notificationBody)
        #expect(valid.content.threadIdentifier == "rakuroku.release")
        #expect(UserNotificationCenterClient.pendingRequest(valid).request == model)

        let repeating = UNNotificationRequest(
            identifier: valid.identifier,
            content: valid.content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: ReleaseNotificationTrigger.dateComponents(airingAt: model.airingAt),
                repeats: true
            )
        )
        #expect(UserNotificationCenterClient.pendingRequest(repeating).request == nil)

        let silentContent = try #require(
            valid.content.mutableCopy() as? UNMutableNotificationContent
        )
        silentContent.sound = nil
        let silent = UNNotificationRequest(
            identifier: valid.identifier,
            content: silentContent,
            trigger: valid.trigger
        )
        #expect(UserNotificationCenterClient.pendingRequest(silent).request == nil)

        let wrongTime = UNNotificationRequest(
            identifier: valid.identifier,
            content: valid.content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: ReleaseNotificationTrigger.dateComponents(airingAt: model.airingAt + 60),
                repeats: false
            )
        )
        #expect(UserNotificationCenterClient.pendingRequest(wrongTime).request == nil)

        var impossibleComponents = ReleaseNotificationTrigger.dateComponents(
            airingAt: model.airingAt
        )
        impossibleComponents.weekday = 7
        let impossibleExtraConstraint = UNNotificationRequest(
            identifier: valid.identifier,
            content: valid.content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: impossibleComponents,
                repeats: false
            )
        )
        #expect(
            UserNotificationCenterClient.pendingRequest(impossibleExtraConstraint).request == nil
        )
    }

    @Test("Synchronization adds desired requests, removes stale managed requests, preserves foreign requests, and skips identical requests")
    func synchronizationDiffsOnlyManagedRequests() async {
        let session = makeSession(username: "owner")
        let kept = candidate(mediaID: 1, episode: 2, airingAt: 2_000).request(ownerUsername: session.id.username)
        let stale = candidate(mediaID: 2, episode: 3, airingAt: 2_100).request(ownerUsername: session.id.username)
        let foreign = PendingReleaseNotificationRequest(identifier: "other.app.keep", request: nil)
        let center = FakeNotificationCenter(status: .authorized)
        let store = ReleaseNotificationStore(center: center, preferences: FakePreferences(isEnabled: true))
        await store.synchronize(candidates: [], sessionID: session.id)
        center.pending = [
            PendingReleaseNotificationRequest(identifier: kept.identifier, request: kept),
            PendingReleaseNotificationRequest(identifier: stale.identifier, request: stale),
            foreign,
        ]
        center.removedIdentifiers.removeAll()

        await store.synchronize(candidates: [
            candidate(mediaID: 1, episode: 2, airingAt: 2_000),
            candidate(mediaID: 3, episode: 4, airingAt: 2_200),
        ], sessionID: session.id)

        #expect(center.removedIdentifiers == [stale.identifier])
        #expect(center.added.map(\.mediaID) == [3])
        #expect(center.pending.contains { $0.identifier == foreign.identifier })
        #expect(store.scheduledCount == 2)
        #expect(store.schedulingError == nil)
    }

    @Test("Opting out and a denied authorization remove only managed requests")
    func optOutAndDeniedCleanup() async {
        let session = makeSession()
        let managed = candidate(mediaID: 1, episode: 2, airingAt: 2_000).request(ownerUsername: session.id.username)
        let foreign = PendingReleaseNotificationRequest(identifier: "foreign", request: nil)
        let center = FakeNotificationCenter(status: .authorized, pending: [
            PendingReleaseNotificationRequest(identifier: managed.identifier, request: managed), foreign,
        ])
        let preferences = FakePreferences(isEnabled: true)
        let store = ReleaseNotificationStore(center: center, preferences: preferences)

        await store.setEnabled(false)

        #expect(!store.isEnabled)
        #expect(!preferences.isEnabled)
        #expect(center.removedIdentifiers == [managed.identifier])
        #expect(center.pending.map(\.identifier) == [foreign.identifier])

        let deniedManaged = candidate(mediaID: 2, episode: 3, airingAt: 2_100).request(ownerUsername: session.id.username)
        center.pending = [PendingReleaseNotificationRequest(identifier: deniedManaged.identifier, request: deniedManaged), foreign]
        preferences.isEnabled = true
        let deniedStore = ReleaseNotificationStore(center: center, preferences: preferences)
        center.status = .denied

        await deniedStore.synchronize(candidates: [candidate(mediaID: 2, episode: 3, airingAt: 2_100)], sessionID: session.id)

        #expect(center.removedIdentifiers.contains(deniedManaged.identifier))
        #expect(center.pending.map(\.identifier) == [foreign.identifier])
        #expect(deniedStore.scheduledCount == 0)
    }

    @Test("Cleanup removes managed delivered notifications and preserves foreign notifications")
    func cleanupRemovesManagedDeliveredNotifications() async {
        let managed = candidate(mediaID: 1, episode: 2, airingAt: 2_000)
            .request(ownerUsername: "owner")
        let center = FakeNotificationCenter(
            status: .authorized,
            deliveredIdentifiers: [managed.identifier, "foreign.delivered"]
        )
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )

        await store.setEnabled(false)

        #expect(center.removedDeliveredIdentifiers == [managed.identifier])
        #expect(center.deliveredIdentifiers == ["foreign.delivered"])
    }

    @Test("A session change cleans managed notifications even when the new snapshot is unavailable")
    func sessionChangeWithNilPlanCleansManagedRequests() async {
        let first = makeSession(username: "first")
        let second = makeSession(username: "second")
        let managedCandidate = candidate(mediaID: 1, episode: 2, airingAt: 2_000)
        let managed = managedCandidate.request(ownerUsername: first.id.username)
        let center = FakeNotificationCenter(status: .authorized)
        center.failingMediaIDs = [managed.mediaID]
        let store = ReleaseNotificationStore(center: center, preferences: FakePreferences(isEnabled: true))

        await store.synchronize(candidates: [managedCandidate], sessionID: first.id)
        #expect(store.schedulingError == "Test add failure")

        center.pending = [PendingReleaseNotificationRequest(identifier: managed.identifier, request: managed)]
        center.removedIdentifiers.removeAll()

        await store.synchronize(candidates: nil, sessionID: second.id)

        #expect(center.removedIdentifiers == [managed.identifier])
        #expect(center.pending.isEmpty)
        #expect(store.scheduledCount == 0)
        #expect(store.schedulingError == nil)
    }

    @Test("Canceling managed notifications clears a previous scheduling error")
    func cancelManagedNotificationsClearsSchedulingError() async {
        let session = makeSession()
        let managedCandidate = candidate(mediaID: 1, episode: 2, airingAt: 2_000)
        let managed = managedCandidate.request(ownerUsername: session.id.username)
        let center = FakeNotificationCenter(status: .authorized)
        center.failingMediaIDs = [managed.mediaID]
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )

        await store.synchronize(candidates: [managedCandidate], sessionID: session.id)
        #expect(store.schedulingError == "Test add failure")

        center.pending = [
            PendingReleaseNotificationRequest(identifier: managed.identifier, request: managed),
        ]
        await store.cancelPendingReleaseNotifications()

        #expect(center.pending.isEmpty)
        #expect(store.scheduledCount == 0)
        #expect(store.schedulingError == nil)
    }

    @Test("A cold store with no candidates sanitizes managed notifications for the resolved owner")
    func coldStoreNilCandidatesSanitizesManagedNotificationsForResolvedOwner() async {
        let session = makeSession(username: "owner")
        let sameOwner = candidate(mediaID: 1, episode: 2, airingAt: 2_000)
            .request(ownerUsername: session.id.username)
        let otherOwner = candidate(mediaID: 2, episode: 3, airingAt: 2_100)
            .request(ownerUsername: "other")
        let malformedPendingIdentifier = "rakuroku.release.malformed-pending"
        let nonCanonicalDeliveredIdentifier = "rakuroku.release.noncanonical-delivered"
        let foreignPending = PendingReleaseNotificationRequest(
            identifier: "foreign.pending",
            request: nil
        )
        let foreignDeliveredIdentifier = "foreign.delivered"
        let center = FakeNotificationCenter(
            status: .authorized,
            pending: [
                PendingReleaseNotificationRequest(
                    identifier: sameOwner.identifier,
                    request: sameOwner
                ),
                PendingReleaseNotificationRequest(
                    identifier: otherOwner.identifier,
                    request: otherOwner
                ),
                PendingReleaseNotificationRequest(
                    identifier: malformedPendingIdentifier,
                    request: nil
                ),
                foreignPending,
            ],
            deliveredIdentifiers: [
                sameOwner.identifier,
                otherOwner.identifier,
                nonCanonicalDeliveredIdentifier,
                foreignDeliveredIdentifier,
            ]
        )
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )

        await store.synchronize(candidates: nil, sessionID: session.id)

        #expect(center.added.isEmpty)
        #expect(center.removedIdentifiers.sorted() == [
            otherOwner.identifier,
            malformedPendingIdentifier,
        ].sorted())
        #expect(center.pending.map(\.identifier) == [
            sameOwner.identifier,
            foreignPending.identifier,
        ])
        #expect(center.removedDeliveredIdentifiers.sorted() == [
            otherOwner.identifier,
            nonCanonicalDeliveredIdentifier,
        ].sorted())
        #expect(center.deliveredIdentifiers == [
            sameOwner.identifier,
            foreignDeliveredIdentifier,
        ])
    }

    @Test("A cold unresolved identity preserves existing managed notifications without loading")
    func coldUnresolvedIdentityPreservesManagedRequests() async {
        let session = makeSession(username: "owner", revision: 1)
        let managed = candidate(mediaID: 1, episode: 2, airingAt: 2_000)
            .request(ownerUsername: session.id.username)
        let center = FakeNotificationCenter(
            status: .authorized,
            pending: [
                PendingReleaseNotificationRequest(
                    identifier: managed.identifier,
                    request: managed
                ),
            ],
            deliveredIdentifiers: [managed.identifier]
        )
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )
        var loadCount = 0
        var candidateReadCount = 0

        await ReleaseNotificationSynchronizationCoordinator.synchronize(
            request: ReleaseNotificationSynchronizationRequest(
                sessionID: session.id,
                isEnabled: true,
                isIdentityResolved: false,
                candidates: nil
            ),
            currentSession: { session },
            loadAnime: { _ in loadCount += 1 },
            currentCandidates: { _ in
                candidateReadCount += 1
                return []
            },
            apply: { candidates, sessionID in
                await store.synchronize(candidates: candidates, sessionID: sessionID)
            }
        )

        #expect(loadCount == 0)
        #expect(candidateReadCount == 0)
        #expect(center.added.isEmpty)
        #expect(center.removedIdentifiers.isEmpty)
        #expect(center.removedDeliveredIdentifiers.isEmpty)
        #expect(center.pending.map(\.identifier) == [managed.identifier])
        #expect(center.deliveredIdentifiers == [managed.identifier])
    }

    @Test("Resolved identity sanitizes a cold owner before a suspended library load", .timeLimit(.minutes(1)))
    func resolvedIdentitySanitizesBeforeSuspendedLibraryLoad() async {
        let session = makeSession(username: "owner")
        let sameOwner = candidate(mediaID: 1, episode: 2, airingAt: 2_000)
            .request(ownerUsername: session.id.username)
        let otherOwner = candidate(mediaID: 2, episode: 3, airingAt: 2_100)
            .request(ownerUsername: "other")
        let foreignPending = PendingReleaseNotificationRequest(
            identifier: "foreign.pending",
            request: nil
        )
        let foreignDeliveredIdentifier = "foreign.delivered"
        let center = FakeNotificationCenter(
            status: .authorized,
            pending: [
                PendingReleaseNotificationRequest(
                    identifier: sameOwner.identifier,
                    request: sameOwner
                ),
                PendingReleaseNotificationRequest(
                    identifier: otherOwner.identifier,
                    request: otherOwner
                ),
                foreignPending,
            ],
            deliveredIdentifiers: [
                sameOwner.identifier,
                otherOwner.identifier,
                foreignDeliveredIdentifier,
            ]
        )
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )
        let loader = SuspendedReleaseNotificationLibraryLoader()
        var candidateReadCount = 0

        let synchronization = Task {
            await ReleaseNotificationSynchronizationCoordinator.synchronize(
                request: ReleaseNotificationSynchronizationRequest(
                    sessionID: session.id,
                    isEnabled: true,
                    isIdentityResolved: true,
                    candidates: nil
                ),
                currentSession: { session },
                loadAnime: { _ in await loader.load() },
                currentCandidates: { _ in
                    candidateReadCount += 1
                    return nil
                },
                apply: { candidates, sessionID in
                    await store.synchronize(candidates: candidates, sessionID: sessionID)
                }
            )
        }

        await loader.waitUntilStarted()

        #expect(center.added.isEmpty)
        #expect(center.removedIdentifiers == [otherOwner.identifier])
        #expect(center.pending.map(\.identifier) == [
            sameOwner.identifier,
            foreignPending.identifier,
        ])
        #expect(center.removedDeliveredIdentifiers == [otherOwner.identifier])
        #expect(center.deliveredIdentifiers == [
            sameOwner.identifier,
            foreignDeliveredIdentifier,
        ])
        #expect(candidateReadCount == 0)

        loader.finish()
        await synchronization.value

        #expect(candidateReadCount == 1)
    }

    @Test("A new session is cleaned before its library load completes", .timeLimit(.minutes(1)))
    func sessionCleanupPrecedesLibraryLoadCompletion() async {
        let first = makeSession(username: "first")
        let second = makeSession(username: "second")
        let managed = candidate(mediaID: 1, episode: 2, airingAt: 2_000)
            .request(ownerUsername: first.id.username)
        let center = FakeNotificationCenter(status: .authorized)
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )
        await store.synchronize(candidates: [], sessionID: first.id)
        center.pending = [
            PendingReleaseNotificationRequest(identifier: managed.identifier, request: managed),
        ]
        center.removedIdentifiers.removeAll()
        let loader = SuspendedReleaseNotificationLibraryLoader()

        let synchronization = Task {
            await ReleaseNotificationSynchronizationCoordinator.synchronize(
                request: ReleaseNotificationSynchronizationRequest(
                    sessionID: second.id,
                    isEnabled: true,
                    isIdentityResolved: true,
                    candidates: nil
                ),
                currentSession: { second },
                loadAnime: { _ in await loader.load() },
                currentCandidates: { _ in [] },
                apply: { candidates, sessionID in
                    await store.synchronize(candidates: candidates, sessionID: sessionID)
                }
            )
        }

        await loader.waitUntilStarted()

        #expect(center.pending.isEmpty)
        #expect(center.removedIdentifiers == [managed.identifier])

        loader.finish()
        await synchronization.value
    }

    @Test("An unresolved authenticated identity cleans old alerts without loading or scheduling")
    func unresolvedIdentityBlocksLibraryAndScheduling() async {
        let oldSession = makeSession(username: "old", revision: 1)
        let unresolvedSession = makeSession(username: "old", revision: 2)
        let oldRequest = candidate(mediaID: 1, episode: 2, airingAt: 2_000)
            .request(ownerUsername: oldSession.id.username)
        let center = FakeNotificationCenter(
            status: .authorized,
            pending: [
                PendingReleaseNotificationRequest(
                    identifier: oldRequest.identifier,
                    request: oldRequest
                ),
            ]
        )
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )
        await store.synchronize(candidates: [], sessionID: oldSession.id)
        center.pending = [
            PendingReleaseNotificationRequest(
                identifier: oldRequest.identifier,
                request: oldRequest
            ),
        ]
        center.added.removeAll()
        center.removedIdentifiers.removeAll()
        var loadCount = 0
        var candidateReadCount = 0

        await ReleaseNotificationSynchronizationCoordinator.synchronize(
            request: ReleaseNotificationSynchronizationRequest(
                sessionID: unresolvedSession.id,
                isEnabled: true,
                isIdentityResolved: false,
                candidates: nil
            ),
            currentSession: { unresolvedSession },
            loadAnime: { _ in loadCount += 1 },
            currentCandidates: { _ in
                candidateReadCount += 1
                return [candidate(mediaID: 2, episode: 3, airingAt: 2_100)]
            },
            apply: { candidates, sessionID in
                await store.synchronize(candidates: candidates, sessionID: sessionID)
            }
        )

        #expect(loadCount == 0)
        #expect(candidateReadCount == 0)
        #expect(center.added.isEmpty)
        #expect(center.pending.isEmpty)
        #expect(center.removedIdentifiers == [oldRequest.identifier])
    }

    @Test("Activation refresh does not load or schedule while identity is unresolved")
    func unresolvedIdentityBlocksActivationRefresh() async {
        let session = makeSession(username: "old", revision: 2)
        var loadCount = 0
        var candidateReadCount = 0
        var applyCount = 0

        await ReleaseNotificationSynchronizationCoordinator.refreshAfterActivation(
            isEnabled: true,
            canSchedule: true,
            isIdentityResolved: { false },
            currentSession: { session },
            loadAnime: { _ in loadCount += 1 },
            currentCandidates: { _ in
                candidateReadCount += 1
                return []
            },
            apply: { _, _ in applyCount += 1 }
        )

        #expect(loadCount == 0)
        #expect(candidateReadCount == 0)
        #expect(applyCount == 0)
    }

    @Test("A newer session waits for canceled scheduling and removes its late request", .timeLimit(.minutes(1)))
    func newerSessionCleansLateCanceledScheduling() async {
        let first = makeSession(username: "first", revision: 1)
        let second = makeSession(username: "second", revision: 2)
        let lateCandidate = candidate(mediaID: 1, episode: 2, airingAt: 2_000)
        let lateRequest = lateCandidate.request(ownerUsername: first.id.username)
        let center = FakeNotificationCenter(status: .authorized)
        center.suspendNextAdd()
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )

        let firstSynchronization = Task {
            await store.synchronize(candidates: [lateCandidate], sessionID: first.id)
        }
        await center.waitUntilAddIsSuspended()
        #expect(center.pending.map(\.identifier) == [lateRequest.identifier])

        let secondSynchronization = Task {
            await store.synchronize(candidates: nil, sessionID: second.id)
        }
        await center.waitUntilSuspendedAddIsCancelled()
        center.resumeSuspendedAdd()

        await firstSynchronization.value
        await secondSynchronization.value

        #expect(center.pending.isEmpty)
        #expect(center.removedIdentifiers.contains(lateRequest.identifier))
        #expect(store.scheduledCount == 0)
    }

    @Test("A partial scheduling failure reports the error and retains the successful count")
    func partialAddFailure() async {
        let session = makeSession()
        let center = FakeNotificationCenter(status: .authorized)
        center.failingMediaIDs = [2]
        let store = ReleaseNotificationStore(center: center, preferences: FakePreferences(isEnabled: true))

        await store.synchronize(candidates: [
            candidate(mediaID: 1, episode: 2, airingAt: 2_000),
            candidate(mediaID: 2, episode: 3, airingAt: 2_100),
        ], sessionID: session.id)

        #expect(center.added.map(\.mediaID) == [1])
        #expect(store.scheduledCount == 1)
        #expect(store.schedulingError == "Test add failure")
    }

    @Test("Scheduling keeps the nearest requests within remaining app capacity")
    func schedulingUsesNearestAvailableCapacity() async {
        let session = makeSession()
        let center = FakeNotificationCenter(status: .authorized)
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )
        await store.synchronize(candidates: [], sessionID: session.id)
        center.pending = [
            PendingReleaseNotificationRequest(identifier: "foreign.one", request: nil),
            PendingReleaseNotificationRequest(identifier: "foreign.two", request: nil),
        ]
        center.added.removeAll()
        center.pendingRequestCallCount = 0
        let candidates = (1...70).reversed().map {
            candidate(mediaID: $0, episode: 2, airingAt: 2_000 + $0)
        }

        await store.synchronize(candidates: candidates, sessionID: session.id)

        #expect(center.added.map(\.mediaID) == Array(1...62))
        #expect(store.scheduledCount == 62)
        #expect(center.pendingRequestCallCount == 2)
    }

    @Test("Scheduled count is read back when the center silently omits an accepted request")
    func scheduledCountUsesPendingReadback() async {
        let session = makeSession()
        let center = FakeNotificationCenter(status: .authorized)
        center.silentlyDroppedMediaIDs = [2]
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )

        await store.synchronize(candidates: [
            candidate(mediaID: 1, episode: 2, airingAt: 2_000),
            candidate(mediaID: 2, episode: 3, airingAt: 2_100),
        ], sessionID: session.id)

        #expect(center.added.map(\.mediaID) == [1, 2])
        #expect(store.scheduledCount == 1)
        #expect(store.schedulingError != nil)
    }

    @Test("A malformed same-identifier request is removed before a failed replacement")
    func malformedRequestCannotSurviveFailedReplacement() async {
        let session = makeSession()
        let desiredCandidate = candidate(mediaID: 2, episode: 3, airingAt: 2_100)
        let desiredRequest = desiredCandidate.request(ownerUsername: session.id.username)
        let center = FakeNotificationCenter(status: .authorized)
        let store = ReleaseNotificationStore(
            center: center,
            preferences: FakePreferences(isEnabled: true)
        )
        await store.synchronize(candidates: [], sessionID: session.id)
        center.pending = [
            PendingReleaseNotificationRequest(
                identifier: desiredRequest.identifier,
                request: nil
            ),
        ]
        center.removedIdentifiers.removeAll()
        center.failingMediaIDs = [2]

        await store.synchronize(
            candidates: [desiredCandidate],
            sessionID: session.id
        )

        #expect(center.removedIdentifiers == [desiredRequest.identifier])
        #expect(center.pending.isEmpty)
        #expect(store.scheduledCount == 0)
        #expect(store.schedulingError == "Test add failure")
    }

    @Test("Enabling requests authorization and persists only after permission is granted")
    func authorizationPreferenceBehavior() async {
        let grantedCenter = FakeNotificationCenter(status: .notDetermined, authorizationResult: true, statusAfterAuthorization: .authorized)
        let grantedPreferences = FakePreferences()
        let grantedStore = ReleaseNotificationStore(center: grantedCenter, preferences: grantedPreferences)

        await grantedStore.setEnabled(true)

        #expect(grantedCenter.authorizationRequestCount == 1)
        #expect(grantedStore.isEnabled)
        #expect(grantedPreferences.isEnabled)

        let deniedCenter = FakeNotificationCenter(status: .notDetermined, authorizationResult: false, statusAfterAuthorization: .denied)
        let deniedPreferences = FakePreferences()
        let deniedStore = ReleaseNotificationStore(center: deniedCenter, preferences: deniedPreferences)

        await deniedStore.setEnabled(true)

        #expect(deniedCenter.authorizationRequestCount == 1)
        #expect(!deniedStore.isEnabled)
        #expect(!deniedPreferences.isEnabled)
        #expect(deniedStore.authorizationStatus == .denied)
    }

    @Test("Notification taps validate ownership and required managed payload fields")
    func tapValidation() throws {
        let request = candidate(mediaID: 42, episode: 3, airingAt: 2_000)
            .request(ownerUsername: "Owner")
            .notificationRequest()
        let tap = try #require(ReleaseNotificationTapValidation.parse(
            identifier: request.identifier,
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: request.content.userInfo
        ))

        #expect(tap == ReleaseNotificationTap(mediaID: 42, ownerUsername: "Owner"))
        #expect(ReleaseNotificationTapValidation.belongsToOwner(tap, username: " owner "))
        #expect(!ReleaseNotificationTapValidation.belongsToOwner(tap, username: "other"))
        #expect(ReleaseNotificationTapValidation.parse(
            identifier: "foreign",
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: request.content.userInfo
        ) == nil)
        #expect(ReleaseNotificationTapValidation.parse(
            identifier: request.identifier,
            actionIdentifier: UNNotificationDismissActionIdentifier,
            userInfo: request.content.userInfo
        ) == nil)
        #expect(ReleaseNotificationTapValidation.parse(
            identifier: request.identifier,
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: ["kind": ReleaseNotificationRequest.kind, "mediaID": 42]
        ) == nil)
    }

    @Test("Router lets one active scene claim each uniquely identified destination")
    func routerTakeSemantics() {
        let router = ReleaseNotificationRouter()
        let firstScene = UUID()
        let secondScene = UUID()

        router.accept(mediaID: 41, ownerUsername: "owner")
        #expect(router.pendingDestination(for: firstScene) == nil)
        router.register(sceneID: firstScene, isActive: true)
        #expect(router.takePendingDestination(for: firstScene)?.mediaID == 41)

        router.register(sceneID: secondScene, isActive: true)

        router.accept(mediaID: 42, ownerUsername: "owner")
        let firstClaim = router.pendingDestination(for: firstScene)
        let secondClaim = router.pendingDestination(for: secondScene)
        #expect(firstClaim?.mediaID == 42)
        #expect(secondClaim?.id == firstClaim?.id)
        #expect(router.takePendingDestination(for: firstScene)?.id == firstClaim?.id)
        #expect(router.takePendingDestination(for: secondScene) == nil)

        router.accept(mediaID: 43, ownerUsername: "owner")
        router.register(sceneID: secondScene, isActive: false)
        #expect(router.takePendingDestination(for: firstScene)?.mediaID == 43)

        router.accept(mediaID: 43, ownerUsername: "owner")
        let firstID = router.pendingDestination(for: firstScene)?.id
        router.accept(mediaID: 43, ownerUsername: "owner")
        #expect(router.pendingDestination(for: firstScene)?.id != firstID)

        router.accept(mediaID: 0, ownerUsername: "owner")
        #expect(router.takePendingDestination(for: firstScene)?.mediaID == 43)
    }

    private func validCandidates(
        _ entries: [MediaListEntry],
        session: MediaLibrarySession
    ) -> [ReleaseNotificationCandidate] {
        ReleaseNotificationPlan.candidates(
            entries: entries,
            hasUsableData: true,
            snapshotSessionID: session.id,
            activeSessionID: session.id,
            nowEpoch: 1_000
        )!
    }
}

@MainActor
private final class FakeNotificationCenter: ReleaseNotificationCenterClient {
    var status: ReleaseNotificationAuthorizationStatus
    var authorizationResult: Bool
    var statusAfterAuthorization: ReleaseNotificationAuthorizationStatus
    var pending: [PendingReleaseNotificationRequest]
    var deliveredIdentifiers: [String]
    var added: [ReleaseNotificationRequest] = []
    var removedIdentifiers: [String] = []
    var removedDeliveredIdentifiers: [String] = []
    var failingMediaIDs: Set<Int> = []
    var silentlyDroppedMediaIDs: Set<Int> = []
    var authorizationRequestCount = 0
    var pendingRequestCallCount = 0
    private var shouldSuspendNextAdd = false
    private var addIsSuspended = false
    private var suspendedAddWasCancelled = false
    private var suspendedAddContinuation: CheckedContinuation<Void, Error>?
    private var addSuspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var addCancellationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        status: ReleaseNotificationAuthorizationStatus,
        authorizationResult: Bool = true,
        statusAfterAuthorization: ReleaseNotificationAuthorizationStatus? = nil,
        pending: [PendingReleaseNotificationRequest] = [],
        deliveredIdentifiers: [String] = []
    ) {
        self.status = status
        self.authorizationResult = authorizationResult
        self.statusAfterAuthorization = statusAfterAuthorization ?? status
        self.pending = pending
        self.deliveredIdentifiers = deliveredIdentifiers
    }

    func authorizationStatus() async -> ReleaseNotificationAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        status = statusAfterAuthorization
        return authorizationResult
    }

    func pendingRequests() async -> [PendingReleaseNotificationRequest] {
        pendingRequestCallCount += 1
        return pending
    }

    func deliveredRequestIdentifiers() async -> [String] { deliveredIdentifiers }

    func add(_ request: ReleaseNotificationRequest) async throws {
        if failingMediaIDs.contains(request.mediaID) {
            throw TestError.addFailure
        }
        added.append(request)
        guard !silentlyDroppedMediaIDs.contains(request.mediaID) else { return }
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(PendingReleaseNotificationRequest(identifier: request.identifier, request: request))

        guard shouldSuspendNextAdd else { return }
        shouldSuspendNextAdd = false
        addIsSuspended = true
        let waiters = addSuspensionWaiters
        addSuspensionWaiters.removeAll()
        waiters.forEach { $0.resume() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                suspendedAddContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.markSuspendedAddCancelled()
            }
        }
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers.append(contentsOf: identifiers)
        deliveredIdentifiers.removeAll { identifiers.contains($0) }
    }

    func suspendNextAdd() {
        shouldSuspendNextAdd = true
    }

    func waitUntilAddIsSuspended() async {
        if addIsSuspended { return }
        await withCheckedContinuation { continuation in
            addSuspensionWaiters.append(continuation)
        }
    }

    func waitUntilSuspendedAddIsCancelled() async {
        if suspendedAddWasCancelled { return }
        await withCheckedContinuation { continuation in
            addCancellationWaiters.append(continuation)
        }
    }

    func resumeSuspendedAdd() {
        suspendedAddContinuation?.resume(returning: ())
        suspendedAddContinuation = nil
        addIsSuspended = false
    }

    private func markSuspendedAddCancelled() {
        suspendedAddWasCancelled = true
        let waiters = addCancellationWaiters
        addCancellationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

@MainActor
private final class FakePreferences: ReleaseNotificationPreferenceStoring {
    var isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

@MainActor
private final class SuspendedReleaseNotificationLibraryLoader {
    private var isStarted = false
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func load() async {
        isStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if isStarted { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish() {
        loadContinuation?.resume()
        loadContinuation = nil
    }
}

private enum TestError: LocalizedError {
    case addFailure

    var errorDescription: String? { "Test add failure" }
}

private func makeSession(
    username: String = "viewer",
    revision: UInt64 = 1
) -> MediaLibrarySession {
    MediaLibrarySession(
        id: MediaLibrarySession.ID(username: username, revision: revision),
        accessToken: nil
    )
}

private func airing(episode: Int, at epoch: Int) -> NextAiringEpisode {
    NextAiringEpisode(airingAt: epoch, timeUntilAiring: epoch - 1_000, episode: episode)
}

private func candidate(mediaID: Int, episode: Int, airingAt: Int) -> ReleaseNotificationCandidate {
    ReleaseNotificationCandidate(mediaID: mediaID, title: "Title \(mediaID)", episode: episode, airingAt: airingAt)
}

private func makeEntry(
    entryID: Int,
    mediaID: Int,
    status: MediaListStatus = .current,
    progress: Int = 0,
    title: MediaTitle? = nil,
    mediaStatus: String? = "RELEASING",
    nextAiringEpisode: NextAiringEpisode? = airing(episode: 2, at: 1_001)
) -> MediaListEntry {
    MediaListEntry(
        id: entryID,
        status: status,
        progress: progress,
        score: 0,
        updatedAt: nil,
        media: Media(
            id: mediaID,
            isAdult: false,
            title: title ?? MediaTitle(romaji: "Title \(mediaID)", english: nil, native: nil),
            coverImage: nil,
            episodes: nil,
            chapters: nil,
            format: "TV",
            status: mediaStatus,
            averageScore: nil,
            nextAiringEpisode: nextAiringEpisode
        )
    )
}

private extension Calendar {
    func withTimeZone(_ identifier: String) -> Calendar? {
        guard let timeZone = TimeZone(identifier: identifier) else { return nil }
        var calendar = self
        calendar.timeZone = timeZone
        return calendar
    }
}
