package app.northax.domain.model

/**
 * A source that can report a completed activity. Raw values match the backend
 * `activities.source` column (`garmin` = imported via intervals.icu).
 */
enum class ActivitySource(val raw: String) {
    Intervals("garmin"),
    Strava("strava"),
    Manual("manual");

    val displayName: String
        get() = when (this) {
            Intervals -> "intervals.icu"
            Strava -> "Strava"
            Manual -> "Manual"
        }

    companion object {
        fun fromRaw(raw: String): ActivitySource? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * Ordered activity-source preference — highest priority first. When the same
 * workout is reported by more than one source, the higher-ranked one wins.
 */
data class ActivitySourcePriority(val order: List<ActivitySource>) {

    val primary: ActivitySource get() = order.firstOrNull() ?: ActivitySource.Intervals

    fun settingPrimary(source: ActivitySource): ActivitySourcePriority {
        val next = order.filter { it != source }.toMutableList()
        next.add(0, source)
        return ActivitySourcePriority(next)
    }

    val wire: List<String> get() = order.map { it.raw }

    companion object {
        val default = ActivitySourcePriority(ActivitySource.entries.toList())

        /** Build from the backend list, appending any missing sources so the
         *  order is always complete (and never empty). */
        fun fromWire(wire: List<String>): ActivitySourcePriority {
            val resolved = wire.mapNotNull { ActivitySource.fromRaw(it) }.toMutableList()
            for (source in ActivitySource.entries) {
                if (source !in resolved) resolved.add(source)
            }
            return ActivitySourcePriority(resolved.ifEmpty { ActivitySource.entries.toList() })
        }
    }
}
