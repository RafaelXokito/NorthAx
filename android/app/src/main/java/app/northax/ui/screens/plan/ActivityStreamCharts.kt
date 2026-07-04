package app.northax.ui.screens.plan

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.domain.engine.ZoneMath
import app.northax.domain.engine.ZoneMode
import app.northax.domain.model.ActivityStreams
import app.northax.domain.model.AthleteThresholds
import app.northax.domain.model.TrainingDomain
import app.northax.ui.components.MetricLineChart
import app.northax.ui.components.ZoneBand
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Time-series charts for a completed activity: heart rate (with HR zone
 * bands), power (with FTP reference), speed, elevation, and cadence — the
 * ActivityStreamChart port. Motion sports show everything; strength shows
 * heart rate only.
 */
@Composable
fun ActivityStreamCharts(
    streams: ActivityStreams,
    domain: TrainingDomain,
    thresholds: AthleteThresholds,
) {
    val isMotion = domain in listOf(
        TrainingDomain.Cycling, TrainingDomain.Running,
        TrainingDomain.Swimming, TrainingDomain.Triathlon,
    )

    Column(verticalArrangement = Arrangement.spacedBy(20.dp), modifier = Modifier.fillMaxWidth()) {
        if (streams.heartRate.size > 1) {
            val hrBands = (1..5).mapNotNull { z ->
                ZoneMath.range(z, ZoneMode.Hr, domain, thresholds)?.let { r ->
                    ZoneBand(r.lower ?: 0.0, r.upper ?: (r.lower ?: 0.0) * 1.1, Ax.zone(z))
                }
            }
            StreamChart(
                title = "Heart rate", values = streams.heartRate, color = Ax.Red, unit = "bpm",
                durationSeconds = streams.durationSeconds, zoneBands = hrBands,
            )
        }

        if (isMotion) {
            if (streams.power.size > 1) {
                StreamChart(
                    title = "Power", values = streams.power, color = Ax.Cycling, unit = "W",
                    durationSeconds = streams.durationSeconds,
                    referenceLine = thresholds.ftpWatts?.toDouble(),
                )
            }
            if (streams.velocity.size > 1) {
                StreamChart(
                    title = "Speed", values = streams.speedKmh, color = Ax.Blue, unit = "km/h",
                    durationSeconds = streams.durationSeconds,
                    format = { String.format(Locale.US, "%.1f", it) },
                )
            }
            if (streams.altitude.size > 1) {
                StreamChart(
                    title = "Elevation", values = streams.altitude, color = Ax.Green, unit = "m",
                    durationSeconds = streams.durationSeconds,
                )
            }
            if (streams.cadence.size > 1) {
                StreamChart(
                    title = "Cadence", values = streams.cadence, color = Ax.Purple, unit = "rpm",
                    durationSeconds = streams.durationSeconds,
                )
            }
        }
    }
}

@Composable
private fun StreamChart(
    title: String,
    values: List<Double>,
    color: Color,
    unit: String,
    durationSeconds: Double,
    zoneBands: List<ZoneBand> = emptyList(),
    referenceLine: Double? = null,
    format: (Double) -> String = { "${it.roundToInt()}" },
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "${title.uppercase()} · ${format(values.min())}–${format(values.max())} ${unit.uppercase()}",
            style = axMono(9, FontWeight.SemiBold).tracked(1.0),
            color = Ax.Tertiary,
        )
        MetricLineChart(
            values = values,
            color = color,
            height = 110.dp,
            formatValue = format,
            interactive = true,
            zoneBands = zoneBands,
            referenceLine = referenceLine,
            showAverage = true,
            xLabels = "0:00" to formatElapsed(durationSeconds),
        )
    }
}

private fun formatElapsed(seconds: Double): String {
    val total = seconds.roundToInt()
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
    else String.format(Locale.US, "%d:%02d", m, s)
}
