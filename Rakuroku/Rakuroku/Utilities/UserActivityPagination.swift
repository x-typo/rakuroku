nonisolated enum UserActivityPagination {
    static func fetch(
        limit: Int,
        maxPages: Int = 20,
        loadPage: @Sendable (Int, Int) async throws -> ActivityPage
    ) async throws -> [ListActivity] {
        guard limit > 0, maxPages > 0 else { return [] }

        var activities: [ListActivity] = []
        var seenIDs = Set<Int>()
        var page = 1
        var hasNextPage = true

        while activities.count < limit && hasNextPage && page <= maxPages {
            try Task.checkCancellation()
            let result = try await loadPage(page, limit)
            try Task.checkCancellation()

            for activity in result.activities
                where activity.media.isAdult != true && seenIDs.insert(activity.id).inserted {
                activities.append(activity)
                if activities.count == limit { break }
            }

            hasNextPage = result.pageInfo.hasNextPage
            page += 1
        }

        return activities
    }
}
