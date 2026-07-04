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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.northax.domain.engine.SessionMatch
import app.northax.domain.engine.StrengthEngine
import app.northax.domain.model.GarminActivity
import app.northax.domain.model.LoggedExercise
import app.northax.domain.model.LoggedSet
import app.northax.domain.model.MuscleGroup
import app.northax.store.AthleteStore
import app.northax.ui.components.AxButton
import app.northax.ui.components.AxCard
import app.northax.ui.components.AxSheet
import app.northax.ui.components.IconTile
import app.northax.ui.components.SectionLabel
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.util.Locale
import java.util.UUID

// In-app live logging for strength sessions: timer, set-by-set entry, and
// exercise management — the StrengthLoggerView port.

private class SetDraft(
    val id: String = UUID.randomUUID().toString(),
    weightText: String = "",
    repsText: String = "",
) {
    var weightText by mutableStateOf(weightText)
    var repsText by mutableStateOf(repsText)

    val weightValue: Double? get() = weightText.replace(',', '.').toDoubleOrNull()
    val repsValue: Int? get() = repsText.toIntOrNull()?.takeIf { it > 0 }
}

private class ExerciseDraft(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val muscleGroup: MuscleGroup,
    val repsHint: String,
    initialSets: Int = 3,
    logged: List<LoggedSet>? = null, // prefill from an existing log (edit mode)
) {
    val sets = mutableStateListOf<SetDraft>().apply {
        if (logged != null) {
            logged.forEach {
                add(SetDraft(weightText = it.weightKg?.let(::weightText) ?: "", repsText = it.reps.toString()))
            }
        } else {
            repeat(initialSets) { add(SetDraft()) }
        }
    }

    fun toLogged(): LoggedExercise? {
        val logged = sets.mapNotNull { draft ->
            draft.repsValue?.let { reps -> LoggedSet(weightKg = draft.weightValue, reps = reps) }
        }
        if (logged.isEmpty()) return null
        return LoggedExercise(name = name, muscleGroup = muscleGroup, sets = logged)
    }
}

@Composable
fun StrengthLoggerSheet(
    store: AthleteStore,
    match: SessionMatch,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
    editing: GarminActivity? = null, // edit an existing log instead of live logging
) {
    val scope = rememberCoroutineScope()
    val startedAt = remember { Instant.now() }
    val exercises = remember {
        mutableStateListOf<ExerciseDraft>().apply {
            if (editing != null) {
                editing.strengthExercises?.forEach {
                    add(ExerciseDraft(name = it.name, muscleGroup = it.muscleGroup, repsHint = "reps", logged = it.sets))
                }
            } else {
                match.session.exercises?.forEach {
                    add(ExerciseDraft(name = it.name, muscleGroup = it.muscleGroup, repsHint = it.repsRange, initialSets = it.sets))
                }
            }
        }
    }
    var elapsed by remember { mutableStateOf(0L) }
    var showPicker by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }

    // Live timer, ticking every second (live logging only).
    if (editing == null) {
        androidx.compose.runtime.LaunchedEffect(Unit) {
            while (true) {
                elapsed = Duration.between(startedAt, Instant.now()).seconds
                delay(1_000)
            }
        }
    }

    val anySetLogged = exercises.any { ex -> ex.sets.any { it.repsValue != null } }

    AxSheet(onDismiss = onDismiss, title = if (editing == null) "Log workout" else "Edit workout", doneLabel = "Cancel") {
        Column(
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            // Timer card (live logging only)
            if (editing == null) AxCard(modifier = Modifier.fillMaxWidth(), highlighted = true) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    IconTile(icon = match.session.domain.icon, color = Ax.StrengthSport, size = 44.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(
                            "WORKOUT IN PROGRESS",
                            style = axMono(9, FontWeight.SemiBold).tracked(1.4),
                            color = Ax.Tertiary,
                        )
                        Text(formatTimer(elapsed), style = axMono(26, FontWeight.Bold), color = Ax.Primary)
                    }
                }
            }

            // Exercise cards
            for (exercise in exercises) {
                ExerciseCard(
                    exercise = exercise,
                    onRemove = { exercises.remove(exercise) },
                )
            }

            // Add exercise
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(Ax.Accent.copy(alpha = 0.10f))
                    .clickable { showPicker = true }
                    .padding(14.dp),
            ) {
                Icon(Icons.Filled.Add, contentDescription = null, tint = Ax.Accent, modifier = Modifier.size(16.dp))
                Text(
                    "ADD EXERCISE",
                    style = axMono(11, FontWeight.SemiBold).tracked(1.2),
                    color = Ax.Accent,
                )
            }

            if (saveError) {
                Text(
                    "Couldn't save the workout. Check your connection and try again.",
                    style = axDisplay(12.5),
                    color = Ax.Red,
                )
            }

            AxButton(
                label = if (saving) "Saving…" else if (editing == null) "FINISH WORKOUT" else "SAVE CHANGES",
                enabled = anySetLogged && !saving,
                color = Ax.Green,
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    saving = true
                    saveError = false
                    scope.launch {
                        val logged = exercises.mapNotNull { it.toLogged() }
                        val ok = if (editing != null) {
                            store.updateStrengthWorkout(activityId = editing.id, exercises = logged)
                        } else {
                            val duration = maxOf(60L, Duration.between(startedAt, Instant.now()).seconds).toInt()
                            store.logStrengthWorkout(
                                title = match.session.title,
                                startedAt = startedAt,
                                durationSeconds = duration,
                                exercises = logged,
                            )
                        }
                        saving = false
                        if (ok) onSaved() else saveError = true
                    }
                },
            )
        }
    }

    if (showPicker) {
        ExercisePickerSheet(
            onDismiss = { showPicker = false },
            onPick = { name, group ->
                exercises.add(ExerciseDraft(name = name, muscleGroup = group, repsHint = "reps"))
                showPicker = false
            },
        )
    }
}

@Composable
private fun ExerciseCard(exercise: ExerciseDraft, onRemove: () -> Unit) {
    AxCard(modifier = Modifier.fillMaxWidth(), radius = 16.dp, padding = 14.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile(icon = Icons.Filled.FitnessCenter, color = exercise.muscleGroup.color, size = 34.dp)
                Column(verticalArrangement = Arrangement.spacedBy(1.dp), modifier = Modifier.weight(1f)) {
                    Text(exercise.name, style = axDisplay(14, FontWeight.SemiBold), color = Ax.Primary)
                    Text(
                        exercise.muscleGroup.raw.uppercase(),
                        style = axMono(9).tracked(0.8),
                        color = exercise.muscleGroup.color,
                    )
                }
                Icon(
                    Icons.Filled.Cancel,
                    contentDescription = "Remove exercise",
                    tint = Ax.Tertiary,
                    modifier = Modifier.size(20.dp).clickable(onClick = onRemove),
                )
            }

            exercise.sets.forEachIndexed { i, set ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        "SET ${i + 1}",
                        style = axMono(10, FontWeight.SemiBold).tracked(0.8),
                        color = Ax.Tertiary,
                        modifier = Modifier.width(44.dp),
                    )
                    LoggerField(
                        value = set.weightText,
                        onValueChange = { set.weightText = it },
                        placeholder = "kg",
                        keyboardType = KeyboardType.Decimal,
                    )
                    Text("×", style = axMono(12), color = Ax.Tertiary)
                    LoggerField(
                        value = set.repsText,
                        onValueChange = { set.repsText = it },
                        placeholder = exercise.repsHint,
                        keyboardType = KeyboardType.Number,
                    )
                    Icon(
                        imageVector = if (set.repsValue != null) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                        contentDescription = null,
                        tint = if (set.repsValue != null) Ax.Green else Ax.Tertiary,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.weight(1f))
                    if (exercise.sets.size > 1) {
                        Icon(
                            Icons.Filled.RemoveCircleOutline,
                            contentDescription = "Remove set",
                            tint = Ax.Tertiary,
                            modifier = Modifier.size(18.dp).clickable { exercise.sets.remove(set) },
                        )
                    }
                }
            }

            Text(
                "+ ADD SET",
                style = axMono(10, FontWeight.SemiBold).tracked(1.0),
                color = Ax.Accent,
                modifier = Modifier
                    .clickable {
                        val lastWeight = exercise.sets.lastOrNull()?.weightText ?: ""
                        exercise.sets.add(SetDraft(weightText = lastWeight))
                    }
                    .padding(vertical = 4.dp),
            )
        }
    }
}

@Composable
private fun LoggerField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    keyboardType: KeyboardType,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = {
            Text(placeholder, style = axMono(12), color = Ax.Tertiary, textAlign = TextAlign.Center)
        },
        singleLine = true,
        textStyle = axMono(13, FontWeight.SemiBold).copy(textAlign = TextAlign.Center),
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
        modifier = Modifier.width(84.dp).height(52.dp),
    )
}

/** Pick a movement grouped by muscle — the ExercisePickerView port. */
@Composable
private fun ExercisePickerSheet(onDismiss: () -> Unit, onPick: (String, MuscleGroup) -> Unit) {
    AxSheet(onDismiss = onDismiss, title = "Add exercise", doneLabel = "Cancel") {
        Column(
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            for (group in MuscleGroup.entries) {
                SectionLabel(group.raw)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (movement in StrengthEngine.movements(group)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(Ax.Surface)
                                .clickable { onPick(movement, group) }
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                        ) {
                            Box(Modifier.size(7.dp).background(group.color, androidx.compose.foundation.shape.CircleShape))
                            Text(movement, style = axDisplay(13.5, FontWeight.Medium), color = Ax.Primary)
                        }
                    }
                }
            }
        }
    }
}

private fun weightText(w: Double): String =
    if (w % 1.0 == 0.0) w.toInt().toString() else w.toString()

private fun formatTimer(seconds: Long): String {
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
    else String.format(Locale.US, "%02d:%02d", m, s)
}
