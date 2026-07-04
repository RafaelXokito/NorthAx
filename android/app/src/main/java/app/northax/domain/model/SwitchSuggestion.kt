package app.northax.domain.model

import app.northax.data.remote.dto.StructuredWorkoutDto
import java.util.UUID

/**
 * An alternative session offered for a planned workout. AI-generated ones
 * carry a `rationale` and (usually) a structured breakdown; deterministic
 * fallbacks have `isAI == false` and no rationale.
 */
data class SwitchSuggestion(
    val id: String = UUID.randomUUID().toString(),
    val domain: TrainingDomain,
    val title: String,
    val duration: Int,
    val intensityLabel: String,
    val description: String,
    val rationale: String? = null,
    val estimatedLoad: Double? = null,
    val workout: StructuredWorkoutDto? = null,
    val exercises: List<ExerciseSuggestion>? = null,
    val isAI: Boolean,
)
