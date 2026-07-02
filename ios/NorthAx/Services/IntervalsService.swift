import Foundation
import Observation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

/// Connects to intervals.icu (OAuth) — the man-in-the-middle over Garmin/Strava
/// (§9): the client secret never touches the app. `connect()` opens the
/// backend-issued authorization URL in an `ASWebAuthenticationSession`; on the
/// `northax://intervals/connected` callback the backend has stored the tokens, so
/// the app polls status and triggers a sync.
@MainActor
@Observable
class IntervalsService {
    var connectionState: IntervalsConnectionState = .disconnected
    var syncedActivities: [GarminActivity] = []
    var isSyncing: Bool = false

    private let api = NorthAxAPI.shared
    private let contextProvider = WebAuthContextProvider()
    private var authSession: ASWebAuthenticationSession?

    // MARK: - Status

    /// Load the current connection state from the backend (call on app start).
    func refreshStatus() async {
        if let state = try? await api.intervalsStatus() {
            connectionState = state
            if state.isConnected {
                syncedActivities = (try? await api.activities(limit: 30)) ?? syncedActivities
            }
        }
    }

    // MARK: - Connection

    func connect() async {
        connectionState = .connecting
        do {
            let url = try await api.intervalsAuthorizationURL()
            try await presentAuth(url: url)
            connectionState = try await api.intervalsStatus()
            await syncActivities()
        } catch let error as APIError {
            if error.isIntervalsNotConfigured {
                connectionState = .error("intervals.icu isn’t enabled on this server yet. Please contact support.")
            } else {
                connectionState = .error(error.userMessage)
            }
        } catch {
            connectionState = .error("Couldn’t connect to intervals.icu.")
        }
    }

    /// Connect with a personal intervals.icu API key (no web OAuth).
    func connectWithAPIKey(athleteId: String, apiKey: String) async {
        connectionState = .connecting
        do {
            connectionState = try await api.connectWithAPIKey(athleteId: athleteId, apiKey: apiKey)
            await syncActivities()
        } catch let error as APIError {
            connectionState = .error(error.userMessage)
        } catch {
            connectionState = .error("Couldn't connect with that API key.")
        }
    }

    func disconnect() {
        Task {
            try? await api.intervalsDisconnect()
            connectionState = .disconnected
            syncedActivities = []
        }
    }

    // MARK: - Sync

    func syncActivities() async {
        guard connectionState.isConnected else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await api.intervalsSync()
            syncedActivities = try await api.activities(limit: 30)
            connectionState = try await api.intervalsStatus()
        } catch {
            // Keep the last good state; a transient sync failure isn't fatal.
        }
    }

    // MARK: - Plan push (§9.4)

    /// Push a planned session to intervals.icu (→ Garmin) as a scheduled workout.
    /// Returns whether the push succeeded.
    @discardableResult
    func pushPlannedSession(_ session: PlannedSession, on date: Date) async -> Bool {
        guard connectionState.isConnected else { return false }
        return (try? await api.pushWorkout(date: date, session: session)) != nil
    }

    // MARK: - ASWebAuthenticationSession

    private func presentAuth(url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: APIConfig.appScheme
            ) { _, error in
                if let error {
                    // User-cancelled is not a hard error.
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume()
                }
            }
            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                continuation.resume(throwing: APIError.offline)
            }
        }
    }
}

/// Supplies the window to anchor the auth sheet to.
final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
