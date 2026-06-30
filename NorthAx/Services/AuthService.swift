import Foundation
import AuthenticationServices
import Observation

@Observable
class AuthService {
    private(set) var currentUser: AuthUser? = nil
    var authError: AuthSignInError? = nil

    private let defaultsKey = "northax.authUser"

    init() {
        restoreSession()
    }

    var isAuthenticated: Bool { currentUser != nil }

    // MARK: - Sign In with Apple

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        authError = nil
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let firstName = cred.fullName?.givenName ?? ""
            let lastName  = cred.fullName?.familyName ?? ""
            let fullName  = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
            let user = AuthUser(
                id: cred.user,
                name: fullName.isEmpty ? "Athlete" : fullName,
                email: cred.email
            )
            persist(user)
            currentUser = user

        case .failure(let err):
            guard let appleErr = err as? ASAuthorizationError else {
                authError = .unknown
                return
            }
            switch appleErr.code {
            case .canceled:
                break  // user dismissed — not an error
            case .unknown:
                // Code 1000: device has no Apple ID signed in
                authError = .noAppleAccount
            case .notHandled, .failed, .invalidResponse:
                authError = .failed
            default:
                authError = .unknown
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Session restore

    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data) else { return }

        // Optimistic restore — validate in background and revoke only if explicitly revoked
        currentUser = user

        // Skip credential check for debug mock users
        if user.id.hasPrefix("debug-") { return }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: user.id) { [weak self] state, _ in
            DispatchQueue.main.async {
                switch state {
                case .revoked, .notFound:
                    self?.signOut()
                default:
                    break
                }
            }
        }
    }

    private func persist(_ user: AuthUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - Debug bypass

#if DEBUG
    func signInAsDebugUser(name: String = "Rafael") {
        let user = AuthUser(id: "debug-\(UUID().uuidString)", name: name, email: nil)
        persist(user)
        currentUser = user
        authError = nil
    }
#endif
}

// MARK: - Error type

enum AuthSignInError: LocalizedError {
    case noAppleAccount
    case failed
    case unknown

    var errorDescription: String? {
        switch self {
        case .noAppleAccount:
            return "No Apple ID is signed in on this device. Go to Settings → Apple ID and sign in, then try again."
        case .failed:
            return "Sign in failed. Please try again."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}
