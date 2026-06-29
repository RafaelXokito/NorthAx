import Foundation
import AuthenticationServices
import Observation

@Observable
class AuthService {
    private(set) var currentUser: AuthUser? = nil
    var authError: String? = nil

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
            // Ignore user-initiated cancellation
            if (err as? ASAuthorizationError)?.code != .canceled {
                authError = "Sign in failed. Please try again."
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

        // Optimistic restore — validate in background and revoke if needed
        currentUser = user

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
}
