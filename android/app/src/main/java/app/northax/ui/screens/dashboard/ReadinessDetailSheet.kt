package app.northax.ui.screens.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.automirrored.filled.TrendingDown
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.domain.model.DailyReadiness
import app.northax.domain.model.MetricInsight
import app.northax.store.AthleteStore
import app.northax.ui.components.AxCard
import app.northax.ui.components.AxPill
import app.northax.ui.components.AxSheet
import app.northax.ui.components.ContributorMeter
import app.northax.ui.components.MetricLineChart
import app.northax.ui.components.FitnessFatigueChart
import app.northax.ui.components.SectionLabel
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import java.util.Locale

/** Full readiness breakdown modal — the ReadinessDetailView port. */
@Composable
fun ReadinessDetailSheet(store: AthleteStore, readiness: DailyReadiness, onDismiss: () -> Unit) {
    val metrics = store.metrics

    AxSheet(onDismiss = onDismiss, title = "Readiness") {
        Column(
            verticalArrangement = Arrangement.spacedBy(20.dp),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            // Score header
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                ReadinessRing(score = readiness.score, status = readiness.status, size = 190.dp)
                AxPill(text = readiness.status.raw, color = readiness.status.color)
            }

            // Explanation
            AxCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        readiness.displayVerdict,
                        style = axDisplay(19, FontWeight.ExtraBold),
                        color = Ax.Primary,
                    )
                    Text(
                        readiness.aiNarrative ?: readiness.explanation,
                        style = axDisplay(13.5),
                        color = Ax.Secondary,
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Ax.Accent.copy(alpha = 0.08f))
                            .padding(12.dp),
                    ) {
                        Icon(Icons.Filled.Psychology, contentDescription = null, tint = Ax.Accent, modifier = Modifier.size(18.dp))
                        Text(readiness.coachingNote, style = axDisplay(13), color = Ax.Primary.copy(alpha = 0.85f))
                    }
                }
            }

            // Contributors
            AxCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionLabel("Contributors")
                    ContributorMeter("HRV", "${readiness.hrvScore}", readiness.hrvScore, Ax.Green)
                    ContributorMeter("Sleep", "${readiness.sleepScore}", readiness.sleepScore, Ax.Purple)
                    ContributorMeter("Load", "${readiness.loadScore}", readiness.loadScore, Ax.Accent)
                }
            }

            // Contributing conditions
            if (readiness.keyInsights.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SectionLabel("Contributing conditions")
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                    ) {
                        for (insight in readiness.keyInsights) {
                            MetricInsightCard(insight)
                        }
                    }
                }
            }

            // Metric trends
            if (metrics != null) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    SectionLabel("Metric trends")

                    if (metrics.ctlSeries.size > 1 && metrics.atlSeries.size > 1) {
                        AxCard(modifier = Modifier.fillMaxWidth()) {
                            FitnessFatigueChart(
                                ctl = metrics.ctlSeries, atl = metrics.atlSeries,
                                dates = metrics.trendDates,
                            )
                        }
                    }

                    TrendCard("HRV", metrics.hrvSeries, metrics.trendDates, Ax.Green) {
                        "${it.toInt()} ms"
                    }
                    TrendCard("Resting HR", metrics.restingHRSeries, metrics.trendDates, Ax.Red) {
                        "${it.toInt()} bpm"
                    }
                    TrendCard("Sleep", metrics.sleepSeries, metrics.trendDates, Ax.Purple) {
                        String.format(Locale.US, "%.1f h", it)
                    }
                    TrendCard("VO2max", metrics.vo2maxSeries, metrics.trendDates, Ax.Blue) {
                        String.format(Locale.US, "%.1f", it)
                    }
                }
            }
        }
    }
}

@Composable
private fun TrendCard(
    title: String,
    series: List<Double>,
    dates: List<java.time.LocalDate>,
    color: androidx.compose.ui.graphics.Color,
    format: (Double) -> String,
) {
    if (series.size < 2) return
    AxCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            SectionLabel(title)
            MetricLineChart(
                values = series,
                color = color,
                dates = dates.takeLast(series.size),
                formatValue = format,
                interactive = true,
                height = 130.dp,
            )
        }
    }
}

/** Compact metric chip for the horizontal insights scroll — MetricInsightCard port. */
@Composable
fun MetricInsightCard(insight: MetricInsight) {
    val trendColor = when (insight.trend) {
        MetricInsight.Trend.Up -> Ax.Green
        MetricInsight.Trend.Down -> Ax.Amber
        MetricInsight.Trend.Warning -> Ax.Red
        MetricInsight.Trend.Neutral -> Ax.Secondary
    }
    val trendIcon = when (insight.trend) {
        MetricInsight.Trend.Up -> Icons.AutoMirrored.Filled.TrendingUp
        MetricInsight.Trend.Down -> Icons.AutoMirrored.Filled.TrendingDown
        MetricInsight.Trend.Warning -> Icons.Filled.Warning
        MetricInsight.Trend.Neutral -> Icons.Filled.Remove
    }

    AxCard(modifier = Modifier.width(150.dp), padding = 14.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    insight.label.uppercase(),
                    style = axMono(9, FontWeight.SemiBold).tracked(1.0),
                    color = Ax.Tertiary,
                )
                Spacer(Modifier.weight(1f))
                Icon(trendIcon, contentDescription = null, tint = trendColor, modifier = Modifier.size(13.dp))
            }
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(insight.value, style = axDisplay(20, FontWeight.Bold), color = Ax.Primary)
                Text(
                    insight.unit.uppercase(),
                    style = axMono(9),
                    color = Ax.Tertiary,
                    modifier = Modifier.padding(bottom = 3.dp),
                )
            }
            Text(insight.explanation, style = axDisplay(11.5, FontWeight.SemiBold), color = trendColor)
            Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))
            Text(insight.context, style = axDisplay(11), color = Ax.Secondary)
        }
    }
}
