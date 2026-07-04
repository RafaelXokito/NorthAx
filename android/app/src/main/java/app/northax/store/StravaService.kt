package app.northax.store

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.northax.data.remote.ApiError
import app.northax.data.remote.NorthAxApi
import app.northax.domain.model.GarminActivity
import app.northax.domain.model.IntervalsConnectionState

/**
 * Connects to Strava via the server's personal refresh token — no web
 * redirect, so `connect()` is a single backend call. Reuses
 * [IntervalsConnectionState] for the connection status.
 */
class StravaService(private val api: NorthAxApi) {

    var connectionState by mutableStateOf<IntervalsConnectionState>(IntervalsConnectionState.Disconnected)
    var syncedActivities by mutableStateOf<List<GarminActivity>>(emptyList())
    var isSyncing by mutableStateOf(false)
        private set

    suspend fun refreshStatus() {
        try {
            val state = api.stravaStatus()
            connectionState = state
            if (state.isConnected) {
                syncedActivities = try {
                    api.activities(limit = 30, source = "strava")
                } catch (_: Exception) {
                    syncedActivities
                }
            }
        } catch (_: Exception) {
        }
    }

    suspend fun connect() {
        connectionState = IntervalsConnectionState.Connecting
        try {
            connectionState = api.stravaConnectPersonal()
            sync()
        } catch (e: ApiError) {
            connectionState = IntervalsConnectionState.Error(e.userMessage)
        } catch (_: Exception) {
            connectionState = IntervalsConnectionState.Error("Couldn't connect Strava.")
        }
    }

    suspend fun sync() {
        if (!connectionState.isConnected) return
        isSyncing = true
        try {
            api.stravaSync()
            connectionState = api.stravaStatus()
            syncedActivities = try {
                api.activities(limit = 30, source = "strava")
            } catch (_: Exception) {
                syncedActivities
            }
        } catch (_: Exception) {
            // Keep the last good state; a transient sync failure isn't fatal.
        } finally {
            isSyncing = false
        }
    }

    suspend fun disconnect() {
        try {
            api.stravaDisconnect()
        } catch (_: Exception) {
        }
        connectionState = IntervalsConnectionState.Disconnected
    }
}
