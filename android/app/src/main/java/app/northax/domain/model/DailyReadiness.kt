package app.northax.domain.model

import androidx.compose.ui.graphics.Color
import app.northax.ui.theme.Ax
import java.util.UUID

data class MetricInsight(
    val id: String = UUID.randomUUID().toString(),
    val label: String,
    val value: String,
    val unit: String,
    val trend: Trend,
    val explanation: String,
    val context: String,
) {
    enum class Trend {
        Up, Down, Neutral, Warning;

        val isPositive: Boolean
            get() = when (this) {
                Up, Neutral -> true
                Down, Warning -> false
            }

        companion object {
            fun fromWire(wire: String): Trend = when (wire) {
                "up" -> Up
                "down" -> Down
                "warning" -> Warning
                else -> Neutral
            }
        }
    }
}

data class DailyReadiness(
    val score: Int, // 0–100
    val status: Status,
    val explanation: String,
    val coachingNote: String,

    val hrvScore: Int,
    val sleepScore: Int,
    val loadScore: Int,
    val recoveryScore: Int,

    val suggestedDomain: TrainingDomain,
    val suggestedSessionTitle: String,
    val suggestedDuration: Int, // minutes
    val suggestedIntensityLabel: String,
    val suggestedIntensityDescription: String,

    val keyInsights: List<MetricInsight>,

    /** One-line server verdict. Falls back to the local `status.verdict`. */
    val serverVerdict: String? = null,
    /** Natural-language explanation from the AI layer, when available. */
    val aiNarrative: String? = null,
) {
    enum class Status(val raw: String) {
        Peak("Peak"),
        High("High"),
        Moderate("Moderate"),
        Low("Low"),
        Rest("Rest Day");

        val verdict: String
            get() = when (this) {
                Peak -> "Train hard today."
                High -> "Good day to train."
                Moderate -> "Train with caution."
                Low -> "Light activity only."
                Rest -> "Rest and recover."
            }

        /** Zone color for the readiness gauge, pills, and status text. */
        val color: Color
            get() = when (this) {
                Peak -> Ax.Accent
                High -> Ax.Green
                Moderate -> Ax.Amber
                Low -> Ax.Red
                Rest -> Ax.Tertiary
            }

        companion object {
            fun fromRaw(raw: String): Status? = entries.firstOrNull { it.raw == raw }
        }
    }

    val displayVerdict: String get() = serverVerdict ?: status.verdict
}
