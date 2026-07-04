package app.northax.ui.screens.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import app.northax.domain.model.DaySplit
import app.northax.domain.model.MuscleGroup
import app.northax.domain.model.WeeklyMuscleGroupSplit
import app.northax.store.AthleteStore
import app.northax.ui.components.SectionLabel
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked

private val dayNames = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

/** Weekly muscle-group split editor: presets + per-day editing — the
 *  MuscleSplitEditor port. */
@Composable
fun MuscleSplitEditor(store: AthleteStore) {
    var editingDayIndex by rememberSaveable { mutableStateOf<Int?>(null) }
    val split = store.muscleGroupSplit

    fun update(index: Int, day: DaySplit) {
        val days = split.days.toMutableList()
        days[index] = day
        store.updateMuscleGroupSplit(WeeklyMuscleGroupSplit(days))
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionLabel("Preset splits")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            PresetButton("Push/Pull/Legs", Modifier.weight(1f)) {
                store.updateMuscleGroupSplit(WeeklyMuscleGroupSplit.pushPullLegs)
                editingDayIndex = null
            }
            PresetButton("Upper/Lower", Modifier.weight(1f)) {
                store.updateMuscleGroupSplit(WeeklyMuscleGroupSplit.upperLower)
                editingDayIndex = null
            }
            PresetButton("Full Body", Modifier.weight(1f)) {
                store.updateMuscleGroupSplit(WeeklyMuscleGroupSplit.fullBody)
                editingDayIndex = null
            }
        }

        SectionLabel("Weekly plan · tap to edit")
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            split.days.forEachIndexed { i, day ->
                val editing = editingDayIndex == i
                val shape = RoundedCornerShape(12.dp)
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(shape)
                        .border(1.dp, if (editing) Ax.Accent.copy(alpha = 0.4f) else Ax.Border, shape)
                        .clickable { editingDayIndex = if (editing) null else i }
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                ) {
                    Text(
                        dayNames[i].uppercase(),
                        style = axMono(10, FontWeight.SemiBold).tracked(0.6),
                        color = Ax.Tertiary,
                        modifier = Modifier.width(38.dp),
                    )
                    if (day.isRestDay || day.muscleGroups.isEmpty()) {
                        Text("Rest", style = axDisplay(12.5), color = Ax.Tertiary)
                    } else {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            modifier = Modifier.horizontalScroll(rememberScrollState()),
                        ) {
                            for (group in day.muscleGroups) {
                                Text(
                                    group.raw.uppercase(),
                                    style = axMono(9, FontWeight.SemiBold).tracked(0.6),
                                    color = group.color,
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(group.color.copy(alpha = 0.14f))
                                        .padding(horizontal = 8.dp, vertical = 3.dp),
                                )
                            }
                        }
                    }
                }

                if (editing) {
                    DayEditor(
                        dayName = dayNames[i],
                        day = day,
                        onChange = { update(i, it) },
                    )
                }
            }
        }
    }
}

@Composable
private fun PresetButton(label: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(10.dp)
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(42.dp)
            .clip(shape)
            .background(Ax.Inset)
            .border(1.dp, Ax.Border, shape)
            .clickable(onClick = onClick),
    ) {
        Text(label, style = axDisplay(11.5, FontWeight.SemiBold), color = Ax.Primary)
    }
}

@Composable
private fun DayEditor(dayName: String, day: DaySplit, onChange: (DaySplit) -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Ax.Surface.copy(alpha = 0.5f))
            .border(1.dp, Ax.Accent.copy(alpha = 0.2f), shape)
            .padding(16.dp),
    ) {
        SectionLabel("Edit $dayName")

        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Rest day", style = axDisplay(13.5, FontWeight.Medium), color = Ax.Primary)
            Spacer(Modifier.weight(1f))
            Switch(
                checked = day.isRestDay,
                onCheckedChange = { rest ->
                    onChange(if (rest) DaySplit.rest else day.copy(isRestDay = false))
                },
                colors = SwitchDefaults.colors(checkedTrackColor = Ax.Accent),
            )
        }

        if (!day.isRestDay) {
            for (group in MuscleGroup.entries) {
                val selected = group in day.muscleGroups
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            val groups = if (selected) day.muscleGroups - group else day.muscleGroups + group
                            onChange(day.copy(muscleGroups = groups))
                        }
                        .padding(vertical = 4.dp),
                ) {
                    Box(Modifier.size(8.dp).background(group.color, CircleShape))
                    Text(group.raw, style = axDisplay(13), color = Ax.Primary)
                    Spacer(Modifier.weight(1f))
                    Icon(
                        imageVector = if (selected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                        contentDescription = null,
                        tint = if (selected) Ax.Accent else Ax.Tertiary,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}
