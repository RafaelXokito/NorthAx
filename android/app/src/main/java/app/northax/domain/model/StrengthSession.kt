package app.northax.domain.model

import java.util.UUID

data class ExerciseSuggestion(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val muscleGroup: MuscleGroup,
    val sets: Int,
    val repsRange: String, // e.g. "5–7", "8–12"
    val rest: String,      // e.g. "2–3 min"
    val notes: String? = null,
) {
    val setDisplay: String get() = "$sets × $repsRange"
}

data class StrengthSession(
    val muscleGroups: List<MuscleGroup>,
    val title: String,
    val exercises: List<ExerciseSuggestion>,
    val duration: Int, // minutes
    val intensityLabel: String,
    val rationale: String,
    val recoveryWarnings: List<String>,
)

// MARK: - Logged strength work (actuals, per set)

data class LoggedSet(
    val id: String = UUID.randomUUID().toString(),
    val weightKg: Double?, // null = bodyweight
    val reps: Int,
) {
    val display: String
        get() {
            val w = weightKg?.let {
                if (it == Math.floor(it)) "${it.toInt()} kg" else String.format(java.util.Locale.US, "%.1f kg", it)
            } ?: "BW"
            return "$w × $reps"
        }
}

data class LoggedExercise(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val muscleGroup: MuscleGroup,
    val sets: List<LoggedSet>,
)
