package app.northax.store

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.northax.data.remote.ApiError
import app.northax.data.remote.NorthAxApi
import app.northax.domain.model.GarminActivity
import app.northax.domain.model.IntervalsConnectionState
import app.northax.domain.model.PlannedSession
import java.time.LocalDate

/**
 * Connects to intervals.icu (OAuth) — the man-in-the-middle over Garmin/Strava:
 * the client secret never touches the app. `beginConnect()` returns the
 * backend-issued authorization URL for a Custom Tab; on the
 * `northax://intervals/connected` deep link the backend has stored the tokens,
 * so the app refreshes status and triggers a sync.
 */
class IntervalsService(private val api: NorthAxApi) {

    var connectionState by mutableStateOf<IntervalsConnectionState>(IntervalsConnectionState.Disconnected)
    var syncedActivities by mutableStateOf<List<GarminActivity>>(emptyList())
    var isSyncing by mutableStateOf(false)
        private set

    // MARK: - Status

    /** Load the current connection state from the backend (call on app start). */
    suspend fun refreshStatus() {
        try {
            val state = api.intervalsStatus()
            connectionState = state
            if (state.isConnected) {
                syncedActivities = try {
                    api.activities(limit = 30)
                } catch (_: Exception) {
                    syncedActivities
                }
            }
        } catch (_: Exception) {
        }
    }

    // MARK: - Connection

    /** Start the OAuth flow: returns the authorization URL to open in a Custom
     *  Tab, or null on failure (connectionState carries the error). */
    suspend fun beginConnect(): String? {
        connectionState = IntervalsConnectionState.Connecting
        return try {
            api.intervalsAuthorizationUrl()
        } catch (e: ApiError) {
            connectionState = if (e.isIntervalsNotConfigured) {
                IntervalsConnectionState.Error("intervals.icu isn't enabled on this server yet. Please contact support.")
            } else {
                IntervalsConnectionState.Error(e.userMessage)
            }
            null
        } catch (_: Exception) {
            connectionState = IntervalsConnectionState.Error("Couldn't connect to intervals.icu.")
            null
        }
    }

    /** Called when the `northax://intervals/connected` deep link arrives. */
    suspend fun completeConnect() {
        try {
            connectionState = api.intervalsStatus()
            syncActivities()
        } catch (_: Exception) {
            connectionState = IntervalsConnectionState.Error("Couldn't connect to intervals.icu.")
        }
    }

    /** Connect with a personal intervals.icu API key (no web OAuth). */
    suspend fun connectWithApiKey(athleteId: String, apiKey: String) {
        connectionState = IntervalsConnectionState.Connecting
        try {
            connectionState = api.connectWithApiKey(athleteId, apiKey)
            syncActivities()
        } catch (e: ApiError) {
            connectionState = IntervalsConnectionState.Error(e.userMessage)
        } catch (_: Exception) {
            connectionState = IntervalsConnectionState.Error("Couldn't connect with that API key.")
        }
    }

    suspend fun disconnect() {
        try {
            api.intervalsDisconnect()
        } catch (_: Exception) {
        }
        connectionState = IntervalsConnectionState.Disconnected
        syncedActivities = emptyList()
    }

    // MARK: - Sync

    suspend fun syncActivities() {
        if (!connectionState.isConnected) return
        isSyncing = true
        try {
            api.intervalsSync()
            syncedActivities = api.activities(limit = 30)
            connectionState = api.intervalsStatus()
        } catch (_: Exception) {
            // Keep the last good state; a transient sync failure isn't fatal.
        } finally {
            isSyncing = false
        }
    }

    // MARK: - Plan push

    /** Push a planned session to intervals.icu (→ Garmin) as a scheduled
     *  workout. Returns whether the push succeeded. */
    suspend fun pushPlannedSession(session: PlannedSession, date: LocalDate): Boolean {
        if (!connectionState.isConnected) return false
        return try {
            api.pushWorkout(date, session)
            true
        } catch (_: Exception) {
            false
        }
    }
}
