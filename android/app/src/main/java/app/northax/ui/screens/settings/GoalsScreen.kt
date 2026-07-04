package app.northax.ui.screens.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.northax.domain.model.GoalType
import app.northax.domain.model.SportTarget
import app.northax.domain.model.TrainingDomain
import app.northax.store.AthleteStore
import app.northax.ui.components.AxCard
import app.northax.ui.components.AxSegmented
import app.northax.ui.components.SectionLabel
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Per-sport goal targets — the GoalsView port (Running race time, Cycling
 *  power hold / distance @ speed), with unsaved-changes protection. */
@Composable
fun GoalsScreen(store: AthleteStore, onBack: () -> Unit) {
    var draft by remember { mutableStateOf(store.sportTargets) }
    var showDiscardDialog by rememberSaveable { mutableStateOf(false) }
    val isDirty = draft != store.sportTargets

    fun defaultDate(): LocalDate = LocalDate.now().plusWeeks(12)

    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .fillMaxSize()
            .background(Ax.Background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.Icon(
                Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back",
                tint = Ax.Primary,
                modifier = Modifier.size(24.dp).clickable {
                    if (isDirty) showDiscardDialog = true else onBack()
                },
            )
            Spacer(Modifier.width(14.dp))
            Text("Goals", style = axDisplay(24, FontWeight.ExtraBold).tracked(-0.5), color = Ax.Primary)
            Spacer(Modifier.weight(1f))
            Text(
                "Save",
                style = axDisplay(15, FontWeight.SemiBold),
                color = if (isDirty) Ax.Accent else Ax.Tertiary,
                modifier = Modifier
                    .clickable(enabled = isDirty) {
                        store.updateSportTargets(draft)
                        onBack()
                    }
                    .padding(4.dp),
            )
        }

        val hasRunning = TrainingDomain.Running in store.enabledDomains
        val hasCycling = TrainingDomain.Cycling in store.enabledDomains

        if (!hasRunning && !hasCycling) {
            Text(
                "Enroll Running or Cycling in your training plan to set a goal.",
                style = axDisplay(13.5),
                color = Ax.Secondary,
            )
        }

        // Running: race time
        if (hasRunning) {
            SectionLabel("Running")
            AxCard(modifier = Modifier.fillMaxWidth(), radius = 16.dp, padding = 16.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    val target = draft[TrainingDomain.Running]
                    AxSegmented(
                        options = listOf<GoalType?>(null, GoalType.RaceTime)
                            .map { it to (if (it == null) "None" else "Race time") },
                        selection = target?.goalType,
                        onSelect = { type ->
                            draft = if (type == null) draft - TrainingDomain.Running
                            else draft + (TrainingDomain.Running to SportTarget(
                                goalType = GoalType.RaceTime,
                                targetDate = target?.targetDate ?: defaultDate(),
                            ))
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (target?.goalType == GoalType.RaceTime) {
                        GoalDecimalField("Race distance", "km", target.distanceKm) {
                            draft = draft + (TrainingDomain.Running to target.copy(distanceKm = it))
                        }
                        GoalDurationField("Finish time", target.finishTimeSec) {
                            draft = draft + (TrainingDomain.Running to target.copy(finishTimeSec = it))
                        }
                        TargetDateRow(target.targetDate) {
                            draft = draft + (TrainingDomain.Running to target.copy(targetDate = it))
                        }
                    }
                }
            }
        }

        // Cycling: power hold / distance @ speed
        if (hasCycling) {
            SectionLabel("Cycling")
            AxCard(modifier = Modifier.fillMaxWidth(), radius = 16.dp, padding = 16.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    val target = draft[TrainingDomain.Cycling]
                    AxSegmented(
                        options = listOf(
                            null to "None",
                            GoalType.PowerHold to "Power hold",
                            GoalType.DistanceAvgSpeed to "Dist @ speed",
                        ),
                        selection = target?.goalType,
                        onSelect = { type ->
                            draft = when (type) {
                                null -> draft - TrainingDomain.Cycling
                                GoalType.PowerHold -> draft + (TrainingDomain.Cycling to SportTarget(
                                    goalType = GoalType.PowerHold,
                                    targetDate = target?.targetDate ?: defaultDate(),
                                    zone = 4,
                                ))
                                else -> draft + (TrainingDomain.Cycling to SportTarget(
                                    goalType = GoalType.DistanceAvgSpeed,
                                    targetDate = target?.targetDate ?: defaultDate(),
                                ))
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    when (target?.goalType) {
                        GoalType.PowerHold -> {
                            SectionLabel("Zone")
                            AxSegmented(
                                options = (1..5).map { it to "Z$it" },
                                selection = target.zone ?: 4,
                                onSelect = { z ->
                                    draft = draft + (TrainingDomain.Cycling to target.copy(zone = z))
                                },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            GoalIntField("Hold duration", "min", target.holdMinutes) {
                                draft = draft + (TrainingDomain.Cycling to target.copy(holdMinutes = it))
                            }
                            TargetDateRow(target.targetDate) {
                                draft = draft + (TrainingDomain.Cycling to target.copy(targetDate = it))
                            }
                        }
                        GoalType.DistanceAvgSpeed -> {
                            GoalDecimalField("Distance", "km", target.distanceKm) {
                                draft = draft + (TrainingDomain.Cycling to target.copy(distanceKm = it))
                            }
                            GoalDecimalField("Avg speed", "km/h", target.avgSpeedKmh) {
                                draft = draft + (TrainingDomain.Cycling to target.copy(avgSpeedKmh = it))
                            }
                            TargetDateRow(target.targetDate) {
                                draft = draft + (TrainingDomain.Cycling to target.copy(targetDate = it))
                            }
                        }
                        else -> {}
                    }
                }
            }
        }
    }

    if (showDiscardDialog) {
        AlertDialog(
            onDismissRequest = { showDiscardDialog = false },
            containerColor = Ax.Surface,
            title = { Text("Discard changes?", style = axDisplay(17, FontWeight.Bold), color = Ax.Primary) },
            text = { Text("Your goal edits haven't been saved.", style = axDisplay(13.5), color = Ax.Secondary) },
            confirmButton = {
                TextButton(onClick = { showDiscardDialog = false; onBack() }) {
                    Text("Discard", color = Ax.Red, style = axDisplay(14, FontWeight.SemiBold))
                }
            },
            dismissButton = {
                TextButton(onClick = { showDiscardDialog = false }) {
                    Text("Keep editing", color = Ax.Secondary, style = axDisplay(14))
                }
            },
        )
    }
}

// MARK: - Goal fields

@Composable
private fun GoalFieldRow(
    label: String,
    unit: String?,
    text: String,
    keyboardType: KeyboardType,
    onTextChange: (String) -> Unit,
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
            modifier = Modifier.width(120.dp),
        )
        if (unit != null) {
            Spacer(Modifier.width(8.dp))
            Text(unit.uppercase(), style = axMono(9), color = Ax.Tertiary)
        }
    }
}

@Composable
private fun GoalDecimalField(label: String, unit: String, value: Double?, onCommit: (Double?) -> Unit) {
    var text by rememberSaveable(label) {
        mutableStateOf(value?.let { if (it == it.toLong().toDouble()) "${it.toLong()}" else "$it" } ?: "")
    }
    GoalFieldRow(label, unit, text, KeyboardType.Decimal) {
        text = it
        onCommit(it.replace(',', '.').toDoubleOrNull())
    }
}

@Composable
private fun GoalIntField(label: String, unit: String, value: Int?, onCommit: (Int?) -> Unit) {
    var text by rememberSaveable(label) { mutableStateOf(value?.toString() ?: "") }
    GoalFieldRow(label, unit, text, KeyboardType.Number) {
        text = it
        onCommit(it.toIntOrNull())
    }
}

/** Duration as "h:mm:ss" or "mm:ss", stored as total seconds. */
@Composable
private fun GoalDurationField(label: String, seconds: Int?, onCommit: (Int?) -> Unit) {
    var text by rememberSaveable(label) {
        mutableStateOf(seconds?.let { formatDuration(it) } ?: "")
    }
    GoalFieldRow(label, "h:mm:ss", text, KeyboardType.Text) {
        text = it
        onCommit(parseDuration(it))
    }
}

private fun formatDuration(total: Int): String {
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
    else String.format(Locale.US, "%d:%02d", m, s)
}

private fun parseDuration(text: String): Int? {
    val parts = text.trim().split(":")
    return when (parts.size) {
        2 -> {
            val m = parts[0].toIntOrNull() ?: return null
            val s = parts[1].toIntOrNull() ?: return null
            if (s >= 60) null else m * 60 + s
        }
        3 -> {
            val h = parts[0].toIntOrNull() ?: return null
            val m = parts[1].toIntOrNull() ?: return null
            val s = parts[2].toIntOrNull() ?: return null
            if (m >= 60 || s >= 60) null else h * 3600 + m * 60 + s
        }
        else -> null
    }
}

/** Compact date stepper: -1w / date / +1w (a lightweight DatePicker stand-in). */
@Composable
private fun TargetDateRow(date: LocalDate, onChange: (LocalDate) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text("Target date", style = axDisplay(13.5), color = Ax.Secondary)
        Spacer(Modifier.weight(1f))
        Text(
            "−1W",
            style = axMono(11, FontWeight.SemiBold),
            color = Ax.Accent,
            modifier = Modifier
                .clickable {
                    val next = date.minusWeeks(1)
                    if (!next.isBefore(LocalDate.now())) onChange(next)
                }
                .padding(8.dp),
        )
        Text(
            date.format(DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.ENGLISH)),
            style = axMono(12, FontWeight.SemiBold),
            color = Ax.Primary,
            modifier = Modifier.padding(horizontal = 4.dp),
        )
        Text(
            "+1W",
            style = axMono(11, FontWeight.SemiBold),
            color = Ax.Accent,
            modifier = Modifier
                .clickable { onChange(date.plusWeeks(1)) }
                .padding(8.dp),
        )
    }
}
