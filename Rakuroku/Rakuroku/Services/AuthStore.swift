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

    var isAuthenticated: Bool { accessToken != nil }

    private let tokenKey = "anilist_access_token"
    private let usernameKey = "anilist_username"
    private let defaultUsername = ProcessInfo.processInfo.environment["ANILIST_USERNAME"] ?? "xtypo"
    private let clientId = "33626"
    private let callbackScheme = "rakuroku"
    private let callbackHost = "auth"
    private var authSession: ASWebAuthenticationSession?

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

        let state = makeOAuthState()
        var components = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "redirect_uri", value: "\(callbackScheme)://\(callbackHost)"),
            URLQueryItem(name: "state", value: state),
        ]

        guard let authURL = components?.url else {
            authError = "Invalid auth URL."
            return
        }

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: authURL, callback: .customScheme(callbackScheme)) { [weak self] url, error in
                    self?.authSession = nil
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
                self.authSession = session
                if !session.start() {
                    self.authSession = nil
                    continuation.resume(throwing: AniListError.graphQLError("Unable to start auth session"))
                }
            }

            guard callbackURL.scheme == callbackScheme, callbackURL.host == callbackHost else {
                authError = "Invalid auth callback."
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
        KeychainHelper.delete(key: tokenKey)
        accessToken = nil
        username = defaultUsername
        authError = message
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    @discardableResult
    func setManualToken(_ token: String) -> Bool {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
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
}

@MainActor
final class ASWebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = ASWebAuthContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            guard let fallbackScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                preconditionFailure("A window scene is required for AniList authentication.")
            }
            return ASPresentationAnchor(windowScene: fallbackScene)
        }
        return window
    }
}
