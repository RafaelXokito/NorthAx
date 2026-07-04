package app.northax.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

// Hand-rolled charts shared by Metrics, Readiness detail, and activity data —
// Canvas ports of the iOS MetricChartView / FitnessFatigueChart.

/** Colored transparent horizontal band behind a chart line (e.g. HR zones). */
data class ZoneBand(val lower: Double, val upper: Double, val color: Color)

/**
 * Filled line chart with min/max Y labels, average dashed line, optional zone
 * bands + reference line, endpoint dot, and (optionally) touch scrubbing with
 * a floating callout.
 */
@Composable
fun MetricLineChart(
    values: List<Double>,
    color: Color,
    modifier: Modifier = Modifier,
    height: Dp = 150.dp,
    dates: List<LocalDate> = emptyList(),
    formatValue: (Double) -> String = { "%.0f".format(it) },
    interactive: Boolean = false,
    zoneBands: List<ZoneBand> = emptyList(),
    referenceLine: Double? = null,
    referenceLabel: String? = null,
    showAverage: Boolean = true,
    xLabels: Pair<String, String>? = null,
) {
    if (values.size < 2) return
    var scrubIndex by remember { mutableStateOf<Int?>(null) }

    val minV = minOf(values.min(), zoneBands.minOfOrNull { it.lower } ?: values.min())
    val maxV = maxOf(values.max(), zoneBands.maxOfOrNull { it.upper } ?: values.max())
    val span = (maxV - minV).takeIf { it > 0.0 } ?: 1.0
    val avg = values.average()

    Column(modifier = modifier) {
        Row(verticalAlignment = Alignment.Top) {
            // Y-axis min/max labels
            Column(
                verticalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier.height(height),
            ) {
                Text(formatValue(maxV), style = axMono(9), color = Ax.Tertiary)
                Spacer(Modifier.weight(1f))
                Text(formatValue(minV), style = axMono(9), color = Ax.Tertiary)
            }
            Spacer(Modifier.width(8.dp))

            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(height)
            ) {
                Canvas(
                    modifier = Modifier
                        .fillMaxSize()
                        .let { m ->
                            if (!interactive) m else m.pointerInput(values) {
                                detectDragGestures(
                                    onDragStart = { pos ->
                                        scrubIndex = indexFor(pos.x, size.width.toFloat(), values.size)
                                    },
                                    onDrag = { change, _ ->
                                        scrubIndex = indexFor(change.position.x, size.width.toFloat(), values.size)
                                    },
                                    onDragEnd = { scrubIndex = null },
                                    onDragCancel = { scrubIndex = null },
                                )
                            }
                        },
                ) {
                    fun x(i: Int) = size.width * i / (values.size - 1).toFloat()
                    fun y(v: Double) = size.height * (1f - ((v - minV) / span).toFloat())

                    // Zone bands behind everything
                    for (band in zoneBands) {
                        val top = y(band.upper.coerceAtMost(maxV))
                        val bottom = y(band.lower.coerceAtLeast(minV))
                        drawRect(
                            color = band.color.copy(alpha = 0.08f),
                            topLeft = Offset(0f, top),
                            size = androidx.compose.ui.geometry.Size(size.width, bottom - top),
                        )
                    }

                    // Gradient fill under the line
                    val fillPath = Path().apply {
                        moveTo(0f, size.height)
                        values.forEachIndexed { i, v -> lineTo(x(i), y(v)) }
                        lineTo(size.width, size.height)
                        close()
                    }
                    drawPath(
                        path = fillPath,
                        brush = Brush.verticalGradient(
                            colors = listOf(color.copy(alpha = 0.25f), color.copy(alpha = 0.02f)),
                        ),
                    )

                    // The line itself
                    drawSeriesLine(values, color) { i, v -> Offset(x(i), y(v)) }

                    // Average dashed line
                    if (showAverage) {
                        val avgY = y(avg)
                        drawLine(
                            color = color.copy(alpha = 0.45f),
                            start = Offset(0f, avgY),
                            end = Offset(size.width, avgY),
                            strokeWidth = 1.dp.toPx(),
                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f)),
                        )
                    }

                    // Reference line (e.g. FTP)
                    if (referenceLine != null && referenceLine in minV..maxV) {
                        val refY = y(referenceLine)
                        drawLine(
                            color = Color.White.copy(alpha = 0.35f),
                            start = Offset(0f, refY),
                            end = Offset(size.width, refY),
                            strokeWidth = 1.dp.toPx(),
                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 6f)),
                        )
                    }

                    // Scrub indicator or resting endpoint dot
                    val idx = scrubIndex
                    if (idx != null) {
                        val sx = x(idx)
                        drawLine(
                            color = Color.White.copy(alpha = 0.4f),
                            start = Offset(sx, 0f),
                            end = Offset(sx, size.height),
                            strokeWidth = 1.dp.toPx(),
                        )
                        drawCircle(color = color, radius = 5.dp.toPx(), center = Offset(sx, y(values[idx])))
                    } else {
                        val lastX = x(values.size - 1)
                        val lastY = y(values.last())
                        drawCircle(color = color, radius = 4.dp.toPx(), center = Offset(lastX, lastY))
                        drawCircle(
                            color = color.copy(alpha = 0.3f),
                            radius = 8.dp.toPx(),
                            center = Offset(lastX, lastY),
                        )
                    }
                }

                // Floating scrub callout
                scrubIndex?.let { idx ->
                    val date = dates.getOrNull(idx)
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier
                            .align(if (idx < values.size / 2) Alignment.TopStart else Alignment.TopEnd)
                            .background(Ax.Surface, androidx.compose.foundation.shape.RoundedCornerShape(8.dp))
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                    ) {
                        Text(formatValue(values[idx]), style = axMono(11, FontWeight.SemiBold), color = Ax.Primary)
                        if (date != null) {
                            Text(
                                date.format(DateTimeFormatter.ofPattern("EEE, MMM d", Locale.ENGLISH)).uppercase(),
                                style = axMono(8).tracked(0.6),
                                color = Ax.Tertiary,
                            )
                        }
                    }
                }
            }
        }

        // X-axis labels: explicit override, or first/last date
        val labels = xLabels ?: run {
            if (dates.size >= 2) {
                val fmt = DateTimeFormatter.ofPattern("MMM d", Locale.ENGLISH)
                dates.first().format(fmt).uppercase() to dates.last().format(fmt).uppercase()
            } else null
        }
        if (labels != null) {
            Spacer(Modifier.height(6.dp))
            Row(modifier = Modifier.fillMaxWidth().padding(start = 30.dp)) {
                Text(labels.first, style = axMono(9).tracked(0.6), color = Ax.Tertiary)
                Spacer(Modifier.weight(1f))
                Text(labels.second, style = axMono(9).tracked(0.6), color = Ax.Tertiary)
            }
        }
    }
}

private fun indexFor(xPos: Float, width: Float, count: Int): Int {
    if (width <= 0f) return 0
    val frac = (xPos / width).coerceIn(0f, 1f)
    return (frac * (count - 1)).roundToInt().coerceIn(0, count - 1)
}

private fun DrawScope.drawSeriesLine(
    values: List<Double>,
    color: Color,
    point: (Int, Double) -> Offset,
) {
    val path = Path()
    values.forEachIndexed { i, v ->
        val p = point(i, v)
        if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
    }
    drawPath(
        path = path,
        color = color,
        style = Stroke(width = 2.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round),
    )
}

/**
 * Dual-line chart (CTL fitness vs ATL fatigue) with gradient fill under the
 * fatigue line and a legend showing the latest values + form (TSB).
 */
@Composable
fun FitnessFatigueChart(
    ctl: List<Double>,
    atl: List<Double>,
    dates: List<LocalDate>,
    modifier: Modifier = Modifier,
) {
    if (ctl.size < 2 || atl.size < 2) return
    val form = (ctl.lastOrNull() ?: 0.0) - (atl.lastOrNull() ?: 0.0)

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            LegendDot(Ax.Green, "Fitness", "%.0f".format(ctl.last()))
            LegendDot(Ax.Amber, "Fatigue", "%.0f".format(atl.last()))
            Spacer(Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.End) {
                Text("FORM", style = axMono(8, FontWeight.SemiBold).tracked(1.2), color = Ax.Tertiary)
                Text(
                    "${if (form >= 0) "+" else ""}${form.roundToInt()}",
                    style = axMono(13, FontWeight.SemiBold),
                    color = if (form >= 0) Ax.Green else Ax.Amber,
                )
            }
        }

        val all = ctl + atl
        val minV = all.min()
        val maxV = all.max()
        val span = (maxV - minV).takeIf { it > 0.0 } ?: 1.0

        Canvas(modifier = Modifier.fillMaxWidth().height(140.dp)) {
            fun x(i: Int, n: Int) = size.width * i / (n - 1).toFloat()
            fun y(v: Double) = size.height * (1f - ((v - minV) / span).toFloat())

            // Fill under ATL only
            val fill = Path().apply {
                moveTo(0f, size.height)
                atl.forEachIndexed { i, v -> lineTo(x(i, atl.size), y(v)) }
                lineTo(size.width, size.height)
                close()
            }
            drawPath(
                path = fill,
                brush = Brush.verticalGradient(listOf(Ax.Amber.copy(alpha = 0.18f), Ax.Amber.copy(alpha = 0.02f))),
            )

            drawSeriesLine(ctl, Ax.Green) { i, v -> Offset(x(i, ctl.size), y(v)) }
            drawSeriesLine(atl, Ax.Amber) { i, v -> Offset(x(i, atl.size), y(v)) }

            // Endpoint dots with soft glow
            for ((series, color) in listOf(ctl to Ax.Green, atl to Ax.Amber)) {
                val p = Offset(size.width, y(series.last()))
                drawCircle(color.copy(alpha = 0.3f), radius = 7.dp.toPx(), center = p)
                drawCircle(color, radius = 3.5.dp.toPx(), center = p)
            }
        }

        if (dates.size >= 2) {
            val fmt = DateTimeFormatter.ofPattern("MMM d", Locale.ENGLISH)
            Row(modifier = Modifier.fillMaxWidth()) {
                Text(dates.first().format(fmt).uppercase(), style = axMono(9).tracked(0.6), color = Ax.Tertiary)
                Spacer(Modifier.weight(1f))
                Text(dates.last().format(fmt).uppercase(), style = axMono(9).tracked(0.6), color = Ax.Tertiary)
            }
        }
    }
}

@Composable
private fun LegendDot(color: Color, label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(8.dp).background(color, CircleShape))
        Text(label.uppercase(), style = axMono(9, FontWeight.SemiBold).tracked(0.8), color = Ax.Secondary)
        Text(value, style = axMono(11, FontWeight.SemiBold), color = Ax.Primary)
    }
}
