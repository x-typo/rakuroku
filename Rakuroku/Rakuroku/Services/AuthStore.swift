import AuthenticationServices
import Foundation
import Observation
import Security
import SwiftUI

@MainActor @Observable
final class AuthStore {
    private(set) var accessToken: String?
    private(set) var username: String
    private(set) var isLoading = true
    private(set) var authError: String?
    private(set) var mediaLibraryRevision: UInt64 = 0

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

    private let tokenKey = "anilist_access_token"
    private let usernameKey = "anilist_username"
    private let defaultUsername = ProcessInfo.processInfo.environment["ANILIST_USERNAME"] ?? "xtypo"
    private let clientId = "33626"
    private let callbackScheme = "rakuroku"
    private let callbackHost = "auth"
    private var authSession: ASWebAuthenticationSession?
    private var authContextProvider: ASWebAuthContextProvider?

    init() {
        accessToken = KeychainHelper.loadString(key: tokenKey)
        username = UserDefaults.standard.string(forKey: usernameKey) ?? defaultUsername
        isLoading = false
    }

    func updateUsername(_ name: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard username != normalizedName else { return }
        username = normalizedName
        mediaLibraryRevision &+= 1
        UserDefaults.standard.set(normalizedName, forKey: usernameKey)
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
        KeychainHelper.delete(key: tokenKey)
        accessToken = nil
        username = defaultUsername
        if identityChanged {
            mediaLibraryRevision &+= 1
        }
        authError = message
        UserDefaults.standard.removeObject(forKey: usernameKey)
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
        guard KeychainHelper.saveString(key: tokenKey, value: token) else {
            authError = "Couldn't save token securely."
            return false
        }
        if accessToken != token {
            mediaLibraryRevision &+= 1
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
