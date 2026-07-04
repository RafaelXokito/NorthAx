package app.northax.domain.model

import java.time.Instant
import java.time.LocalDate

enum class GoalType(val raw: String) {
    RaceTime("raceTime"),                  // Running: distance + finish time
    PowerHold("powerHold"),                // Cycling: hold a power zone for a duration
    DistanceAvgSpeed("distanceAvgSpeed");  // Cycling: distance at an average speed

    companion object {
        fun fromRaw(raw: String): GoalType? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * One structured goal per sport, fed to the AI planner and the post-sync
 * progress analysis. Flat class + `goalType` discriminator.
 */
data class SportTarget(
    val goalType: GoalType,
    val targetDate: LocalDate,
    val distanceKm: Double? = null,   // raceTime, distanceAvgSpeed
    val finishTimeSec: Int? = null,   // raceTime
    val zone: Int? = null,            // powerHold (1-5)
    val holdMinutes: Int? = null,     // powerHold
    val avgSpeedKmh: Double? = null,  // distanceAvgSpeed
)

/** Latest AI goal-progress verdict for one targeted sport. */
data class GoalCheck(
    val domain: TrainingDomain,
    val verdict: Verdict,
    val summary: String,
    val recommendReplan: Boolean,
    val analyzedAt: Instant,
) {
    enum class Verdict(val raw: String) {
        OnTrack("on_track"), Behind("behind"), Ahead("ahead");

        companion object {
            fun fromRaw(raw: String): Verdict? = entries.firstOrNull { it.raw == raw }
        }
    }
}
