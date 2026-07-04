package app.northax.ui.screens.settings

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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.northax.store.AthleteStore
import app.northax.store.AuthService
import app.northax.ui.components.NavRow
import app.northax.ui.components.SectionLabel
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlinx.coroutines.launch

/** Profile, training config, integrations, sign out — the SettingsView port. */
@Composable
fun SettingsScreen(
    store: AthleteStore,
    auth: AuthService,
    onOpenTrainingPlan: () -> Unit,
    onOpenIntegrations: () -> Unit,
) {
    var showSignOutDialog by rememberSaveable { mutableStateOf(false) }
    var nameDraft by rememberSaveable(store.athleteName) { mutableStateOf(store.athleteName) }

    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .fillMaxSize()
            .background(Ax.Background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
    ) {
        Text("Settings", style = axDisplay(32, FontWeight.ExtraBold).tracked(-0.96), color = Ax.Primary)

        // Profile
        SectionLabel("Profile")
        val shape = RoundedCornerShape(16.dp)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(Ax.Surface)
                .border(1.dp, Ax.Border, shape)
                .padding(horizontal = 16.dp, vertical = 4.dp),
        ) {
            Text("Name", style = axDisplay(14, FontWeight.SemiBold), color = Ax.Primary)
            Spacer(Modifier.weight(1f))
            TextField(
                value = nameDraft,
                onValueChange = { nameDraft = it },
                singleLine = true,
                textStyle = axDisplay(14).copy(textAlign = TextAlign.End),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    cursorColor = Ax.Accent,
                    focusedTextColor = Ax.Secondary,
                    unfocusedTextColor = Ax.Secondary,
                ),
                modifier = Modifier.width(200.dp),
            )
        }
        if (nameDraft.trim() != store.athleteName && nameDraft.isNotBlank()) {
            Text(
                "SAVE NAME",
                style = axMono(10, FontWeight.SemiBold).tracked(1.2),
                color = Ax.Accent,
                modifier = Modifier
                    .clickable { store.saveAthleteName(nameDraft.trim()) }
                    .padding(vertical = 2.dp),
            )
        }

        // Training
        SectionLabel("Training")
        NavRow(
            icon = Icons.Filled.CalendarMonth,
            iconColor = Ax.Accent,
            title = "Training plan",
            subtitle = "${store.trainingFrequency.totalSessions} sessions/week · ${store.enabledDomains.size} sports",
            onClick = onOpenTrainingPlan,
        )

        // Integrations
        SectionLabel("Integrations")
        NavRow(
            icon = Icons.Filled.Link,
            iconColor = Ax.Blue,
            title = "Data sources",
            subtitle = if (store.intervals.connectionState.isConnected) "intervals.icu connected" else "Not connected",
            subtitleColor = if (store.intervals.connectionState.isConnected) Ax.Green else Ax.Secondary,
            onClick = onOpenIntegrations,
        )

        // Account
        SectionLabel("Account")
        NavRow(
            icon = Icons.AutoMirrored.Filled.Logout,
            iconColor = Ax.Red,
            title = "Sign out",
            showChevron = false,
            isDestructive = true,
            onClick = { showSignOutDialog = true },
        )
    }

    if (showSignOutDialog) {
        AlertDialog(
            onDismissRequest = { showSignOutDialog = false },
            containerColor = Ax.Surface,
            title = { Text("Sign out?", style = axDisplay(17, FontWeight.Bold), color = Ax.Primary) },
            text = {
                Text(
                    "Your plan and preferences stay on the server; local data is cleared.",
                    style = axDisplay(13.5),
                    color = Ax.Secondary,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showSignOutDialog = false
                    store.resetForSignOut()
                    auth.signOut()
                }) {
                    Text("Sign Out", color = Ax.Red, style = axDisplay(14, FontWeight.SemiBold))
                }
            },
            dismissButton = {
                TextButton(onClick = { showSignOutDialog = false }) {
                    Text("Cancel", color = Ax.Secondary, style = axDisplay(14))
                }
            },
        )
    }
}
