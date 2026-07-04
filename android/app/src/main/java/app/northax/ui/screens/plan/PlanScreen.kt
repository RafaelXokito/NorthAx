package app.northax.ui.screens.plan

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.domain.engine.SessionCompletion
import app.northax.domain.engine.SessionMatch
import app.northax.store.AthleteStore
import app.northax.ui.components.AxCard
import app.northax.ui.components.CompletionPill
import app.northax.ui.components.IconTile
import app.northax.ui.components.NoDataView
import app.northax.ui.components.SectionLabel
import app.northax.ui.screens.dashboard.WeekGlance
import app.northax.ui.screens.settings.FrequencyOnboardingSheet
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** Two-week rolling plan with session list — the PlanView port. */
@Composable
fun PlanScreen(store: AthleteStore) {
    var weekOffset by rememberSaveable { mutableStateOf(0) }
    var selectedMatchId by rememberSaveable { mutableStateOf<String?>(null) }
    var showPlanSetup by rememberSaveable { mutableStateOf(false) }

    val weekData = store.weekData(weekOffset)
    val matches = weekData?.matches ?: emptyList()

    if (store.weeklyPlans.isEmpty() && weekOffset >= 0) {
        Box(modifier = Modifier.fillMaxSize().background(Ax.Background).padding(20.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("Plan", style = axDisplay(32, FontWeight.ExtraBold).tracked(-0.96), color = Ax.Primary)
                NoDataView(
                    icon = Icons.Filled.CalendarMonth,
                    title = "No plan yet",
                    message = "Choose which days you train and NorthAx will lay out your next two weeks.",
                    ctaLabel = "Create a plan",
                    onCta = { showPlanSetup = true },
                )
            }
        }
        if (showPlanSetup) {
            FrequencyOnboardingSheet(store = store, onDismiss = { showPlanSetup = false })
        }
        return
    }

    LazyColumn(
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxSize().background(Ax.Background),
    ) {
        item(key = "title") {
            Text("Plan", style = axDisplay(32, FontWeight.ExtraBold).tracked(-0.96), color = Ax.Primary)
        }

        // Plan updated banner
        item(key = "updated-banner") {
            AnimatedVisibility(visible = store.planWasRecentlyUpdated) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(Ax.Green.copy(alpha = 0.10f))
                        .border(1.dp, Ax.Green.copy(alpha = 0.25f), RoundedCornerShape(14.dp))
                        .padding(12.dp),
                ) {
                    Icon(Icons.Filled.Autorenew, contentDescription = null, tint = Ax.Green, modifier = Modifier.size(18.dp))
                    Text(
                        "Plan updated to match your new training setup.",
                        style = axDisplay(13),
                        color = Ax.Green,
                    )
                }
            }
        }

        // Week glance
        if (weekData != null) {
            item(key = "week-glance") {
                AxCard(modifier = Modifier.fillMaxWidth()) {
                    WeekGlance(
                        weekData = weekData,
                        maxForwardOffset = store.maxFutureWeekOffset,
                        onStep = { weekOffset += it },
                        onSelectDay = { },
                    )
                }
            }
        }

        // Sessions
        val sectionTitle = when {
            weekData?.isHistorical == true -> "Completed workouts"
            weekOffset == 0 -> "This week"
            else -> "Planned sessions"
        }
        item(key = "sessions-label") { SectionLabel(sectionTitle) }

        if (matches.isEmpty()) {
            item(key = "no-sessions") {
                Text(
                    text = if (weekData?.isHistorical == true) "No workouts imported for this week."
                    else "No training days this week.",
                    style = axDisplay(13),
                    color = Ax.Tertiary,
                )
            }
        } else {
            items(count = matches.size, key = { matches[it].id }) { i ->
                val match = matches[i]
                SessionMatchCard(match = match) { selectedMatchId = match.id }
            }
        }

        // Weekly load progression
        store.metrics?.let { m ->
            item(key = "weekly-load") {
                val changePct = (m.weeklyLoadChange * 100).roundToInt()
                val aggressive = changePct > 15
                AxCard(modifier = Modifier.fillMaxWidth()) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        IconTile(
                            icon = if (aggressive) Icons.Filled.Warning else Icons.Filled.BarChart,
                            color = if (aggressive) Ax.Red else Ax.Green,
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                "Week-on-week change: ${if (changePct >= 0) "+" else ""}$changePct%",
                                style = axDisplay(14, FontWeight.SemiBold),
                                color = if (aggressive) Ax.Red else Ax.Primary,
                            )
                            Text(
                                text = if (aggressive) {
                                    "That's an aggressive ramp — load jumps above ~15% raise injury risk."
                                } else {
                                    "Load progression is within a sustainable range."
                                },
                                style = axDisplay(12),
                                color = Ax.Secondary,
                            )
                        }
                    }
                }
            }
        }

        item(key = "bottom") { Spacer(Modifier.height(8.dp)) }
    }

    selectedMatchId?.let { id ->
        matches.firstOrNull { it.id == id }?.let { match ->
            WorkoutDetailSheet(store = store, match = match, onDismiss = { selectedMatchId = null })
        }
    }
}

/** Compact session row — the SessionMatchCard port. */
@Composable
fun SessionMatchCard(match: SessionMatch, onClick: () -> Unit) {
    val session = match.session
    val greyed = match.day.isPast && !match.completion.isCompleted

    AxCard(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        radius = 16.dp,
        padding = 16.dp,
        highlighted = match.day.isToday && !match.completion.isCompleted,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile(
                    icon = session.domain.icon,
                    color = if (greyed) Ax.Tertiary else session.domain.color,
                    size = 44.dp,
                )
                Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.weight(1f)) {
                    Text(session.title, style = axDisplay(15, FontWeight.SemiBold), color = Ax.Primary)
                    val meta = buildList {
                        add(dayLabel(match.day.date).uppercase())
                        add("${session.duration} MIN")
                        if (session.intensityLabel.isNotEmpty()) add(session.intensityLabel.uppercase())
                    }.joinToString(" · ")
                    Text(meta, style = axMono(9).tracked(0.6), color = Ax.Tertiary)
                }
                CompletionPill(match.completion)
            }

            match.activity?.let { activity ->
                Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))
                val stats = buildList {
                    add(activity.formattedDuration.uppercase())
                    activity.formattedDistance?.let { add(it.uppercase()) }
                    activity.avgHeartRate?.let { add("$it BPM") }
                    activity.trainingLoad?.let { add("${it.roundToInt()} LOAD") }
                }.joinToString(" · ")
                Text(stats, style = axMono(10, FontWeight.SemiBold).tracked(0.6), color = Ax.Green)
            }
        }
    }
}

private fun dayLabel(date: LocalDate): String {
    val today = LocalDate.now()
    return when (date) {
        today -> "Today"
        today.plusDays(1) -> "Tomorrow"
        else -> date.format(DateTimeFormatter.ofPattern("EEE", Locale.ENGLISH))
    }
}
