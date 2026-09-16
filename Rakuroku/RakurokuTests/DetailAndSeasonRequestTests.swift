import Testing
@testable import Rakuroku

@Suite("Detail and season request ordering")
@MainActor
struct DetailAndSeasonRequestTests {
    private let session = MediaLibrarySession.ID(username: "viewer", revision: 1)

    @Test("A delayed refresh cannot undo a successful progress mutation")
    func mutationRetiresDetailRead() async throws {
        let store = MediaDetailEntryStore()
        store.replace(with: entry(progress: 5))
        let request = store.beginRead(sessionID: session)
        let loader = DeferredResult<UserMediaEntry?>()
        let refresh = Task {
            try await store.load(request: request, currentSessionID: { session }) {
                try await loader.load()
            }
        }
        await loader.waitUntilRequested()

        store.invalidateReads()
        store.replace(with: entry(progress: 6))
        loader.complete(.success(entry(progress: 5)))

        #expect(try await refresh.value == false)
        #expect(store.entry?.progress == 6)
    }

    @Test("The latest detail read wins even when an earlier read finishes last")
    func newerDetailReadWins() async throws {
        let store = MediaDetailEntryStore()
        let firstRequest = store.beginRead(sessionID: session)
        let loader = DeferredResult<UserMediaEntry?>()
        let first = Task {
            try await store.load(request: firstRequest, currentSessionID: { session }) {
                try await loader.load()
            }
        }
        await loader.waitUntilRequested()
        let secondRequest = store.beginRead(sessionID: session)
        let accepted = try await store.load(request: secondRequest, currentSessionID: { session }) {
            entry(progress: 7)
        }
        loader.complete(.success(entry(progress: 5)))

        #expect(accepted)
        #expect(try await first.value == false)
        #expect(store.entry?.progress == 7)
    }

    @Test("A changed account rejects a read before its replacement task begins")
    func changedSessionRejectsDetailRead() async throws {
        let store = MediaDetailEntryStore()
        var currentSession = session
        let request = store.beginRead(sessionID: session)
        let loader = DeferredResult<UserMediaEntry?>()
        let read = Task {
            try await store.load(request: request, currentSessionID: { currentSession }) {
                try await loader.load()
            }
        }
        await loader.waitUntilRequested()
        currentSession = MediaLibrarySession.ID(username: "other", revision: 2)
        loader.complete(.success(entry(progress: 5)))

        #expect(try await read.value == false)
        #expect(store.entry == nil)
    }

    @Test("A canonical deletion retires both initial and refresh detail reads", arguments: [false, true])
    func canonicalDeletionWins(hasLoadedEntry: Bool) async throws {
        let store = MediaDetailEntryStore()
        if hasLoadedEntry { store.replace(with: entry(progress: 5)) }
        let request = store.beginRead(sessionID: session)
        let loader = DeferredResult<UserMediaEntry?>()
        let read = Task {
            try await store.load(request: request, currentSessionID: { session }) {
                try await loader.load()
            }
        }
        await loader.waitUntilRequested()
        #expect(store.applyCanonical(nil))
        loader.complete(.success(entry(progress: 5)))

        #expect(try await read.value == false)
        #expect(store.entry == nil)
    }

    @Test("An older canonical snapshot cannot roll back a fresher detail entry")
    func olderCanonicalSnapshotIsIgnored() {
        let store = MediaDetailEntryStore()
        store.replace(with: entry(progress: 6))
        #expect(!store.applyCanonical(entry(progress: 5)))
        #expect(store.entry?.progress == 6)
    }

    @Test("Refresh discards an old page three in either completion order", arguments: [true, false])
    func seasonRefreshRetiresPagination(refreshFinishesFirst: Bool) async {
        let store = SeasonListStore()
        await store.refresh { _ in page(1) }
        await store.loadMore { _ in page(2) }

        let oldPage = DeferredResult<SeasonListStore.Page>()
        let pagination = Task {
            await store.loadMore { requestedPage in
                #expect(requestedPage == 3)
                return try await oldPage.load()
            }
        }
        await oldPage.waitUntilRequested()

        let firstPage = DeferredResult<SeasonListStore.Page>()
        let refresh = Task {
            await store.refresh { requestedPage in
                #expect(requestedPage == 1)
                return try await firstPage.load()
            }
        }
        await firstPage.waitUntilRequested()
        await store.loadMore { _ in
            Issue.record("Pagination ran during refresh")
            return page(99)
        }

        if refreshFinishesFirst {
            firstPage.complete(.success(page(1)))
            await refresh.value
            oldPage.complete(.success(page(3, hasNextPage: false)))
            await pagination.value
        } else {
            oldPage.complete(.success(page(3, hasNextPage: false)))
            await pagination.value
            firstPage.complete(.success(page(1)))
            await refresh.value
        }

        #expect(store.media.map(\.id) == [1])
        #expect(store.currentPage == 1)
        #expect(store.hasNextPage)
        #expect(!store.loadingMore)
        await store.loadMore { requestedPage in
            #expect(requestedPage == 2)
            return page(2)
        }
        #expect(store.media.map(\.id) == [1, 2])
    }

    @Test("An obsolete page failure cannot attach an error to refreshed results")
    func stalePaginationFailureIsIgnored() async {
        let store = SeasonListStore()
        await store.refresh { _ in page(1) }
        let loader = DeferredResult<SeasonListStore.Page>()
        let pagination = Task {
            await store.loadMore { _ in try await loader.load() }
        }
        await loader.waitUntilRequested()
        await store.refresh { _ in page(10) }
        loader.complete(.failure(TestError.failed))
        await pagination.value

        #expect(store.media.map(\.id) == [10])
        #expect(store.loadMoreError == nil)
        #expect(store.currentPage == 1)
    }

    private func entry(progress: Int) -> UserMediaEntry {
        UserMediaEntry(id: 1, status: .current, score: 8.5, progress: progress, updatedAt: progress)
    }

    private func page(_ id: Int, hasNextPage: Bool = true) -> SeasonListStore.Page {
        ([SeasonalMedia(
            id: id, isAdult: false, type: .anime,
            title: MediaTitle(romaji: "Title \(id)", english: nil, native: nil),
            coverImage: nil, episodes: nil, chapters: nil, format: nil, status: nil,
            averageScore: nil, popularity: nil, genres: nil, studios: nil, nextAiringEpisode: nil
        )], hasNextPage)
    }
}

private enum TestError: Error { case failed }

@MainActor
private final class DeferredResult<Value: Sendable> {
    private var completion: CheckedContinuation<Value, Error>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    func load() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            startedWaiters.forEach { $0.resume() }
            startedWaiters.removeAll()
        }
    }

    func waitUntilRequested() async {
        guard completion == nil else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func complete(_ result: Result<Value, Error>) {
        guard let completion else {
            Issue.record("No pending request to complete")
            return
        }
        self.completion = nil
        completion.resume(with: result)
    }
}
