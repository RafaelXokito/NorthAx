package app.northax.domain.model

/**
 * Downsampled time-series for a completed activity. Arrays are index-aligned
 * with `time` (seconds from start); any absent metric is empty.
 */
data class ActivityStreams(
    val activityId: String,
    val time: List<Double>,
    val heartRate: List<Double>,
    val power: List<Double>,
    val velocity: List<Double>, // m/s
    val altitude: List<Double>,
    val cadence: List<Double>,
    /**
     * GPS route as [[lat, lng], …]; denser than the scalar arrays and NOT
     * index-aligned with `time`. Empty for indoor/virtual activities.
     */
    val latLng: List<List<Double>> = emptyList(),
    val source: String,
) {
    val hasData: Boolean
        get() = heartRate.isNotEmpty() || power.isNotEmpty() || velocity.isNotEmpty() ||
            altitude.isNotEmpty() || cadence.isNotEmpty()

    /** Speed in km/h (from m/s) — intuitive for a review chart. */
    val speedKmh: List<Double> get() = velocity.map { it * 3.6 }

    val durationSeconds: Double get() = time.lastOrNull() ?: 0.0
}
