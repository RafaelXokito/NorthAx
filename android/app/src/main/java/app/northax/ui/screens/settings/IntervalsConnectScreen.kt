package app.northax.ui.screens.settings

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.SyncAlt
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.northax.domain.model.IntervalsConnectionState
import app.northax.store.AthleteStore
import app.northax.ui.components.AxButton
import app.northax.ui.components.AxCard
import app.northax.ui.components.AxOutlineButton
import app.northax.ui.components.SectionLabel
import app.northax.ui.components.SyncedActivityRow
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlinx.coroutines.launch

/** intervals.icu connection (OAuth via Custom Tab or personal API key) —
 *  the IntervalsConnectView port. */
@Composable
fun IntervalsConnectScreen(store: AthleteStore, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val intervals = store.intervals
    var athleteId by rememberSaveable { mutableStateOf("") }
    var apiKey by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(Unit) { intervals.refreshStatus() }

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
            Text("intervals.icu", style = axDisplay(24, FontWeight.ExtraBold).tracked(-0.5), color = Ax.Primary)
        }

        // Status card
        AxCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                val state = intervals.connectionState
                val (icon, color) = when (state) {
                    is IntervalsConnectionState.Connected -> Icons.Filled.CheckCircle to Ax.Green
                    is IntervalsConnectionState.Error -> Icons.Filled.ErrorOutline to Ax.Red
                    IntervalsConnectionState.Connecting -> Icons.Filled.SyncAlt to Ax.Accent
                    else -> Icons.Filled.WifiOff to Ax.Secondary
                }
                if (state == IntervalsConnectionState.Connecting) {
                    CircularProgressIndicator(color = Ax.Accent, modifier = Modifier.size(30.dp))
                } else {
                    Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(34.dp))
                }
                Text(
                    state.connectedName ?: "intervals.icu",
                    style = axDisplay(17, FontWeight.Bold),
                    color = Ax.Primary,
                )
                Text(
                    state.displayLabel.uppercase(),
                    style = axMono(10, FontWeight.SemiBold).tracked(1.0),
                    color = color,
                )

                if (state.isConnected) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                        AxOutlineButton(
                            label = if (intervals.isSyncing) "Syncing…" else "Sync now",
                            enabled = !intervals.isSyncing,
                            modifier = Modifier.weight(1f),
                        ) { scope.launch { intervals.syncActivities() } }
                        AxOutlineButton(label = "Disconnect", color = Ax.Red, modifier = Modifier.weight(1f)) {
                            scope.launch { intervals.disconnect() }
                        }
                    }
                } else {
                    AxButton(label = "Connect intervals.icu", modifier = Modifier.fillMaxWidth()) {
                        scope.launch {
                            intervals.beginConnect()?.let { url ->
                                CustomTabsIntent.Builder().build()
                                    .launchUrl(context, Uri.parse(url))
                            }
                        }
                    }
                }
            }
        }

        if (intervals.connectionState.isConnected) {
            if (intervals.syncedActivities.isNotEmpty()) {
                SectionLabel("Synced activities")
                for (activity in intervals.syncedActivities) {
                    SyncedActivityRow(activity)
                }
            }
        } else {
            // How it works
            AxCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionLabel("How it works")
                    InfoRow(Icons.Filled.Timeline, "intervals.icu aggregates your Garmin (and more) training + wellness data.")
                    InfoRow(Icons.Filled.SyncAlt, "Activities, HRV, sleep, and load sync automatically.")
                    InfoRow(Icons.Filled.Insights, "NorthAx turns them into readiness and an adaptive plan.")
                    InfoRow(Icons.Filled.Lock, "Tokens stay on the server — the app never sees your credentials.")
                }
            }

            // API key fallback
            AxCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionLabel("Or connect with an API key")
                    ApiKeyField(value = athleteId, onValueChange = { athleteId = it }, placeholder = "Athlete id (e.g. i12345)")
                    ApiKeyField(
                        value = apiKey, onValueChange = { apiKey = it },
                        placeholder = "API key", secure = true,
                    )
                    AxButton(
                        label = "Connect with API key",
                        enabled = athleteId.isNotBlank() && apiKey.isNotBlank(),
                        height = 44.dp,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        scope.launch { intervals.connectWithApiKey(athleteId.trim(), apiKey.trim()) }
                    }
                }
            }
        }
    }
}

@Composable
private fun InfoRow(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, contentDescription = null, tint = Ax.Accent, modifier = Modifier.size(18.dp))
        Text(text, style = axDisplay(13), color = Ax.Secondary)
    }
}

@Composable
private fun ApiKeyField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    secure: Boolean = false,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, style = axDisplay(13.5), color = Ax.Tertiary) },
        singleLine = true,
        textStyle = axDisplay(13.5),
        visualTransformation = if (secure) PasswordVisualTransformation()
        else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (secure) KeyboardType.Password else KeyboardType.Text),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Ax.Inset,
            unfocusedContainerColor = Ax.Inset,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            cursorColor = Ax.Accent,
            focusedTextColor = Ax.Primary,
            unfocusedTextColor = Ax.Primary,
        ),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth(),
    )
}
