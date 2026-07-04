package app.northax.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.northax.store.AppTab
import app.northax.store.AthleteStore
import app.northax.store.AuthService
import app.northax.ui.screens.auth.SignInScreen
import app.northax.ui.screens.coach.CoachScreen
import app.northax.ui.screens.dashboard.DashboardScreen
import app.northax.ui.screens.metrics.MetricsScreen
import app.northax.ui.screens.plan.PlanScreen
import app.northax.ui.screens.settings.FrequencyOnboardingSheet
import app.northax.ui.screens.settings.SettingsNavHost
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked

/** Root switch: sign-in when unauthenticated, otherwise the tabbed main app
 *  with the plan-generating overlay — the ContentView port. */
@Composable
fun AppRoot(authService: AuthService, store: AthleteStore) {
    Box(modifier = Modifier.fillMaxSize().background(Ax.Background)) {
        if (authService.isAuthenticated) {
            MainApp(authService = authService, store = store)
        } else {
            SignInScreen(auth = authService)
        }

        AnimatedVisibility(
            visible = store.isGeneratingPlan,
            enter = fadeIn(),
            exit = fadeOut(),
        ) {
            PlanGeneratingOverlay()
        }
    }

    // A session restored during AuthService init (which sets currentUser
    // before this composable starts observing) still triggers the data load.
    val user = authService.currentUser
    LaunchedEffect(user?.id) {
        if (user != null) store.configure(user)
    }
}

@Composable
private fun MainApp(authService: AuthService, store: AthleteStore) {
    Column(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
        // Plain root switch above a custom tab bar. Switching tabs resets the
        // tab's navigation history — per the design ("tabs clear the history").
        Box(modifier = Modifier.weight(1f)) {
            when (store.selectedTab) {
                AppTab.Dashboard -> DashboardScreen(store)
                // Coach tab hidden for now — kept for later (CoachScreen remains).
                AppTab.Coach -> CoachScreen(store)
                AppTab.Metrics -> MetricsScreen(store)
                AppTab.Plan -> PlanScreen(store)
                AppTab.Settings -> SettingsNavHost(store = store, auth = authService)
            }
        }

        AxTabBar(selection = store.selectedTab, onSelect = { store.selectedTab = it })
    }

    // First-launch onboarding: prompt for the training frequency.
    if (!store.hasSetFrequency) {
        FrequencyOnboardingSheet(store = store, onDismiss = { store.setHasSetFrequencyFlag(true) })
    }
}

/**
 * "Instrument" tab bar: flat line icons over mono uppercase labels on a
 * near-black strip with a top hairline.
 */
@Composable
private fun AxTabBar(selection: AppTab, onSelect: (AppTab) -> Unit) {
    val items: List<Triple<AppTab, ImageVector, String>> = listOf(
        Triple(AppTab.Dashboard, Icons.Outlined.Home, "Today"),
        Triple(AppTab.Metrics, Icons.AutoMirrored.Outlined.ShowChart, "Metrics"),
        Triple(AppTab.Plan, Icons.Outlined.CalendarMonth, "Plan"),
        Triple(AppTab.Settings, Icons.Outlined.Settings, "Settings"),
    )

    Column(modifier = Modifier.fillMaxWidth().background(Ax.Background.copy(alpha = 0.96f))) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 10.dp, bottom = 4.dp)
                .navigationBarsPadding(),
        ) {
            for ((tab, icon, label) in items) {
                val active = selection == tab
                val tint = if (active) Ax.Accent else Ax.Primary.copy(alpha = 0.38f)
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(5.dp),
                    modifier = Modifier
                        .weight(1f)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onSelect(tab) }
                        .padding(vertical = 4.dp),
                ) {
                    Icon(imageVector = icon, contentDescription = label, tint = tint, modifier = Modifier.size(23.dp))
                    Text(
                        text = label.uppercase(),
                        style = axMono(9, FontWeight.SemiBold).tracked(1.2),
                        color = tint,
                    )
                }
            }
        }
    }
}

/** Full-screen loading overlay while the AI generates the plan. */
@Composable
fun PlanGeneratingOverlay() {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxSize()
            .background(Ax.Background.copy(alpha = 0.92f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { /* swallow taps under the overlay */ },
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
            modifier = Modifier.padding(horizontal = 40.dp),
        ) {
            CircularProgressIndicator(color = Ax.Accent)
            Text(
                text = "BUILDING YOUR PLAN",
                style = axMono(11, FontWeight.SemiBold).tracked(1.8),
                color = Ax.Accent,
            )
            Text(
                text = "The coach is weighing your recovery, recent training, and goals to lay out the next two weeks.",
                style = axDisplay(13.5),
                color = Ax.Secondary,
                textAlign = TextAlign.Center,
            )
        }
    }
}
