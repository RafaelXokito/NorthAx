package app.northax.domain.model

import androidx.compose.ui.graphics.Color
import app.northax.ui.theme.Ax
import kotlinx.serialization.Serializable

@Serializable
enum class MuscleGroup(val raw: String) {
    Chest("Chest"),
    Back("Back"),
    Shoulders("Shoulders"),
    Biceps("Biceps"),
    Triceps("Triceps"),
    Quads("Quads"),
    Hamstrings("Hamstrings"),
    Glutes("Glutes"),
    Calves("Calves"),
    Core("Core");

    val color: Color
        get() = when (this) {
            Chest, Shoulders, Triceps -> Ax.StrengthSport // push
            Back, Biceps -> Ax.Blue                       // pull
            Quads, Hamstrings, Glutes, Calves -> Ax.Green // legs
            Core -> Ax.Purple                             // core
        }

    /** Minimum recovery time in hours before this muscle group can be trained again. */
    val recoveryHours: Int
        get() = when (this) {
            Quads, Hamstrings, Glutes -> 72
            Chest, Back -> 60
            Shoulders, Biceps, Triceps -> 48
            Calves, Core -> 36
        }

    companion object {
        fun fromRaw(raw: String): MuscleGroup? = entries.firstOrNull { it.raw == raw }
    }
}

// MARK: - Day split

@Serializable
data class DaySplit(
    val muscleGroups: List<MuscleGroup>,
    val isRestDay: Boolean,
) {
    val displayName: String
        get() = when {
            isRestDay || muscleGroups.isEmpty() -> "Rest"
            muscleGroups.size > 2 -> "${muscleGroups[0].raw} + ${muscleGroups.size - 1} more"
            else -> muscleGroups.joinToString(" + ") { it.raw }
        }

    companion object {
        val rest = DaySplit(emptyList(), isRestDay = true)
    }
}

// MARK: - Weekly split

@Serializable
data class WeeklyMuscleGroupSplit(
    /** Seven entries, index 0 = Monday, 6 = Sunday. */
    val days: List<DaySplit>,
) {
    init {
        require(days.size == 7) { "Weekly split must have 7 days" }
    }

    /** `isoWeekday`: 1=Mon … 7=Sun (java.time DayOfWeek value). */
    fun splitForIsoWeekday(isoWeekday: Int): DaySplit = days[isoWeekday - 1]

    companion object {
        val pushPullLegs: WeeklyMuscleGroupSplit
            get() = WeeklyMuscleGroupSplit(
                listOf(
                    DaySplit(listOf(MuscleGroup.Chest, MuscleGroup.Shoulders, MuscleGroup.Triceps), false), // Mon – Push
                    DaySplit(listOf(MuscleGroup.Back, MuscleGroup.Biceps), false),                          // Tue – Pull
                    DaySplit(listOf(MuscleGroup.Quads, MuscleGroup.Hamstrings, MuscleGroup.Glutes, MuscleGroup.Calves), false), // Wed – Legs
                    DaySplit.rest,                                                                          // Thu
                    DaySplit(listOf(MuscleGroup.Chest, MuscleGroup.Shoulders, MuscleGroup.Triceps), false), // Fri – Push
                    DaySplit(listOf(MuscleGroup.Back, MuscleGroup.Biceps), false),                          // Sat – Pull
                    DaySplit.rest,                                                                          // Sun
                )
            )

        val upperLower: WeeklyMuscleGroupSplit
            get() {
                val upper = listOf(MuscleGroup.Chest, MuscleGroup.Back, MuscleGroup.Shoulders, MuscleGroup.Biceps, MuscleGroup.Triceps)
                val lower = listOf(MuscleGroup.Quads, MuscleGroup.Hamstrings, MuscleGroup.Glutes, MuscleGroup.Calves)
                return WeeklyMuscleGroupSplit(
                    listOf(
                        DaySplit(upper, false), // Mon
                        DaySplit(lower, false), // Tue
                        DaySplit.rest,          // Wed
                        DaySplit(upper, false), // Thu
                        DaySplit(lower, false), // Fri
                        DaySplit.rest,          // Sat
                        DaySplit.rest,          // Sun
                    )
                )
            }

        val fullBody: WeeklyMuscleGroupSplit
            get() {
                val all = listOf(MuscleGroup.Chest, MuscleGroup.Back, MuscleGroup.Quads, MuscleGroup.Hamstrings, MuscleGroup.Shoulders, MuscleGroup.Core)
                return WeeklyMuscleGroupSplit(
                    listOf(
                        DaySplit(all, false),
                        DaySplit.rest,
                        DaySplit(all, false),
                        DaySplit.rest,
                        DaySplit(all, false),
                        DaySplit.rest,
                        DaySplit.rest,
                    )
                )
            }
    }
}
