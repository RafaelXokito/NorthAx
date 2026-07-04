package app.northax.ui.screens.settings

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.domain.model.ActivitySource
import app.northax.domain.model.MergeableMetric
import app.northax.store.AthleteStore
import app.northax.ui.components.SectionLabel
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked

/** Per-metric and activity source priority — the MetricPriorityView port.
 *  Android ranks intervals.icu vs manual (Apple Health is iOS-only). */
@Composable
fun MetricPriorityScreen(store: AthleteStore, onBack: () -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .fillMaxSize()
            .background(Ax.Background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back",
                tint = Ax.Primary,
                modifier = Modifier.size(24.dp).clickable(onClick = onBack),
            )
            Spacer(Modifier.width(14.dp))
            Text("Source priority", style = axDisplay(24, FontWeight.ExtraBold).tracked(-0.5), color = Ax.Primary)
        }

        Text(
            "When more than one source reports the same reading, the highest-priority source wins. The rest gap-fill anything it's missing.",
            style = axDisplay(13),
            color = Ax.Secondary,
        )

        SectionLabel("Wellness metrics")
        for (metric in MergeableMetric.entries) {
            val current = store.metricPriority.sources(metric).firstOrNull()
            PriorityRow(
                title = metric.displayName,
                subtitle = "Primary: ${current?.displayName ?: "–"}",
                options = metric.candidateSources.map { it.displayName },
                selectedIndex = metric.candidateSources.indexOfFirst { it == current },
            ) { index ->
                store.updateMetricPriority(
                    store.metricPriority.settingPrimary(metric.candidateSources[index], metric)
                )
            }
        }

        SectionLabel("Activity data")
        Text(
            "Used to de-duplicate the same workout reported by several sources.",
            style = axDisplay(12.5),
            color = Ax.Tertiary,
        )
        val currentActivity = store.activityPriority.primary
        PriorityRow(
            title = "Workouts",
            subtitle = "Primary: ${currentActivity.displayName}",
            options = ActivitySource.entries.map { it.displayName },
            selectedIndex = ActivitySource.entries.indexOf(currentActivity),
        ) { index ->
            store.updateActivityPriority(
                store.activityPriority.settingPrimary(ActivitySource.entries[index])
            )
        }
    }
}

@Composable
private fun PriorityRow(
    title: String,
    subtitle: String,
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(16.dp)

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Ax.Surface)
            .border(1.dp, Ax.Border, shape)
            .padding(16.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.weight(1f)) {
            Text(title, style = axDisplay(14, FontWeight.SemiBold), color = Ax.Primary)
            Text(subtitle, style = axDisplay(12), color = Ax.Secondary)
        }

        Box {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier.clickable { menuOpen = true },
            ) {
                Text(
                    options.getOrNull(selectedIndex)?.uppercase() ?: "–",
                    style = axMono(10, FontWeight.SemiBold).tracked(0.6),
                    color = Ax.Accent,
                )
                Icon(Icons.Filled.ExpandMore, contentDescription = null, tint = Ax.Accent, modifier = Modifier.size(16.dp))
            }
            DropdownMenu(
                expanded = menuOpen,
                onDismissRequest = { menuOpen = false },
                containerColor = Ax.Surface,
            ) {
                options.forEachIndexed { i, option ->
                    DropdownMenuItem(
                        text = { Text(option, style = axDisplay(13.5), color = Ax.Primary) },
                        trailingIcon = {
                            if (i == selectedIndex) {
                                Icon(Icons.Filled.Check, contentDescription = null, tint = Ax.Accent, modifier = Modifier.size(16.dp))
                            }
                        },
                        onClick = {
                            menuOpen = false
                            onSelect(i)
                        },
                    )
                }
            }
        }
    }
}
