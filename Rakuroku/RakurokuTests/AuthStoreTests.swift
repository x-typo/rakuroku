import Testing
@testable import Rakuroku

@Suite("Auth store", .timeLimit(.minutes(1)))
@MainActor
struct AuthStoreTests {
    @Test("Changing a username normalizes and advances the session revision")
    func changedUsernameAdvancesRevision() {
        let persistence = InMemoryAuthPersistence(username: "current")
        let store = AuthStore(persistence: persistence, defaultUsername: "default")

        store.updateUsername("  next  ")

        #expect(store.mediaLibrarySession.id.username == "next")
        #expect(store.mediaLibrarySession.id.revision == 1)
        #expect(persistence.username == "next")
    }

    @Test("An unchanged normalized username preserves the session revision")
    func unchangedUsernamePreservesRevision() {
        let persistence = InMemoryAuthPersistence(username: "current")
        let store = AuthStore(persistence: persistence, defaultUsername: "default")

        store.updateUsername("  current  ")

        #expect(store.mediaLibrarySession.id.username == "current")
        #expect(store.mediaLibrarySession.id.revision == 0)
        #expect(persistence.username == "current")
    }

    @Test("A manual credential change advances the session revision while the same credential does not")
    func manualCredentialTransitionRevision() {
        let persistence = InMemoryAuthPersistence(accessToken: "credential-a")
        let store = AuthStore(persistence: persistence, defaultUsername: "default")

        #expect(store.setManualToken("credential-b"))
        #expect(store.mediaLibrarySession.id.revision == 1)

        #expect(store.setManualToken("credential-b"))
        #expect(store.mediaLibrarySession.id.revision == 1)
    }

    @Test("Logout advances the revision only when the identity changes")
    func logoutTransitionRevision() {
        let persistence = InMemoryAuthPersistence(accessToken: "credential", username: "alternate")
        let store = AuthStore(persistence: persistence, defaultUsername: "default")

        store.logout()

        #expect(store.mediaLibrarySession.id.username == "default")
        #expect(store.mediaLibrarySession.id.revision == 1)
        #expect(persistence.accessToken == nil)
        #expect(persistence.username == nil)

        store.logout()

        #expect(store.mediaLibrarySession.id.revision == 1)
    }

    @Test("Credential persistence failure preserves the session and reports an error")
    func credentialPersistenceFailure() {
        let persistence = InMemoryAuthPersistence(accessToken: "credential", shouldSaveAccessToken: false)
        let store = AuthStore(persistence: persistence, defaultUsername: "default")

        #expect(!store.setManualToken("replacement"))

        #expect(store.mediaLibrarySession.id.revision == 0)
        #expect(store.accessToken == "credential")
        #expect(store.authError == "Couldn't save token securely.")
    }

    @Test("Canonical library loads receive the AuthStore session identity and credential")
    func mediaLibraryReceivesAuthSession() async {
        let persistence = InMemoryAuthPersistence(
            accessToken: "credential-a",
            username: "viewer"
        )
        let authStore = AuthStore(persistence: persistence, defaultUsername: "default")
        let client = RecordingAuthSessionMediaLibraryClient()
        let mediaLibraryStore = MediaLibraryStore(client: client)

        await mediaLibraryStore.load(.anime, session: authStore.mediaLibrarySession)
        #expect(await client.requests == [
            .init(type: .anime, username: "viewer", accessToken: "credential-a"),
        ])

        #expect(authStore.setManualToken("credential-b"))
        await mediaLibraryStore.load(
            .anime,
            session: authStore.mediaLibrarySession,
            force: true
        )

        #expect(authStore.mediaLibrarySession.id.revision == 1)
        #expect(await client.requests == [
            .init(type: .anime, username: "viewer", accessToken: "credential-a"),
            .init(type: .anime, username: "viewer", accessToken: "credential-b"),
        ])
    }

    @Test("Resolved usernames and authentication failures apply only to the initiating session")
    func resolvedIdentityRequiresCurrentSession() {
        let persistence = InMemoryAuthPersistence(
            accessToken: "credential-a",
            username: "viewer-a"
        )
        let store = AuthStore(persistence: persistence, defaultUsername: "default")
        #expect(!store.isMediaLibraryIdentityResolved)
        let staleSession = store.mediaLibrarySession

        #expect(store.setManualToken("credential-b"))
        #expect(!store.isMediaLibraryIdentityResolved)
        #expect(!store.applyResolvedUsername("stale-viewer", for: staleSession))
        #expect(!store.logoutIfCurrent(staleSession, authError: "stale failure"))
        #expect(store.username == "viewer-a")
        #expect(store.accessToken == "credential-b")
        #expect(store.authError == nil)

        let currentSession = store.mediaLibrarySession
        #expect(store.applyResolvedUsername("viewer-b", for: currentSession))
        #expect(store.isMediaLibraryIdentityResolved)
        #expect(store.username == "viewer-b")
        #expect(store.mediaLibrarySession.id.revision == 2)
    }

    @Test("Reusing the same token after logout does not revive an earlier session response")
    func reusedCredentialStillRejectsStaleSession() {
        let persistence = InMemoryAuthPersistence(
            accessToken: "credential",
            username: "viewer"
        )
        let store = AuthStore(persistence: persistence, defaultUsername: "default")
        let staleSession = store.mediaLibrarySession

        store.logout()
        #expect(store.isMediaLibraryIdentityResolved)
        #expect(store.setManualToken("credential"))
        #expect(!store.isMediaLibraryIdentityResolved)

        #expect(store.accessToken == staleSession.accessToken)
        #expect(store.mediaLibrarySession.id != staleSession.id)
        #expect(!store.applyResolvedUsername("stale-viewer", for: staleSession))
        #expect(!store.logoutIfCurrent(staleSession))
        #expect(store.username == "default")
        #expect(store.accessToken == "credential")
    }

    @Test("A current authenticated Viewer failure logs out exactly that session")
    func currentViewerFailureLogsOut() {
        let persistence = InMemoryAuthPersistence(
            accessToken: "credential",
            username: "viewer"
        )
        let store = AuthStore(persistence: persistence, defaultUsername: "default")
        let session = store.mediaLibrarySession

        #expect(store.logoutIfCurrent(session, authError: "expired"))

        #expect(store.accessToken == nil)
        #expect(store.username == "default")
        #expect(store.mediaLibrarySession.id.revision == 1)
        #expect(store.authError == "expired")
        #expect(store.isMediaLibraryIdentityResolved)
    }

    @Test("Only the first resolver for a captured session can commit a changed username")
    func duplicateViewerResolutionCannotOverwriteWinner() {
        let persistence = InMemoryAuthPersistence(
            accessToken: "credential",
            username: "old"
        )
        let store = AuthStore(persistence: persistence, defaultUsername: "default")
        let sharedSession = store.mediaLibrarySession

        #expect(store.applyResolvedUsername("winner", for: sharedSession))
        #expect(!store.applyResolvedUsername("stale", for: sharedSession))

        #expect(store.username == "winner")
        #expect(store.mediaLibrarySession.id.revision == 1)
        #expect(store.isMediaLibraryIdentityResolved)
    }

    @Test("A transient Viewer failure can retry and resolve without changing tokens")
    func transientViewerFailureCanRetry() throws {
        let persistence = InMemoryAuthPersistence(
            accessToken: "credential",
            username: "old"
        )
        let store = AuthStore(persistence: persistence, defaultUsername: "default")
        let firstRequest = try #require(store.authenticatedViewerResolutionRequest)

        #expect(store.recordMediaLibraryIdentityResolutionFailure(for: firstRequest.session))
        #expect(store.mediaLibraryIdentityResolutionError != nil)
        #expect(!store.isMediaLibraryIdentityResolved)

        store.retryMediaLibraryIdentityResolution()
        let retryRequest = try #require(store.authenticatedViewerResolutionRequest)

        #expect(retryRequest.accessToken == firstRequest.accessToken)
        #expect(retryRequest.sessionID == firstRequest.sessionID)
        #expect(retryRequest.attempt == firstRequest.attempt + 1)
        #expect(store.mediaLibraryIdentityResolutionError == nil)
        #expect(store.applyResolvedUsername("resolved", for: retryRequest.session))
        #expect(store.isMediaLibraryIdentityResolved)
        #expect(store.username == "resolved")
    }
}

@Suite("Content identity gating", .timeLimit(.minutes(1)))
@MainActor
struct ContentIdentityGateTests {
    @Test("Credential changes hide library tabs until the new Viewer identity resolves")
    func credentialChangeHidesTabsUntilIdentityResolution() throws {
        let persistence = InMemoryAuthPersistence(
            accessToken: "credential-a",
            username: "viewer-a"
        )
        let store = AuthStore(persistence: persistence, defaultUsername: "default")
        let initialRequest = try #require(store.authenticatedViewerResolutionRequest)
        #expect(store.applyResolvedUsername("viewer-a", for: initialRequest.session))
        #expect(presentationState(for: store) == .tabs)

        #expect(store.setManualToken("credential-b"))

        #expect(!store.isMediaLibraryIdentityResolved)
        #expect(presentationState(for: store) == .identityResolution)

        let replacementRequest = try #require(store.authenticatedViewerResolutionRequest)
        #expect(store.applyResolvedUsername("viewer-b", for: replacementRequest.session))
        #expect(presentationState(for: store) == .tabs)
    }

    @Test("Viewer resolution failure keeps library tabs hidden on the safe profile fallback")
    func resolutionFailureKeepsProfileFallback() throws {
        let persistence = InMemoryAuthPersistence(
            accessToken: "credential",
            username: "viewer"
        )
        let store = AuthStore(persistence: persistence, defaultUsername: "default")
        let request = try #require(store.authenticatedViewerResolutionRequest)

        #expect(store.recordMediaLibraryIdentityResolutionFailure(for: request.session))

        #expect(store.mediaLibraryIdentityResolutionError != nil)
        #expect(presentationState(for: store) == .identityResolution)
    }

    private func presentationState(for store: AuthStore) -> ContentPresentationState {
        ContentPresentationState.resolve(
            isReady: true,
            isMediaLibraryIdentityResolved: store.isMediaLibraryIdentityResolved
        )
    }
}

private actor RecordingAuthSessionMediaLibraryClient: MediaLibraryClient {
    struct Request: Equatable, Sendable {
        let type: MediaType
        let username: String
        let accessToken: String?
    }

    private(set) var requests: [Request] = []

    func fetchMediaList(
        type: MediaType,
        username: String,
        accessToken: String?
    ) async throws -> [MediaListEntry] {
        requests.append(Request(
            type: type,
            username: username,
            accessToken: accessToken
        ))
        return []
    }
}

@MainActor
private final class InMemoryAuthPersistence: AuthPersistence {
    var accessToken: String?
    var username: String?
    var shouldSaveAccessToken: Bool

    init(
        accessToken: String? = nil,
        username: String? = nil,
        shouldSaveAccessToken: Bool = true
    ) {
        self.accessToken = accessToken
        self.username = username
        self.shouldSaveAccessToken = shouldSaveAccessToken
    }

    func loadAccessToken() -> String? {
        accessToken
    }

    func loadUsername() -> String? {
        username
    }

    func saveAccessToken(_ token: String) -> Bool {
        guard shouldSaveAccessToken else { return false }
        accessToken = token
        return true
    }

    func saveUsername(_ username: String) {
        self.username = username
    }

    func deleteAccessToken() {
        accessToken = nil
    }

    func deleteUsername() {
        username = nil
    }
}
