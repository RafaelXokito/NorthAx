package app.northax.ui.screens.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.automirrored.filled.Rule
import androidx.compose.material.icons.filled.SyncAlt
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.store.AthleteStore
import app.northax.ui.components.NavRow
import app.northax.ui.components.SectionLabel
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.tracked

/** Data-source hub — the IntegrationsView port (Apple Health is iOS-only). */
@Composable
fun IntegrationsScreen(
    store: AthleteStore,
    onBack: () -> Unit,
    onOpenIntervals: () -> Unit,
    onOpenStrava: () -> Unit,
    onOpenPriority: () -> Unit,
) {
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
            Text("Data sources", style = axDisplay(24, FontWeight.ExtraBold).tracked(-0.5), color = Ax.Primary)
        }

        SectionLabel("Connected")
        NavRow(
            icon = Icons.Filled.Timeline,
            iconColor = Ax.Accent,
            title = "intervals.icu",
            subtitle = if (store.intervals.connectionState.isConnected) "Connected" else "Not connected",
            subtitleColor = if (store.intervals.connectionState.isConnected) Ax.Green else Ax.Secondary,
            onClick = onOpenIntervals,
        )
        NavRow(
            icon = Icons.AutoMirrored.Filled.DirectionsBike,
            iconColor = Ax.Cycling,
            title = "Strava",
            subtitle = if (store.strava.connectionState.isConnected) "Connected" else "Not connected",
            subtitleColor = if (store.strava.connectionState.isConnected) Ax.Green else Ax.Secondary,
            onClick = onOpenStrava,
        )

        SectionLabel("Data priority")
        NavRow(
            icon = Icons.AutoMirrored.Filled.Rule,
            iconColor = Ax.Purple,
            title = "Source priority",
            subtitle = "Choose which source wins per metric",
            onClick = onOpenPriority,
        )

        SectionLabel("Coming soon")
        Column(modifier = Modifier.alpha(0.6f)) {
            NavRow(
                icon = Icons.Filled.SyncAlt,
                iconColor = Ax.Blue,
                title = "Wahoo",
                subtitle = "Not available yet",
                showChevron = false,
            )
        }
    }
}
