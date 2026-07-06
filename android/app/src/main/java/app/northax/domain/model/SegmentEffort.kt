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
) {
    /** "7:05" or "1:02:45". */
    val formattedTime: String
        get() {
            val h = elapsedSeconds / 3600
            val m = (elapsedSeconds % 3600) / 60
            val s = elapsedSeconds % 60
            return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
            else String.format(Locale.US, "%d:%02d", m, s)
        }

    /** "3.2 KM · 5.4%". */
    val metaLine: String
        get() = buildList {
            distanceMeters?.let { add(String.format(Locale.US, "%.1f KM", it / 1000)) }
            avgGrade?.let { add(String.format(Locale.US, "%.1f%%", it)) }
        }.joinToString(" · ")
}

/** A segment's metadata plus the athlete's efforts on it, newest first. */
data class SegmentHistory(
    val segmentId: String,
    val name: String,
    val distanceMeters: Double? = null,
    val avgGrade: Double? = null,
    val climbCategory: Int? = null,
    val efforts: List<SegmentEffort>,
) {
    val bestElapsedSeconds: Int? get() = efforts.minOfOrNull { it.elapsedSeconds }
}
