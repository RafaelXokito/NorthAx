package app.northax.ui.screens.settings

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.northax.domain.model.AthleteThresholds
import app.northax.domain.model.PaceUnit
import app.northax.domain.model.PoolUnit
import app.northax.domain.model.TrainingDomain
import app.northax.store.AthleteStore
import app.northax.ui.components.AxButton
import app.northax.ui.components.AxCard
import app.northax.ui.components.AxSegmented
import app.northax.ui.components.AxSheet
import app.northax.ui.components.IconTile
import app.northax.ui.components.NavRow
import app.northax.ui.components.SectionLabel
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlinx.coroutines.launch

/** Enrolled sports, weekday schedules, thresholds, goals — TrainingPlanView port. */
@Composable
fun TrainingPlanScreen(store: AthleteStore, onBack: () -> Unit, onOpenGoals: () -> Unit) {
    val scope = rememberCoroutineScope()
    var expandedDomain by rememberSaveable { mutableStateOf<String?>(null) }
    var showEnrollSheet by rememberSaveable { mutableStateOf(false) }
    var confirmRemove by rememberSaveable { mutableStateOf<String?>(null) }

    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .fillMaxSize()
            .background(Ax.Background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
    ) {
        // Title bar
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back",
                tint = Ax.Primary,
                modifier = Modifier.size(24.dp).clickable(onClick = onBack),
            )
            Spacer(Modifier.width(14.dp))
            Text("Training plan", style = axDisplay(24, FontWeight.ExtraBold).tracked(-0.5), color = Ax.Primary)
            Spacer(Modifier.weight(1f))
            Icon(
                Icons.Filled.Add, contentDescription = "Enroll a sport",
                tint = Ax.Accent,
                modifier = Modifier.size(24.dp).clickable { showEnrollSheet = true },
            )
        }

        // Staged plan changes bar
        if (store.pendingPlanChanges) {
            AxCard(modifier = Modifier.fillMaxWidth(), highlighted = true) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = Ax.Accent, modifier = Modifier.size(16.dp))
                        Text("You have unsaved plan changes", style = axDisplay(14, FontWeight.SemiBold), color = Ax.Primary)
                    }
                    Text(
                        "Generate a new two-week plan that reflects your updated schedule, split, and goals.",
                        style = axDisplay(12.5),
                        color = Ax.Secondary,
                    )
                    AxButton(label = "Update plan", height = 44.dp, modifier = Modifier.fillMaxWidth()) {
                        scope.launch { store.applyPlanChanges() }
                    }
                }
            }
        }

        // Enrolled sports
        SectionLabel("Enrolled sports")
        if (store.enabledDomains.isEmpty()) {
            Text("No sports yet. Tap + to add one.", style = axDisplay(13), color = Ax.Tertiary)
        }
        for (domain in store.enabledDomains) {
            SportConfigBlock(
                store = store,
                domain = domain,
                expanded = expandedDomain == domain.raw,
                onToggleExpand = {
                    expandedDomain = if (expandedDomain == domain.raw) null else domain.raw
                },
                onRemove = { confirmRemove = domain.raw },
            )
        }

        // Goals
        SectionLabel("Goals")
        NavRow(
            icon = Icons.Filled.Flag,
            iconColor = Ax.Purple,
            title = "Sport goals",
            subtitle = if (store.sportTargets.isEmpty()) "No goals set"
            else "${store.sportTargets.size} active ${if (store.sportTargets.size == 1) "goal" else "goals"}",
            onClick = onOpenGoals,
        )

        // Frequency summary
        val freq = store.trainingFrequency
        Text(
            "${freq.totalSessions} SESSIONS/WEEK ACROSS ${store.enabledDomains.size} SPORTS",
            style = axMono(10, FontWeight.SemiBold).tracked(1.0),
            color = Ax.Secondary,
        )
        if (freq.isOverloaded) {
            Text(
                "Training 7 days a week leaves no room for recovery.",
                style = axDisplay(12.5),
                color = Ax.Red,
            )
        }
    }

    if (showEnrollSheet) {
        EnrollSportSheet(
            enabled = store.enabledDomains,
            onDismiss = { showEnrollSheet = false },
            onEnroll = { domain ->
                store.updateEnabledDomains(store.enabledDomains + domain)
                showEnrollSheet = false
                expandedDomain = domain.raw
            },
        )
    }

    confirmRemove?.let { raw ->
        val domain = TrainingDomain.fromRaw(raw)
        AlertDialog(
            onDismissRequest = { confirmRemove = null },
            containerColor = Ax.Surface,
            title = { Text("Remove ${domain?.raw}?", style = axDisplay(17, FontWeight.Bold), color = Ax.Primary) },
            text = {
                Text(
                    "Its sessions are removed from your plan the next time you update it.",
                    style = axDisplay(13.5), color = Ax.Secondary,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    domain?.let { d ->
                        store.updateEnabledDomains(store.enabledDomains.filter { it != d })
                        store.updateTrainingFrequency(store.trainingFrequency.settingDays(emptySet(), d))
                    }
                    confirmRemove = null
                }) { Text("Remove", color = Ax.Red, style = axDisplay(14, FontWeight.SemiBold)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmRemove = null }) {
                    Text("Cancel", color = Ax.Secondary, style = axDisplay(14))
                }
            },
        )
    }
}

// MARK: - Sport config block

@Composable
private fun SportConfigBlock(
    store: AthleteStore,
    domain: TrainingDomain,
    expanded: Boolean,
    onToggleExpand: () -> Unit,
    onRemove: () -> Unit,
) {
    val days = store.trainingFrequency.weekdays(domain)
    val shape = RoundedCornerShape(16.dp)

    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Ax.Surface)
            .border(1.dp, Ax.Border, shape)
            .animateContentSize()
            .padding(16.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxWidth().clickable(onClick = onToggleExpand),
        ) {
            IconTile(icon = domain.icon, color = domain.color, size = 38.dp)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.weight(1f)) {
                Text(domain.raw, style = axDisplay(15, FontWeight.SemiBold), color = Ax.Primary)
                Text(
                    "${days.size} ${if (days.size == 1) "day" else "days"}/week",
                    style = axMono(10).tracked(0.6),
                    color = Ax.Tertiary,
                )
            }
            Icon(
                imageVector = if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                contentDescription = null,
                tint = Ax.Tertiary,
                modifier = Modifier.size(20.dp),
            )
        }

        if (expanded) {
            WeekdayGrid(
                domain = domain,
                selected = days,
                onToggle = { wd ->
                    store.updateTrainingFrequency(store.trainingFrequency.toggling(wd, domain))
                },
            )

            when (domain) {
                TrainingDomain.Strength -> MuscleSplitEditor(store)
                TrainingDomain.Cycling -> CyclingConfig(store)
                TrainingDomain.Running -> RunningConfig(store)
                TrainingDomain.Swimming -> SwimmingConfig(store)
                else -> {}
            }

            Text(
                "REMOVE SPORT",
                style = axMono(10, FontWeight.SemiBold).tracked(1.2),
                color = Ax.Red,
                modifier = Modifier.clickable(onClick = onRemove).padding(vertical = 4.dp),
            )
        }
    }
}

/** Reusable Mon–Sun toggle grid for one sport's training days. */
@Composable
fun WeekdayGrid(domain: TrainingDomain, selected: Set<Int>, onToggle: (Int) -> Unit) {
    val labels = listOf("M", "T", "W", "T", "F", "S", "S")
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
        for (wd in 0..6) {
            val on = wd in selected
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .weight(1f)
                    .height(44.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (on) domain.color else Ax.Inset)
                    .clickable { onToggle(wd) },
            ) {
                Text(
                    labels[wd],
                    style = axMono(12, FontWeight.SemiBold),
                    color = if (on) Ax.Background else Ax.Tertiary,
                )
            }
        }
    }
}

// MARK: - Sport-specific config

@Composable
private fun CyclingConfig(store: AthleteStore) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionLabel("Structured workout target")
        AxSegmented(
            options = listOf("hr" to "Heart rate", "power" to "Power"),
            selection = store.cyclingTarget,
            onSelect = { store.updateCyclingTarget(it) },
            modifier = Modifier.fillMaxWidth(),
        )
        if (store.cyclingTarget == "power") {
            ThresholdIntField(
                label = "FTP",
                unit = "W",
                value = store.thresholds.ftpWatts,
            ) { store.updateThresholds(store.thresholds.copy(ftpWatts = it)) }
        } else {
            ThresholdIntField(
                label = "Threshold HR",
                unit = "bpm",
                value = store.thresholds.thresholdHr,
            ) { store.updateThresholds(store.thresholds.copy(thresholdHr = it)) }
            ThresholdIntField(
                label = "Max HR",
                unit = "bpm",
                value = store.thresholds.maxHr,
            ) { store.updateThresholds(store.thresholds.copy(maxHr = it)) }
        }
    }
}

@Composable
private fun RunningConfig(store: AthleteStore) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionLabel("Threshold pace")
        AxSegmented(
            options = listOf(PaceUnit.Km to "min/km", PaceUnit.Mile to "min/mile"),
            selection = store.thresholds.paceUnit,
            onSelect = { store.updateThresholds(store.thresholds.copy(paceUnit = it)) },
            modifier = Modifier.fillMaxWidth(),
        )
        ThresholdPaceField(
            label = "Threshold pace",
            seconds = store.thresholds.runThresholdPaceSecPerKm,
        ) { store.updateThresholds(store.thresholds.copy(runThresholdPaceSecPerKm = it)) }
    }
}

@Composable
private fun SwimmingConfig(store: AthleteStore) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionLabel("Pool")
        AxSegmented(
            options = listOf(
                PoolUnit.Pool25m to "25 m",
                PoolUnit.Pool50m to "50 m",
                PoolUnit.OpenWater to "Open water",
            ),
            selection = store.thresholds.poolUnit,
            onSelect = { store.updateThresholds(store.thresholds.copy(poolUnit = it)) },
            modifier = Modifier.fillMaxWidth(),
        )
        ThresholdPaceField(
            label = "Pace / 100 m",
            seconds = store.thresholds.swimThresholdPaceSecPer100m,
        ) { store.updateThresholds(store.thresholds.copy(swimThresholdPaceSecPer100m = it)) }
    }
}

@Composable
private fun ThresholdIntField(label: String, unit: String, value: Int?, onCommit: (Int?) -> Unit) {
    var text by rememberSaveable(label, value) { mutableStateOf(value?.toString() ?: "") }
    ConfigFieldRow(label = label, unit = unit, text = text, keyboardType = KeyboardType.Number,
        onTextChange = { text = it },
        onCommit = { onCommit(text.toIntOrNull()) })
}

/** Pace as "mm:ss", stored as total seconds. */
@Composable
private fun ThresholdPaceField(label: String, seconds: Int?, onCommit: (Int?) -> Unit) {
    var text by rememberSaveable(label, seconds) {
        mutableStateOf(seconds?.let { "${it / 60}:" + "%02d".format(it % 60) } ?: "")
    }
    ConfigFieldRow(label = label, unit = "mm:ss", text = text, keyboardType = KeyboardType.Text,
        onTextChange = { text = it },
        onCommit = { onCommit(parsePace(text)) })
}

private fun parsePace(text: String): Int? {
    val parts = text.trim().split(":")
    if (parts.size != 2) return null
    val m = parts[0].toIntOrNull() ?: return null
    val s = parts[1].toIntOrNull() ?: return null
    if (s >= 60 || m < 0 || s < 0) return null
    return m * 60 + s
}

@Composable
private fun ConfigFieldRow(
    label: String,
    unit: String,
    text: String,
    keyboardType: KeyboardType,
    onTextChange: (String) -> Unit,
    onCommit: () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text(label, style = axDisplay(13.5), color = Ax.Secondary)
        Spacer(Modifier.weight(1f))
        TextField(
            value = text,
            onValueChange = onTextChange,
            singleLine = true,
            placeholder = { Text("–", style = axMono(12), color = Ax.Tertiary, textAlign = TextAlign.End) },
            textStyle = axMono(13, FontWeight.SemiBold).copy(textAlign = TextAlign.End),
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Ax.Inset,
                unfocusedContainerColor = Ax.Inset,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                cursorColor = Ax.Accent,
                focusedTextColor = Ax.Primary,
                unfocusedTextColor = Ax.Primary,
            ),
            shape = RoundedCornerShape(10.dp),
            modifier = Modifier
                .width(120.dp)
                .onFocusLost(onCommit),
        )
        Spacer(Modifier.width(8.dp))
        Text(unit.uppercase(), style = axMono(9), color = Ax.Tertiary)
    }
}

/** Commit the field when it loses focus (the iOS onSubmit/onChange-of-focus port). */
private fun Modifier.onFocusLost(onCommit: () -> Unit): Modifier = composed {
    var hadFocus by remember { mutableStateOf(false) }
    onFocusChanged { state ->
        if (hadFocus && !state.isFocused) onCommit()
        hadFocus = state.isFocused
    }
}

// MARK: - Enroll sport sheet

@Composable
fun EnrollSportSheet(
    enabled: List<TrainingDomain>,
    onDismiss: () -> Unit,
    onEnroll: (TrainingDomain) -> Unit,
) {
    val available = TrainingDomain.entries.filter { it !in enabled && it != TrainingDomain.Recovery }

    AxSheet(onDismiss = onDismiss, title = "Enroll a sport", doneLabel = "Cancel") {
        Column(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            if (available.isEmpty()) {
                Text("All sports are already enrolled.", style = axDisplay(13.5), color = Ax.Secondary)
            }
            for (domain in available) {
                AxCard(
                    modifier = Modifier.fillMaxWidth().clickable { onEnroll(domain) },
                    radius = 16.dp,
                    padding = 16.dp,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        IconTile(icon = domain.icon, color = domain.color, size = 38.dp)
                        Text(domain.raw, style = axDisplay(15, FontWeight.SemiBold), color = Ax.Primary)
                        Spacer(Modifier.weight(1f))
                        Icon(Icons.Filled.AddCircle, contentDescription = null, tint = domain.color, modifier = Modifier.size(22.dp))
                    }
                }
            }
        }
    }
}
