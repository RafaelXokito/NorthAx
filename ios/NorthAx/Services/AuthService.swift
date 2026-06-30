import Foundation
import AuthenticationServices
import Observation

/// Owns the authenticated session. Sign in with Apple yields an identity token
/// that is exchanged with the backend (`POST /auth/apple`) for an access +
/// refresh JWT pair stored in the Keychain (§3). The session is restored on
/// launch from those tokens, and dropped if the backend revokes them.
@MainActor
@Observable
class AuthService {
    private(set) var currentUser: AuthUser? = nil
    var authError: AuthSignInError? = nil
    private(set) var isAuthenticating: Bool = false

    private let api = APIClient.shared
    private let tokens = TokenStore.shared
    private let cachedUserKey = "northax.cachedUser"
    private var expiryObserver: NSObjectProtocol?

    init() {
        observeSessionExpiry()
        restoreSession()
    }

    var isAuthenticated: Bool { currentUser != nil }

    // MARK: - Sign In with Apple

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        authError = nil
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = cred.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                authError = .failed
                return
            }
            let authCode = cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let fullName = AppleFullNameDTO(
                givenName: cred.fullName?.givenName,
                familyName: cred.fullName?.familyName
            )
            Task { await exchange(identityToken: identityToken, authCode: authCode, fullName: fullName) }

        case .failure(let err):
            guard let appleErr = err as? ASAuthorizationError else {
                authError = .unknown
                return
            }
            switch appleErr.code {
            case .canceled:      break            // user dismissed — not an error
            case .unknown:       authError = .noAppleAccount   // code 1000: no Apple ID on device
            case .notHandled, .failed, .invalidResponse:
                authError = .failed
            default:             authError = .unknown
            }
        }
    }

    /// Exchange the Apple identity token for app tokens (§3.1).
    private func exchange(identityToken: String, authCode: String?, fullName: AppleFullNameDTO?) async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let body = AppleSignInRequest(
                identityToken: identityToken,
                authorizationCode: authCode,
                fullName: fullName
            )
            let resp: AuthResponse = try await api.post("auth/apple", body: body, authenticated: false)
            tokens.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
            setUser(AuthUser(id: resp.user.id, name: resp.user.name, email: resp.user.email))
        } catch let error as APIError {
            authError = .server(error.userMessage)
        } catch {
            authError = .failed
        }
    }

    // MARK: - Sign Out

    func signOut() {
        // Best-effort server revoke; local clear is authoritative.
        Task { _ = try? await api.send("DELETE", "auth/session") }
        tokens.clear()
        UserDefaults.standard.removeObject(forKey: cachedUserKey)
        currentUser = nil
    }

    // MARK: - Session restore

    private func restoreSession() {
        guard tokens.hasSession else { return }
        // Optimistic restore from cache, then validate against the backend.
        if let data = UserDefaults.standard.data(forKey: cachedUserKey),
           let user = try? JSONDecoder().decode(AuthUser.self, from: data) {
            currentUser = user
        }
        Task {
            do {
                let profile: UserProfileDTO = try await api.get("user/profile")
                setUser(AuthUser(id: profile.id, name: profile.name, email: profile.email))
            } catch let error as APIError where error.isUnauthorized {
                signOut()
            } catch {
                // Network error: keep optimistic session; will retry next launch.
            }
        }
    }

    private func setUser(_ user: AuthUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: cachedUserKey)
        }
    }

    private func observeSessionExpiry() {
        expiryObserver = NotificationCenter.default.addObserver(
            forName: .northaxSessionExpired, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentUser = nil
                UserDefaults.standard.removeObject(forKey: self.cachedUserKey)
            }
        }
    }

    // MARK: - Debug bypass

#if DEBUG
    /// Local-only session for offline UI work. Has no backend tokens, so live
    /// API calls will not succeed — the app should fall back to client engines.
    func signInAsDebugUser(name: String = "Rafael") {
        setUser(AuthUser(id: "debug-\(UUID().uuidString)", name: name, email: nil))
        authError = nil
    }
#endif
}

// MARK: - Error type

enum AuthSignInError: LocalizedError {
    case noAppleAccount
    case failed
    case unknown
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noAppleAccount:
            return "No Apple ID is signed in on this device. Go to Settings → Apple ID and sign in, then try again."
        case .failed:
            return "Sign in failed. Please try again."
        case .unknown:
            return "Something went wrong. Please try again."
        case .server(let message):
            return message
        }
    }
}
