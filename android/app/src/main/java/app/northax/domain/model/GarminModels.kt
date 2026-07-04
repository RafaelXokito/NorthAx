package app.northax.domain.model

import java.time.Duration
import java.time.Instant

// MARK: - Activity

enum class GarminActivityType(val raw: String) {
    Cycling("Cycling"),
    Running("Running"),
    Swimming("Swimming"),
    StrengthTraining("Strength Training"),
    Hiking("Hiking"),
    Yoga("Yoga"),
    Other("Other");

    val domain: TrainingDomain
        get() = when (this) {
            Cycling -> TrainingDomain.Cycling
            Running -> TrainingDomain.Running
            Swimming -> TrainingDomain.Swimming
            StrengthTraining -> TrainingDomain.Strength
            Yoga -> TrainingDomain.Mobility
            else -> TrainingDomain.Recovery
        }
}

data class GarminActivity(
    val id: String,
    val name: String,
    val type: GarminActivityType,
    val startTime: Instant,
    val durationSeconds: Long,
    val distanceMeters: Double? = null,
    val elevationGain: Double? = null,
    val avgHeartRate: Int? = null,
    val maxHeartRate: Int? = null,
    val calories: Int? = null,
    val trainingLoad: Double? = null, // normalized TSS equivalent
    val strengthExercises: List<LoggedExercise>? = null, // in-app logged sets (strength only)
    val source: String? = null, // backend source ("manual", "garmin", …); null = local-only
) {
    /** Only in-app logged (manual) activities can be edited after the fact —
     *  synced ones live in the source system, and their DTO id is external. */
    val isEditable: Boolean get() = source == "manual" || source == null

    val formattedDuration: String
        get() {
            val m = (durationSeconds / 60).toInt()
            return if (m >= 60) "${m / 60}h ${m % 60}m" else "$m min"
        }

    val formattedDistance: String?
        get() = distanceMeters?.let { String.format(java.util.Locale.US, "%.1f km", it / 1000) }

    val hoursAgo: Double
        get() = Duration.between(startTime, Instant.now()).seconds / 3600.0
}

// MARK: - Connection state

sealed class IntervalsConnectionState {
    data object Disconnected : IntervalsConnectionState()
    data object Connecting : IntervalsConnectionState()
    data class Connected(val displayName: String, val lastSync: Instant) : IntervalsConnectionState()
    data class Error(val message: String) : IntervalsConnectionState()

    val isConnected: Boolean get() = this is Connected

    val displayLabel: String
        get() = when (this) {
            is Disconnected -> "Not connected"
            is Connecting -> "Connecting…"
            is Connected -> "Synced ${relativeTime(lastSync)}"
            is Error -> "Error: $message"
        }

    val connectedName: String? get() = (this as? Connected)?.displayName

    private fun relativeTime(date: Instant): String {
        val diff = Duration.between(date, Instant.now()).seconds
        return when {
            diff < 60 -> "just now"
            diff < 3600 -> "${diff / 60}m ago"
            else -> "${diff / 3600}h ago"
        }
    }
}
