package app.northax.ui.screens.plan

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.northax.domain.engine.SessionCompletion
import app.northax.domain.engine.SessionMatch
import app.northax.domain.model.ActivityStreams
import app.northax.domain.model.SegmentEffort
import app.northax.domain.model.SwitchSuggestion
import app.northax.domain.model.TrainingDomain
import app.northax.store.AthleteStore
import app.northax.ui.components.AxButton
import app.northax.ui.components.AxCard
import app.northax.ui.components.AxOutlineButton
import app.northax.ui.components.AxPill
import app.northax.ui.components.AxPillStyle
import app.northax.ui.components.AxSheet
import app.northax.ui.components.CompletionPill
import app.northax.ui.components.IconTile
import app.northax.ui.components.RouteMapCard
import app.northax.ui.components.SectionLabel
import app.northax.ui.components.StatTile
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlinx.coroutines.launch
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Full session detail: stat tiles, workout breakdown, planned vs actual,
 * logged sets, activity streams, switch suggestions, push-to-Garmin, and
 * mark-complete — the WorkoutDetailView port.
 */
@Composable
fun WorkoutDetailSheet(store: AthleteStore, match: SessionMatch, onDismiss: () -> Unit) {
    val session = match.session
    val scope = rememberCoroutineScope()
    var showLogger by remember { mutableStateOf(false) }
    var showLogEditor by remember { mutableStateOf(false) }
    var streams by remember { mutableStateOf<ActivityStreams?>(null) }
    var segments by remember { mutableStateOf<List<SegmentEffort>>(emptyList()) }
    var selectedSegment by remember { mutableStateOf<SegmentEffort?>(null) }
    var pushState by remember { mutableStateOf(PushState.Idle) }

    // Load the activity streams (and Strava segment efforts) for completed workouts.
    LaunchedEffect(match.activity?.id) {
        match.activity?.let {
            streams = store.activityStreams(it.id)
            // The backend resolves the id across sources, so no source gating here.
            if (session.domain in listOf(TrainingDomain.Cycling, TrainingDomain.Running)) {
                segments = store.activitySegments(it.id) ?: emptyList()
            }
        }
    }

    AxSheet(onDismiss = onDismiss, title = session.domain.raw) {
        Column(
            verticalArrangement = Arrangement.spacedBy(18.dp),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            // Header
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                IconTile(icon = session.domain.icon, color = session.domain.color, size = 52.dp, radius = 14.dp)
                Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.weight(1f)) {
                    Text(
                        session.domain.raw.uppercase(),
                        style = axMono(10, FontWeight.SemiBold).tracked(1.4),
                        color = session.domain.color,
                    )
                    Text(session.title, style = axDisplay(20, FontWeight.ExtraBold), color = Ax.Primary)
                    Text(
                        match.day.date.format(DateTimeFormatter.ofPattern("EEEE, MMM d", Locale.ENGLISH)).uppercase(),
                        style = axMono(10).tracked(0.8),
                        color = Ax.Tertiary,
                    )
                }
                CompletionPill(match.completion)
            }

            // Stat tiles
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (match.completion == SessionCompletion.Extra) {
                    val activity = match.activity
                    StatTile("Time", activity?.formattedDuration ?: "${session.duration} min", modifier = Modifier.weight(1f))
                    StatTile(
                        "Load",
                        activity?.trainingLoad?.let { "${it.roundToInt()}" } ?: "–",
                        modifier = Modifier.weight(1f),
                    )
                } else {
                    StatTile("Time", "${session.duration} min", modifier = Modifier.weight(1f))
                    StatTile(
                        "Effort", session.intensityLabel.ifEmpty { "–" },
                        valueColor = effortColor(session.intensityLabel),
                        modifier = Modifier.weight(1f),
                    )
                    StatTile(
                        "Load",
                        "${store.sessionLoad(session.duration, session.intensityLabel).roundToInt()}",
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            // Workout breakdown
            if (session.exercises != null || session.workout != null) {
                AxCard(modifier = Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionLabel("Workout")
                        SessionBreakdown(
                            domain = session.domain,
                            workout = session.workout,
                            exercises = session.exercises,
                            thresholds = store.thresholds,
                            cyclingTarget = store.cyclingTarget,
                        )
                    }
                }
            }

            // Planned targets (hidden for unplanned extras)
            if (match.completion != SessionCompletion.Extra) {
                AxCard(modifier = Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        SectionLabel("Planned targets")
                        DetailRow("Duration", "${session.duration} min")
                        DetailRow("Intensity", session.intensityLabel.ifEmpty { "–" })
                        if (session.subtitle.isNotEmpty()) DetailRow("Focus", session.subtitle)
                    }
                }
            }

            // Planned vs actual
            match.activity?.takeIf { match.completion == SessionCompletion.Done }?.let { activity ->
                AxCard(modifier = Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        SectionLabel("Planned vs actual")
                        DetailRow("Duration", "${session.duration} min → ${activity.formattedDuration}")
                        activity.formattedDistance?.let { DetailRow("Distance", it) }
                        activity.avgHeartRate?.let { DetailRow("Avg HR", "$it bpm") }
                        activity.trainingLoad?.let { DetailRow("Load", "${it.roundToInt()}") }
                    }
                }
            }

            // Logged strength sets
            match.activity?.strengthExercises?.takeIf { it.isNotEmpty() }?.let { logged ->
                AxCard(modifier = Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            SectionLabel("Logged sets")
                            Spacer(Modifier.weight(1f))
                            // Only in-app logged (manual) activities are editable.
                            if (match.activity?.isEditable == true) {
                                Text(
                                    "EDIT",
                                    style = axMono(10, FontWeight.SemiBold).tracked(1.2),
                                    color = Ax.Accent,
                                    modifier = Modifier
                                        .clickable { showLogEditor = true }
                                        .padding(vertical = 2.dp),
                                )
                            }
                        }
                        for (exercise in logged) {
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(exercise.name, style = axDisplay(13, FontWeight.Bold), color = Ax.Primary)
                                Text(
                                    exercise.sets.joinToString("  ·  ") { it.display },
                                    style = axMono(11),
                                    color = Ax.Secondary,
                                )
                            }
                        }
                    }
                }
            }

            // Activity data streams (completed only)
            val isMotionDomain = session.domain in listOf(
                TrainingDomain.Cycling, TrainingDomain.Running,
                TrainingDomain.Swimming, TrainingDomain.Triathlon,
            )
            streams?.takeIf {
                match.completion.isCompleted && (it.hasData || (isMotionDomain && it.latLng.size > 1))
            }?.let { s ->
                AxCard(modifier = Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        SectionLabel("Activity data")
                        if (isMotionDomain && s.latLng.size > 1) {
                            RouteMapCard(points = s.latLng, color = session.domain.color)
                        }
                        ActivityStreamCharts(
                            streams = s,
                            domain = session.domain,
                            thresholds = store.thresholds,
                        )
                    }
                }
            }

            // Strava segment efforts (§13)
            if (segments.isNotEmpty()) {
                AxCard(modifier = Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionLabel("Segments")
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            segments.forEach { effort ->
                                SegmentEffortRow(effort) { selectedSegment = effort }
                            }
                        }
                    }
                }
            }

            // Start workout (strength, planned/missed)
            if (session.domain == TrainingDomain.Strength && !match.completion.isCompleted) {
                AxButton(
                    label = "Start workout",
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { showLogger = true },
                )
            }

            // Switch alternatives (unless completed)
            if (!match.completion.isCompleted) {
                SwitchSection(store = store, match = match, onApplied = onDismiss)
            }

            // Push to Garmin (planned + intervals.icu connected)
            if (match.completion == SessionCompletion.Planned && store.intervals.connectionState.isConnected) {
                AxOutlineButton(
                    label = when (pushState) {
                        PushState.Idle -> "Sync your workout"
                        PushState.Pushing -> "Sending…"
                        PushState.Pushed -> "Sent to intervals.icu ✓"
                        PushState.Failed -> "Failed — try again"
                    },
                    color = if (pushState == PushState.Failed) Ax.Red else Ax.Accent,
                    enabled = pushState == PushState.Idle || pushState == PushState.Failed,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        pushState = PushState.Pushing
                        scope.launch {
                            val ok = store.intervals.pushPlannedSession(session, match.day.date)
                            pushState = if (ok) PushState.Pushed else PushState.Failed
                        }
                    },
                )
            }
        }
    }

    selectedSegment?.let { segment ->
        SegmentHistorySheet(store = store, segment = segment, onDismiss = { selectedSegment = null })
    }

    if (showLogger) {
        StrengthLoggerSheet(
            store = store,
            match = match,
            onDismiss = { showLogger = false },
            onSaved = {
                showLogger = false
                onDismiss()
            },
        )
    }

    // Edit the exercise log of a done workout — the match snapshot is stale
    // after a save, so close the whole detail like the live logger does.
    if (showLogEditor) {
        match.activity?.let { activity ->
            StrengthLoggerSheet(
                store = store,
                match = match,
                onDismiss = { showLogEditor = false },
                onSaved = {
                    showLogEditor = false
                    onDismiss()
                },
                editing = activity,
            )
        }
    }
}

private enum class PushState { Idle, Pushing, Pushed, Failed }

@Composable
private fun SegmentEffortRow(effort: SegmentEffort, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Ax.Inset)
            .clickable(onClick = onClick)
            .padding(12.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.weight(1f)) {
            Text(
                effort.name,
                style = axDisplay(14, FontWeight.Bold),
                color = Ax.Primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                effort.formattedBest?.let { "${effort.metaLine} · PB $it" } ?: effort.metaLine,
                style = axMono(10).tracked(0.4),
                color = Ax.Tertiary,
            )
        }
        Text(effort.formattedTime, style = axMono(12, FontWeight.SemiBold), color = Ax.Primary)
        // All-time rank from our DB — Strava's pr_rank was only true at ride time.
        effort.komRank?.let { kom ->
            AxPill(if (kom == 1) "KOM" else "#$kom", Ax.Purple)
        } ?: when (effort.rank) {
            1 -> AxPill("BEST", Ax.Accent)
            2 -> AxPill("2nd", Ax.Amber, AxPillStyle.Outline)
            3 -> AxPill("3rd", Ax.Amber, AxPillStyle.Outline)
            else -> {}
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = Ax.Tertiary,
            modifier = Modifier.size(16.dp),
        )
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Text(label, style = axDisplay(13), color = Ax.Secondary)
        Spacer(Modifier.weight(1f))
        Text(value, style = axMono(11, FontWeight.SemiBold), color = Ax.Primary)
    }
}

private fun effortColor(intensity: String) = when (intensity.lowercase()) {
    "easy", "very easy", "minimal", "recovery", "light" -> Ax.Green
    "moderate", "tempo" -> Ax.Amber
    "hard", "threshold", "max", "heavy" -> Ax.Red
    else -> Ax.Primary
}

/** Switch-to-alternative suggestions: AI pre-fetched, falling back to the
 *  deterministic switcher. */
@Composable
private fun SwitchSection(store: AthleteStore, match: SessionMatch, onApplied: () -> Unit) {
    val scope = rememberCoroutineScope()
    val key = match.suggestionKey
    val loading = key in store.suggestionsLoading
    val ai = store.dailySuggestions[key]
    val suggestions = if (!ai.isNullOrEmpty()) ai else store.fallbackSuggestions(excluding = match.session.domain)
    var expandedId by remember { mutableStateOf<String?>(null) }
    var applying by remember { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionLabel("Switch to")

        if (loading && ai == null) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.padding(vertical = 8.dp),
            ) {
                CircularProgressIndicator(color = Ax.Accent, modifier = Modifier.size(16.dp))
                Text("Fetching alternatives…", style = axDisplay(12.5), color = Ax.Tertiary)
            }
        }

        for (suggestion in suggestions) {
            SwitchSuggestionRow(
                store = store,
                suggestion = suggestion,
                expanded = expandedId == suggestion.id,
                onToggle = { expandedId = if (expandedId == suggestion.id) null else suggestion.id },
                applying = applying,
                onApply = {
                    applying = true
                    scope.launch {
                        store.applySwitch(match, suggestion)
                        applying = false
                        onApplied()
                    }
                },
            )
        }

        if (ai.isNullOrEmpty() && !loading && suggestions.isNotEmpty()) {
            Text(
                "Offline alternatives — AI suggestions weren't available.",
                style = axMono(9).tracked(0.6),
                color = Ax.Tertiary,
            )
        }
    }
}

@Composable
private fun SwitchSuggestionRow(
    store: AthleteStore,
    suggestion: SwitchSuggestion,
    expanded: Boolean,
    onToggle: () -> Unit,
    applying: Boolean,
    onApply: () -> Unit,
) {
    AxCard(modifier = Modifier.fillMaxWidth().clickable(onClick = onToggle), radius = 16.dp, padding = 14.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile(icon = suggestion.domain.icon, color = suggestion.domain.color, size = 36.dp)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.weight(1f)) {
                    Text(suggestion.title, style = axDisplay(14, FontWeight.SemiBold), color = Ax.Primary)
                    val meta = buildList {
                        add("${suggestion.duration} MIN")
                        add(suggestion.intensityLabel.uppercase())
                        suggestion.estimatedLoad?.let { add("~${it.roundToInt()} LOAD") }
                    }.joinToString(" · ")
                    Text(meta, style = axMono(9).tracked(0.6), color = Ax.Tertiary)
                }
            }

            Text(suggestion.description, style = axDisplay(12.5), color = Ax.Secondary)

            if (expanded) {
                suggestion.rationale?.let {
                    Text(it, style = axDisplay(12), color = Ax.Tertiary)
                }
                if (suggestion.workout != null || suggestion.exercises != null) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))
                    SessionBreakdown(
                        domain = suggestion.domain,
                        workout = suggestion.workout,
                        exercises = suggestion.exercises,
                        thresholds = store.thresholds,
                        cyclingTarget = store.cyclingTarget,
                    )
                }
                AxButton(
                    label = if (applying) "Applying…" else "Use this session",
                    enabled = !applying,
                    height = 44.dp,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = onApply,
                )
            }
        }
    }
}
