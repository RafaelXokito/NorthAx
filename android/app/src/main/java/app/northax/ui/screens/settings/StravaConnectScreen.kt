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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.domain.model.IntervalsConnectionState
import app.northax.store.AthleteStore
import app.northax.ui.components.AxButton
import app.northax.ui.components.AxCard
import app.northax.ui.components.AxOutlineButton
import app.northax.ui.components.IconTile
import app.northax.ui.components.SectionLabel
import app.northax.ui.components.SyncedActivityRow
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlinx.coroutines.launch

/** Strava connection (server-side personal token) — the StravaConnectView port. */
@Composable
fun StravaConnectScreen(store: AthleteStore, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val strava = store.strava

    LaunchedEffect(Unit) { strava.refreshStatus() }

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
            Text("Strava", style = axDisplay(24, FontWeight.ExtraBold).tracked(-0.5), color = Ax.Primary)
        }

        // Header
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            IconTile(
                icon = Icons.AutoMirrored.Filled.DirectionsBike,
                color = Ax.Cycling,
                size = 76.dp,
                radius = 20.dp,
            )
            Text(
                strava.connectionState.connectedName ?: "Strava",
                style = axDisplay(20, FontWeight.ExtraBold),
                color = Ax.Primary,
            )
            Text(
                strava.connectionState.displayLabel.uppercase(),
                style = axMono(10, FontWeight.SemiBold).tracked(1.0),
                color = if (strava.connectionState.isConnected) Ax.Green else Ax.Secondary,
            )
        }

        if (strava.connectionState.isConnected) {
            AxCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                        AxOutlineButton(
                            label = if (strava.isSyncing) "Syncing…" else "Sync now",
                            enabled = !strava.isSyncing,
                            modifier = Modifier.weight(1f),
                        ) { scope.launch { strava.sync() } }
                        AxOutlineButton(label = "Disconnect", color = Ax.Red, modifier = Modifier.weight(1f)) {
                            scope.launch { strava.disconnect() }
                        }
                    }
                    AxOutlineButton(
                        label = when {
                            strava.isBackfillingSegments -> "Importing segments…"
                            strava.segmentsBackfillRemaining == null -> "Import segment history"
                            strava.segmentsBackfillRemaining == 0 -> "Segment history imported"
                            else -> "${strava.segmentsBackfillRemaining} left — tap to continue"
                        },
                        color = Ax.Secondary,
                        enabled = !strava.isBackfillingSegments && strava.segmentsBackfillRemaining != 0,
                        modifier = Modifier.fillMaxWidth(),
                    ) { scope.launch { strava.backfillSegments() } }
                }
            }

            if (strava.syncedActivities.isNotEmpty()) {
                SectionLabel("Synced activities")
                for (activity in strava.syncedActivities) {
                    SyncedActivityRow(activity)
                }
            }
        } else {
            AxCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        "Pull your Strava activities into NorthAx so they count toward your plan and training load. The connection is made server-side — no login required here.",
                        style = axDisplay(13.5),
                        color = Ax.Secondary,
                    )
                    (strava.connectionState as? IntervalsConnectionState.Error)?.let {
                        Text(it.message, style = axDisplay(12.5), color = Ax.Red)
                    }
                    AxButton(label = "Connect Strava", modifier = Modifier.fillMaxWidth()) {
                        scope.launch { strava.connect() }
                    }
                }
            }
        }
    }
}
