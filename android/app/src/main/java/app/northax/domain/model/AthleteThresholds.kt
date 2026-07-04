package app.northax.domain.model

enum class PaceUnit(val raw: String) {
    Km("km"), Mile("mile");

    companion object {
        fun fromRaw(raw: String): PaceUnit? = entries.firstOrNull { it.raw == raw }
    }
}

enum class PoolUnit(val raw: String) {
    Pool25m("pool25m"), Pool50m("pool50m"), OpenWater("openWater");

    companion object {
        fun fromRaw(raw: String): PoolUnit? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * Athlete physiological thresholds used at render time to compute training
 * zones (ZoneMath consumes these; this model just carries the data).
 */
data class AthleteThresholds(
    val ftpWatts: Int? = null,
    val thresholdHr: Int? = null,
    val maxHr: Int? = null,
    val runThresholdPaceSecPerKm: Int? = null,
    val paceUnit: PaceUnit = PaceUnit.Km,
    val swimThresholdPaceSecPer100m: Int? = null,
    val poolUnit: PoolUnit = PoolUnit.Pool25m,
)
