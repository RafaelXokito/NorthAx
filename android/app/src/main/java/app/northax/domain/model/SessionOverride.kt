package app.northax.domain.model

/** A load-matched alternative session for one sport (feeds the deterministic
 *  switch-suggestion fallback). */
data class SessionOverride(
    val domain: TrainingDomain,
    val title: String,
    val duration: Int,
    val intensityLabel: String,
    val intensityDescription: String,
)
