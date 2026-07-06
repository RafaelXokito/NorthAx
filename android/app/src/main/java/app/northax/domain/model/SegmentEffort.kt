package app.northax.domain.model

import java.time.Instant
import java.util.Locale

/** One Strava segment result within an activity (§13). */
data class SegmentEffort(
    val id: String, // backend effort row UUID
    val segmentId: String,
    val name: String,
    val distanceMeters: Double? = null,
    val avgGrade: Double? = null,
    val climbCategory: Int? = null,
    val elapsedSeconds: Int,
    val movingSeconds: Int? = null,
    val startDate: Instant,
    val prRank: Int? = null, // 1–3 personal-record rank
    val komRank: Int? = null, // 1–10 leaderboard placement
    val points: List<List<Double>>? = null, // segment geometry [[lat, lng], …]
    val bestElapsedSeconds: Int? = null, // the athlete's all-time best on this segment
) {
    /** Whether this effort is (still) the athlete's fastest on the segment. */
    val isAllTimeBest: Boolean
        get() = bestElapsedSeconds != null && elapsedSeconds == bestElapsedSeconds

    /** "7:05" or "1:02:45". */
    val formattedTime: String
        get() = formatSeconds(elapsedSeconds)

    /** The all-time best as "6:45", when known and not this effort. */
    val formattedBest: String?
        get() = bestElapsedSeconds?.takeIf { it != elapsedSeconds }?.let(::formatSeconds)

    /** "3.2 KM · 5.4%". */
    val metaLine: String
        get() = buildList {
            distanceMeters?.let { add(String.format(Locale.US, "%.1f KM", it / 1000)) }
            avgGrade?.let { add(String.format(Locale.US, "%.1f%%", it)) }
        }.joinToString(" · ")
}

private fun formatSeconds(total: Int): String {
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
    else String.format(Locale.US, "%d:%02d", m, s)
}

/** A segment's metadata plus the athlete's efforts on it, newest first. */
data class SegmentHistory(
    val segmentId: String,
    val name: String,
    val distanceMeters: Double? = null,
    val avgGrade: Double? = null,
    val climbCategory: Int? = null,
    val points: List<List<Double>>? = null,
    val efforts: List<SegmentEffort>,
) {
    val bestElapsedSeconds: Int? get() = efforts.minOfOrNull { it.elapsedSeconds }
}
