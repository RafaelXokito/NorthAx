package app.northax.domain.engine

import app.northax.domain.model.DailyReadiness
import app.northax.domain.model.ExerciseSuggestion
import app.northax.domain.model.GarminActivity
import app.northax.domain.model.GarminActivityType
import app.northax.domain.model.MuscleGroup
import app.northax.domain.model.StrengthSession

/** Deterministic strength session generator — offline fallback (iOS StrengthEngine). */
object StrengthEngine {

    fun generateSession(
        muscleGroups: List<MuscleGroup>,
        readiness: DailyReadiness,
        recentActivities: List<GarminActivity>,
    ): StrengthSession {
        val intensity = intensityFor(readiness)
        val warnings = buildRecoveryWarnings(muscleGroups, recentActivities)
        val exercises = buildExercises(muscleGroups, intensity)
        return StrengthSession(
            muscleGroups = muscleGroups,
            title = buildTitle(muscleGroups),
            exercises = exercises,
            duration = estimateDuration(exercises),
            intensityLabel = intensity.label,
            rationale = buildRationale(muscleGroups, readiness, warnings.size),
            recoveryWarnings = warnings,
        )
    }

    // MARK: - Intensity levels

    enum class Intensity(val label: String) {
        Heavy("Heavy"), Moderate("Moderate"), Light("Light");

        val primarySets: Int get() = when (this) { Heavy -> 4; Moderate -> 3; Light -> 2 }
        val accessorySets: Int get() = maxOf(2, primarySets - 1)

        val primaryReps: String get() = when (this) { Heavy -> "5–7"; Moderate -> "8–12"; Light -> "15–20" }
        val accessoryReps: String get() = when (this) { Heavy -> "8–12"; Moderate -> "10–15"; Light -> "15–20" }
        val primaryRest: String get() = when (this) { Heavy -> "2–3 min"; Moderate -> "90 sec"; Light -> "60 sec" }
        val accessoryRest: String get() = when (this) { Heavy -> "90 sec"; Moderate -> "60 sec"; Light -> "45 sec" }
    }

    private fun intensityFor(readiness: DailyReadiness): Intensity = when (readiness.status) {
        DailyReadiness.Status.Peak, DailyReadiness.Status.High -> Intensity.Heavy
        DailyReadiness.Status.Moderate -> Intensity.Moderate
        DailyReadiness.Status.Low, DailyReadiness.Status.Rest -> Intensity.Light
    }

    // MARK: - Exercise database

    private data class Movement(val name: String, val isCompound: Boolean, val note: String? = null)

    private val db: Map<MuscleGroup, List<Movement>> = mapOf(
        MuscleGroup.Chest to listOf(
            Movement("Barbell Bench Press", true, "Control the descent, full range"),
            Movement("Incline Dumbbell Press", true),
            Movement("Cable Chest Fly", false, "Squeeze at midpoint"),
            Movement("Dips", false),
        ),
        MuscleGroup.Back to listOf(
            Movement("Pull-Ups", true, "Drive elbows down, not hands"),
            Movement("Barbell Row", true, "Chest stays up, hinge at hips"),
            Movement("Seated Cable Row", false),
            Movement("Lat Pulldown", false),
        ),
        MuscleGroup.Shoulders to listOf(
            Movement("Overhead Press", true, "Full lockout at top"),
            Movement("Lateral Raise", false, "Lead with elbow, not wrist"),
            Movement("Face Pull", false, "External rotation at end range"),
            Movement("Arnold Press", false),
        ),
        MuscleGroup.Biceps to listOf(
            Movement("Barbell Curl", true),
            Movement("Hammer Curl", false),
            Movement("Incline Dumbbell Curl", false, "Stretch at bottom"),
        ),
        MuscleGroup.Triceps to listOf(
            Movement("Skull Crushers", true, "Keep elbows fixed"),
            Movement("Close-Grip Bench Press", true),
            Movement("Cable Pushdown", false),
        ),
        MuscleGroup.Quads to listOf(
            Movement("Back Squat", true, "Break parallel if mobility allows"),
            Movement("Leg Press", false),
            Movement("Hack Squat", false),
            Movement("Walking Lunge", false),
        ),
        MuscleGroup.Hamstrings to listOf(
            Movement("Romanian Deadlift", true, "Maintain neutral spine throughout"),
            Movement("Leg Curl", false),
            Movement("Nordic Curl", false, "Progress slowly — high injury risk if rushed"),
            Movement("Good Morning", false),
        ),
        MuscleGroup.Glutes to listOf(
            Movement("Hip Thrust", true, "Full hip extension at top"),
            Movement("Bulgarian Split Squat", true),
            Movement("Cable Kickback", false),
        ),
        MuscleGroup.Calves to listOf(
            Movement("Standing Calf Raise", true, "Full stretch at bottom"),
            Movement("Seated Calf Raise", false),
        ),
        MuscleGroup.Core to listOf(
            Movement("Dead Bug", true, "Lower back stays flat throughout"),
            Movement("Plank", false),
            Movement("Russian Twist", false),
            Movement("Hanging Leg Raise", false),
            Movement("Cable Crunch", false),
        ),
    )

    /** Movement names for one muscle group — the pick list for the live logger. */
    fun movements(group: MuscleGroup): List<String> = (db[group] ?: emptyList()).map { it.name }

    private fun buildExercises(muscleGroups: List<MuscleGroup>, intensity: Intensity): List<ExerciseSuggestion> {
        val exercisesPerGroup = if (muscleGroups.size <= 2) 3 else 2
        val result = mutableListOf<ExerciseSuggestion>()
        for (group in muscleGroups) {
            val selected = (db[group] ?: emptyList()).take(exercisesPerGroup)
            selected.forEachIndexed { i, movement ->
                val isFirst = i == 0
                result.add(
                    ExerciseSuggestion(
                        name = movement.name,
                        muscleGroup = group,
                        sets = if (isFirst) intensity.primarySets else intensity.accessorySets,
                        repsRange = if (isFirst) intensity.primaryReps else intensity.accessoryReps,
                        rest = if (isFirst) intensity.primaryRest else intensity.accessoryRest,
                        notes = if (isFirst) movement.note else null,
                    )
                )
            }
        }
        return result
    }

    private fun estimateDuration(exercises: List<ExerciseSuggestion>): Int {
        val totalSets = exercises.sumOf { it.sets }
        return (10 + totalSets * 3).coerceIn(30, 90) // 10 min warmup + ~3 min/set
    }

    private fun buildTitle(muscleGroups: List<MuscleGroup>): String = when (muscleGroups.size) {
        0 -> "Gym Session"
        1 -> "${muscleGroups[0].raw} Day"
        2 -> "${muscleGroups[0].raw} + ${muscleGroups[1].raw}"
        else -> {
            val hasPush = muscleGroups.any { it in listOf(MuscleGroup.Chest, MuscleGroup.Shoulders, MuscleGroup.Triceps) }
            val hasPull = muscleGroups.any { it in listOf(MuscleGroup.Back, MuscleGroup.Biceps) }
            val hasLegs = muscleGroups.any { it in listOf(MuscleGroup.Quads, MuscleGroup.Hamstrings, MuscleGroup.Glutes, MuscleGroup.Calves) }
            when {
                hasPush && !hasPull && !hasLegs -> "Push Day"
                !hasPush && hasPull && !hasLegs -> "Pull Day"
                !hasPush && !hasPull && hasLegs -> "Leg Day"
                else -> "Full Body"
            }
        }
    }

    // MARK: - Recovery warnings

    private fun buildRecoveryWarnings(
        muscleGroups: List<MuscleGroup>,
        recentActivities: List<GarminActivity>,
    ): List<String> {
        val lastStrength = recentActivities
            .filter { it.type == GarminActivityType.StrengthTraining }
            .maxByOrNull { it.startTime } ?: return emptyList()

        val hoursAgo = lastStrength.hoursAgo
        return muscleGroups.mapNotNull { group ->
            if (hoursAgo >= group.recoveryHours) return@mapNotNull null
            val remaining = (group.recoveryHours - hoursAgo).toInt()
            "${group.raw} trained ${hoursAgo.toInt()}h ago — ~${remaining}h until fully recovered. Reduce volume on these movements."
        }
    }

    // MARK: - Rationale

    private fun buildRationale(
        muscleGroups: List<MuscleGroup>,
        readiness: DailyReadiness,
        warningCount: Int,
    ): String {
        val groups = muscleGroups.take(3).joinToString(", ") { it.raw }
        var text = when (readiness.status) {
            DailyReadiness.Status.Peak ->
                "Readiness is at ${readiness.score}/100 — an ideal window for heavy work. The $groups session is loaded for strength adaptation: compound lifts first, heavier weights, longer rest intervals."
            DailyReadiness.Status.High ->
                "Readiness at ${readiness.score}/100 supports solid strength work. Stick to your working weights and focus on controlled reps — no reason to max out today, but no reason to hold back either."
            DailyReadiness.Status.Moderate ->
                "With readiness at ${readiness.score}/100, the session is dialled back to moderate intensity. Prioritise technique and mind-muscle connection. The volume is enough to maintain strength without adding recovery debt."
            DailyReadiness.Status.Low, DailyReadiness.Status.Rest ->
                "Readiness is low (${readiness.score}/100). If you train at all, keep loads very light — this is maintenance work only. Mobility or a walk may be a better investment of today's energy."
        }
        if (warningCount > 0) {
            text += " Recovery warnings are noted above — treat those muscle groups with care."
        }
        return text
    }
}
