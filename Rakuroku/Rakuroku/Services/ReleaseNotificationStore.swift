import Foundation
import Observation
import OSLog
import UserNotifications

enum ReleaseNotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    nonisolated var canSchedule: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        }
    }
}

struct ReleaseNotificationCandidate: Hashable, Sendable {
    let mediaID: Int
    let title: String
    let episode: Int
    let airingAt: Int

    nonisolated func request(ownerUsername: String) -> ReleaseNotificationRequest {
        ReleaseNotificationRequest(
            identifier: Self.identifier(
                ownerUsername: ownerUsername,
                mediaID: mediaID,
                airingAt: airingAt
            ),
            ownerUsername: ownerUsername,
            mediaID: mediaID,
            title: title,
            episode: episode,
            airingAt: airingAt
        )
    }

    nonisolated static func identifier(
        ownerUsername: String,
        mediaID: Int,
        airingAt: Int
    ) -> String {
        let ownerComponent = ownerIdentifierComponent(ownerUsername)
        return "\(ReleaseNotificationRequest.identifierPrefix)\(ownerComponent).\(mediaID).\(airingAt)"
    }

    nonisolated static func identifier(
        _ identifier: String,
        belongsToOwner ownerUsername: String
    ) -> Bool {
        let normalizedOwner = normalizedOwnerUsername(ownerUsername)
        guard !normalizedOwner.isEmpty else { return false }

        let suffix = identifier.dropFirst(ReleaseNotificationRequest.identifierPrefix.count)
        let components = suffix.split(separator: ".", omittingEmptySubsequences: false)
        guard identifier.hasPrefix(ReleaseNotificationRequest.identifierPrefix),
              components.count == 3,
              components[0] == ownerIdentifierComponent(ownerUsername),
              let mediaID = Int(components[1]),
              mediaID > 0,
              let airingAt = Int(components[2]),
              airingAt > 0 else {
            return false
        }

        return identifier == Self.identifier(
            ownerUsername: ownerUsername,
            mediaID: mediaID,
            airingAt: airingAt
        )
    }

    nonisolated static func normalizedOwnerUsername(_ username: String) -> String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private nonisolated static func ownerIdentifierComponent(_ username: String) -> String {
        normalizedOwnerUsername(username)
            .utf8
            .map { byte in
                let hex = String(byte, radix: 16)
                return hex.count == 1 ? "0\(hex)" : hex
            }
            .joined()
    }
}

enum ReleaseNotificationPlan {
    nonisolated static func candidates(
        entries: [MediaListEntry],
        hasUsableData: Bool,
        snapshotSessionID: MediaLibrarySession.ID?,
        activeSessionID: MediaLibrarySession.ID,
        nowEpoch: Int
    ) -> [ReleaseNotificationCandidate]? {
        guard MediaLibrarySnapshotValidation.isCurrent(
            hasUsableData: hasUsableData,
            snapshotSessionID: snapshotSessionID,
            activeSessionID: activeSessionID
        ) else {
            return nil
        }

        var candidatesByMediaID: [Int: ReleaseNotificationCandidate] = [:]
        for entry in entries {
            guard entry.status == .current,
                  entry.media.status == "RELEASING",
                  let nextAiringEpisode = entry.media.nextAiringEpisode,
                  nextAiringEpisode.episode > 0,
                  nextAiringEpisode.airingAt > nowEpoch else {
                continue
            }

            let title = entry.media.title.english
                ?? entry.media.title.romaji
                ?? entry.media.title.native
                ?? "Unknown"
            let candidate = ReleaseNotificationCandidate(
                mediaID: entry.media.id,
                title: title,
                episode: nextAiringEpisode.episode,
                airingAt: nextAiringEpisode.airingAt
            )

            if let existing = candidatesByMediaID[candidate.mediaID] {
                if candidate.airingAt < existing.airingAt
                    || (candidate.airingAt == existing.airingAt && candidate.episode < existing.episode) {
                    candidatesByMediaID[candidate.mediaID] = candidate
                }
            } else {
                candidatesByMediaID[candidate.mediaID] = candidate
            }
        }

        return candidatesByMediaID.values.sorted {
            if $0.airingAt == $1.airingAt {
                return $0.mediaID < $1.mediaID
            }
            return $0.airingAt < $1.airingAt
        }
    }
}

struct ReleaseNotificationRequest: Equatable, Sendable {
    nonisolated static let identifierPrefix = "rakuroku.release."
    nonisolated static let kind = "episodeRelease"

    let identifier: String
    let ownerUsername: String
    let mediaID: Int
    let title: String
    let episode: Int
    let airingAt: Int

    nonisolated var notificationBody: String {
        "Episode \(episode) is airing now."
    }

    nonisolated func notificationRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = notificationBody
        content.sound = .default
        content.threadIdentifier = "rakuroku.release"
        content.userInfo = [
            "kind": Self.kind,
            "ownerUsername": ownerUsername,
            "mediaID": mediaID,
            "episode": episode,
            "airingAt": airingAt,
        ]

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: ReleaseNotificationTrigger.dateComponents(airingAt: airingAt),
                repeats: false
            )
        )
    }
}

struct PendingReleaseNotificationRequest: Equatable, Sendable {
    let identifier: String
    let request: ReleaseNotificationRequest?
}

struct ReleaseNotificationTap: Hashable, Sendable {
    let mediaID: Int
    let ownerUsername: String
}

enum ReleaseNotificationTapValidation {
    nonisolated static func parse(
        identifier: String,
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> ReleaseNotificationTap? {
        guard identifier.hasPrefix(ReleaseNotificationRequest.identifierPrefix),
              actionIdentifier == UNNotificationDefaultActionIdentifier,
              userInfo["kind"] as? String == ReleaseNotificationRequest.kind,
              let ownerUsername = userInfo["ownerUsername"] as? String,
              !ReleaseNotificationCandidate.normalizedOwnerUsername(ownerUsername).isEmpty,
              let mediaID = integer(from: userInfo["mediaID"]),
              mediaID > 0,
              let airingAt = integer(from: userInfo["airingAt"]),
              identifier == ReleaseNotificationCandidate.identifier(
                ownerUsername: ownerUsername,
                mediaID: mediaID,
                airingAt: airingAt
              ) else {
            return nil
        }
        return ReleaseNotificationTap(
            mediaID: mediaID,
            ownerUsername: ownerUsername
        )
    }

    nonisolated static func belongsToOwner(
        _ tap: ReleaseNotificationTap,
        username: String
    ) -> Bool {
        ReleaseNotificationCandidate.normalizedOwnerUsername(tap.ownerUsername)
            == ReleaseNotificationCandidate.normalizedOwnerUsername(username)
    }

    private nonisolated static func integer(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        return (value as? NSNumber)?.intValue
    }
}

enum ReleaseNotificationTrigger {
    nonisolated static func dateComponents(airingAt: Int) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: TimeInterval(airingAt))
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }

    nonisolated static func matches(
        _ trigger: UNNotificationTrigger?,
        airingAt: Int
    ) -> Bool {
        guard let trigger = trigger as? UNCalendarNotificationTrigger,
              !trigger.repeats else {
            return false
        }
        return trigger.dateComponents == dateComponents(airingAt: airingAt)
    }
}

enum ReleaseNotificationSchedulingPolicy {
    nonisolated static let maximumPendingRequestCount = 64

    nonisolated static func requests(
        candidates: [ReleaseNotificationCandidate],
        ownerUsername: String,
        nonManagedPendingCount: Int
    ) -> [ReleaseNotificationRequest] {
        let availableCapacity = max(
            0,
            maximumPendingRequestCount - max(0, nonManagedPendingCount)
        )
        var requestsByIdentifier: [String: ReleaseNotificationRequest] = [:]

        for candidate in candidates.sorted(by: candidatePrecedes) {
            let request = candidate.request(ownerUsername: ownerUsername)
            if let _ = requestsByIdentifier[request.identifier] { continue }
            requestsByIdentifier[request.identifier] = request
        }

        return Array(requestsByIdentifier.values)
            .sorted(by: requestPrecedes)
            .prefix(availableCapacity)
            .map { $0 }
    }

    private nonisolated static func candidatePrecedes(
        _ lhs: ReleaseNotificationCandidate,
        _ rhs: ReleaseNotificationCandidate
    ) -> Bool {
        if lhs.airingAt != rhs.airingAt { return lhs.airingAt < rhs.airingAt }
        if lhs.mediaID != rhs.mediaID { return lhs.mediaID < rhs.mediaID }
        if lhs.episode != rhs.episode { return lhs.episode < rhs.episode }
        return lhs.title < rhs.title
    }

    private nonisolated static func requestPrecedes(
        _ lhs: ReleaseNotificationRequest,
        _ rhs: ReleaseNotificationRequest
    ) -> Bool {
        if lhs.airingAt != rhs.airingAt { return lhs.airingAt < rhs.airingAt }
        if lhs.mediaID != rhs.mediaID { return lhs.mediaID < rhs.mediaID }
        return lhs.identifier < rhs.identifier
    }
}

@MainActor
protocol ReleaseNotificationCenterClient: AnyObject {
    func authorizationStatus() async -> ReleaseNotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [PendingReleaseNotificationRequest]
    func deliveredRequestIdentifiers() async -> [String]
    func add(_ request: ReleaseNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
    func removeDeliveredRequests(withIdentifiers identifiers: [String])
}

@MainActor
final class UserNotificationCenterClient: ReleaseNotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> ReleaseNotificationAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: Self.status(from: settings.authorizationStatus))
            }
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func pendingRequests() async -> [PendingReleaseNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(Self.pendingRequest))
            }
        }
    }

    func add(_ request: ReleaseNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request.notificationRequest()) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func deliveredRequestIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map(\.request.identifier))
            }
        }
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private nonisolated static func status(
        from status: UNAuthorizationStatus
    ) -> ReleaseNotificationAuthorizationStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .provisional:
            .provisional
        case .ephemeral:
            .ephemeral
        @unknown default:
            .denied
        }
    }

    nonisolated static func pendingRequest(
        _ request: UNNotificationRequest
    ) -> PendingReleaseNotificationRequest {
        guard request.identifier.hasPrefix(ReleaseNotificationRequest.identifierPrefix) else {
            return PendingReleaseNotificationRequest(identifier: request.identifier, request: nil)
        }

        let userInfo = request.content.userInfo
        guard userInfo["kind"] as? String == ReleaseNotificationRequest.kind,
              let ownerUsername = userInfo["ownerUsername"] as? String,
              let mediaID = integer(from: userInfo["mediaID"]),
              let episode = integer(from: userInfo["episode"]),
              let airingAt = integer(from: userInfo["airingAt"]),
              request.identifier == ReleaseNotificationCandidate.identifier(
                ownerUsername: ownerUsername,
                mediaID: mediaID,
                airingAt: airingAt
              ),
              request.content.body
                == "Episode \(episode) is airing now.",
              request.content.threadIdentifier == "rakuroku.release",
              request.content.sound == .default,
              ReleaseNotificationTrigger.matches(request.trigger, airingAt: airingAt) else {
            return PendingReleaseNotificationRequest(identifier: request.identifier, request: nil)
        }

        return PendingReleaseNotificationRequest(
            identifier: request.identifier,
            request: ReleaseNotificationRequest(
                identifier: request.identifier,
                ownerUsername: ownerUsername,
                mediaID: mediaID,
                title: request.content.title,
                episode: episode,
                airingAt: airingAt
            )
        )
    }

    private nonisolated static func integer(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        return (value as? NSNumber)?.intValue
    }
}

@MainActor
protocol ReleaseNotificationPreferenceStoring: AnyObject {
    var isEnabled: Bool { get set }
}

@MainActor
final class UserDefaultsReleaseNotificationPreferences: ReleaseNotificationPreferenceStoring {
    private let defaults: UserDefaults
    private let key = "release_notifications_enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

@MainActor @Observable
final class ReleaseNotificationStore {
    private(set) var isEnabled: Bool
    private(set) var authorizationStatus: ReleaseNotificationAuthorizationStatus = .notDetermined
    private(set) var schedulingError: String?
    private(set) var scheduledCount = 0
    private(set) var isUpdatingPreference = false

    @ObservationIgnored
    private let center: any ReleaseNotificationCenterClient
    @ObservationIgnored
    private let preferences: any ReleaseNotificationPreferenceStoring
    @ObservationIgnored
    private var activeSessionID: MediaLibrarySession.ID?
    @ObservationIgnored
    private var sessionNeedsCleanup = false
    @ObservationIgnored
    private var sessionNeedsOwnershipSanitation = false
    @ObservationIgnored
    private var synchronizationGeneration: UInt64 = 0
    @ObservationIgnored
    private var synchronizationTask: Task<Void, Never>?
    @ObservationIgnored
    private var preferenceGeneration: UInt64 = 0

    convenience init() {
        self.init(
            center: UserNotificationCenterClient(),
            preferences: UserDefaultsReleaseNotificationPreferences()
        )
    }

    init(
        center: any ReleaseNotificationCenterClient,
        preferences: any ReleaseNotificationPreferenceStoring
    ) {
        self.center = center
        self.preferences = preferences
        isEnabled = preferences.isEnabled
    }

    func setEnabled(_ enabled: Bool) async {
        preferenceGeneration &+= 1
        let operation = preferenceGeneration
        isUpdatingPreference = true
        defer {
            if operation == preferenceGeneration {
                isUpdatingPreference = false
            }
        }

        guard enabled else {
            preferences.isEnabled = false
            isEnabled = false
            schedulingError = nil
            await enqueueSynchronizationOperation { [weak self] generation in
                guard let self else { return }
                _ = await self.removeAllManagedRequests(generation: generation)
            }
            return
        }

        var status = await center.authorizationStatus()
        guard operation == preferenceGeneration, !Task.isCancelled else { return }
        authorizationStatus = status

        if status == .notDetermined {
            do {
                let granted = try await center.requestAuthorization()
                guard operation == preferenceGeneration, !Task.isCancelled else { return }
                status = await center.authorizationStatus()
                guard operation == preferenceGeneration, !Task.isCancelled else { return }
                if granted && status == .notDetermined {
                    status = .authorized
                }
                authorizationStatus = status
            } catch {
                guard operation == preferenceGeneration, !Task.isCancelled else { return }
                preferences.isEnabled = false
                isEnabled = false
                schedulingError = error.localizedDescription
                return
            }
        }

        guard status.canSchedule else {
            preferences.isEnabled = false
            isEnabled = false
            schedulingError = nil
            await enqueueSynchronizationOperation { [weak self] generation in
                guard let self else { return }
                _ = await self.removeAllManagedRequests(generation: generation)
            }
            return
        }

        preferences.isEnabled = true
        isEnabled = true
        schedulingError = nil
    }

    func refreshAuthorizationStatus() async {
        let status = await center.authorizationStatus()
        guard !Task.isCancelled else { return }
        authorizationStatus = status

        if isEnabled && !status.canSchedule {
            schedulingError = nil
            await enqueueSynchronizationOperation { [weak self] generation in
                guard let self else { return }
                _ = await self.removeAllManagedRequests(generation: generation)
            }
        }
    }

    func synchronize(
        candidates: [ReleaseNotificationCandidate]?,
        sessionID: MediaLibrarySession.ID
    ) async {
        await enqueueSynchronizationOperation { [weak self] generation in
            guard let self else { return }
            await self.performSynchronization(
                candidates: candidates,
                sessionID: sessionID,
                generation: generation
            )
        }
    }

    func cancelPendingReleaseNotifications() async {
        await enqueueSynchronizationOperation { [weak self] generation in
            guard let self else { return }
            _ = await self.removeAllManagedRequests(generation: generation)
        }
    }

    private func performSynchronization(
        candidates: [ReleaseNotificationCandidate]?,
        sessionID: MediaLibrarySession.ID,
        generation: UInt64
    ) async {

        if let establishedSessionID = activeSessionID,
           establishedSessionID != sessionID {
            activeSessionID = sessionID
            sessionNeedsCleanup = true
        } else if activeSessionID == nil {
            activeSessionID = sessionID
            sessionNeedsOwnershipSanitation = true
        }

        if sessionNeedsCleanup || !isEnabled {
            let removed = await removeAllManagedRequests(generation: generation)
            guard isCurrent(generation, sessionID: sessionID) else { return }
            if removed {
                sessionNeedsCleanup = false
                sessionNeedsOwnershipSanitation = false
            }
            guard isEnabled else { return }
        }

        if sessionNeedsOwnershipSanitation {
            let sanitized = await sanitizeManagedRequests(
                ownerUsername: sessionID.username,
                generation: generation
            )
            guard isCurrent(generation, sessionID: sessionID) else { return }
            if sanitized {
                sessionNeedsOwnershipSanitation = false
            }
        }

        guard let candidates else { return }

        let status = await center.authorizationStatus()
        guard isCurrent(generation, sessionID: sessionID) else { return }
        authorizationStatus = status
        guard status.canSchedule else {
            schedulingError = nil
            _ = await removeAllManagedRequests(generation: generation)
            return
        }

        let pendingRequests = await center.pendingRequests()
        guard isCurrent(generation, sessionID: sessionID) else { return }

        let managedPending = pendingRequests.filter {
            $0.identifier.hasPrefix(ReleaseNotificationRequest.identifierPrefix)
        }
        let desiredRequests = ReleaseNotificationSchedulingPolicy.requests(
            candidates: candidates,
            ownerUsername: sessionID.username,
            nonManagedPendingCount: pendingRequests.count - managedPending.count
        )
        let desiredByIdentifier = Dictionary(
            uniqueKeysWithValues: desiredRequests.map { ($0.identifier, $0) }
        )
        let staleIdentifiers = managedPending.compactMap { pendingRequest in
            guard let desiredRequest = desiredByIdentifier[pendingRequest.identifier],
                  pendingRequest.request == desiredRequest else {
                return pendingRequest.identifier
            }
            return nil
        }
        .sorted()
        center.removePendingRequests(withIdentifiers: staleIdentifiers)

        var existingByIdentifier: [String: ReleaseNotificationRequest] = [:]
        for pendingRequest in managedPending {
            if let request = pendingRequest.request {
                existingByIdentifier[pendingRequest.identifier] = request
            }
        }
        var firstError: String?

        for request in desiredRequests {
            guard isCurrent(generation, sessionID: sessionID) else { return }
            if existingByIdentifier[request.identifier] == request {
                continue
            }
            do {
                try await center.add(request)
            } catch is CancellationError {
                return
            } catch {
                if firstError == nil {
                    firstError = error.localizedDescription
                }
            }
        }

        guard isCurrent(generation, sessionID: sessionID) else { return }
        let reconciledPendingRequests = await center.pendingRequests()
        guard isCurrent(generation, sessionID: sessionID) else { return }
        var reconciledByIdentifier: [String: ReleaseNotificationRequest] = [:]
        for request in reconciledPendingRequests {
            if let parsedRequest = request.request {
                reconciledByIdentifier[request.identifier] = parsedRequest
            }
        }
        scheduledCount = desiredRequests.reduce(into: 0) { count, desiredRequest in
            if reconciledByIdentifier[desiredRequest.identifier] == desiredRequest {
                count += 1
            }
        }
        if firstError == nil, scheduledCount < desiredRequests.count {
            firstError = "Some release notifications could not be scheduled. Open Rakuroku to try again."
        }
        schedulingError = firstError
    }

    private func enqueueSynchronizationOperation(
        _ operation: @escaping @MainActor (UInt64) async -> Void
    ) async {
        synchronizationGeneration &+= 1
        let generation = synchronizationGeneration
        let predecessor = synchronizationTask
        predecessor?.cancel()

        let task = Task { @MainActor [weak self] in
            await predecessor?.value
            guard let self, self.isCurrent(generation) else { return }
            await operation(generation)
        }
        synchronizationTask = task
        await task.value

        if generation == synchronizationGeneration {
            synchronizationTask = nil
        }
    }

    private func removeAllManagedRequests(generation: UInt64) async -> Bool {
        let pendingRequests = await center.pendingRequests()
        guard isCurrent(generation) else { return false }
        let managedIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(ReleaseNotificationRequest.identifierPrefix) }
            .sorted()
        center.removePendingRequests(withIdentifiers: managedIdentifiers)

        let deliveredIdentifiers = await center.deliveredRequestIdentifiers()
        guard isCurrent(generation) else { return false }
        let managedDeliveredIdentifiers = deliveredIdentifiers
            .filter { $0.hasPrefix(ReleaseNotificationRequest.identifierPrefix) }
            .sorted()
        center.removeDeliveredRequests(withIdentifiers: managedDeliveredIdentifiers)
        scheduledCount = 0
        schedulingError = nil
        return true
    }

    private func sanitizeManagedRequests(
        ownerUsername: String,
        generation: UInt64
    ) async -> Bool {
        let normalizedOwner = ReleaseNotificationCandidate.normalizedOwnerUsername(ownerUsername)
        let pendingRequests = await center.pendingRequests()
        guard isCurrent(generation) else { return false }
        let mismatchedPendingIdentifiers: [String] = pendingRequests.compactMap {
            pendingRequest -> String? in
            guard pendingRequest.identifier.hasPrefix(ReleaseNotificationRequest.identifierPrefix)
            else { return nil }
            guard let request = pendingRequest.request,
                  !normalizedOwner.isEmpty,
                  ReleaseNotificationCandidate.normalizedOwnerUsername(request.ownerUsername)
                    == normalizedOwner else {
                return pendingRequest.identifier
            }
            return nil
        }
        .sorted()
        center.removePendingRequests(withIdentifiers: mismatchedPendingIdentifiers)

        let deliveredIdentifiers = await center.deliveredRequestIdentifiers()
        guard isCurrent(generation) else { return false }
        let mismatchedDeliveredIdentifiers = deliveredIdentifiers.filter { identifier in
            identifier.hasPrefix(ReleaseNotificationRequest.identifierPrefix)
                && !ReleaseNotificationCandidate.identifier(
                    identifier,
                    belongsToOwner: ownerUsername
                )
        }
        .sorted()
        center.removeDeliveredRequests(withIdentifiers: mismatchedDeliveredIdentifiers)
        return true
    }

    private func isCurrent(
        _ generation: UInt64,
        sessionID: MediaLibrarySession.ID? = nil
    ) -> Bool {
        guard generation == synchronizationGeneration, !Task.isCancelled else { return false }
        if let sessionID {
            return activeSessionID == sessionID
        }
        return true
    }

}

@MainActor @Observable
final class ReleaseNotificationRouter {
    struct Destination: Hashable {
        let id: UUID
        let mediaID: Int
        let ownerUsername: String
    }

    static let shared = ReleaseNotificationRouter()

    private(set) var pendingDestination: Destination?
    private var activeSceneIDs = Set<UUID>()

    init() {}

    func register(sceneID: UUID, isActive: Bool) {
        var updatedSceneIDs = activeSceneIDs
        if isActive {
            updatedSceneIDs.insert(sceneID)
        } else {
            updatedSceneIDs.remove(sceneID)
        }
        activeSceneIDs = updatedSceneIDs
        ReleaseNotificationRouteDiagnostics.sceneRegistrationChanged(
            isActive: isActive,
            activeSceneCount: activeSceneIDs.count
        )
    }

    func accept(mediaID: Int, ownerUsername: String) {
        guard mediaID > 0,
              !ReleaseNotificationCandidate.normalizedOwnerUsername(ownerUsername).isEmpty else {
            return
        }
        pendingDestination = Destination(
            id: UUID(),
            mediaID: mediaID,
            ownerUsername: ownerUsername
        )
        ReleaseNotificationRouteDiagnostics.destinationQueued(
            mediaID: mediaID,
            activeSceneCount: activeSceneIDs.count
        )
    }

    func pendingDestination(for sceneID: UUID) -> Destination? {
        guard activeSceneIDs.contains(sceneID) else { return nil }
        return pendingDestination
    }

    func takePendingDestination(for sceneID: UUID) -> Destination? {
        guard let destination = pendingDestination(for: sceneID) else { return nil }
        pendingDestination = nil
        return destination
    }
}

enum ReleaseNotificationRouteDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Rakuroku",
        category: "ReleaseNotifications"
    )

    nonisolated static func responseReceived(isManaged: Bool, isDefaultAction: Bool) {
        logger.notice(
            "Response received; managed: \(isManaged, privacy: .public), default action: \(isDefaultAction, privacy: .public)"
        )
    }

    nonisolated static func responseAccepted(mediaID: Int) {
        logger.notice("Response accepted for media ID \(mediaID, privacy: .private(mask: .hash))")
    }

    nonisolated static func responseRejected() {
        logger.notice("Response rejected during payload validation")
    }

    nonisolated static func destinationQueued(mediaID: Int, activeSceneCount: Int) {
        logger.notice(
            "Destination queued for media ID \(mediaID, privacy: .private(mask: .hash)); active scenes: \(activeSceneCount, privacy: .public)"
        )
    }

    nonisolated static func sceneRegistrationChanged(isActive: Bool, activeSceneCount: Int) {
        logger.debug(
            "Scene registration changed; active: \(isActive, privacy: .public), active scenes: \(activeSceneCount, privacy: .public)"
        )
    }

    nonisolated static func navigationDeferred(mediaID: Int) {
        logger.notice("Navigation deferred for media ID \(mediaID, privacy: .private(mask: .hash))")
    }

    nonisolated static func navigationRejected(mediaID: Int) {
        logger.notice("Navigation rejected for media ID \(mediaID, privacy: .private(mask: .hash))")
    }

    nonisolated static func navigationAccepted(mediaID: Int) {
        logger.notice("Navigation accepted for media ID \(mediaID, privacy: .private(mask: .hash))")
    }

    nonisolated static func navigationPresented(mediaID: Int, pathCount: Int) {
        logger.notice(
            "Navigation presented for media ID \(mediaID, privacy: .private(mask: .hash)); path count: \(pathCount, privacy: .public)"
        )
    }
}
