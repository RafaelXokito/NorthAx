package app.northax.ui.screens.dashboard

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.northax.domain.model.DailyReadiness
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * 270° tachometer gauge showing the readiness score (0–100) with a tick ring,
 * a glowing endpoint dot, and an animated count-up — the ReadinessRingView port.
 */
@Composable
fun ReadinessRing(
    score: Int,
    status: DailyReadiness.Status,
    size: Dp = 220.dp,
) {
    val fraction by animateFloatAsState(
        targetValue = score.coerceIn(0, 100) / 100f,
        animationSpec = tween(durationMillis = 1150, easing = CubicBezierEasing(0.33f, 1f, 0.68f, 1f)),
        label = "readiness",
    )
    val color = status.color

    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(size)) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val startAngle = 135f
            val sweep = 270f
            val strokeWidth = 10.dp.toPx()
            val inset = strokeWidth * 1.8f
            val arcSize = Size(this.size.width - inset * 2, this.size.height - inset * 2)
            val topLeft = Offset(inset, inset)

            // Tick ring: 38 short capsules around the gauge.
            val tickCount = 38
            val radius = this.size.minDimension / 2f
            for (i in 0 until tickCount) {
                val angle = startAngle + sweep * i / (tickCount - 1)
                val filled = i.toFloat() / (tickCount - 1) <= fraction
                rotate(degrees = angle + 90f, pivot = center) {
                    drawLine(
                        color = if (filled) color.copy(alpha = 0.55f) else Color.White.copy(alpha = 0.10f),
                        start = Offset(center.x, center.y - radius + 1.dp.toPx()),
                        end = Offset(center.x, center.y - radius + 7.dp.toPx()),
                        strokeWidth = 2.dp.toPx(),
                        cap = StrokeCap.Round,
                    )
                }
            }

            // Track
            drawArc(
                color = Color.White.copy(alpha = 0.07f),
                startAngle = startAngle,
                sweepAngle = sweep,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
            )

            // Progress
            drawArc(
                color = color,
                startAngle = startAngle,
                sweepAngle = sweep * fraction,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
            )

            // Glowing endpoint dot
            val endAngleRad = Math.toRadians((startAngle + sweep * fraction).toDouble())
            val arcRadius = arcSize.width / 2f
            val endCenter = Offset(
                x = center.x + arcRadius * cos(endAngleRad).toFloat(),
                y = center.y + arcRadius * sin(endAngleRad).toFloat(),
            )
            drawCircle(color = color.copy(alpha = 0.4f), radius = strokeWidth * 1.2f, center = endCenter)
            drawCircle(color = color, radius = strokeWidth * 0.65f, center = endCenter)
        }

        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "${(fraction * 100).roundToInt()}",
                style = axDisplay((size.value * 0.26).toInt(), FontWeight.ExtraBold),
                color = Ax.Primary,
            )
            Text(
                text = "READINESS",
                style = axMono(10, FontWeight.SemiBold).tracked(2.0),
                color = Ax.Tertiary,
            )
        }
    }
}
