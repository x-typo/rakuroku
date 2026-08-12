import Foundation
import Observation

nonisolated protocol MediaLibraryClient: Sendable {
    func fetchMediaList(
        type: MediaType,
        username: String,
        accessToken: String?
    ) async throws -> [MediaListEntry]
}

extension AniListClient: MediaLibraryClient {}

struct MediaLibrarySession: Sendable {
    struct ID: Hashable, Sendable {
        let username: String
        let revision: UInt64
    }

    let id: ID
    let accessToken: String?
}

enum MediaLibraryMutationAuthorization {
    static func accessToken(
        displayedSessionID: MediaLibrarySession.ID?,
        currentSession: MediaLibrarySession
    ) -> String? {
        guard displayedSessionID == currentSession.id else { return nil }
        return currentSession.accessToken
    }
}

enum MediaLibraryPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

struct MediaLibraryMutation: Hashable, Sendable {
    fileprivate let sequence: UInt64
    fileprivate let mediaID: Int
    fileprivate let type: MediaType
    fileprivate let sessionID: MediaLibrarySession.ID
}

enum MediaLibraryReconciliationResult: Equatable, Sendable {
    case applied
    case unavailable
    case rejected

    var shouldApplyLocally: Bool {
        self != .rejected
    }
}

struct MediaLibraryTypeState: Sendable {
    fileprivate var orderedIDs: [Int] = []
    fileprivate var entriesByID: [Int: MediaListEntry] = [:]
    fileprivate(set) var phase: MediaLibraryPhase = .idle
    fileprivate(set) var hasSnapshot = false
    fileprivate(set) var snapshotSessionID: MediaLibrarySession.ID?

    var entries: [MediaListEntry] {
        orderedIDs.compactMap { entriesByID[$0] }
    }

    var hasUsableData: Bool {
        hasSnapshot
    }
}

@MainActor @Observable
final class MediaLibraryStore {
    private struct MutationKey: Hashable {
        let mediaID: Int
        let type: MediaType
        let sessionID: MediaLibrarySession.ID
    }

    private enum PendingMutationOperation {
        case update(UserMediaEntry, media: Media?)
        case deletion(entryID: Int)
    }

    private struct PendingMutation {
        let mutation: MediaLibraryMutation
        let operation: PendingMutationOperation
    }

    private struct InFlightRequest {
        let id: UUID
        let sessionID: MediaLibrarySession.ID
        let generation: UInt64
        let task: Task<[MediaListEntry], Error>
    }

    private(set) var states: [MediaType: MediaLibraryTypeState]

    @ObservationIgnored
    private let client: any MediaLibraryClient
    @ObservationIgnored
    private var sessionID: MediaLibrarySession.ID?
    @ObservationIgnored
    private var generation: UInt64 = 0
    @ObservationIgnored
    private var inFlight: [MediaType: InFlightRequest] = [:]
    @ObservationIgnored
    private var nextMutationSequence: UInt64 = 0
    @ObservationIgnored
    private var latestReconciledMutation: [MutationKey: UInt64] = [:]
    @ObservationIgnored
    private var pendingMutations: [MutationKey: PendingMutation] = [:]

    init(client: any MediaLibraryClient = AniListClient.shared) {
        states = Self.emptyStates
        self.client = client
    }

    func state(for type: MediaType) -> MediaLibraryTypeState {
        states[type] ?? MediaLibraryTypeState()
    }

    func entries(for type: MediaType) -> [MediaListEntry] {
        state(for: type).entries
    }

    func entry(mediaID: Int, type: MediaType) -> MediaListEntry? {
        state(for: type).entriesByID[mediaID]
    }

    func status(mediaID: Int, type: MediaType) -> MediaListStatus? {
        entry(mediaID: mediaID, type: type)?.status
    }

    func beginMutation(
        mediaID: Int,
        type: MediaType,
        sessionID: MediaLibrarySession.ID
    ) -> MediaLibraryMutation {
        nextMutationSequence &+= 1
        return MediaLibraryMutation(
            sequence: nextMutationSequence,
            mediaID: mediaID,
            type: type,
            sessionID: sessionID
        )
    }

    @discardableResult
    func reconcile(
        _ updatedEntry: UserMediaEntry,
        mutation: MediaLibraryMutation,
        media: Media? = nil
    ) -> MediaLibraryReconciliationResult {
        if let result = prepareReconciliation(for: mutation) {
            if result == .unavailable {
                queuePendingMutation(
                    mutation,
                    operation: .update(updatedEntry, media: media)
                )
            }
            return result
        }

        var typeState = state(for: mutation.type)
        guard typeState.hasSnapshot else {
            queuePendingMutation(
                mutation,
                operation: .update(updatedEntry, media: media)
            )
            return .unavailable
        }

        let result = apply(
            updatedEntry,
            mutation: mutation,
            media: media,
            to: &typeState
        )
        if result == .unavailable {
            queuePendingMutation(
                mutation,
                operation: .update(updatedEntry, media: media)
            )
        }
        guard result == .applied else { return result }

        invalidateInFlightRequest(for: mutation.type)
        if typeState.phase == .loading {
            typeState.phase = .loaded
        }
        states[mutation.type] = typeState
        return result
    }

    @discardableResult
    func reconcileDeletion(
        entryID: Int,
        mutation: MediaLibraryMutation
    ) -> MediaLibraryReconciliationResult {
        if let result = prepareReconciliation(for: mutation) {
            if result == .unavailable {
                queuePendingMutation(
                    mutation,
                    operation: .deletion(entryID: entryID)
                )
            }
            return result
        }

        var typeState = state(for: mutation.type)
        guard typeState.hasSnapshot else {
            queuePendingMutation(
                mutation,
                operation: .deletion(entryID: entryID)
            )
            return .unavailable
        }

        let result = applyDeletion(
            entryID: entryID,
            mutation: mutation,
            to: &typeState
        )
        guard result == .applied else { return result }

        invalidateInFlightRequest(for: mutation.type)
        if typeState.phase == .loading {
            typeState.phase = .loaded
        }
        states[mutation.type] = typeState
        return result
    }

    func load(
        _ type: MediaType,
        session: MediaLibrarySession,
        force: Bool = false
    ) async {
        guard adoptSessionIfNeeded(session.id) else { return }

        if let request = inFlight[type] {
            await finish(request, for: type)
            return
        }

        guard force || state(for: type).phase != .loaded else { return }

        var typeState = state(for: type)
        typeState.phase = .loading
        states[type] = typeState

        let request = InFlightRequest(
            id: UUID(),
            sessionID: session.id,
            generation: generation,
            task: Task {
                try await client.fetchMediaList(
                    type: type,
                    username: session.id.username,
                    accessToken: session.accessToken
                )
            }
        )
        inFlight[type] = request

        await finish(request, for: type)
    }

    func reset() {
        generation &+= 1
        cancelInFlightRequests()
        states = Self.emptyStates
    }

    private func adoptSessionIfNeeded(_ newSessionID: MediaLibrarySession.ID) -> Bool {
        if let sessionID {
            if sessionID == newSessionID { return true }
            guard newSessionID.revision > sessionID.revision else { return false }
        }

        generation &+= 1
        sessionID = newSessionID
        cancelInFlightRequests()
        latestReconciledMutation = latestReconciledMutation.filter {
            $0.key.sessionID == newSessionID
        }
        pendingMutations = pendingMutations.filter {
            $0.key.sessionID == newSessionID
        }
        states = Self.emptyStates
        return true
    }

    private func finish(_ request: InFlightRequest, for type: MediaType) async {
        let result = await request.task.result

        guard request.generation == generation,
              request.sessionID == sessionID,
              inFlight[type]?.id == request.id else {
            return
        }

        inFlight[type] = nil
        var typeState = state(for: type)

        switch result {
        case .success(let entries):
            var orderedIDs: [Int] = []
            var entriesByID: [Int: MediaListEntry] = [:]
            for entry in entries {
                if entriesByID[entry.media.id] == nil {
                    orderedIDs.append(entry.media.id)
                }
                entriesByID[entry.media.id] = entry
            }
            typeState.orderedIDs = orderedIDs
            typeState.entriesByID = entriesByID
            typeState.hasSnapshot = true
            typeState.snapshotSessionID = request.sessionID
            applyPendingMutations(
                for: type,
                sessionID: request.sessionID,
                to: &typeState
            )
            typeState.phase = .loaded
        case .failure(let error) where error.isCancellation:
            typeState.phase = typeState.hasSnapshot ? .loaded : .idle
        case .failure(let error):
            typeState.phase = .failed(message: error.localizedDescription)
        }

        states[type] = typeState
    }

    private func cancelInFlightRequests() {
        let requests = Array(inFlight.values)
        inFlight.removeAll()
        for request in requests {
            request.task.cancel()
        }
    }

    private func invalidateInFlightRequest(for type: MediaType) {
        guard let request = inFlight.removeValue(forKey: type) else { return }
        request.task.cancel()
    }

    private func apply(
        _ updatedEntry: UserMediaEntry,
        mutation: MediaLibraryMutation,
        media: Media?,
        to typeState: inout MediaLibraryTypeState
    ) -> MediaLibraryReconciliationResult {
        let existingEntry = typeState.entriesByID[mutation.mediaID]
        let resolvedMedia: Media
        let resolvedUpdatedAt: Int?
        if let existingEntry {
            if existingEntry.id == updatedEntry.id {
                if let updatedAt = updatedEntry.updatedAt {
                    if let existingUpdatedAt = existingEntry.updatedAt,
                       updatedAt < existingUpdatedAt {
                        return .rejected
                    }
                    resolvedUpdatedAt = updatedAt
                } else {
                    resolvedUpdatedAt = existingEntry.updatedAt
                }
                resolvedMedia = existingEntry.media
            } else {
                guard let media,
                      media.id == mutation.mediaID,
                      media.isAdult != true,
                      let updatedAt = updatedEntry.updatedAt else {
                    return .unavailable
                }
                if let existingUpdatedAt = existingEntry.updatedAt,
                   updatedAt < existingUpdatedAt {
                    return .rejected
                }
                resolvedMedia = media
                resolvedUpdatedAt = updatedAt
            }
        } else {
            guard let media,
                  media.id == mutation.mediaID,
                  media.isAdult != true else {
                return .unavailable
            }
            resolvedMedia = media
            resolvedUpdatedAt = updatedEntry.updatedAt
        }

        if existingEntry == nil {
            typeState.orderedIDs.append(mutation.mediaID)
        }
        typeState.entriesByID[mutation.mediaID] = MediaListEntry(
            id: updatedEntry.id,
            status: updatedEntry.status,
            progress: updatedEntry.progress,
            score: updatedEntry.score,
            updatedAt: resolvedUpdatedAt,
            media: resolvedMedia
        )
        return .applied
    }

    private func applyDeletion(
        entryID: Int,
        mutation: MediaLibraryMutation,
        to typeState: inout MediaLibraryTypeState
    ) -> MediaLibraryReconciliationResult {
        if let existingEntry = typeState.entriesByID[mutation.mediaID], existingEntry.id != entryID {
            return .rejected
        }

        typeState.entriesByID.removeValue(forKey: mutation.mediaID)
        typeState.orderedIDs.removeAll { $0 == mutation.mediaID }
        return .applied
    }

    private func queuePendingMutation(
        _ mutation: MediaLibraryMutation,
        operation: PendingMutationOperation
    ) {
        pendingMutations[mutationKey(for: mutation)] = PendingMutation(
            mutation: mutation,
            operation: operation
        )
    }

    private func applyPendingMutations(
        for type: MediaType,
        sessionID: MediaLibrarySession.ID,
        to typeState: inout MediaLibraryTypeState
    ) {
        let matchingMutations = pendingMutations
            .filter { key, _ in key.type == type && key.sessionID == sessionID }
            .sorted { $0.value.mutation.sequence < $1.value.mutation.sequence }

        for (key, pendingMutation) in matchingMutations {
            if let latestSequence = latestReconciledMutation[key],
               pendingMutation.mutation.sequence < latestSequence {
                pendingMutations.removeValue(forKey: key)
                continue
            }

            let result: MediaLibraryReconciliationResult
            switch pendingMutation.operation {
            case .update(let entry, let media):
                result = apply(
                    entry,
                    mutation: pendingMutation.mutation,
                    media: media,
                    to: &typeState
                )
            case .deletion(let entryID):
                result = applyDeletion(
                    entryID: entryID,
                    mutation: pendingMutation.mutation,
                    to: &typeState
                )
            }
            if result != .unavailable {
                pendingMutations.removeValue(forKey: key)
            }
        }
    }

    private func prepareReconciliation(
        for mutation: MediaLibraryMutation
    ) -> MediaLibraryReconciliationResult? {
        let key = mutationKey(for: mutation)
        if let latestSequence = latestReconciledMutation[key], mutation.sequence < latestSequence {
            return .rejected
        }

        if let pendingMutation = pendingMutations[key],
           pendingMutation.mutation.sequence <= mutation.sequence {
            pendingMutations.removeValue(forKey: key)
        }

        guard let sessionID else {
            latestReconciledMutation[key] = mutation.sequence
            return .unavailable
        }
        guard mutation.sessionID == sessionID else {
            if mutation.sessionID.revision > sessionID.revision {
                latestReconciledMutation[key] = mutation.sequence
                return .unavailable
            }
            return .rejected
        }

        latestReconciledMutation[key] = mutation.sequence
        return nil
    }

    private func mutationKey(for mutation: MediaLibraryMutation) -> MutationKey {
        MutationKey(
            mediaID: mutation.mediaID,
            type: mutation.type,
            sessionID: mutation.sessionID
        )
    }

    private static var emptyStates: [MediaType: MediaLibraryTypeState] {
        [.anime: MediaLibraryTypeState(), .manga: MediaLibraryTypeState()]
    }
}
