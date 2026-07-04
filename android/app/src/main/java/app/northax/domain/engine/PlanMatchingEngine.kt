package app.northax.domain.engine

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import app.northax.domain.model.GarminActivity
import app.northax.domain.model.PlannedDay
import app.northax.domain.model.PlannedSession
import app.northax.domain.model.WeeklyPlan
import app.northax.ui.theme.Ax
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.abs

/**
 * Completion state of a planned session, derived by matching it against
 * workouts imported from intervals.icu / Garmin / Strava.
 */
enum class SessionCompletion {
    Planned, // scheduled today or in the future, not yet done
    Done,    // a matching imported workout was found
    Extra,   // an imported workout with no planned session (off-plan)
    Missed,  // the planned day has passed with no matching workout
    Rest;    // no session scheduled

    val label: String
        get() = when (this) {
            Planned -> "Planned"; Done -> "Done"; Extra -> "Extra"; Missed -> "Missed"; Rest -> "Rest"
        }

    val color: Color
        get() = when (this) {
            Planned -> Ax.Accent
            Done -> Ax.Green
            Extra -> Ax.Purple
            Missed -> Ax.Red
            Rest -> Ax.Tertiary
        }

    val icon: ImageVector
        get() = when (this) {
            Planned -> Icons.Outlined.Circle
            Done -> Icons.Filled.CheckCircle
            Extra -> Icons.Filled.AddCircle
            Missed -> Icons.Filled.Cancel
            Rest -> Icons.Filled.NightsStay
        }

    /** A workout actually happened — planned (Done) or off-plan (Extra). */
    val isCompleted: Boolean get() = this == Done || this == Extra
}

/**
 * A planned session paired with its completion state and (when done) the
 * imported workout it matched.
 */
data class SessionMatch(
    val id: String,
    val day: PlannedDay,
    val session: PlannedSession,
    val completion: SessionCompletion,
    val activity: GarminActivity?,
) {
    /** Stable key for caching daily switch suggestions — survives plan reloads. */
    val suggestionKey: String get() = suggestionKey(day, session)

    companion object {
        fun suggestionKey(day: PlannedDay, session: PlannedSession): String =
            "${day.date}|${session.domain.raw}|${session.title}"
    }
}

/** One navigable week: the plan (or a synthesized past week) plus its matches. */
data class WeekData(
    val offset: Int,
    val week: WeeklyPlan,
    val matches: List<SessionMatch>,
    val isHistorical: Boolean,
)

/**
 * Client-side matching of a week's planned sessions to imported workouts.
 * Match on same calendar day + same sport; when several workouts fit, pick the
 * one closest in duration to the planned session.
 */
object PlanMatchingEngine {

    private fun GarminActivity.localDate(): LocalDate =
        startTime.atZone(ZoneId.systemDefault()).toLocalDate()

    fun matches(
        week: WeeklyPlan,
        activities: List<GarminActivity>,
        today: LocalDate = LocalDate.now(),
    ): List<SessionMatch> {
        val out = mutableListOf<SessionMatch>()
        val matchedActivityIds = mutableSetOf<String>()

        for (day in week.days) {
            if (day.isRest || day.sessions.isEmpty()) continue
            for (session in day.sessions) {
                val sameDaySameSport = activities.filter {
                    it.localDate() == day.date && it.type.domain == session.domain &&
                        it.id !in matchedActivityIds
                }
                val matched = sameDaySameSport.minByOrNull {
                    abs(it.durationSeconds / 60.0 - session.duration)
                }
                if (matched != null) matchedActivityIds.add(matched.id)
                val completion = when {
                    matched != null -> SessionCompletion.Done
                    day.date.isBefore(today) -> SessionCompletion.Missed
                    else -> SessionCompletion.Planned
                }
                out.add(SessionMatch(session.id, day, session, completion, matched))
            }
        }

        // Surface imported workouts that don't correspond to any planned session
        // as extra entries, so an off-plan workout still shows up on the week.
        for (day in week.days) {
            val extras = activities.filter {
                it.localDate() == day.date && it.id !in matchedActivityIds
            }
            for (a in extras) {
                matchedActivityIds.add(a.id)
                out.add(extraMatch(a, day))
            }
        }

        // Chronological order regardless of planned/unplanned. Stable within a
        // day (original index tiebreak) so planned sessions stay ahead of extras.
        return out.withIndex()
            .sortedWith(compareBy({ it.value.day.date }, { it.index }))
            .map { it.value }
    }

    /**
     * Today's rows for the dashboard: today's matches from the current week,
     * plus an extra entry for any workout done today that no plan day covers —
     * a lapsed or missing plan must not hide what the athlete actually did.
     */
    fun todayMatches(
        week: WeeklyPlan?,
        activities: List<GarminActivity>,
        today: LocalDate = LocalDate.now(),
    ): List<SessionMatch> {
        val weekMatches = week?.let { matches(it, activities, today) } ?: emptyList()
        val out = weekMatches.filter { it.day.date == today }.toMutableList()
        val seen = out.mapNotNull { it.activity?.id }.toSet()
        val day = PlannedDay(date = today, sessions = emptyList(), isRest = false)
        for (a in activities) {
            if (a.localDate() != today || a.id in seen) continue
            out.add(extraMatch(a, day))
        }
        return out
    }

    /** Off-plan workout as a match row. The id derives from the activity so it
     *  stays stable across recomputations (extras have no persisted session). */
    private fun extraMatch(a: GarminActivity, day: PlannedDay): SessionMatch {
        val session = PlannedSession(
            id = "extra-${a.id}",
            domain = a.type.domain, title = a.name, subtitle = "",
            duration = (a.durationSeconds / 60).toInt(), intensityLabel = "Completed",
        )
        return SessionMatch(session.id, day, session, SessionCompletion.Extra, a)
    }

    /**
     * Roll a day's session matches up to a single state for the week strip:
     * rest → any missed → all done → otherwise planned.
     */
    fun dayState(day: PlannedDay, matches: List<SessionMatch>): SessionCompletion {
        val dayMatches = matches.filter { it.day.date == day.date }
        if (day.isRest || day.sessions.isEmpty()) {
            // A rest day still marks done if an unplanned workout was imported for it.
            return if (dayMatches.any { it.completion.isCompleted }) SessionCompletion.Done
            else SessionCompletion.Rest
        }
        if (dayMatches.isEmpty()) return SessionCompletion.Planned
        if (dayMatches.any { it.completion == SessionCompletion.Missed }) return SessionCompletion.Missed
        if (dayMatches.all { it.completion.isCompleted }) return SessionCompletion.Done
        return SessionCompletion.Planned
    }
}
