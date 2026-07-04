package app.northax.domain.model

import java.time.LocalDate
import kotlin.math.sin

data class TrainingMetrics(
    // HRV
    val hrv: Double,            // ms, today's morning reading
    val hrvBaseline: Double,    // 7-day rolling average
    val hrvTrend: List<Double>, // last 7 days (oldest → newest)

    // Heart Rate
    val restingHR: Int,
    val restingHRBaseline: Int,

    // Sleep
    val sleepDuration: Double, // hours
    val sleepScore: Int,       // 0–100
    val remSleep: Double,      // hours
    val deepSleep: Double,     // hours
    val sleepDebt: Double,     // cumulative hours shortfall

    // Training Load (Banister impulse–response model)
    val acuteLoad: Double,        // 7-day ATL
    val chronicLoad: Double,      // 42-day CTL
    val todayLoad: Double,        // today's planned training stress
    val weeklyLoadChange: Double, // fraction vs previous week

    // Optional
    val bodyWeight: Double? = null, // kg

    // Daily history for the detail graphs (oldest→newest, aligned with `trendDates`).
    val trendDates: List<LocalDate> = emptyList(),
    val hrvSeries: List<Double> = emptyList(),
    val restingHRSeries: List<Double> = emptyList(),
    val sleepSeries: List<Double> = emptyList(),
    val tsbSeries: List<Double> = emptyList(), // Fitness − Fatigue
    val ctlSeries: List<Double> = emptyList(), // fitness (chronic load)
    val atlSeries: List<Double> = emptyList(), // fatigue (acute load)
    val vo2maxSeries: List<Double> = emptyList(),
    val vo2max: Double? = null, // latest estimate

    /** Which source won each mergeable metric (keyed by [MergeableMetric.raw]). */
    val provenance: Map<String, MetricSource> = emptyMap(),
) {
    fun source(metric: MergeableMetric): MetricSource? = provenance[metric.raw]

    // Derived
    val trainingBalance: Double get() = chronicLoad - acuteLoad // positive = fresh
    val trainingRatio: Double get() = acuteLoad / maxOf(1.0, chronicLoad)
    val hrvChange: Double get() = (hrv - hrvBaseline) / maxOf(1.0, hrvBaseline)
    val restingHRChange: Int get() = restingHR - restingHRBaseline

    companion object {
        // MARK: - Mock data (debug sessions only)

        val mockFresh: TrainingMetrics
            get() = TrainingMetrics(
                hrv = 58.0, hrvBaseline = 54.0,
                hrvTrend = listOf(51.0, 49.0, 52.0, 54.0, 53.0, 56.0, 58.0),
                restingHR = 46, restingHRBaseline = 47,
                sleepDuration = 7.5, sleepScore = 84,
                remSleep = 1.8, deepSleep = 1.4, sleepDebt = 0.3,
                acuteLoad = 68.0, chronicLoad = 72.0,
                todayLoad = 0.0, weeklyLoadChange = 0.08,
                bodyWeight = 78.2,
                trendDates = mockDates(),
                hrvSeries = ramp(49.0, 58.0, wiggle = 2.5),
                restingHRSeries = ramp(49.0, 46.0, wiggle = 1.0),
                sleepSeries = ramp(6.6, 7.5, wiggle = 0.45),
                tsbSeries = ramp(-3.0, 4.0, wiggle = 3.0),
                provenance = mapOf(
                    MergeableMetric.Hrv.raw to MetricSource.Intervals,
                    MergeableMetric.RestingHR.raw to MetricSource.Intervals,
                    MergeableMetric.Sleep.raw to MetricSource.Intervals,
                ),
            )

        val mockFatigued: TrainingMetrics
            get() = TrainingMetrics(
                hrv = 42.0, hrvBaseline = 54.0,
                hrvTrend = listOf(54.0, 53.0, 51.0, 48.0, 45.0, 43.0, 42.0),
                restingHR = 54, restingHRBaseline = 47,
                sleepDuration = 5.8, sleepScore = 58,
                remSleep = 1.0, deepSleep = 0.8, sleepDebt = 3.2,
                acuteLoad = 98.0, chronicLoad = 72.0,
                todayLoad = 0.0, weeklyLoadChange = 0.28,
                bodyWeight = 78.8,
                trendDates = mockDates(),
                hrvSeries = ramp(55.0, 42.0, wiggle = 2.5),
                restingHRSeries = ramp(47.0, 54.0, wiggle = 1.0),
                sleepSeries = ramp(7.2, 5.8, wiggle = 0.5),
                tsbSeries = ramp(3.0, -26.0, wiggle = 3.5),
                provenance = mapOf(
                    MergeableMetric.Hrv.raw to MetricSource.Intervals,
                    MergeableMetric.RestingHR.raw to MetricSource.Intervals,
                    MergeableMetric.Sleep.raw to MetricSource.Intervals,
                ),
            )

        /** Last `count` calendar days, oldest→newest, for mock graph series. */
        fun mockDates(count: Int = 30): List<LocalDate> {
            val today = LocalDate.now()
            return (count - 1 downTo 0).map { today.minusDays(it.toLong()) }
        }

        /** Believable synthetic series: a linear drift with a gentle wiggle. */
        private fun ramp(from: Double, to: Double, count: Int = 30, wiggle: Double): List<Double> =
            (0 until count).map { i ->
                val t = i.toDouble() / (count - 1)
                from + (to - from) * t + sin(i * 1.3) * wiggle
            }
    }
}
