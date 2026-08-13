import Foundation
import Testing
@testable import Rakuroku

@Suite("Media library store", .timeLimit(.minutes(1)))
@MainActor
struct MediaLibraryStoreTests {
    @Test("Starts with independent idle anime and manga states")
    func startsIdle() {
        let store = MediaLibraryStore(client: ControlledMediaLibraryClient())

        #expect(store.state(for: .anime).phase == .idle)
        #expect(store.state(for: .manga).phase == .idle)
        #expect(store.entries(for: .anime).isEmpty)
        #expect(store.entries(for: .manga).isEmpty)
    }

    @Test("Every saved status is emphasized while unsaved seasonal media is dimmed")
    func seasonalMembershipAppearance() {
        let activeSessionID = makeSession(username: "active", revision: 2).id
        let staleSessionID = makeSession(username: "stale", revision: 1).id

        for status in MediaListStatus.allCases {
            #expect(MediaLibraryMembershipAppearance.opacity(
                hasUsableData: true,
                snapshotSessionID: activeSessionID,
                activeSessionID: activeSessionID,
                status: status
            ) == 1)
        }

        #expect(MediaLibraryMembershipAppearance.opacity(
            hasUsableData: true,
            snapshotSessionID: activeSessionID,
            activeSessionID: activeSessionID,
            status: nil
        ) == 0.5)
        #expect(MediaLibraryMembershipAppearance.opacity(
            hasUsableData: false,
            snapshotSessionID: activeSessionID,
            activeSessionID: activeSessionID,
            status: nil
        ) == 1)
        #expect(MediaLibraryMembershipAppearance.opacity(
            hasUsableData: true,
            snapshotSessionID: nil,
            activeSessionID: activeSessionID,
            status: nil
        ) == 1)
        #expect(MediaLibraryMembershipAppearance.opacity(
            hasUsableData: true,
            snapshotSessionID: staleSessionID,
            activeSessionID: activeSessionID,
            status: nil
        ) == 1)
    }

    @Test("Up Next requires a current snapshot and watching or rewatching status")
    func upNextRequiresCurrentSnapshotAndEligibleStatus() {
        let session = makeSession(username: "active", revision: 2)
        let staleSession = makeSession(username: "stale", revision: 1)
        let entries = MediaListStatus.allCases.enumerated().map { index, status in
            makeEntry(
                entryID: index + 1,
                mediaID: 100 + index,
                status: status,
                progress: 0,
                updatedAt: index,
                mediaStatus: "RELEASING",
                nextAiringEpisode: NextAiringEpisode(
                    airingAt: 1_100,
                    timeUntilAiring: 100,
                    episode: 3
                )
            )
        }

        let items = MediaLibraryUpNext.items(
            entries: entries,
            hasUsableData: true,
            snapshotSessionID: session.id,
            activeSessionID: session.id,
            nowEpoch: 1_000
        )

        #expect(Set(items.map(\.entry.status)) == Set([.current, .repeating]))
        #expect(items.allSatisfy { $0.nextEpisode == 1 })
        #expect(MediaLibraryUpNext.items(
            entries: entries,
            hasUsableData: false,
            snapshotSessionID: session.id,
            activeSessionID: session.id,
            nowEpoch: 1_000
        ).isEmpty)
        #expect(MediaLibraryUpNext.items(
            entries: entries,
            hasUsableData: true,
            snapshotSessionID: nil,
            activeSessionID: session.id,
            nowEpoch: 1_000
        ).isEmpty)
        #expect(MediaLibraryUpNext.items(
            entries: entries,
            hasUsableData: true,
            snapshotSessionID: staleSession.id,
            activeSessionID: session.id,
            nowEpoch: 1_000
        ).isEmpty)
    }

    @Test("Up Next exposes only episodes available at the injected time")
    func upNextAvailabilityBoundaries() {
        let session = makeSession()
        let futureBoundary = makeEntry(
            entryID: 1,
            mediaID: 101,
            progress: 3,
            mediaStatus: "RELEASING",
            nextAiringEpisode: NextAiringEpisode(
                airingAt: 1_001,
                timeUntilAiring: 1,
                episode: 5
            )
        )
        let currentBoundary = makeEntry(
            entryID: 2,
            mediaID: 102,
            progress: 4,
            mediaStatus: "RELEASING",
            nextAiringEpisode: NextAiringEpisode(
                airingAt: 1_000,
                timeUntilAiring: 0,
                episode: 5
            )
        )
        let pastBoundary = makeEntry(
            entryID: 3,
            mediaID: 103,
            progress: 4,
            mediaStatus: "RELEASING",
            nextAiringEpisode: NextAiringEpisode(
                airingAt: 999,
                timeUntilAiring: -1,
                episode: 5
            )
        )
        let finished = makeEntry(
            entryID: 4,
            mediaID: 104,
            progress: 10,
            episodes: 12,
            mediaStatus: "FINISHED"
        )
        let excluded = [
            makeEntry(
                entryID: 5,
                mediaID: 105,
                progress: 0,
                mediaStatus: "NOT_YET_RELEASED",
                nextAiringEpisode: NextAiringEpisode(
                    airingAt: 1_001,
                    timeUntilAiring: 1,
                    episode: 1
                )
            ),
            makeEntry(
                entryID: 6,
                mediaID: 106,
                progress: 4,
                mediaStatus: "RELEASING",
                nextAiringEpisode: NextAiringEpisode(
                    airingAt: 1_001,
                    timeUntilAiring: 1,
                    episode: 5
                )
            ),
            makeEntry(
                entryID: 7,
                mediaID: 107,
                progress: 1,
                episodes: 12,
                mediaStatus: "RELEASING"
            ),
            makeEntry(
                entryID: 8,
                mediaID: 108,
                progress: 1,
                mediaStatus: "FINISHED"
            ),
            makeEntry(
                entryID: 9,
                mediaID: 109,
                progress: 12,
                episodes: 12,
                mediaStatus: "FINISHED"
            )
        ]

        let items = MediaLibraryUpNext.items(
            entries: [futureBoundary, currentBoundary, pastBoundary, finished] + excluded,
            hasUsableData: true,
            snapshotSessionID: session.id,
            activeSessionID: session.id,
            nowEpoch: 1_000
        )
        let nextEpisodes = Dictionary(uniqueKeysWithValues: items.map {
            ($0.entry.media.id, $0.nextEpisode)
        })

        #expect(nextEpisodes == [101: 4, 102: 5, 103: 5, 104: 11])
    }

    @Test("Up Next schedules refresh when a future episode becomes playable")
    func upNextRefreshBoundary() {
        let session = makeSession()
        let boundaryEntry = makeEntry(
            entryID: 1,
            mediaID: 101,
            progress: 4,
            mediaStatus: "RELEASING",
            nextAiringEpisode: NextAiringEpisode(
                airingAt: 1_001,
                timeUntilAiring: 1,
                episode: 5
            )
        )

        let refreshEpoch = MediaLibraryUpNext.nextRefreshEpoch(
            entries: [boundaryEntry],
            hasUsableData: true,
            snapshotSessionID: session.id,
            activeSessionID: session.id,
            nowEpoch: 1_000
        )
        let beforeBoundary = MediaLibraryUpNext.items(
            entries: [boundaryEntry],
            hasUsableData: true,
            snapshotSessionID: session.id,
            activeSessionID: session.id,
            nowEpoch: 1_000
        )
        let atBoundary = MediaLibraryUpNext.items(
            entries: [boundaryEntry],
            hasUsableData: true,
            snapshotSessionID: session.id,
            activeSessionID: session.id,
            nowEpoch: refreshEpoch ?? 0
        )

        #expect(refreshEpoch == 1_001)
        #expect(beforeBoundary.isEmpty)
        #expect(atBoundary.map(\.nextEpisode) == [5])
        #expect(MediaLibraryUpNext.nextRefreshEpoch(
            entries: [boundaryEntry],
            hasUsableData: true,
            snapshotSessionID: session.id,
            activeSessionID: session.id,
            nowEpoch: 1_001
        ) == nil)
        #expect(MediaLibraryUpNext.nextRefreshEpoch(
            entries: [boundaryEntry],
            hasUsableData: true,
            snapshotSessionID: nil,
            activeSessionID: session.id,
            nowEpoch: 1_000
        ) == nil)
    }

    @Test("Up Next sorts by list recency and then media ID")
    func upNextSortOrder() {
        let session = makeSession()
        let entries = [
            makeEntry(
                entryID: 1,
                mediaID: 300,
                progress: 0,
                updatedAt: 20,
                episodes: 12,
                mediaStatus: "FINISHED"
            ),
            makeEntry(
                entryID: 2,
                mediaID: 200,
                progress: 0,
                updatedAt: 10,
                episodes: 12,
                mediaStatus: "FINISHED"
            ),
            makeEntry(
                entryID: 3,
                mediaID: 100,
                progress: 0,
                updatedAt: 20,
                episodes: 12,
                mediaStatus: "FINISHED"
            )
        ]

        let items = MediaLibraryUpNext.items(
            entries: entries,
            hasUsableData: true,
            snapshotSessionID: session.id,
            activeSessionID: session.id,
            nowEpoch: 1_000
        )

        #expect(items.map(\.entry.media.id) == [100, 300, 200])
    }

    @Test("Store Up Next derives only from the canonical anime state")
    func upNextUsesAnimeStateOnly() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let anime = makeEntry(
            entryID: 1,
            mediaID: 101,
            progress: 1,
            episodes: 12,
            mediaStatus: "FINISHED"
        )
        let manga = makeEntry(
            entryID: 2,
            mediaID: 202,
            progress: 1,
            episodes: 12,
            mediaStatus: "FINISHED"
        )

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: session,
            entries: [anime]
        )
        await completeLoad(
            store: store,
            client: client,
            type: .manga,
            session: session,
            entries: [manga]
        )

        let items = store.upNextItems(
            activeSessionID: session.id,
            nowEpoch: 1_000
        )

        #expect(items.map(\.entry.media.id) == [101])
        #expect(items.map(\.nextEpisode) == [2])
    }

    @Test("Forced reload advances the Up Next airing schedule")
    func forcedReloadAdvancesUpNextSchedule() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let initial = makeEntry(
            entryID: 1,
            mediaID: 101,
            progress: 4,
            mediaStatus: "RELEASING",
            nextAiringEpisode: NextAiringEpisode(
                airingAt: 1_001,
                timeUntilAiring: 1,
                episode: 5
            )
        )

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: session,
            entries: [initial]
        )
        #expect(store.nextUpNextRefreshEpoch(
            activeSessionID: session.id,
            nowEpoch: 1_000
        ) == 1_001)

        let mutation = store.beginMutation(
            mediaID: initial.media.id,
            type: .anime,
            sessionID: session.id
        )
        let result = store.reconcile(
            makeUserEntry(
                entryID: initial.id,
                status: .current,
                progress: 5,
                score: 0,
                updatedAt: 2
            ),
            mutation: mutation,
            media: initial.media
        )

        #expect(result == .applied)
        #expect(store.upNextItems(
            activeSessionID: session.id,
            nowEpoch: 1_001
        ).isEmpty)
        #expect(store.nextUpNextRefreshEpoch(
            activeSessionID: session.id,
            nowEpoch: 1_001
        ) == nil)

        let refreshed = makeEntry(
            entryID: initial.id,
            mediaID: initial.media.id,
            progress: 5,
            updatedAt: 3,
            mediaStatus: "RELEASING",
            nextAiringEpisode: NextAiringEpisode(
                airingAt: 2_000,
                timeUntilAiring: 999,
                episode: 6
            )
        )
        let reload = Task {
            await store.load(.anime, session: session, force: true)
        }
        let request = await client.nextRequest()
        await client.succeed(request, with: [refreshed])
        await reload.value

        #expect(store.nextUpNextRefreshEpoch(
            activeSessionID: session.id,
            nowEpoch: 1_001
        ) == 2_000)
    }

    @Test("Home season loads apply only the latest request")
    func homeSeasonLoadsApplyOnlyLatestRequest() {
        var tracker = HomeSeasonLoadTracker()

        let first = tracker.begin()
        #expect(tracker.isCurrent(first))

        let second = tracker.begin()
        #expect(!tracker.isCurrent(first))
        #expect(tracker.isCurrent(second))
    }

    @Test("Home reloads Up Next only after a missed airing boundary")
    func homeReloadsUpNextAfterMissedBoundary() {
        #expect(!HomeUpNextRefreshPolicy.shouldReloadAfterActivation(
            scheduledRefreshEpoch: nil,
            nowEpoch: 1_000
        ))
        #expect(!HomeUpNextRefreshPolicy.shouldReloadAfterActivation(
            scheduledRefreshEpoch: 1_001,
            nowEpoch: 1_000
        ))
        #expect(HomeUpNextRefreshPolicy.shouldReloadAfterActivation(
            scheduledRefreshEpoch: 1_000,
            nowEpoch: 1_000
        ))
        #expect(HomeUpNextRefreshPolicy.shouldReloadAfterActivation(
            scheduledRefreshEpoch: 999,
            nowEpoch: 1_000
        ))
        #expect(HomeUpNextRefreshPolicy.shouldAdvanceAfterScheduledLoad(
            phase: .loaded
        ))
        #expect(!HomeUpNextRefreshPolicy.shouldAdvanceAfterScheduledLoad(
            phase: .failed(message: "Offline")
        ))
    }

    @Test("Successful load preserves order and indexes by media ID")
    func successfulLoad() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let first = makeEntry(entryID: 1, mediaID: 101, status: .current)
        let second = makeEntry(entryID: 2, mediaID: 202, status: .completed)

        let load = Task { await store.load(.anime, session: session) }
        let request = await client.nextRequest()
        await client.succeed(request, with: [second, first])
        await load.value

        #expect(store.state(for: .anime).phase == .loaded)
        #expect(store.entries(for: .anime).map(\.media.id) == [202, 101])
        #expect(store.entry(mediaID: 101, type: .anime)?.id == first.id)
        #expect(store.status(mediaID: 202, type: .anime) == .completed)
        #expect(store.state(for: .anime).snapshotSessionID == session.id)
    }

    @Test("Nullable mutation timestamps decode safely")
    func nullableMutationTimestampDecodes() throws {
        let data = Data(#"{"id":1,"status":"CURRENT","score":7,"progress":4,"updatedAt":null}"#.utf8)

        let entry = try JSONDecoder().decode(UserMediaEntry.self, from: data)

        #expect(entry.id == 1)
        #expect(entry.updatedAt == nil)
    }

    @Test("Mutation authorization requires matching displayed-session provenance")
    func mutationAuthorizationRequiresMatchingSession() {
        let currentSession = makeSession(username: "current", revision: 3, accessToken: "current-token")
        let wrongUsername = makeSession(username: "other", revision: 3).id
        let wrongRevision = makeSession(username: "current", revision: 2).id
        let signedOutSession = makeSession(
            username: "current",
            revision: 3,
            accessToken: nil
        )

        #expect(MediaLibraryMutationAuthorization.accessToken(
            displayedSessionID: currentSession.id,
            currentSession: currentSession
        ) == "current-token")
        #expect(MediaLibraryMutationAuthorization.accessToken(
            displayedSessionID: wrongUsername,
            currentSession: currentSession
        ) == nil)
        #expect(MediaLibraryMutationAuthorization.accessToken(
            displayedSessionID: wrongRevision,
            currentSession: currentSession
        ) == nil)
        #expect(MediaLibraryMutationAuthorization.accessToken(
            displayedSessionID: nil,
            currentSession: currentSession
        ) == nil)
        #expect(MediaLibraryMutationAuthorization.accessToken(
            displayedSessionID: signedOutSession.id,
            currentSession: signedOutSession
        ) == nil)
    }

    @Test("Stale-session card mutation completion restores displayed progress")
    func staleSessionCardMutationRestoresDisplayedProgress() {
        let displayedSession = makeSession(username: "old", revision: 1).id
        let currentSession = makeSession(username: "new", revision: 2).id

        #expect(MediaCardProgressResolution.fallbackProgress(
            displayedProgress: 4,
            canonicalProgress: 9,
            canonicalSessionID: displayedSession,
            currentSessionID: currentSession
        ) == 4)
        #expect(MediaCardProgressResolution.fallbackProgress(
            displayedProgress: 4,
            canonicalProgress: nil,
            canonicalSessionID: nil,
            currentSessionID: currentSession
        ) == 4)
    }

    @Test("Current-session card mutation failure restores canonical progress")
    func currentSessionCardMutationRestoresCanonicalProgress() {
        let currentSession = makeSession(revision: 3).id

        #expect(MediaCardProgressResolution.fallbackProgress(
            displayedProgress: 4,
            canonicalProgress: 7,
            canonicalSessionID: currentSession,
            currentSessionID: currentSession
        ) == 7)
    }

    @Test("Known timestamps sort ahead of unknown timestamps deterministically")
    func optionalTimestampSortOrder() {
        let unknown = MediaListEntry(
            id: 3,
            status: .current,
            progress: 0,
            score: 0,
            updatedAt: nil,
            media: makeMedia(mediaID: 303)
        )
        let older = makeEntry(entryID: 1, mediaID: 101, updatedAt: 10)
        let newer = makeEntry(entryID: 2, mediaID: 202, updatedAt: 20)

        let sorted = [unknown, older, newer].sorted {
            MediaListEntry.isUpdatedMoreRecently($0, than: $1)
        }

        #expect(sorted.map(\.media.id) == [202, 101, 303])
    }

    @Test("Rejected detail mutations restore the canonical entry")
    func rejectedDetailMutationsRestoreCanonicalEntry() {
        let staleResponse = makeUserEntry(
            entryID: 1,
            status: .current,
            progress: 5,
            score: 6,
            updatedAt: 20
        )
        let canonicalEntry = makeEntry(
            entryID: 2,
            mediaID: 101,
            status: .completed,
            progress: 12,
            score: 9,
            updatedAt: 30
        )

        let resolvedUpdate = MediaDetailMutationResolution.afterUpdate(
            staleResponse,
            reconciliation: .rejected,
            canonicalEntry: canonicalEntry
        )
        let resolvedDeletion = MediaDetailMutationResolution.afterDeletion(
            reconciliation: .rejected,
            canonicalEntry: canonicalEntry
        )

        #expect(resolvedUpdate?.id == canonicalEntry.id)
        #expect(resolvedUpdate?.status == canonicalEntry.status)
        #expect(resolvedUpdate?.progress == canonicalEntry.progress)
        #expect(resolvedUpdate?.score == canonicalEntry.score)
        #expect(resolvedDeletion?.id == canonicalEntry.id)
        #expect(resolvedDeletion?.progress == canonicalEntry.progress)
        #expect(MediaDetailMutationResolution.afterDeletion(
            reconciliation: .applied,
            canonicalEntry: canonicalEntry
        ) == nil)
    }

    @Test("Progress mutation reconciles into the canonical entry")
    func reconcilesProgress() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let original = makeEntry(entryID: 1, mediaID: 101, progress: 4, score: 7, updatedAt: 10)

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [original])
        let mutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)
        let result = store.reconcile(
            makeUserEntry(entryID: 1, status: .current, progress: 5, score: 7, updatedAt: 20),
            mutation: mutation
        )

        #expect(result == .applied)
        #expect(store.entry(mediaID: 101, type: .anime)?.progress == 5)
        #expect(store.entry(mediaID: 101, type: .anime)?.score == 7)
        #expect(store.entry(mediaID: 101, type: .anime)?.status == .current)
        #expect(store.entry(mediaID: 101, type: .anime)?.updatedAt == 20)
        #expect(store.entry(mediaID: 101, type: .anime)?.media.title.display == "Title 101")
    }

    @Test("Score mutation preserves progress and a missing server timestamp")
    func reconcilesScoreWithoutTimestamp() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let original = makeEntry(entryID: 1, mediaID: 101, progress: 4, score: 6, updatedAt: 10)

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [original])
        let mutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)
        let result = store.reconcile(
            makeUserEntry(entryID: 1, status: .current, progress: 4, score: 9, updatedAt: nil),
            mutation: mutation
        )

        #expect(result == .applied)
        #expect(store.entry(mediaID: 101, type: .anime)?.score == 9)
        #expect(store.entry(mediaID: 101, type: .anime)?.progress == 4)
        #expect(store.entry(mediaID: 101, type: .anime)?.updatedAt == 10)
    }

    @Test("Status mutation reconciles without changing list order")
    func reconcilesStatusPreservingOrder() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let first = makeEntry(entryID: 1, mediaID: 101)
        let updated = makeEntry(entryID: 2, mediaID: 202, status: .current, updatedAt: 10)
        let last = makeEntry(entryID: 3, mediaID: 303)

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: session,
            entries: [first, updated, last]
        )
        let mutation = store.beginMutation(mediaID: 202, type: .anime, sessionID: session.id)
        let result = store.reconcile(
            makeUserEntry(entryID: 2, status: .completed, progress: 0, score: 0, updatedAt: 20),
            mutation: mutation
        )

        #expect(result == .applied)
        #expect(store.status(mediaID: 202, type: .anime) == .completed)
        #expect(store.entries(for: .anime).map(\.media.id) == [101, 202, 303])
    }

    @Test("Authoritative media payload upserts a missing entry into a loaded snapshot")
    func upsertsMissingEntry() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let existing = makeEntry(entryID: 1, mediaID: 101)

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [existing])
        let mutation = store.beginMutation(mediaID: 202, type: .anime, sessionID: session.id)
        let result = store.reconcile(
            makeUserEntry(entryID: 2, status: .planning, progress: 0, score: 0, updatedAt: 20),
            mutation: mutation,
            media: makeMedia(mediaID: 202)
        )

        #expect(result == .applied)
        #expect(store.entries(for: .anime).map(\.media.id) == [101, 202])
        #expect(store.entry(mediaID: 202, type: .anime)?.status == .planning)
        #expect(store.entry(mediaID: 202, type: .anime)?.updatedAt == 20)
    }

    @Test("Authoritative media upserts a missing entry with an unknown timestamp")
    func upsertsMissingEntryWithoutTimestamp() async throws {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [])
        let mutation = store.beginMutation(mediaID: 303, type: .anime, sessionID: session.id)
        let result = store.reconcile(
            makeUserEntry(entryID: 3, status: .planning, progress: 0, score: 0, updatedAt: nil),
            mutation: mutation,
            media: makeMedia(mediaID: 303)
        )

        #expect(result == .applied)
        let insertedEntry = try #require(store.entry(mediaID: 303, type: .anime))
        #expect(insertedEntry.status == .planning)
        #expect(insertedEntry.updatedAt == nil)
    }

    @Test("Incomplete results cannot fabricate a missing list entry")
    func refusesIncompleteUpsert() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [])

        let missingMedia = store.beginMutation(mediaID: 202, type: .anime, sessionID: session.id)
        #expect(store.reconcile(
            makeUserEntry(entryID: 2, status: .planning, progress: 0, score: 0, updatedAt: 20),
            mutation: missingMedia
        ) == .unavailable)

        #expect(store.entries(for: .anime).isEmpty)
        #expect(store.state(for: .anime).hasUsableData)
    }

    @Test("A nil timestamp cannot replace a different canonical entry identity")
    func unknownTimestampDoesNotReplaceDifferentEntry() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let canonicalEntry = makeEntry(entryID: 2, mediaID: 303, updatedAt: 30)

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: session,
            entries: [canonicalEntry]
        )
        let mutation = store.beginMutation(mediaID: 303, type: .anime, sessionID: session.id)
        let result = store.reconcile(
            makeUserEntry(entryID: 3, status: .planning, progress: 0, score: 0, updatedAt: nil),
            mutation: mutation,
            media: makeMedia(mediaID: 303)
        )

        #expect(result == .unavailable)
        #expect(store.entry(mediaID: 303, type: .anime)?.id == canonicalEntry.id)
        #expect(store.entry(mediaID: 303, type: .anime)?.updatedAt == 30)
    }

    @Test("Deletion removes only the matching entry and preserves remaining order")
    func reconcilesDeletionPreservingOrder() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: session,
            entries: [
                makeEntry(entryID: 1, mediaID: 101),
                makeEntry(entryID: 2, mediaID: 202),
                makeEntry(entryID: 3, mediaID: 303),
            ]
        )

        let mutation = store.beginMutation(mediaID: 202, type: .anime, sessionID: session.id)
        let result = store.reconcileDeletion(entryID: 2, mutation: mutation)

        #expect(result == .applied)
        #expect(store.entries(for: .anime).map(\.media.id) == [101, 303])
        #expect(store.entry(mediaID: 202, type: .anime) == nil)
    }

    @Test("Mutation reconciliation is isolated by media type")
    func mutationTypeIsolation() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: session,
            entries: [makeEntry(entryID: 1, mediaID: 42, status: .current, updatedAt: 10)]
        )
        await completeLoad(
            store: store,
            client: client,
            type: .manga,
            session: session,
            entries: [makeEntry(entryID: 2, mediaID: 42, status: .planning, updatedAt: 10)]
        )

        let update = store.beginMutation(mediaID: 42, type: .anime, sessionID: session.id)
        #expect(store.reconcile(
            makeUserEntry(entryID: 1, status: .completed, progress: 12, score: 8, updatedAt: 20),
            mutation: update
        ) == .applied)
        #expect(store.status(mediaID: 42, type: .anime) == .completed)
        #expect(store.status(mediaID: 42, type: .manga) == .planning)

        let deletion = store.beginMutation(mediaID: 42, type: .anime, sessionID: session.id)
        #expect(store.reconcileDeletion(entryID: 1, mutation: deletion) == .applied)
        #expect(store.entry(mediaID: 42, type: .anime) == nil)
        #expect(store.entry(mediaID: 42, type: .manga)?.id == 2)
    }

    @Test("Unloaded snapshots do not fabricate canonical state")
    func unloadedSnapshotDoesNotFabricateState() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [])
        store.reset()

        let update = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)
        #expect(store.reconcile(
            makeUserEntry(entryID: 1, status: .current, progress: 1, score: 0, updatedAt: 20),
            mutation: update,
            media: makeMedia(mediaID: 101)
        ) == .unavailable)
        let deletion = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)
        #expect(store.reconcileDeletion(entryID: 1, mutation: deletion) == .unavailable)
        #expect(store.state(for: .anime).phase == .idle)
        #expect(!store.state(for: .anime).hasUsableData)
        #expect(store.entries(for: .anime).isEmpty)
    }

    @Test("A mutation completed before the first load is applied to its snapshot")
    func mutationBeforeInitialLoadIsApplied() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let mutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)

        #expect(store.reconcile(
            makeUserEntry(entryID: 1, status: .planning, progress: 0, score: 0, updatedAt: 20),
            mutation: mutation,
            media: makeMedia(mediaID: 101)
        ) == .unavailable)

        let load = Task { await store.load(.anime, session: session) }
        let request = await client.nextRequest()
        await client.succeed(request, with: [])
        await load.value

        #expect(store.entries(for: .anime).map(\.media.id) == [101])
        #expect(store.status(mediaID: 101, type: .anime) == .planning)
        #expect(store.entry(mediaID: 101, type: .anime)?.updatedAt == 20)
    }

    @Test("An unknown-timestamp mutation overlays the initial snapshot")
    func unknownTimestampMutationBeforeInitialLoadIsApplied() async throws {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let mutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)

        #expect(store.reconcile(
            makeUserEntry(entryID: 1, status: .planning, progress: 0, score: 0, updatedAt: nil),
            mutation: mutation,
            media: makeMedia(mediaID: 101)
        ) == .unavailable)

        let load = Task { await store.load(.anime, session: session) }
        let request = await client.nextRequest()
        await client.succeed(request, with: [])
        await load.value

        let insertedEntry = try #require(store.entry(mediaID: 101, type: .anime))
        #expect(insertedEntry.status == .planning)
        #expect(insertedEntry.updatedAt == nil)
    }

    @Test("Unavailable pending mutations survive until an authoritative snapshot can apply them")
    func unavailablePendingMutationIsRetained() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let mutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)

        #expect(store.reconcile(
            makeUserEntry(entryID: 1, status: .completed, progress: 5, score: 8, updatedAt: nil),
            mutation: mutation
        ) == .unavailable)

        let firstLoad = Task { await store.load(.anime, session: session) }
        let firstRequest = await client.nextRequest()
        await client.succeed(firstRequest, with: [])
        await firstLoad.value
        #expect(store.entry(mediaID: 101, type: .anime) == nil)

        let authoritativeEntry = makeEntry(
            entryID: 1,
            mediaID: 101,
            status: .current,
            progress: 4,
            score: 6,
            updatedAt: 30
        )
        let refresh = Task { await store.load(.anime, session: session, force: true) }
        let refreshRequest = await client.nextRequest()
        await client.succeed(refreshRequest, with: [authoritativeEntry])
        await refresh.value

        #expect(store.entry(mediaID: 101, type: .anime)?.status == .completed)
        #expect(store.entry(mediaID: 101, type: .anime)?.progress == 5)
        #expect(store.entry(mediaID: 101, type: .anime)?.score == 8)
        #expect(store.entry(mediaID: 101, type: .anime)?.updatedAt == 30)
    }

    @Test("A newer applied mutation supersedes an older unavailable overlay")
    func newerMutationSupersedesPendingOverlay() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let original = makeEntry(
            entryID: 1,
            mediaID: 101,
            status: .current,
            progress: 1,
            score: 0,
            updatedAt: 10
        )

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: session,
            entries: [original]
        )

        let olderMutation = store.beginMutation(
            mediaID: 101,
            type: .anime,
            sessionID: session.id
        )
        #expect(store.reconcile(
            makeUserEntry(
                entryID: 2,
                status: .planning,
                progress: 0,
                score: 0,
                updatedAt: nil
            ),
            mutation: olderMutation,
            media: original.media
        ) == .unavailable)

        let newerMutation = store.beginMutation(
            mediaID: 101,
            type: .anime,
            sessionID: session.id
        )
        #expect(store.reconcile(
            makeUserEntry(
                entryID: 2,
                status: .completed,
                progress: 10,
                score: 8,
                updatedAt: 40
            ),
            mutation: newerMutation,
            media: original.media
        ) == .applied)

        let refreshedEntry = makeEntry(
            entryID: 2,
            mediaID: 101,
            status: .completed,
            progress: 10,
            score: 8,
            updatedAt: 40
        )
        let refresh = Task { await store.load(.anime, session: session, force: true) }
        let request = await client.nextRequest()
        await client.succeed(request, with: [refreshedEntry])
        await refresh.value

        #expect(store.entry(mediaID: 101, type: .anime)?.id == 2)
        #expect(store.entry(mediaID: 101, type: .anime)?.status == .completed)
        #expect(store.entry(mediaID: 101, type: .anime)?.progress == 10)
        #expect(store.entry(mediaID: 101, type: .anime)?.score == 8)
        #expect(store.entry(mediaID: 101, type: .anime)?.updatedAt == 40)
    }

    @Test("A mutation completed during the first load overlays its stale response")
    func mutationDuringInitialLoadIsApplied() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let staleEntry = makeEntry(
            entryID: 1,
            mediaID: 101,
            status: .current,
            progress: 4,
            updatedAt: 10
        )

        let load = Task { await store.load(.anime, session: session) }
        let request = await client.nextRequest()
        let mutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)

        #expect(store.reconcile(
            makeUserEntry(entryID: 1, status: .current, progress: 5, score: 0, updatedAt: 20),
            mutation: mutation
        ) == .unavailable)
        await client.succeed(request, with: [staleEntry])
        await load.value

        #expect(store.entry(mediaID: 101, type: .anime)?.progress == 5)
        #expect(store.entry(mediaID: 101, type: .anime)?.updatedAt == 20)
    }

    @Test("A deletion completed during the first load removes its stale entry")
    func deletionDuringInitialLoadIsApplied() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let staleEntry = makeEntry(entryID: 1, mediaID: 101)

        let load = Task { await store.load(.anime, session: session) }
        let request = await client.nextRequest()
        let mutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)

        #expect(store.reconcileDeletion(entryID: 1, mutation: mutation) == .unavailable)
        await client.succeed(request, with: [staleEntry])
        await load.value

        #expect(store.state(for: .anime).phase == .loaded)
        #expect(store.entries(for: .anime).isEmpty)
    }

    @Test("An older session mutation cannot alter the adopted session")
    func staleSessionMutationIsRejected() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let oldSession = makeSession(username: "old-user", revision: 1)
        let currentSession = makeSession(username: "current-user", revision: 2)

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: oldSession,
            entries: [makeEntry(entryID: 1, mediaID: 101)]
        )
        let oldUpdate = store.beginMutation(mediaID: 101, type: .anime, sessionID: oldSession.id)
        let oldDeletion = store.beginMutation(mediaID: 202, type: .anime, sessionID: oldSession.id)
        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: currentSession,
            entries: [makeEntry(entryID: 2, mediaID: 202, status: .planning, updatedAt: 10)]
        )

        #expect(store.reconcile(
            makeUserEntry(entryID: 1, status: .completed, progress: 10, score: 9, updatedAt: 30),
            mutation: oldUpdate,
            media: makeMedia(mediaID: 101)
        ) == .rejected)
        #expect(store.reconcileDeletion(entryID: 2, mutation: oldDeletion) == .rejected)
        #expect(store.entries(for: .anime).map(\.media.id) == [202])
        #expect(store.status(mediaID: 202, type: .anime) == .planning)
    }

    @Test("An older equal-timestamp response cannot replace a newer response")
    func equalTimestampStaleResponseIsRejected() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: session,
            entries: [makeEntry(entryID: 1, mediaID: 101, progress: 4, updatedAt: 10)]
        )
        let olderMutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)
        let newerMutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)

        #expect(store.reconcile(
            makeUserEntry(entryID: 1, status: .current, progress: 6, score: 0, updatedAt: 20),
            mutation: newerMutation
        ) == .applied)
        let staleResult = store.reconcile(
            makeUserEntry(entryID: 1, status: .current, progress: 5, score: 0, updatedAt: 20),
            mutation: olderMutation
        )

        #expect(staleResult == .rejected)
        #expect(!staleResult.shouldApplyLocally)
        #expect(store.entry(mediaID: 101, type: .anime)?.progress == 6)
        #expect(store.entry(mediaID: 101, type: .anime)?.updatedAt == 20)
    }

    @Test("A refresh started before a mutation cannot overwrite its result")
    func mutationInvalidatesOlderRefresh() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let original = makeEntry(entryID: 1, mediaID: 101, progress: 4, updatedAt: 10)

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [original])

        let refresh = Task { await store.load(.anime, session: session, force: true) }
        let refreshRequest = await client.nextRequest()
        #expect(store.state(for: .anime).phase == .loading)

        let mutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)
        #expect(store.reconcile(
            makeUserEntry(entryID: 1, status: .current, progress: 5, score: 0, updatedAt: 20),
            mutation: mutation
        ) == .applied)
        #expect(store.state(for: .anime).phase == .loaded)

        await client.succeed(refreshRequest, with: [original])
        await refresh.value

        #expect(store.entry(mediaID: 101, type: .anime)?.progress == 5)
        #expect(store.entry(mediaID: 101, type: .anime)?.updatedAt == 20)
    }

    @Test("A card mutation can restore an entry removed by an earlier refresh")
    func cardMutationRestoresEntryRemovedByRefresh() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let original = makeEntry(entryID: 1, mediaID: 101, progress: 4, updatedAt: 10)

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [original])
        let mutation = store.beginMutation(mediaID: 101, type: .anime, sessionID: session.id)
        let refresh = Task { await store.load(.anime, session: session, force: true) }
        let refreshRequest = await client.nextRequest()
        await client.succeed(refreshRequest, with: [])
        await refresh.value

        #expect(store.entry(mediaID: 101, type: .anime) == nil)
        #expect(store.reconcile(
            makeUserEntry(entryID: 1, status: .current, progress: 5, score: 0, updatedAt: 20),
            mutation: mutation,
            media: original.media
        ) == .applied)
        #expect(store.entry(mediaID: 101, type: .anime)?.progress == 5)
        #expect(store.entry(mediaID: 101, type: .anime)?.media.id == original.media.id)
    }

    @Test("Concurrent consumers share one request")
    func coalescesConcurrentLoads() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        let firstLoad = Task { await store.load(.anime, session: session) }
        let request = await client.nextRequest()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        var startedIterator = started.makeAsyncIterator()
        let secondLoad = Task { @MainActor in
            startedContinuation.yield()
            await store.load(.anime, session: session)
        }
        _ = await startedIterator.next()

        #expect(await client.requestCount() == 1)
        await client.succeed(request, with: [makeEntry(entryID: 1, mediaID: 101)])
        await firstLoad.value
        await secondLoad.value
        #expect(store.state(for: .anime).phase == .loaded)
    }

    @Test("Anime and manga load independently")
    func loadsTypesIndependently() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        let animeLoad = Task { await store.load(.anime, session: session) }
        let animeRequest = await client.nextRequest()
        let mangaLoad = Task { await store.load(.manga, session: session) }
        let mangaRequest = await client.nextRequest()

        #expect(Set([animeRequest.type, mangaRequest.type]) == Set([.anime, .manga]))
        await client.succeed(animeRequest, with: [makeEntry(entryID: 1, mediaID: 101)])
        await client.succeed(mangaRequest, with: [makeEntry(entryID: 2, mediaID: 202)])
        await animeLoad.value
        await mangaLoad.value

        #expect(store.state(for: .anime).phase == .loaded)
        #expect(store.state(for: .manga).phase == .loaded)
        #expect(await client.requestCount() == 2)
    }

    @Test("Loaded state skips a non-forced reload")
    func skipsNonForcedReload() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: session,
            entries: [makeEntry(entryID: 1, mediaID: 101)]
        )
        await store.load(.anime, session: session)

        #expect(await client.requestCount() == 1)
    }

    @Test("Forced refresh retains data then replaces it atomically")
    func forcedRefresh() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let original = makeEntry(entryID: 1, mediaID: 101, status: .current)
        let replacement = makeEntry(entryID: 2, mediaID: 202, status: .planning)

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [original])

        let refresh = Task { await store.load(.anime, session: session, force: true) }
        let request = await client.nextRequest()
        #expect(store.state(for: .anime).phase == .loading)
        #expect(store.entries(for: .anime).map(\.media.id) == [101])

        await client.succeed(request, with: [replacement])
        await refresh.value
        #expect(store.entries(for: .anime).map(\.media.id) == [202])
        #expect(store.status(mediaID: 202, type: .anime) == .planning)
    }

    @Test("First-load failure is distinct from loaded empty")
    func firstLoadFailure() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        let load = Task { await store.load(.anime, session: session) }
        let request = await client.nextRequest()
        await client.fail(request, with: .offline)
        await load.value

        #expect(store.entries(for: .anime).isEmpty)
        #expect(store.state(for: .anime).phase == .failed(message: StubError.offline.localizedDescription))

        await completeLoad(store: store, client: client, type: .manga, session: session, entries: [])
        #expect(store.state(for: .manga).phase == .loaded)
        #expect(store.state(for: .manga).hasUsableData)
        #expect(store.entries(for: .manga).isEmpty)
    }

    @Test("Failed refresh preserves a successful empty snapshot")
    func emptyRefreshFailurePreservesSnapshot() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [])
        let refresh = Task { await store.load(.anime, session: session, force: true) }
        let request = await client.nextRequest()

        #expect(store.state(for: .anime).phase == .loading)
        #expect(store.state(for: .anime).hasUsableData)
        await client.fail(request, with: .offline)
        await refresh.value

        #expect(store.entries(for: .anime).isEmpty)
        #expect(store.state(for: .anime).hasUsableData)
        #expect(store.state(for: .anime).phase == .failed(message: StubError.offline.localizedDescription))
    }

    @Test("Refresh failure preserves prior entries")
    func refreshFailurePreservesData() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()
        let original = makeEntry(entryID: 1, mediaID: 101)

        await completeLoad(store: store, client: client, type: .anime, session: session, entries: [original])
        let refresh = Task { await store.load(.anime, session: session, force: true) }
        let request = await client.nextRequest()
        await client.fail(request, with: .offline)
        await refresh.value

        #expect(store.entries(for: .anime).map(\.media.id) == [101])
        #expect(store.state(for: .anime).hasUsableData)
        #expect(store.state(for: .anime).phase == .failed(message: StubError.offline.localizedDescription))
    }

    @Test("A new session clears state and rejects the old response")
    func sessionChangeRejectsStaleResponse() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let oldSession = makeSession(revision: 1)
        let newSession = makeSession(revision: 2)

        await completeLoad(
            store: store,
            client: client,
            type: .manga,
            session: oldSession,
            entries: [makeEntry(entryID: 1, mediaID: 101)]
        )
        #expect(store.state(for: .manga).snapshotSessionID == oldSession.id)

        let oldLoad = Task { await store.load(.anime, session: oldSession, force: true) }
        let oldRequest = await client.nextRequest()
        let newLoad = Task { await store.load(.manga, session: newSession) }
        let newRequest = await client.nextRequest()

        #expect(store.state(for: .anime).phase == .idle)
        #expect(store.state(for: .manga).phase == .loading)
        #expect(store.state(for: .manga).snapshotSessionID == nil)
        #expect(store.entries(for: .manga).isEmpty)

        await client.succeed(newRequest, with: [makeEntry(entryID: 2, mediaID: 202)])
        await client.succeed(oldRequest, with: [makeEntry(entryID: 3, mediaID: 303)])
        await newLoad.value
        await oldLoad.value

        #expect(store.state(for: .anime).phase == .idle)
        #expect(store.entries(for: .anime).isEmpty)
        #expect(store.entries(for: .manga).map(\.media.id) == [202])
        #expect(store.state(for: .manga).snapshotSessionID == newSession.id)
    }

    @Test("Session replacement cancels the old request without accepting its late completion", .timeLimit(.minutes(1)))
    func sessionReplacementCancelsOldRequest() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let oldSession = makeSession(username: "old-user", revision: 1)
        let newSession = makeSession(username: "new-user", revision: 2)

        let oldLoad = Task { await store.load(.anime, session: oldSession) }
        let oldRequest = await client.nextRequest()
        let newLoad = Task { await store.load(.manga, session: newSession) }
        let newRequest = await client.nextRequest()

        await oldLoad.value
        await client.succeed(oldRequest, with: [makeEntry(entryID: 1, mediaID: 101)])
        await client.fail(oldRequest, with: .offline)
        await client.succeed(newRequest, with: [makeEntry(entryID: 2, mediaID: 202)])
        await newLoad.value

        #expect(store.state(for: .anime).phase == .idle)
        #expect(store.entries(for: .anime).isEmpty)
        #expect(store.state(for: .manga).phase == .loaded)
        #expect(store.entries(for: .manga).map(\.media.id) == [202])
        #expect(store.state(for: .manga).snapshotSessionID == newSession.id)
    }

    @Test("A late older-session load cannot replace the current session")
    func staleSessionInvocationIsRejected() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let oldSession = makeSession(username: "old-user", revision: 1)
        let currentSession = makeSession(username: "current-user", revision: 2)

        let currentLoad = Task { await store.load(.anime, session: currentSession) }
        let currentRequest = await client.nextRequest()
        await store.load(.anime, session: oldSession, force: true)

        #expect(await client.requestCount() == 1)
        #expect(store.state(for: .anime).phase == .loading)
        await client.succeed(
            currentRequest,
            with: [makeEntry(entryID: 1, mediaID: 202)]
        )
        await currentLoad.value

        #expect(store.entries(for: .anime).map(\.media.id) == [202])
        #expect(store.state(for: .anime).phase == .loaded)
    }

    @Test("Lookups are scoped by media type")
    func typeScopedLookup() async {
        let client = ControlledMediaLibraryClient()
        let store = MediaLibraryStore(client: client)
        let session = makeSession()

        await completeLoad(
            store: store,
            client: client,
            type: .anime,
            session: session,
            entries: [makeEntry(entryID: 1, mediaID: 42, status: .current)]
        )
        await completeLoad(
            store: store,
            client: client,
            type: .manga,
            session: session,
            entries: [makeEntry(entryID: 2, mediaID: 42, status: .completed)]
        )

        #expect(store.status(mediaID: 42, type: .anime) == .current)
        #expect(store.status(mediaID: 42, type: .manga) == .completed)
    }

    private func completeLoad(
        store: MediaLibraryStore,
        client: ControlledMediaLibraryClient,
        type: MediaType,
        session: MediaLibrarySession,
        entries: [MediaListEntry]
    ) async {
        let load = Task { await store.load(type, session: session) }
        let request = await client.nextRequest()
        #expect(request.type == type)
        #expect(request.username == session.id.username)
        await client.succeed(request, with: entries)
        await load.value
    }

    private func makeSession(
        username: String = "tester",
        revision: UInt64 = 1,
        accessToken: String? = "token"
    ) -> MediaLibrarySession {
        MediaLibrarySession(
            id: MediaLibrarySession.ID(username: username, revision: revision),
            accessToken: accessToken
        )
    }

    private func makeEntry(
        entryID: Int,
        mediaID: Int,
        status: MediaListStatus = .current,
        progress: Int = 0,
        score: Double = 0,
        updatedAt: Int? = nil,
        episodes: Int? = nil,
        mediaStatus: String? = nil,
        nextAiringEpisode: NextAiringEpisode? = nil
    ) -> MediaListEntry {
        MediaListEntry(
            id: entryID,
            status: status,
            progress: progress,
            score: score,
            updatedAt: updatedAt ?? entryID,
            media: makeMedia(
                mediaID: mediaID,
                episodes: episodes,
                status: mediaStatus,
                nextAiringEpisode: nextAiringEpisode
            )
        )
    }

    private func makeUserEntry(
        entryID: Int,
        status: MediaListStatus,
        progress: Int,
        score: Double,
        updatedAt: Int?
    ) -> UserMediaEntry {
        UserMediaEntry(
            id: entryID,
            status: status,
            score: score,
            progress: progress,
            updatedAt: updatedAt
        )
    }

    private func makeMedia(
        mediaID: Int,
        episodes: Int? = nil,
        status: String? = nil,
        nextAiringEpisode: NextAiringEpisode? = nil
    ) -> Media {
        Media(
            id: mediaID,
            isAdult: false,
            title: MediaTitle(romaji: "Title \(mediaID)", english: nil, native: nil),
            coverImage: nil,
            episodes: episodes,
            chapters: nil,
            format: nil,
            status: status,
            averageScore: nil,
            nextAiringEpisode: nextAiringEpisode
        )
    }
}

private enum StubError: LocalizedError, Sendable {
    case offline

    var errorDescription: String? { "Offline" }
}

private actor ControlledMediaLibraryClient: MediaLibraryClient {
    struct Request: Sendable {
        let id: Int
        let type: MediaType
        let username: String
        let accessToken: String?
    }

    private var nextID = 0
    private var count = 0
    private var queuedRequests: [Request] = []
    private var requestWaiters: [CheckedContinuation<Request, Never>] = []
    private var completions: [Int: CheckedContinuation<[MediaListEntry], Error>] = [:]
    private var canceledRequestIDs: Set<Int> = []

    func fetchMediaList(
        type: MediaType,
        username: String,
        accessToken: String?
    ) async throws -> [MediaListEntry] {
        let request = Request(
            id: nextID,
            type: type,
            username: username,
            accessToken: accessToken
        )
        nextID += 1
        count += 1

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if canceledRequestIDs.remove(request.id) != nil {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                completions[request.id] = continuation
                if requestWaiters.isEmpty {
                    queuedRequests.append(request)
                } else {
                    requestWaiters.removeFirst().resume(returning: request)
                }
            }
        } onCancel: {
            Task { await self.cancel(requestID: request.id) }
        }
    }

    func nextRequest() async -> Request {
        if !queuedRequests.isEmpty {
            return queuedRequests.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func requestCount() -> Int {
        count
    }

    func succeed(_ request: Request, with entries: [MediaListEntry]) {
        guard let continuation = completions.removeValue(forKey: request.id) else { return }
        continuation.resume(returning: entries)
    }

    func fail(_ request: Request, with error: StubError) {
        guard let continuation = completions.removeValue(forKey: request.id) else { return }
        continuation.resume(throwing: error)
    }

    private func cancel(requestID: Int) {
        guard let continuation = completions.removeValue(forKey: requestID) else {
            canceledRequestIDs.insert(requestID)
            return
        }
        continuation.resume(throwing: CancellationError())
    }
}
