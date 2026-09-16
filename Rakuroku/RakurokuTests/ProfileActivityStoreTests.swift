import Foundation
import Testing
@testable import Rakuroku

@Suite("Profile activity loading")
@MainActor
struct ProfileActivityStoreTests {
    @Test("A failed refresh preserves history and exposes rate limiting")
    func preservesHistoryOnFailure() async {
        let store = ProfileActivityStore()
        await store.load(isCurrent: { true }) { [activity(1)] }
        await store.load(isCurrent: { true }) { throw AniListError.rateLimited }

        #expect(store.activities.map(\.id) == [1])
        #expect(store.hasLoaded)
        #expect(!store.isLoading)
        #expect(store.error == AniListError.rateLimited.localizedDescription)

        await store.load(isCurrent: { true }) { [] }
        #expect(store.activities.isEmpty)
        #expect(store.hasLoaded)
        #expect(store.error == nil)
    }

    @Test("First-load failure is not a successful empty activity feed")
    func firstLoadFailure() async {
        let store = ProfileActivityStore()
        await store.load(isCurrent: { true }) { throw AniListError.apiError(500) }
        #expect(!store.hasLoaded)
        #expect(store.error != nil)
        #expect(!store.isLoading)
    }

    @Test("A cancelled response does not replace history")
    func cancellation() async {
        let store = ProfileActivityStore()
        await store.load(isCurrent: { true }) { [activity(1)] }
        let loader = SuspendedActivityLoader()
        let task = Task { await store.load(isCurrent: { true }) { try await loader.load() } }
        await loader.waitUntilStarted()
        #expect(store.isLoading)
        task.cancel()
        loader.finish(with: [activity(2)])
        await task.value
        #expect(store.activities.map(\.id) == [1])
        #expect(store.error == nil)
        #expect(!store.isLoading)
    }

    @Test("An older response cannot replace a newer refresh")
    func staleResponse() async {
        let store = ProfileActivityStore()
        let loader = SuspendedActivityLoader()
        let task = Task { await store.load(isCurrent: { true }) { try await loader.load() } }
        await loader.waitUntilStarted()
        await store.load(isCurrent: { true }) { [activity(2)] }
        loader.finish(with: [activity(1)])
        await task.value
        #expect(store.activities.map(\.id) == [2])
        #expect(!store.isLoading)
    }

    @Test("Session reset retires a pending response and clears history")
    func sessionReset() async {
        let store = ProfileActivityStore()
        await store.load(isCurrent: { true }) { [activity(1)] }
        let loader = SuspendedActivityLoader()
        let task = Task { await store.load(isCurrent: { true }) { try await loader.load() } }
        await loader.waitUntilStarted()
        store.reset()
        loader.finish(with: [activity(2)])
        await task.value
        #expect(store.activities.isEmpty)
        #expect(!store.hasLoaded)
        #expect(!store.isLoading)
        #expect(store.error == nil)
    }

    @Test("A changed owner is rejected even before the view resets")
    func ownerChanges() async {
        let store = ProfileActivityStore()
        let loader = SuspendedActivityLoader()
        var current = true
        let task = Task { await store.load(isCurrent: { current }) { try await loader.load() } }
        await loader.waitUntilStarted()
        current = false
        loader.finish(with: [activity(1)])
        await task.value
        #expect(store.activities.isEmpty)
        #expect(!store.hasLoaded)
    }

    private func activity(_ id: Int) -> ListActivity {
        ListActivity(
            id: id, status: "watched episode", progress: "1", createdAt: id,
            media: Media(
                id: id, isAdult: false,
                title: MediaTitle(romaji: "Fixture", english: nil, native: nil),
                coverImage: nil, episodes: 12, chapters: nil, format: "TV",
                status: "RELEASING", averageScore: nil, nextAiringEpisode: nil
            )
        )
    }
}

@MainActor
private final class SuspendedActivityLoader {
    private var continuation: CheckedContinuation<[ListActivity], Error>?
    private var startedWaiter: CheckedContinuation<Void, Never>?

    func load() async throws -> [ListActivity] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            startedWaiter?.resume()
            startedWaiter = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func finish(with activities: [ListActivity]) {
        continuation?.resume(returning: activities)
        continuation = nil
    }
}
