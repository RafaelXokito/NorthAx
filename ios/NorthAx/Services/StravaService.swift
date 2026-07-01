import Foundation
import Observation

/// Connects to Strava (§13) via the server's personal refresh token — no web
/// redirect, so `connect()` is a single backend call. Reuses
/// `IntervalsConnectionState` for the connection status.
@MainActor
@Observable
class StravaService {
    var connectionState: IntervalsConnectionState = .disconnected
    var syncedActivities: [GarminActivity] = []
    var isSyncing: Bool = false

    private let api = NorthAxAPI.shared

    func refreshStatus() async {
        if let state = try? await api.stravaStatus() {
            connectionState = state
            if state.isConnected {
                syncedActivities = (try? await api.activities(limit: 30, source: "strava")) ?? syncedActivities
            }
        }
    }

    func connect() async {
        connectionState = .connecting
        do {
            connectionState = try await api.stravaConnectPersonal()
            await sync()
        } catch let error as APIError {
            connectionState = .error(error.userMessage)
        } catch {
            connectionState = .error("Couldn't connect Strava.")
        }
    }

    func sync() async {
        guard connectionState.isConnected else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await api.stravaSync()
            connectionState = try await api.stravaStatus()
            syncedActivities = (try? await api.activities(limit: 30, source: "strava")) ?? syncedActivities
        } catch {
            // Keep the last good state; a transient sync failure isn't fatal.
        }
    }

    func disconnect() {
        Task {
            try? await api.stravaDisconnect()
            connectionState = .disconnected
        }
    }
}
