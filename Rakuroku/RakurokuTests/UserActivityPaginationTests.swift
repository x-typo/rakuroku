import Testing
@testable import Rakuroku

@Suite("User activity pagination")
@MainActor
struct UserActivityPaginationTests {
    @Test("Backfills filtered activities from later pages")
    func backfillsLaterPages() async throws {
        let loader = PageLoader(pages: [
            1: page([activity(id: 1, isAdult: true)], number: 1, hasNextPage: true),
            2: page([
                activity(id: 2, isAdult: false),
                activity(id: 3, isAdult: nil),
            ], number: 2, hasNextPage: false),
        ])

        let result = try await UserActivityPagination.fetch(limit: 2) { page, pageSize in
            await loader.load(page: page, pageSize: pageSize)
        }
        let requests = await loader.requests

        #expect(result.map(\.id) == [2, 3])
        #expect(requests == [Request(page: 1, pageSize: 2), Request(page: 2, pageSize: 2)])
    }

    @Test("Stops once the requested safe count is reached")
    func stopsAtLimit() async throws {
        let loader = PageLoader(pages: [
            1: page([
                activity(id: 1, isAdult: false),
                activity(id: 2, isAdult: false),
                activity(id: 3, isAdult: false),
            ], number: 1, hasNextPage: true),
        ])

        let result = try await UserActivityPagination.fetch(limit: 2) { page, pageSize in
            await loader.load(page: page, pageSize: pageSize)
        }
        let requests = await loader.requests

        #expect(result.map(\.id) == [1, 2])
        #expect(requests == [Request(page: 1, pageSize: 2)])
    }

    @Test("Stops at the page cap and removes duplicate activity IDs")
    func honorsPageCapAndDeduplicates() async throws {
        let loader = PageLoader(pages: [
            1: page([activity(id: 1, isAdult: false)], number: 1, hasNextPage: true),
            2: page([
                activity(id: 1, isAdult: false),
                activity(id: 2, isAdult: true),
            ], number: 2, hasNextPage: true),
        ])

        let result = try await UserActivityPagination.fetch(limit: 3, maxPages: 2) { page, pageSize in
            await loader.load(page: page, pageSize: pageSize)
        }
        let requests = await loader.requests

        #expect(result.map(\.id) == [1])
        #expect(requests.map(\.page) == [1, 2])
    }

    @Test("Skips page loading for nonpositive limits")
    func rejectsNonpositiveLimit() async throws {
        let loader = PageLoader(pages: [:])

        let result = try await UserActivityPagination.fetch(limit: 0) { page, pageSize in
            await loader.load(page: page, pageSize: pageSize)
        }
        let requests = await loader.requests

        #expect(result.isEmpty)
        #expect(requests.isEmpty)
    }

    private func page(
        _ activities: [ListActivity],
        number: Int,
        hasNextPage: Bool
    ) -> ActivityPage {
        ActivityPage(
            pageInfo: PageInfo(hasNextPage: hasNextPage, currentPage: number),
            activities: activities
        )
    }

    private func activity(id: Int, isAdult: Bool?) -> ListActivity {
        ListActivity(
            id: id,
            status: nil,
            progress: nil,
            createdAt: id,
            media: Media(
                id: id,
                isAdult: isAdult,
                title: MediaTitle(romaji: "Activity \(id)", english: nil, native: nil),
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

private struct Request: Equatable, Sendable {
    let page: Int
    let pageSize: Int
}

private actor PageLoader {
    let pages: [Int: ActivityPage]
    private(set) var requests: [Request] = []

    init(pages: [Int: ActivityPage]) {
        self.pages = pages
    }

    func load(page: Int, pageSize: Int) -> ActivityPage {
        requests.append(Request(page: page, pageSize: pageSize))
        return pages[page] ?? ActivityPage(
            pageInfo: PageInfo(hasNextPage: false, currentPage: page),
            activities: []
        )
    }
}
