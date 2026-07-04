package app.northax.ui.screens.metrics

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.SensorsOff
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.domain.model.MetricSource
import app.northax.domain.model.TrainingMetrics
import app.northax.store.AppTab
import app.northax.store.AthleteStore
import app.northax.ui.components.AxCard
import app.northax.ui.components.AxPill
import app.northax.ui.components.AxSegmented
import app.northax.ui.components.FitnessFatigueChart
import app.northax.ui.components.MetricLineChart
import app.northax.ui.components.NoDataView
import app.northax.ui.components.SectionLabel
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import java.time.LocalDate
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** One metric's full description for the cards + detail sheet. */
data class MetricDetail(
    val id: String,
    val title: String,
    val icon: ImageVector,
    val color: Color,
    val value: String,
    val unit: String,
    val statusLabel: String,
    val statusColor: Color,
    val delta: String?,
    val description: String,
    val rows: List<Pair<String, String>>,
    val strip: List<Triple<String, String, Color?>>,
    val series: List<Double>,
    val dates: List<LocalDate>,
    val format: (Double) -> String,
    val sourceLabel: String?,
)

/** Training trends — the MetricsView port. */
@Composable
fun MetricsScreen(store: AthleteStore) {
    var selectedDetailId by rememberSaveable { mutableStateOf<String?>(null) }
    var showManualEntry by rememberSaveable { mutableStateOf(false) }

    val metrics = store.metrics
    val details = metrics?.let { buildDetails(it) } ?: emptyList()

    LazyColumn(
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxSize().background(Ax.Background),
    ) {
        item(key = "title") {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text("Metrics", style = axDisplay(32, FontWeight.ExtraBold).tracked(-0.96), color = Ax.Primary)
                Spacer(Modifier.weight(1f))
                Icon(
                    imageVector = Icons.Filled.Edit,
                    contentDescription = "Manual entry",
                    tint = Ax.Accent,
                    modifier = Modifier.size(22.dp).clickable { showManualEntry = true },
                )
            }
        }

        if (metrics == null) {
            item(key = "empty") {
                NoDataView(
                    icon = Icons.Filled.SensorsOff,
                    title = "No metrics yet",
                    message = "Connect intervals.icu or Strava — or log values manually — and your wellness trends will build up here.",
                    ctaLabel = "Enable integrations",
                    onCta = { store.selectedTab = AppTab.Settings },
                )
            }
        } else {
            // Fitness & fatigue
            if (metrics.ctlSeries.size > 1 && metrics.atlSeries.size > 1) {
                item(key = "ff-label") { SectionLabel("Fitness & fatigue") }
                item(key = "ff-chart") {
                    AxCard(modifier = Modifier.fillMaxWidth()) {
                        FitnessFatigueChart(
                            ctl = metrics.ctlSeries,
                            atl = metrics.atlSeries,
                            dates = metrics.trendDates,
                        )
                    }
                }
            }

            items(count = details.size, key = { details[it].id }) { i ->
                MetricCard(detail = details[i]) { selectedDetailId = details[i].id }
            }
        }

        item(key = "bottom") { Spacer(Modifier.height(8.dp)) }
    }

    selectedDetailId?.let { id ->
        details.firstOrNull { it.id == id }?.let { detail ->
            MetricDetailSheet(detail = detail, onDismiss = { selectedDetailId = null })
        }
    }

    if (showManualEntry) {
        ManualEntrySheet(store = store, onDismiss = { showManualEntry = false })
    }
}

@Composable
private fun MetricCard(detail: MetricDetail, onClick: () -> Unit) {
    var range by rememberSaveable(detail.id) { mutableStateOf(30) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionLabel(detail.title)
        AxCard(modifier = Modifier.fillMaxWidth().clickable(onClick = onClick), padding = 20.dp) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                MetricHeader(detail)

                if (detail.series.size > 1) {
                    AxSegmented(
                        options = listOf(7 to "7d", 30 to "30d", 90 to "90d"),
                        selection = range,
                        onSelect = { range = it },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    val n = minOf(range, detail.series.size)
                    MetricLineChart(
                        values = detail.series.takeLast(n),
                        color = detail.color,
                        dates = detail.dates.takeLast(n),
                        formatValue = detail.format,
                        height = 150.dp,
                    )
                }

                if (detail.strip.isNotEmpty()) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))
                    Row(modifier = Modifier.fillMaxWidth()) {
                        for ((label, value, color) in detail.strip) {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(3.dp),
                                modifier = Modifier.weight(1f),
                            ) {
                                Text(
                                    label.uppercase(),
                                    style = axMono(8, FontWeight.SemiBold).tracked(1.0),
                                    color = Ax.Tertiary,
                                )
                                Text(
                                    value,
                                    style = axMono(12, FontWeight.SemiBold),
                                    color = color ?: Ax.Primary,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun MetricHeader(detail: MetricDetail) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(detail.icon, contentDescription = null, tint = detail.color, modifier = Modifier.size(22.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(detail.value, style = axDisplay(26, FontWeight.ExtraBold), color = Ax.Primary)
                Text(
                    detail.unit.uppercase(),
                    style = axMono(10),
                    color = Ax.Tertiary,
                    modifier = Modifier.padding(bottom = 4.dp),
                )
                detail.delta?.let {
                    Text(
                        it,
                        style = axMono(11, FontWeight.SemiBold),
                        color = detail.statusColor,
                        modifier = Modifier.padding(bottom = 4.dp, start = 4.dp),
                    )
                }
            }
        }
        AxPill(text = detail.statusLabel, color = detail.statusColor)
    }
}

private fun fmt1(v: Double) = String.format(Locale.US, "%.1f", v)

private fun buildDetails(m: TrainingMetrics): List<MetricDetail> {
    val details = mutableListOf<MetricDetail>()

    fun sourceLabel(metric: app.northax.domain.model.MergeableMetric): String? =
        m.source(metric)?.displayName

    // HRV
    run {
        val (label, color) = when {
            m.hrvChange > 0.03 -> "Strong recovery" to Ax.Green
            m.hrvChange < -0.05 -> "Suppressed" to Ax.Red
            else -> "Normal" to Ax.Secondary
        }
        val deltaPct = (m.hrvChange * 100).roundToInt()
        details.add(
            MetricDetail(
                id = "hrv",
                title = "Heart Rate Variability",
                icon = Icons.Filled.MonitorHeart,
                color = Ax.Green,
                value = "${m.hrv.toInt()}",
                unit = "ms",
                statusLabel = label,
                statusColor = color,
                delta = "${if (deltaPct >= 0) "+" else ""}$deltaPct%",
                description = "HRV reflects your autonomic nervous system's recovery state. Higher-than-baseline readings indicate readiness for load; sustained suppression signals accumulated stress.",
                rows = listOf(
                    "Today" to "${m.hrv.toInt()} ms",
                    "Baseline (7d)" to "${m.hrvBaseline.toInt()} ms",
                    "Change vs baseline" to "${if (deltaPct >= 0) "+" else ""}$deltaPct%",
                ),
                strip = listOf(
                    Triple("Today", "${m.hrv.toInt()}", null),
                    Triple("Base", "${m.hrvBaseline.toInt()}", null),
                    Triple("Change", "${if (deltaPct >= 0) "+" else ""}$deltaPct%", color),
                ),
                series = m.hrvSeries,
                dates = m.trendDates,
                format = { "${it.toInt()} ms" },
                sourceLabel = sourceLabel(app.northax.domain.model.MergeableMetric.Hrv),
            )
        )
    }

    // Sleep
    run {
        val (label, color) = when {
            m.sleepScore >= 80 -> "Well rested" to Ax.Green
            m.sleepScore >= 60 -> "Adequate" to Ax.Amber
            else -> "Insufficient" to Ax.Red
        }
        details.add(
            MetricDetail(
                id = "sleep",
                title = "Sleep",
                icon = Icons.Filled.Bedtime,
                color = Ax.Purple,
                value = fmt1(m.sleepDuration),
                unit = "hrs",
                statusLabel = label,
                statusColor = color,
                delta = null,
                description = "Sleep is when training adaptations consolidate. Duration, deep sleep, and REM together determine how much of yesterday's stress your body absorbed.",
                rows = listOf(
                    "Duration" to "${fmt1(m.sleepDuration)} h",
                    "Sleep score" to "${m.sleepScore}/100",
                    "Deep sleep" to "${fmt1(m.deepSleep)} h",
                    "REM sleep" to "${fmt1(m.remSleep)} h",
                    "Sleep debt" to "${fmt1(m.sleepDebt)} h",
                ),
                strip = listOf(
                    Triple("Score", "${m.sleepScore}", color),
                    Triple("Deep", fmt1(m.deepSleep), null),
                    Triple("REM", fmt1(m.remSleep), null),
                    Triple("Debt", fmt1(m.sleepDebt), null),
                ),
                series = m.sleepSeries,
                dates = m.trendDates,
                format = { String.format(Locale.US, "%.1f h", it) },
                sourceLabel = sourceLabel(app.northax.domain.model.MergeableMetric.Sleep),
            )
        )
    }

    // Training load (TSB)
    run {
        val tsb = m.trainingBalance
        val (label, color) = when {
            abs(tsb) < 10 -> "Balanced" to Ax.Green
            tsb < -15 -> "Fatigued" to Ax.Red
            tsb < 0 -> "Building" to Ax.Amber
            else -> "Fresh" to Ax.Blue
        }
        val changePct = (m.weeklyLoadChange * 100).roundToInt()
        details.add(
            MetricDetail(
                id = "load",
                title = "Training Load",
                icon = Icons.AutoMirrored.Filled.ShowChart,
                color = Ax.Accent,
                value = "${if (tsb >= 0) "+" else ""}${tsb.toInt()}",
                unit = "tsb",
                statusLabel = label,
                statusColor = color,
                delta = null,
                description = "Training Stress Balance = Fitness (CTL) − Fatigue (ATL). Positive means fresh; negative means carrying fatigue. The optimal performance window sits roughly between −10 and +5.",
                rows = listOf(
                    "Fitness (CTL)" to "${m.chronicLoad.toInt()}",
                    "Fatigue (ATL)" to "${m.acuteLoad.toInt()}",
                    "Balance (TSB)" to "${if (tsb >= 0) "+" else ""}${tsb.toInt()}",
                    "Weekly change" to "${if (changePct >= 0) "+" else ""}$changePct%",
                ),
                strip = listOf(
                    Triple("CTL", "${m.chronicLoad.toInt()}", null),
                    Triple("ATL", "${m.acuteLoad.toInt()}", null),
                    Triple("TSB", "${if (tsb >= 0) "+" else ""}${tsb.toInt()}", color),
                    Triple("Week", "${if (changePct >= 0) "+" else ""}$changePct%", null),
                ),
                series = m.tsbSeries,
                dates = m.trendDates,
                format = { "${it.roundToInt()}" },
                sourceLabel = "intervals.icu",
            )
        )
    }

    // Cardiovascular (Resting HR)
    run {
        val diff = m.restingHRChange
        val (label, color) = when {
            diff <= 0 -> "Efficient" to Ax.Green
            diff > 5 -> "Elevated" to Ax.Red
            else -> "Slightly elevated" to Ax.Amber
        }
        details.add(
            MetricDetail(
                id = "rhr",
                title = "Cardiovascular",
                icon = Icons.Filled.Favorite,
                color = Ax.Red,
                value = "${m.restingHR}",
                unit = "bpm",
                statusLabel = label,
                statusColor = color,
                delta = "${if (diff >= 0) "+" else ""}$diff",
                description = "Resting heart rate is a simple recovery barometer: a lower-than-baseline value signals an efficient cardiovascular system, while an elevated one means your heart is working harder to recover.",
                rows = listOf(
                    "Resting HR" to "${m.restingHR} bpm",
                    "Baseline" to "${m.restingHRBaseline} bpm",
                    "Change" to "${if (diff >= 0) "+" else ""}$diff bpm",
                ),
                strip = listOf(
                    Triple("Today", "${m.restingHR}", null),
                    Triple("Base", "${m.restingHRBaseline}", null),
                    Triple("Change", "${if (diff >= 0) "+" else ""}$diff", color),
                ),
                series = m.restingHRSeries,
                dates = m.trendDates,
                format = { "${it.toInt()} bpm" },
                sourceLabel = sourceLabel(app.northax.domain.model.MergeableMetric.RestingHR),
            )
        )
    }

    // VO2max
    m.vo2max?.let { vo2 ->
        details.add(
            MetricDetail(
                id = "vo2max",
                title = "VO2max",
                icon = Icons.Filled.Speed,
                color = Ax.Blue,
                value = fmt1(vo2),
                unit = "ml/kg/min",
                statusLabel = "Aerobic capacity",
                statusColor = Ax.Blue,
                delta = null,
                description = "Estimated maximal oxygen uptake — the ceiling of your aerobic engine. It moves slowly; consistent weeks of endurance work push it up.",
                rows = listOf("Latest estimate" to "${fmt1(vo2)} ml/kg/min"),
                strip = emptyList(),
                series = m.vo2maxSeries,
                dates = m.trendDates,
                format = { String.format(Locale.US, "%.1f", it) },
                sourceLabel = "intervals.icu",
            )
        )
    }

    return details
}
