package app.northax.data.local

import android.content.Context
import android.content.SharedPreferences
import app.northax.data.remote.JsonCoders
import app.northax.domain.model.AuthUser
import app.northax.domain.model.MetricSourcePriority
import app.northax.domain.model.TrainingFrequency

/**
 * Non-secret local persistence (the UserDefaults equivalent): cached user,
 * training frequency, per-metric priority, onboarding flag, and the daily
 * suggestion-fetch marker.
 */
class LocalPrefs(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("app.northax.prefs", Context.MODE_PRIVATE)
    private val json = JsonCoders.json

    var hasSetFrequency: Boolean
        get() = prefs.getBoolean(KEY_HAS_SET_FREQUENCY, false)
        set(value) = prefs.edit().putBoolean(KEY_HAS_SET_FREQUENCY, value).apply()

    var lastSuggestionFetchDate: String?
        get() = prefs.getString(KEY_LAST_SUGGESTION_FETCH, null)
        set(value) = prefs.edit().putString(KEY_LAST_SUGGESTION_FETCH, value).apply()

    // MARK: - Cached user (optimistic session restore)

    var cachedUser: AuthUser?
        get() = prefs.getString(KEY_CACHED_USER, null)?.let {
            try {
                json.decodeFromString<AuthUser>(it)
            } catch (_: Exception) {
                null
            }
        }
        set(value) {
            if (value == null) prefs.edit().remove(KEY_CACHED_USER).apply()
            else prefs.edit().putString(KEY_CACHED_USER, json.encodeToString(AuthUser.serializer(), value)).apply()
        }

    // MARK: - Training frequency

    /** No saved frequency means the user hasn't defined a plan — start empty so
     *  the Plan tab prompts them to create one rather than assuming a default. */
    fun loadFrequency(): TrainingFrequency =
        prefs.getString(KEY_FREQUENCY, null)?.let {
            try {
                json.decodeFromString<TrainingFrequency>(it)
            } catch (_: Exception) {
                null
            }
        } ?: TrainingFrequency.empty

    fun saveFrequency(freq: TrainingFrequency) {
        prefs.edit().putString(KEY_FREQUENCY, json.encodeToString(TrainingFrequency.serializer(), freq)).apply()
    }

    // MARK: - Metric priority

    fun loadMetricPriority(): MetricSourcePriority =
        prefs.getString(KEY_METRIC_PRIORITY, null)?.let {
            try {
                json.decodeFromString<MetricSourcePriority>(it)
            } catch (_: Exception) {
                null
            }
        } ?: MetricSourcePriority.default

    fun saveMetricPriority(priority: MetricSourcePriority) {
        prefs.edit()
            .putString(KEY_METRIC_PRIORITY, json.encodeToString(MetricSourcePriority.serializer(), priority))
            .apply()
    }

    private companion object {
        const val KEY_HAS_SET_FREQUENCY = "northax.hasSetFrequency"
        const val KEY_LAST_SUGGESTION_FETCH = "northax.lastSuggestionFetchDate"
        const val KEY_CACHED_USER = "northax.cachedUser"
        const val KEY_FREQUENCY = "northax.trainingFrequency"
        const val KEY_METRIC_PRIORITY = "northax.metricPriority"
    }
}
