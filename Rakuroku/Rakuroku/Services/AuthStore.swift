import AuthenticationServices
import Observation
import SwiftUI

@MainActor @Observable
final class AuthStore {
    private(set) var accessToken: String?
    private(set) var username: String
    private(set) var isLoading = true
    private(set) var authError: String?

    var isAuthenticated: Bool { accessToken != nil }

    private let tokenKey = "anilist_access_token"
    private let usernameKey = "anilist_username"
    private let defaultUsername = ProcessInfo.processInfo.environment["ANILIST_USERNAME"] ?? "xtypo"
    private let clientId = "33626"
    private var authSession: ASWebAuthenticationSession? // Must retain for duration of auth flow

    init() {
        accessToken = KeychainHelper.loadString(key: tokenKey)
        username = UserDefaults.standard.string(forKey: usernameKey) ?? defaultUsername
        isLoading = false
    }

    func updateUsername(_ name: String) {
        username = name
        UserDefaults.standard.set(name, forKey: usernameKey)
    }

    func login() async {
        guard !clientId.isEmpty, clientId != "YOUR_CLIENT_ID" else {
            authError = "Missing AniList client ID."
            return
        }

        authError = nil

        let urlString = "https://anilist.co/api/v2/oauth/authorize"
            + "?client_id=\(clientId)"
            + "&response_type=token"

        guard let authURL = URL(string: urlString) else {
            authError = "Invalid auth URL."
            return
        }

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: authURL, callback: .customScheme("rakuroku")) { [weak self] url, error in
                    self?.authSession = nil // Release after callback
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: AniListError.graphQLError("No callback URL"))
                    }
                }
                session.prefersEphemeralWebBrowserSession = false
                session.presentationContextProvider = ASWebAuthContextProvider.shared
                self.authSession = session // Retain session for auth flow duration
                if !session.start() {
                    self.authSession = nil
                    continuation.resume(throwing: AniListError.graphQLError("Unable to start auth session"))
                }
            }

            // Parse token from fragment: #access_token=xxx&token_type=Bearer&expires_in=xxx
            guard let fragment = callbackURL.fragment else {
                authError = "No token in callback."
                return
            }

            let params = fragment.split(separator: "&").reduce(into: [String: String]()) { dict, pair in
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 { dict[String(parts[0])] = String(parts[1]).removingPercentEncoding ?? String(parts[1]) }
            }

            guard let token = params["access_token"], !token.isEmpty else {
                authError = "Access token missing from callback."
                return
            }

            KeychainHelper.saveString(key: tokenKey, value: token)
            accessToken = token

        } catch {
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                authError = "Login cancelled."
            } else {
                authError = "Login failed. Try again or use manual token paste."
            }
        }
    }

    func logout() {
        KeychainHelper.delete(key: tokenKey)
        accessToken = nil
        username = defaultUsername
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    func setManualToken(_ token: String) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            authError = "Token cannot be empty."
            return
        }
        KeychainHelper.saveString(key: tokenKey, value: normalized)
        accessToken = normalized
        authError = nil
    }

    func clearAuthError() {
        authError = nil
    }
}

// Presentation context for ASWebAuthenticationSession
@MainActor
final class ASWebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = ASWebAuthContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
