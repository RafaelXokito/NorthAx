package app.northax.domain.model

import app.northax.data.remote.dto.StructuredWorkoutDto
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

data class PlannedSession(
    val id: String = UUID.randomUUID().toString(),
    val domain: TrainingDomain,
    val title: String,
    val subtitle: String,
    val duration: Int, // minutes
    val intensityLabel: String,
    val workout: StructuredWorkoutDto? = null,   // structured steps (targets in zones)
    val exercises: List<ExerciseSuggestion>? = null, // strength: movement breakdown
) {
    /** Renderable lines for the structured workout, e.g. "5× Work 8 min · Z4 HR". */
    val workoutLines: List<String>
        get() {
            val w = workout ?: return emptyList()
            if (w.targetMode == "none") return emptyList()
            return w.blocks.map { block ->
                val prefix = if (block.repeatCount > 1) "${block.repeatCount}× " else ""
                val body = block.steps.joinToString(", ") { step ->
                    "${step.cue} ${step.minutes} min" + if (step.icu.isEmpty()) "" else " · ${step.icu}"
                }
                prefix + body
            }
        }
}

data class PlannedDay(
    val date: LocalDate,
    val sessions: List<PlannedSession>, // empty + isRest == rest day
    val isRest: Boolean,
) {
    val weekdayShort: String
        get() = date.format(DateTimeFormatter.ofPattern("EEE", Locale.ENGLISH))

    val dayNumber: String get() = date.dayOfMonth.toString()

    val isToday: Boolean get() = date == LocalDate.now()
    val isPast: Boolean get() = date.isBefore(LocalDate.now())
}

data class WeeklyPlan(
    val weekStart: LocalDate,
    val days: List<PlannedDay>, // always 7 entries, Mon → Sun
) {
    val trainingDays: List<PlannedDay> get() = days.filter { !it.isRest }
    val restDays: List<PlannedDay> get() = days.filter { it.isRest }

    val weekLabel: String
        get() {
            val fmt = DateTimeFormatter.ofPattern("MMM d", Locale.ENGLISH)
            val end = weekStart.plusDays(6)
            return "${weekStart.format(fmt)} – ${end.format(fmt)}"
        }

    val isCurrentWeek: Boolean
        get() {
            val today = LocalDate.now()
            return !today.isBefore(weekStart) && today.isBefore(weekStart.plusDays(7))
        }
}
