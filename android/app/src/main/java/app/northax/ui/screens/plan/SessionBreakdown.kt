package app.northax.ui.screens.plan

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.data.remote.dto.StructuredWorkoutDto
import app.northax.domain.model.AthleteThresholds
import app.northax.domain.model.ExerciseSuggestion
import app.northax.domain.model.TrainingDomain
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked

/**
 * Workout structure: exercise list for strength, effort graph for endurance —
 * the SessionBreakdownView port.
 */
@Composable
fun SessionBreakdown(
    domain: TrainingDomain,
    workout: StructuredWorkoutDto?,
    exercises: List<ExerciseSuggestion>?,
    thresholds: AthleteThresholds,
    cyclingTarget: String,
) {
    if (!exercises.isNullOrEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            exercises.forEachIndexed { i, exercise ->
                if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        exercise.muscleGroup.raw.uppercase(),
                        style = axMono(9, FontWeight.SemiBold).tracked(1.0),
                        color = exercise.muscleGroup.color,
                    )
                    Row(modifier = Modifier.fillMaxWidth()) {
                        Text(exercise.name, style = axDisplay(13, FontWeight.Bold), color = Ax.Primary)
                        Spacer(Modifier.weight(1f))
                        Text(exercise.setDisplay, style = axMono(11, FontWeight.SemiBold), color = Ax.Secondary)
                    }
                    Text("Rest ${exercise.rest}", style = axMono(10), color = Ax.Tertiary)
                    exercise.notes?.let {
                        Text(it, style = axDisplay(12), color = Ax.Secondary)
                    }
                }
            }
        }
    } else if (workout != null && workout.targetMode != "none") {
        WorkoutEffortGraph(
            workout = workout,
            sport = domain,
            thresholds = thresholds,
            cyclingTarget = cyclingTarget,
        )
    }
}
