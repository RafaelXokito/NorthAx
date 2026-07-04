package app.northax.ui.screens.settings

import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import app.northax.store.AthleteStore
import app.northax.store.AuthService

/** Settings tab navigation: hub → training plan / goals / integrations / sources. */
@Composable
fun SettingsNavHost(store: AthleteStore, auth: AuthService) {
    val nav = rememberNavController()

    NavHost(navController = nav, startDestination = "settings") {
        composable("settings") {
            SettingsScreen(
                store = store,
                auth = auth,
                onOpenTrainingPlan = { nav.navigate("trainingPlan") },
                onOpenIntegrations = { nav.navigate("integrations") },
            )
        }
        composable("trainingPlan") {
            TrainingPlanScreen(
                store = store,
                onBack = { nav.popBackStack() },
                onOpenGoals = { nav.navigate("goals") },
            )
        }
        composable("goals") {
            GoalsScreen(store = store, onBack = { nav.popBackStack() })
        }
        composable("integrations") {
            IntegrationsScreen(
                store = store,
                onBack = { nav.popBackStack() },
                onOpenIntervals = { nav.navigate("intervals") },
                onOpenStrava = { nav.navigate("strava") },
                onOpenPriority = { nav.navigate("metricPriority") },
            )
        }
        composable("intervals") {
            IntervalsConnectScreen(store = store, onBack = { nav.popBackStack() })
        }
        composable("strava") {
            StravaConnectScreen(store = store, onBack = { nav.popBackStack() })
        }
        composable("metricPriority") {
            MetricPriorityScreen(store = store, onBack = { nav.popBackStack() })
        }
    }
}
