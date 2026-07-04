package app.northax.ui.screens.dashboard

import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.SensorsOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.domain.engine.SessionMatch
import app.northax.domain.model.GoalCheck
import app.northax.store.AppTab
import app.northax.store.AthleteStore
import app.northax.ui.components.AxCard
import app.northax.ui.components.AxPill
import app.northax.ui.components.CompletionPill
import app.northax.ui.components.IconTile
import app.northax.ui.components.NoDataView
import app.northax.ui.components.SectionLabel
import app.northax.ui.screens.plan.WorkoutDetailSheet
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Today's readiness + plan hub — the DashboardView port. */
@Composable
fun DashboardScreen(store: AthleteStore) {
    var weekOffset by rememberSaveable { mutableStateOf(0) }
    var showReadinessDetail by rememberSaveable { mutableStateOf(false) }
    var selectedMatchId by rememberSaveable { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    val weekData = store.weekData(weekOffset)
    val matches = weekData?.matches ?: emptyList()
    val readiness = store.readiness

    LazyColumn(
        state = listState,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxSize().background(Ax.Background),
    ) {
        // Header
        item(key = "header") {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = LocalDate.now()
                        .format(DateTimeFormatter.ofPattern("EEEE · MMM d", Locale.ENGLISH)).uppercase(),
                    style = axMono(10, FontWeight.SemiBold).tracked(1.8),
                    color = Ax.Tertiary,
                )
                Text(
                    text = "${greeting()}, ${store.athleteName}",
                    style = axDisplay(30, FontWeight.ExtraBold).tracked(-0.9),
                    color = Ax.Primary,
                )
            }
        }

        // Readiness ring
        if (readiness != null) {
            item(key = "readiness") {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { showReadinessDetail = true },
                ) {
                    ReadinessRing(score = readiness.score, status = readiness.status)
                    AxPill(text = readiness.status.raw, color = readiness.status.color)
                    Text(
                        text = readiness.displayVerdict,
                        style = axDisplay(15, FontWeight.SemiBold),
                        color = Ax.Secondary,
                    )
                }
            }
        }

        // Today's session(s) — sourced independently of the browsed week, and
        // shown even when no plan week covers today (off-plan extras still appear).
        val todayMatches = store.todayMatches
        val todayIsRest = weekOffset == 0 &&
            (store.currentWeek?.days?.firstOrNull { it.isToday }?.isRest ?: false)
        if (weekOffset == 0 && (store.currentWeek != null || todayMatches.isNotEmpty())) {
            item(key = "today-label") { SectionLabel("Today's session") }
            if (todayIsRest && todayMatches.none { it.completion.isCompleted }) {
                item(key = "today-rest") { TodayRestCard() }
            } else {
                items(count = todayMatches.size, key = { "today-${todayMatches[it].id}" }) { i ->
                    val match = todayMatches[i]
                    SessionHeroCard(store = store, match = match) { selectedMatchId = match.id }
                }
            }
        }

        // Week at a glance
        if (weekData != null) {
            item(key = "week-glance") {
                AxCard(modifier = Modifier.fillMaxWidth()) {
                    WeekGlance(
                        weekData = weekData,
                        maxForwardOffset = store.maxFutureWeekOffset,
                        onStep = { delta -> weekOffset += delta },
                        onSelectDay = { date ->
                            val idx = matches.indexOfFirst { it.day.date == date }
                            if (idx >= 0) scope.launch { listState.animateScrollToItem(0) }
                        },
                    )
                }
            }
        }

        // Back-to-this-week pill
        if (weekOffset != 0) {
            item(key = "back-to-week") {
                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Text(
                        text = "BACK TO THIS WEEK",
                        style = axMono(10, FontWeight.SemiBold).tracked(1.2),
                        color = Ax.Accent,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(Ax.Accent.copy(alpha = 0.12f))
                            .clickable { weekOffset = 0 }
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }
        }

        // Goal check
        if (store.goalChecks.isNotEmpty()) {
            item(key = "goal-label") { SectionLabel("Goal check") }
            items(count = store.goalChecks.size, key = { "goal-${store.goalChecks[it].domain.raw}" }) { i ->
                GoalCheckCard(check = store.goalChecks[i]) {
                    scope.launch { store.applyPlanChanges() }
                }
            }
        }

        // Empty state
        if (readiness == null && store.weeklyPlans.isEmpty() && store.todayMatches.isEmpty()) {
            item(key = "empty") {
                NoDataView(
                    icon = Icons.Filled.SensorsOff,
                    title = "No data yet",
                    message = "Connect a data source and set up your plan to see your readiness and training here.",
                    ctaLabel = "Enable integrations",
                    onCta = { store.selectedTab = AppTab.Settings },
                )
            }
        }

        item(key = "bottom-spacer") { Spacer(Modifier.height(8.dp)) }
    }

    if (showReadinessDetail && readiness != null) {
        ReadinessDetailSheet(store = store, readiness = readiness) { showReadinessDetail = false }
    }

    selectedMatchId?.let { id ->
        (matches + store.todayMatches).firstOrNull { it.id == id }?.let { match ->
            WorkoutDetailSheet(store = store, match = match, onDismiss = { selectedMatchId = null })
        }
    }
}

private fun greeting(): String {
    val hour = LocalTime.now().hour
    return when {
        hour < 12 -> "Good morning"
        hour < 18 -> "Good afternoon"
        else -> "Good evening"
    }
}

@Composable
private fun TodayRestCard() {
    AxCard(modifier = Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            IconTile(icon = Icons.Filled.NightsStay, color = Ax.Recovery, size = 44.dp)
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("REST DAY", style = axMono(10, FontWeight.SemiBold).tracked(1.4), color = Ax.Tertiary)
                Text(
                    "Nothing scheduled. Recovery is where the adaptation happens.",
                    style = axDisplay(13.5),
                    color = Ax.Secondary,
                )
            }
        }
    }
}

/** Today's session card: highlighted treatment, meta line, exercise preview,
 *  completion pill, and actual stats when a workout matched. */
@Composable
private fun SessionHeroCard(store: AthleteStore, match: SessionMatch, onClick: () -> Unit) {
    val session = match.session
    AxCard(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        highlighted = !match.completion.isCompleted,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconTile(icon = session.domain.icon, color = session.domain.color, size = 44.dp)
                Spacer(Modifier.size(14.dp))
                Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.weight(1f)) {
                    Text(
                        text = session.domain.raw.uppercase(),
                        style = axMono(10, FontWeight.SemiBold).tracked(1.4),
                        color = session.domain.color,
                    )
                    Text(
                        text = session.title,
                        style = axDisplay(22, FontWeight.ExtraBold).tracked(-0.4),
                        color = Ax.Primary,
                    )
                }
                CompletionPill(match.completion)
            }

            val meta = buildList {
                add("${session.duration} MIN")
                if (session.intensityLabel.isNotEmpty()) add(session.intensityLabel.uppercase())
                session.exercises?.let { add("${it.size} MOVES") }
            }.joinToString(" · ")
            Text(text = meta, style = axMono(10).tracked(0.8), color = Ax.Tertiary)

            if (session.subtitle.isNotEmpty()) {
                Text(text = session.subtitle, style = axDisplay(13), color = Ax.Secondary)
            }

            // Exercise preview (first 3, +N more)
            session.exercises?.takeIf { it.isNotEmpty() }?.let { exercises ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))
                    for (exercise in exercises.take(3)) {
                        Row(modifier = Modifier.fillMaxWidth()) {
                            Text(exercise.name, style = axDisplay(13, FontWeight.Medium), color = Ax.Primary)
                            Spacer(Modifier.weight(1f))
                            Text(exercise.setDisplay, style = axMono(11), color = Ax.Tertiary)
                        }
                    }
                    if (exercises.size > 3) {
                        Text(
                            "+${exercises.size - 3} more",
                            style = axMono(10).tracked(0.6),
                            color = Ax.Tertiary,
                        )
                    }
                }
            }

            // Actual stats when a workout matched
            match.activity?.let { activity ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))
                    val stats = buildList {
                        add(activity.formattedDuration.uppercase())
                        activity.formattedDistance?.let { add(it.uppercase()) }
                        activity.avgHeartRate?.let { add("$it BPM") }
                        activity.trainingLoad?.let { add("${it.toInt()} LOAD") }
                    }.joinToString(" · ")
                    Text(stats, style = axMono(10, FontWeight.SemiBold).tracked(0.8), color = Ax.Green)
                }
            }
        }
    }
}

/** Goal-progress verdict card — the GoalCheckCard port. */
@Composable
fun GoalCheckCard(check: GoalCheck, onReanalyse: () -> Unit) {
    val (color, label) = when (check.verdict) {
        GoalCheck.Verdict.OnTrack -> Ax.Green to "On track"
        GoalCheck.Verdict.Behind -> Ax.Red to "Behind"
        GoalCheck.Verdict.Ahead -> Ax.Purple to "Ahead"
    }
    AxCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = check.domain.raw.uppercase(),
                    style = axMono(10, FontWeight.SemiBold).tracked(1.4),
                    color = check.domain.color,
                )
                Spacer(Modifier.weight(1f))
                AxPill(text = label, color = color)
            }
            Text(text = check.summary, style = axDisplay(13.5), color = Ax.Secondary)

            if (check.verdict != GoalCheck.Verdict.OnTrack || check.recommendReplan) {
                Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))
                Text(
                    text = "RE-ANALYSE PLAN",
                    style = axMono(10, FontWeight.SemiBold).tracked(1.2),
                    color = Ax.Accent,
                    modifier = Modifier.clickable(onClick = onReanalyse).padding(vertical = 4.dp),
                )
            }
        }
    }
}
