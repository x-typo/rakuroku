import Foundation
import Observation

@Observable
@MainActor
final class SeasonListStore {
    typealias Page = (media: [SeasonalMedia], hasNextPage: Bool)

    private(set) var media: [SeasonalMedia] = []
    private(set) var loading = true
    private(set) var error: String?
    private(set) var hasNextPage = false
    private(set) var loadingMore = false
    private(set) var currentPage = 1
    private(set) var loadMoreError: String?
    private var refreshing = false
    private var generation: UInt64 = 0

    var canLoadMore: Bool {
        !refreshing && !loadingMore && hasNextPage
    }

    func refresh(loader: (Int) async throws -> Page) async {
        generation &+= 1
        let requestGeneration = generation
        refreshing = true
        loadingMore = false
        if media.isEmpty { loading = true }
        error = nil
        loadMoreError = nil
        defer {
            if requestGeneration == generation {
                refreshing = false
                loading = false
            }
        }
        do {
            let result = try await loader(1)
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            media = result.media
            hasNextPage = result.hasNextPage
            currentPage = 1
        } catch where error.isCancellation {
        } catch {
            guard requestGeneration == generation else { return }
            self.error = error.localizedDescription
        }
    }

    func loadMore(loader: (Int) async throws -> Page) async {
        guard canLoadMore else { return }
        let requestGeneration = generation
        let nextPage = currentPage + 1
        loadingMore = true
        loadMoreError = nil
        defer {
            if requestGeneration == generation { loadingMore = false }
        }
        do {
            let result = try await loader(nextPage)
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            let existingIDs = Set(media.map(\.id))
            media.append(contentsOf: result.media.filter { !existingIDs.contains($0.id) })
            hasNextPage = result.hasNextPage
            currentPage = nextPage
        } catch where error.isCancellation {
        } catch {
            guard requestGeneration == generation else { return }
            loadMoreError = error.localizedDescription
        }
    }
}
