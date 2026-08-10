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

        let oldLoad = Task { await store.load(.anime, session: oldSession, force: true) }
        let oldRequest = await client.nextRequest()
        let newLoad = Task { await store.load(.manga, session: newSession) }
        let newRequest = await client.nextRequest()

        #expect(store.state(for: .anime).phase == .idle)
        #expect(store.state(for: .manga).phase == .loading)
        #expect(store.entries(for: .manga).isEmpty)

        await client.succeed(newRequest, with: [makeEntry(entryID: 2, mediaID: 202)])
        await client.succeed(oldRequest, with: [makeEntry(entryID: 3, mediaID: 303)])
        await newLoad.value
        await oldLoad.value

        #expect(store.state(for: .anime).phase == .idle)
        #expect(store.entries(for: .anime).isEmpty)
        #expect(store.entries(for: .manga).map(\.media.id) == [202])
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
        status: MediaListStatus = .current
    ) -> MediaListEntry {
        MediaListEntry(
            id: entryID,
            status: status,
            progress: 0,
            score: 0,
            updatedAt: entryID,
            media: Media(
                id: mediaID,
                isAdult: false,
                title: MediaTitle(romaji: "Title \(mediaID)", english: nil, native: nil),
                coverImage: nil,
                episodes: nil,
                chapters: nil,
                format: nil,
                status: nil,
                averageScore: nil,
                nextAiringEpisode: nil
            )
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

        return try await withCheckedThrowingContinuation { continuation in
            completions[request.id] = continuation
            if requestWaiters.isEmpty {
                queuedRequests.append(request)
            } else {
                requestWaiters.removeFirst().resume(returning: request)
            }
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
        guard let continuation = completions.removeValue(forKey: request.id) else {
            fatalError("Missing request continuation")
        }
        continuation.resume(returning: entries)
    }

    func fail(_ request: Request, with error: StubError) {
        guard let continuation = completions.removeValue(forKey: request.id) else {
            fatalError("Missing request continuation")
        }
        continuation.resume(throwing: error)
    }
}
