import Foundation
import Observation

/// Owns the authenticated session. Email/password credentials are exchanged with
/// the backend (`POST /auth/login` or `POST /auth/register`) for an access +
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

    // MARK: - Email / Password

    /// Sign in with an existing account (§3.1).
    func signIn(email: String, password: String) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(email) else {
            authError = .invalidInput("Enter a valid email address.")
            return
        }
        guard !password.isEmpty else {
            authError = .invalidInput("Enter your password.")
            return
        }
        authError = nil
        Task { await exchange(path: "auth/login", body: EmailSignInRequest(email: email, password: password)) }
    }

    /// Create a new account, then start an authenticated session (§3.1).
    func register(name: String, email: String, password: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            authError = .invalidInput("Enter your name.")
            return
        }
        guard Self.isValidEmail(email) else {
            authError = .invalidInput("Enter a valid email address.")
            return
        }
        guard password.count >= 8 else {
            authError = .invalidInput("Password must be at least 8 characters.")
            return
        }
        authError = nil
        Task {
            await exchange(path: "auth/register", body: EmailSignUpRequest(name: name, email: email, password: password))
        }
    }

    /// Exchange credentials for app tokens and open the session.
    private func exchange(path: String, body: Encodable) async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let resp: AuthResponse = try await api.post(path, body: body, authenticated: false)
            tokens.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
            setUser(AuthUser(id: resp.user.id, name: resp.user.name, email: resp.user.email))
        } catch let error as APIError {
            authError = .server(error.userMessage)
        } catch {
            authError = .failed
        }
    }

    private static func isValidEmail(_ email: String) -> Bool {
        // Pragmatic check: one @, non-empty local part, dotted domain.
        email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
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
    case invalidInput(String)
    case failed
    case unknown
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .failed:
            return "Sign in failed. Please try again."
        case .unknown:
            return "Something went wrong. Please try again."
        case .server(let message):
            return message
        }
    }
}
