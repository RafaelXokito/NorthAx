package app.northax.ui.screens.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.domain.engine.PlanMatchingEngine
import app.northax.domain.engine.SessionCompletion
import app.northax.domain.engine.WeekData
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * 7-day navigation strip with completion state per day — the WeekGlanceView
 * port, including the swipe gesture and arrow navigation.
 */
@Composable
fun WeekGlance(
    weekData: WeekData,
    maxForwardOffset: Int,
    onStep: (Int) -> Unit,
    onSelectDay: (LocalDate) -> Unit,
) {
    var dragConsumed by remember { mutableStateOf(false) }

    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .pointerInput(weekData.offset) {
                detectHorizontalDragGestures(
                    onDragStart = { dragConsumed = false },
                    onHorizontalDrag = { _, dragAmount ->
                        if (dragConsumed) return@detectHorizontalDragGestures
                        if (dragAmount < -18f && weekData.offset < maxForwardOffset) {
                            dragConsumed = true
                            onStep(1)
                        } else if (dragAmount > 18f) {
                            dragConsumed = true
                            onStep(-1)
                        }
                    },
                )
            },
    ) {
        // Navigation header
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                contentDescription = "Previous week",
                tint = Ax.Secondary,
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .clickable { onStep(-1) },
            )
            Spacer(Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = relativeWeekLabel(weekData.offset),
                    style = axMono(10, FontWeight.SemiBold).tracked(1.8),
                    color = if (weekData.offset == 0) Ax.Accent else Ax.Secondary,
                )
                Text(
                    text = weekData.week.weekLabel.uppercase(),
                    style = axMono(9).tracked(0.8),
                    color = Ax.Tertiary,
                )
            }
            Spacer(Modifier.weight(1f))
            val canForward = weekData.offset < maxForwardOffset
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "Next week",
                tint = if (canForward) Ax.Secondary else Ax.Tertiary.copy(alpha = 0.3f),
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .clickable(enabled = canForward) { onStep(1) },
            )
        }

        // 7-day column grid
        Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
            for (day in weekData.week.days) {
                val state = PlanMatchingEngine.dayState(day, weekData.matches)
                val domain = day.sessions.firstOrNull()?.domain
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.clickable { onSelectDay(day.date) },
                ) {
                    Text(
                        text = day.date.format(DateTimeFormatter.ofPattern("EEEEE", Locale.ENGLISH)).uppercase(),
                        style = axMono(9, FontWeight.SemiBold).tracked(0.5),
                        color = if (day.isToday) Ax.Accent else Ax.Tertiary,
                    )

                    val dotColor = when (state) {
                        SessionCompletion.Done -> Ax.Green
                        SessionCompletion.Missed -> Ax.Tertiary
                        SessionCompletion.Rest -> Ax.Inset
                        else -> domain?.color ?: Ax.Inset
                    }
                    val fillAlpha = when (state) {
                        SessionCompletion.Done -> 0.22f
                        SessionCompletion.Missed -> 0.10f
                        else -> 0.14f
                    }
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(38.dp)
                            .clip(CircleShape)
                            .background(if (state == SessionCompletion.Rest) Ax.Inset else dotColor.copy(alpha = fillAlpha))
                            .border(
                                width = if (day.isToday) 1.5.dp else 0.dp,
                                color = if (day.isToday) Ax.Accent else Color.Transparent,
                                shape = CircleShape,
                            ),
                    ) {
                        if (state == SessionCompletion.Rest) {
                            Icon(
                                Icons.Filled.NightsStay, contentDescription = "Rest",
                                tint = Ax.Tertiary, modifier = Modifier.size(15.dp),
                            )
                        } else if (domain != null) {
                            Icon(
                                domain.icon, contentDescription = domain.raw,
                                tint = if (state == SessionCompletion.Missed) Ax.Tertiary else dotColor,
                                modifier = Modifier.size(17.dp),
                            )
                        }
                    }

                    Icon(
                        imageVector = state.icon,
                        contentDescription = state.label,
                        tint = state.color.copy(alpha = if (state == SessionCompletion.Planned) 0.5f else 1f),
                        modifier = Modifier.size(11.dp),
                    )
                }
            }
        }
    }
}

private fun relativeWeekLabel(offset: Int): String = when {
    offset == 0 -> "THIS WEEK"
    offset == 1 -> "NEXT WEEK"
    offset == -1 -> "LAST WEEK"
    offset > 1 -> "IN $offset WEEKS"
    else -> "${-offset} WEEKS AGO"
}
