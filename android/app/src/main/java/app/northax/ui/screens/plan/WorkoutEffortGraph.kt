package app.northax.ui.screens.plan

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.graphics.drawscope.Stroke
import app.northax.data.remote.dto.StructuredWorkoutDto
import app.northax.domain.engine.ZoneMath
import app.northax.domain.engine.ZoneMode
import app.northax.domain.model.AthleteThresholds
import app.northax.domain.model.TrainingDomain
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlin.math.roundToInt

// Structured workout visualization: stepped trapezoid bars, zone coloring,
// ramps for warm-up/cool-down, tap-to-inspect — the WorkoutEffortGraphView port.

private data class EffortStep(
    val cue: String,
    val minutes: Int,
    val zone: Int,      // 0 = neutral
    val icu: String,
    val ramp: Ramp,
)

private enum class Ramp { None, Up, Down }

private fun zoneOf(icu: String): Int {
    val match = Regex("[Zz](\\d)").find(icu) ?: return 0
    return match.groupValues[1].toIntOrNull()?.coerceIn(0, 5) ?: 0
}

private fun rampOf(cue: String): Ramp {
    val c = cue.lowercase()
    return when {
        c.contains("warm") -> Ramp.Up
        c.contains("cool") -> Ramp.Down
        else -> Ramp.None
    }
}

private fun flatten(workout: StructuredWorkoutDto): List<EffortStep> {
    val steps = mutableListOf<EffortStep>()
    for (block in workout.blocks) {
        repeat(maxOf(1, block.repeatCount)) {
            for (step in block.steps) {
                steps.add(EffortStep(step.cue, step.minutes, zoneOf(step.icu), step.icu, rampOf(step.cue)))
            }
        }
    }
    return steps
}

@Composable
fun WorkoutEffortGraph(
    workout: StructuredWorkoutDto,
    sport: TrainingDomain,
    thresholds: AthleteThresholds,
    cyclingTarget: String,
) {
    val steps = remember(workout) { flatten(workout) }
    if (steps.isEmpty()) return
    var selectedIndex by remember { mutableStateOf<Int?>(null) }

    val mode = when (workout.targetMode) {
        "power" -> ZoneMode.Power
        "pace" -> ZoneMode.Pace
        else -> ZoneMode.Hr
    }
    val axisLabel = when (mode) {
        ZoneMode.Power -> "POWER"
        ZoneMode.Pace -> "PACE"
        ZoneMode.Hr -> "HEART RATE"
    }

    val totalMinutes = steps.sumOf { it.minutes }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(axisLabel, style = axMono(8, FontWeight.SemiBold).tracked(1.2), color = Ax.Tertiary)
            Spacer(Modifier.weight(1f))
            Text("DURATION", style = axMono(8, FontWeight.SemiBold).tracked(1.2), color = Ax.Tertiary)
        }

        // Trapezoid bars, width proportional to duration
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(72.dp)
                .pointerInput(steps) {
                    detectTapGestures { pos ->
                        var acc = 0f
                        for ((i, step) in steps.withIndex()) {
                            val w = size.width * step.minutes / totalMinutes.toFloat()
                            if (pos.x >= acc && pos.x < acc + w) {
                                selectedIndex = if (selectedIndex == i) null else i
                                break
                            }
                            acc += w
                        }
                    }
                },
        ) {
            val gap = 2.dp.toPx()
            var xCursor = 0f
            val maxZone = steps.maxOf { maxOf(it.zone, 1) }.coerceAtLeast(3)

            fun heightFor(zone: Int): Float {
                val base = 0.22f
                val frac = base + (1f - base) * (zone.coerceAtLeast(1).toFloat() / maxZone)
                return size.height * frac
            }

            steps.forEachIndexed { i, step ->
                val w = size.width * step.minutes / totalMinutes.toFloat()
                val color = Ax.zone(step.zone)
                val peak = heightFor(step.zone)
                val baseH = size.height * 0.18f
                val selected = selectedIndex == i

                val path = Path().apply {
                    when (step.ramp) {
                        Ramp.Up -> {
                            moveTo(xCursor, size.height - baseH)
                            lineTo(xCursor + w - gap, size.height - peak)
                            lineTo(xCursor + w - gap, size.height)
                            lineTo(xCursor, size.height)
                        }
                        Ramp.Down -> {
                            moveTo(xCursor, size.height - peak)
                            lineTo(xCursor + w - gap, size.height - baseH)
                            lineTo(xCursor + w - gap, size.height)
                            lineTo(xCursor, size.height)
                        }
                        Ramp.None -> {
                            moveTo(xCursor, size.height - peak)
                            lineTo(xCursor + w - gap, size.height - peak)
                            lineTo(xCursor + w - gap, size.height)
                            lineTo(xCursor, size.height)
                        }
                    }
                    close()
                }
                drawPath(path, color = color.copy(alpha = if (selected) 0.55f else 0.30f))
                drawPath(path, color = color, style = Stroke(width = 1.5.dp.toPx()))
                xCursor += w
            }
        }

        // Detail row for the tapped step
        selectedIndex?.let { idx ->
            val step = steps[idx]
            val range = ZoneMath.range(step.zone, mode, sport, thresholds)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(Ax.Inset)
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                Box(Modifier.size(8.dp).background(Ax.zone(step.zone), CircleShape))
                Text(
                    buildString {
                        if (step.icu.isNotEmpty()) append("${step.icu} · ")
                        append("${step.cue} · ${step.minutes} min")
                        if (range != null) append(" · ${ZoneMath.format(range, mode, sport, thresholds.paceUnit)}")
                    },
                    style = axMono(10),
                    color = Ax.Primary,
                )
            }
        }

        // Zone distribution + total
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            val byZone = steps.groupBy { it.zone }.mapValues { (_, s) -> s.sumOf { it.minutes } }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (zone in byZone.keys.sorted()) {
                    if (zone == 0) continue
                    val pct = (byZone[zone]!! * 100.0 / totalMinutes).roundToInt()
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Box(Modifier.size(7.dp).background(Ax.zone(zone), CircleShape))
                        Text("Z$zone $pct%", style = axMono(9), color = Ax.Tertiary)
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            Text("$totalMinutes MIN", style = axMono(9, FontWeight.SemiBold).tracked(0.8), color = Ax.Secondary)
        }
    }
}
