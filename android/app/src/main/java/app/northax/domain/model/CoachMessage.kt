package app.northax.domain.model

import java.time.Instant
import java.util.UUID

data class CoachMessage(
    val id: String = UUID.randomUUID().toString(),
    val content: String,
    val isCoach: Boolean,
    val timestamp: Instant,
) {
    companion object {
        val opening: CoachMessage
            get() = CoachMessage(
                content = "Good morning. Based on your data today, your readiness is looking strong — your HRV has returned above baseline and sleep quality was excellent.\n\nWhat would you like to know?",
                isCoach = true,
                timestamp = Instant.now(),
            )

        val quickQuestions: List<String> = listOf(
            "Should I train today?",
            "Why is my recovery low?",
            "Am I overtraining?",
            "What should I focus on?",
            "Explain my training load",
        )
    }
}
