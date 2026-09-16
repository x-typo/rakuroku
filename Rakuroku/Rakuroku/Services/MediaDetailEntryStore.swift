import Observation

@Observable
@MainActor
final class MediaDetailEntryStore {
    struct Request {
        let generation: UInt64
        let sessionID: MediaLibrarySession.ID
    }

    struct Snapshot: Equatable {
        let id: Int?
        let status: MediaListStatus?
        let score: Double?
        let progress: Int?
        let updatedAt: Int?

        init(_ entry: UserMediaEntry?) {
            id = entry?.id
            status = entry?.status
            score = entry?.score
            progress = entry?.progress
            updatedAt = entry?.updatedAt
        }
    }

    private(set) var entry: UserMediaEntry?
    private var generation: UInt64 = 0

    func beginRead(sessionID: MediaLibrarySession.ID) -> Request {
        invalidateReads()
        return Request(generation: generation, sessionID: sessionID)
    }

    func isCurrent(_ request: Request, sessionID: MediaLibrarySession.ID) -> Bool {
        request.generation == generation && request.sessionID == sessionID
    }

    func invalidateReads() {
        generation &+= 1
    }

    func replace(with entry: UserMediaEntry?) {
        invalidateReads()
        self.entry = entry
    }

    @discardableResult
    func applyCanonical(_ entry: UserMediaEntry?) -> Bool {
        if let canonicalDate = entry?.updatedAt, let detailDate = self.entry?.updatedAt,
           canonicalDate < detailDate { return false }
        // Even an equal value retires reads begun before the canonical change.
        replace(with: entry)
        return true
    }

    func load(
        request: Request,
        currentSessionID: () -> MediaLibrarySession.ID,
        loader: () async throws -> UserMediaEntry?
    ) async throws -> Bool {
        let result = try await loader()
        try Task.checkCancellation()
        guard isCurrent(request, sessionID: currentSessionID()) else { return false }
        entry = result
        return true
    }
}
