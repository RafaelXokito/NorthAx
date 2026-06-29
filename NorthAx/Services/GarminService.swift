import Foundation
import Observation

/// Manages the connection to Garmin Connect and syncs activity data.
///
/// Real integration requires a server-side OAuth2 proxy because the Garmin Health API
/// client secret must not be embedded in the app. The flow would be:
///   1. App opens a WKWebView / ASWebAuthenticationSession pointing to your backend's
///      `/garmin/auth` endpoint, which redirects to Garmin's OAuth page.
///   2. After the user authorises, Garmin redirects to your backend callback URL.
///   3. Your backend exchanges the code for access + refresh tokens, stores them, and
///      returns a session token to the app.
///   4. The app uses that session token to call your backend, which proxies requests to
///      `https://apis.garmin.com/wellness-api/rest/`.
///
/// All methods below are stubbed with mock data until those credentials are wired up.
@Observable
class GarminService {
    var connectionState: GarminConnectionState = .disconnected
    var syncedActivities: [GarminActivity] = []
    var isSyncing: Bool = false

    // MARK: - Connection

    func connect() async {
        connectionState = .connecting

        // TODO: Replace with real ASWebAuthenticationSession OAuth flow
        try? await Task.sleep(for: .seconds(2))

        connectionState = .connected(displayName: "Rafael's Garmin", lastSync: Date())
        await syncActivities()
    }

    func disconnect() {
        connectionState = .disconnected
        syncedActivities = []
    }

    // MARK: - Sync

    func syncActivities() async {
        guard connectionState.isConnected else { return }
        isSyncing = true

        // TODO: Replace with real Garmin Health API call via your backend
        // GET /wellness-api/rest/activities?uploadStartTimeInSeconds=...
        try? await Task.sleep(for: .seconds(1.5))
        syncedActivities = GarminActivity.mockActivities

        isSyncing = false
        if case .connected(let name, _) = connectionState {
            connectionState = .connected(displayName: name, lastSync: Date())
        }
    }

    // MARK: - Plan push

    /// Push a planned session to Garmin as a scheduled workout.
    /// Requires the Garmin Training API — also server-side only.
    func pushPlannedSession(_ session: PlannedSession) async {
        guard connectionState.isConnected else { return }
        // TODO: POST to Garmin Training API via backend
    }
}
