package app.northax.domain.model

import kotlinx.serialization.Serializable

/**
 * A data source that can report wellness metrics. `intervals` already
 * aggregates Garmin/Strava upstream; `manual` is user-entered values.
 * (HealthKit exists in the iOS app only; Android ranks intervals vs manual.)
 */
@Serializable
enum class MetricSource(val raw: String) {
    Intervals("intervals"),
    Healthkit("healthkit"),
    Manual("manual");

    val displayName: String
        get() = when (this) {
            Intervals -> "intervals.icu"
            Healthkit -> "Apple Health"
            Manual -> "Manual entry"
        }

    companion object {
        fun fromRaw(raw: String): MetricSource? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * Metrics that more than one source can report, so they need conflict
 * resolution. Training load (CTL/ATL) is intervals-only and intentionally absent.
 */
enum class MergeableMetric(val raw: String) {
    Hrv("hrv"),
    RestingHR("restingHR"),
    Sleep("sleep"),
    BodyWeight("bodyWeight");

    val displayName: String
        get() = when (this) {
            Hrv -> "Heart Rate Variability"
            RestingHR -> "Resting Heart Rate"
            Sleep -> "Sleep"
            BodyWeight -> "Body Weight"
        }

    /** Sources that can actually produce this metric on Android. */
    val candidateSources: List<MetricSource>
        get() = when (this) {
            Hrv, RestingHR, Sleep -> listOf(MetricSource.Intervals, MetricSource.Manual)
            BodyWeight -> listOf(MetricSource.Manual) // intervals doesn't carry weight
        }
}

/**
 * Per-metric ordered source preference (highest first). The first source that
 * has a value for a given day wins.
 */
@Serializable
data class MetricSourcePriority(
    /** [MergeableMetric.raw] → ordered list of sources. */
    val order: Map<String, List<MetricSource>>,
) {
    fun sources(metric: MergeableMetric): List<MetricSource> =
        order[metric.raw] ?: metric.candidateSources

    /** Promote `source` to the top of `metric`'s ranking, keeping the rest in order. */
    fun settingPrimary(source: MetricSource, metric: MergeableMetric): MetricSourcePriority {
        val list = sources(metric).toMutableList()
        list.remove(source)
        list.add(0, source)
        return copy(order = order + (metric.raw to list))
    }

    /** `metric.raw -> [source.raw]`, for syncing to the backend. */
    val wire: Map<String, List<String>>
        get() = order.mapValues { (_, sources) -> sources.map { it.raw } }

    companion object {
        /** Defaults to each metric's candidate order, i.e. intervals.icu wins. */
        val default: MetricSourcePriority
            get() = MetricSourcePriority(MergeableMetric.entries.associate { it.raw to it.candidateSources })

        /** Rebuild from the wire form, filling any missing metric with defaults. */
        fun fromWire(wire: Map<String, List<String>>): MetricSourcePriority {
            val o = mutableMapOf<String, List<MetricSource>>()
            for ((metric, sources) in wire) {
                o[metric] = sources.mapNotNull { MetricSource.fromRaw(it) }
            }
            for (m in MergeableMetric.entries) {
                if (o[m.raw] == null) o[m.raw] = m.candidateSources
            }
            return MetricSourcePriority(o)
        }
    }
}
