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

enum MediaLibraryPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

struct MediaLibraryTypeState: Sendable {
    fileprivate var orderedIDs: [Int] = []
    fileprivate var entriesByID: [Int: MediaListEntry] = [:]
    fileprivate(set) var phase: MediaLibraryPhase = .idle
    fileprivate(set) var hasSnapshot = false

    var entries: [MediaListEntry] {
        orderedIDs.compactMap { entriesByID[$0] }
    }

    var hasUsableData: Bool {
        hasSnapshot
    }
}

@MainActor @Observable
final class MediaLibraryStore {
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

    private static var emptyStates: [MediaType: MediaLibraryTypeState] {
        [.anime: MediaLibraryTypeState(), .manga: MediaLibraryTypeState()]
    }
}
