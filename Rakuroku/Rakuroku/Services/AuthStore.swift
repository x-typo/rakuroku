import AuthenticationServices
import Foundation
import Observation
import Security
import SwiftUI

@MainActor
protocol AuthPersistence {
    func loadAccessToken() -> String?
    func loadUsername() -> String?
    func saveAccessToken(_ token: String) -> Bool
    func saveUsername(_ username: String)
    func deleteAccessToken()
    func deleteUsername()
}

struct AuthenticatedViewerResolutionRequest: Hashable, Sendable {
    let sessionID: MediaLibrarySession.ID
    let accessToken: String
    let attempt: UInt64

    var session: MediaLibrarySession {
        MediaLibrarySession(id: sessionID, accessToken: accessToken)
    }
}

@MainActor
private final class DefaultAuthPersistence: AuthPersistence {
    private let tokenKey = "anilist_access_token"
    private let usernameKey = "anilist_username"

    func loadAccessToken() -> String? {
        KeychainHelper.loadString(key: tokenKey)
    }

    func loadUsername() -> String? {
        UserDefaults.standard.string(forKey: usernameKey)
    }

    func saveAccessToken(_ token: String) -> Bool {
        KeychainHelper.saveString(key: tokenKey, value: token)
    }

    func saveUsername(_ username: String) {
        UserDefaults.standard.set(username, forKey: usernameKey)
    }

    func deleteAccessToken() {
        KeychainHelper.delete(key: tokenKey)
    }

    func deleteUsername() {
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }
}

@MainActor @Observable
final class AuthStore {
    private(set) var accessToken: String?
    private(set) var username: String
    private(set) var isLoading = true
    private(set) var authError: String?
    private(set) var mediaLibraryRevision: UInt64 = 0
    private(set) var isMediaLibraryIdentityResolved: Bool
    private(set) var mediaLibraryIdentityResolutionError: String?
    private(set) var mediaLibraryIdentityResolutionAttempt: UInt64 = 0

    var isAuthenticated: Bool { accessToken != nil }
    var mediaLibrarySession: MediaLibrarySession {
        MediaLibrarySession(
            id: MediaLibrarySession.ID(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                revision: mediaLibraryRevision
            ),
            accessToken: accessToken
        )
    }

    var authenticatedViewerResolutionRequest: AuthenticatedViewerResolutionRequest? {
        guard !isMediaLibraryIdentityResolved, let accessToken else { return nil }
        return AuthenticatedViewerResolutionRequest(
            sessionID: mediaLibrarySession.id,
            accessToken: accessToken,
            attempt: mediaLibraryIdentityResolutionAttempt
        )
    }

    func isCurrent(_ session: MediaLibrarySession) -> Bool {
        mediaLibrarySession.id == session.id
            && accessToken == session.accessToken
    }

    private let persistence: any AuthPersistence
    private let defaultUsername: String
    private let clientId = "33626"
    private let callbackScheme = "rakuroku"
    private let callbackHost = "auth"
    private var authSession: ASWebAuthenticationSession?
    private var authContextProvider: ASWebAuthContextProvider?

    convenience init() {
        self.init(
            persistence: DefaultAuthPersistence(),
            defaultUsername: ProcessInfo.processInfo.environment["ANILIST_USERNAME"] ?? "xtypo"
        )
    }

    init(persistence: any AuthPersistence, defaultUsername: String) {
        self.persistence = persistence
        self.defaultUsername = defaultUsername
        let persistedAccessToken = persistence.loadAccessToken()
        accessToken = persistedAccessToken
        username = persistence.loadUsername() ?? defaultUsername
        isMediaLibraryIdentityResolved = persistedAccessToken == nil
        isLoading = false
    }

    func updateUsername(_ name: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard username != normalizedName else { return }
        username = normalizedName
        mediaLibraryRevision &+= 1
        persistence.saveUsername(normalizedName)
    }

    @discardableResult
    func applyResolvedUsername(
        _ name: String,
        for session: MediaLibrarySession
    ) -> Bool {
        guard session.accessToken != nil, isCurrent(session) else { return false }
        updateUsername(name)
        isMediaLibraryIdentityResolved = true
        mediaLibraryIdentityResolutionError = nil
        return true
    }

    @discardableResult
    func recordMediaLibraryIdentityResolutionFailure(
        for session: MediaLibrarySession
    ) -> Bool {
        guard session.accessToken != nil,
              isCurrent(session),
              !isMediaLibraryIdentityResolved else {
            return false
        }
        mediaLibraryIdentityResolutionError =
            "Couldn't verify your AniList account. Check your connection and try again."
        return true
    }

    func retryMediaLibraryIdentityResolution() {
        guard accessToken != nil, !isMediaLibraryIdentityResolved else { return }
        mediaLibraryIdentityResolutionError = nil
        mediaLibraryIdentityResolutionAttempt &+= 1
    }

    func login() async {
        guard !clientId.isEmpty, clientId != "YOUR_CLIENT_ID" else {
            authError = "Missing AniList client ID."
            return
        }

        authError = nil

        let state = makeOAuthState()
        var components = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "state", value: state),
        ]

        guard let authURL = components?.url else {
            authError = "Invalid auth URL."
            return
        }

        guard let presentationAnchor = ASWebAuthContextProvider.currentPresentationAnchor else {
            authError = "No active window available for AniList login."
            return
        }
        let contextProvider = ASWebAuthContextProvider(anchor: presentationAnchor)

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: authURL, callback: .customScheme(callbackScheme)) { [weak self] url, error in
                    self?.authSession = nil
                    self?.authContextProvider = nil
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: AniListError.graphQLError("No callback URL"))
                    }
                }
                session.prefersEphemeralWebBrowserSession = false
                session.presentationContextProvider = contextProvider
                self.authContextProvider = contextProvider
                self.authSession = session
                if !session.start() {
                    self.authSession = nil
                    self.authContextProvider = nil
                    continuation.resume(throwing: AniListError.graphQLError("Unable to start auth session"))
                }
            }

            guard isExpectedCallbackURL(callbackURL) else {
                authError = "AniList redirect URL must use \(callbackScheme)://."
                return
            }

            guard let fragment = callbackURL.fragment else {
                authError = "No token in callback."
                return
            }

            let params = URLComponents(string: "?\(fragment)")?.queryItems?.reduce(into: [String: String]()) { dict, item in
                dict[item.name] = item.value ?? ""
            } ?? [:]

            guard params["state"] == state else {
                authError = "Invalid auth state."
                return
            }

            guard let token = params["access_token"], !token.isEmpty else {
                authError = "Access token missing from callback."
                return
            }

            guard persistAccessToken(token) else { return }

        } catch {
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                authError = "Login cancelled."
            } else {
                authError = "Login failed. Try again or use manual token paste."
            }
        }
    }

    func logout(authError message: String? = nil) {
        let identityChanged = accessToken != nil || username != defaultUsername
        persistence.deleteAccessToken()
        accessToken = nil
        username = defaultUsername
        isMediaLibraryIdentityResolved = true
        mediaLibraryIdentityResolutionError = nil
        if identityChanged {
            mediaLibraryRevision &+= 1
        }
        authError = message
        persistence.deleteUsername()
    }

    @discardableResult
    func logoutIfCurrent(
        _ session: MediaLibrarySession,
        authError message: String? = nil
    ) -> Bool {
        guard session.accessToken != nil, isCurrent(session) else { return false }
        logout(authError: message)
        return true
    }

    @discardableResult
    func setManualToken(_ token: String) -> Bool {
        let normalized = normalizeAccessToken(token)
        guard !normalized.isEmpty else {
            authError = "Token cannot be empty."
            return false
        }
        return persistAccessToken(normalized)
    }

    func clearAuthError() {
        authError = nil
    }

    private func persistAccessToken(_ token: String) -> Bool {
        guard persistence.saveAccessToken(token) else {
            authError = "Couldn't save token securely."
            return false
        }
        if accessToken != token {
            mediaLibraryRevision &+= 1
            isMediaLibraryIdentityResolved = false
            mediaLibraryIdentityResolutionError = nil
            mediaLibraryIdentityResolutionAttempt &+= 1
        } else if !isMediaLibraryIdentityResolved {
            retryMediaLibraryIdentityResolution()
        }
        accessToken = token
        authError = nil
        return true
    }

    private func makeOAuthState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString
    }

    private func normalizeAccessToken(_ token: String) -> String {
        var normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let callbackToken = accessToken(fromCallbackText: normalized) {
            normalized = callbackToken
        }
        if normalized.lowercased().hasPrefix("bearer ") {
            normalized = String(normalized.dropFirst("bearer ".count))
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func accessToken(fromCallbackText text: String) -> String? {
        guard let components = URLComponents(string: text) else { return nil }
        if let token = value(named: "access_token", in: components.fragment) {
            return token
        }
        return components.queryItems?.first { $0.name == "access_token" }?.value
    }

    private func value(named name: String, in fragment: String?) -> String? {
        guard let fragment else { return nil }
        return URLComponents(string: "?\(fragment)")?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func isExpectedCallbackURL(_ url: URL) -> Bool {
        guard url.scheme == callbackScheme else { return false }
        guard let host = url.host, !host.isEmpty else {
            return url.path.isEmpty || url.path == "/"
        }
        return host == callbackHost
    }
}

@MainActor
final class ASWebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    static var currentPresentationAnchor: ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first

        return scene?.windows.first(where: { $0.isKeyWindow })
            ?? scene?.windows.first(where: { !$0.isHidden })
            ?? scene?.windows.first
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
