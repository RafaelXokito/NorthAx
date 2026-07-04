package app.northax

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import app.northax.store.AthleteStore
import app.northax.store.AuthService
import app.northax.ui.AppRoot
import app.northax.ui.theme.NorthAxTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val factory by lazy {
        val container = (application as NorthAxApp).container
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T = when (modelClass) {
                AuthService::class.java -> AuthService(container) as T
                AthleteStore::class.java -> AthleteStore(container) as T
                else -> throw IllegalArgumentException("Unknown ViewModel $modelClass")
            }
        }
    }

    private val authService: AuthService by viewModels { factory }
    private val store: AthleteStore by viewModels { factory }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            NorthAxTheme {
                AppRoot(authService = authService, store = store)
            }
        }

        // Foregrounding pre-fetches AI switch suggestions on the first
        // foreground of a new day and pulls the latest from connected sources
        // (throttled) — mirrors the iOS scenePhase hook.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.RESUMED) {
                if (authService.isAuthenticated) {
                    store.prefetchDailySuggestionsIfNeeded()
                    store.syncConnectedSourcesIfNeeded()
                }
            }
        }

        handleDeepLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDeepLink(intent)
    }

    /** OAuth callback deep links: northax://intervals/connected etc. */
    private fun handleDeepLink(intent: Intent?) {
        val uri: Uri = intent?.data ?: return
        if (uri.scheme != "northax") return
        when (uri.host) {
            "intervals" -> lifecycleScope.launch {
                if (uri.path?.contains("connected") == true) {
                    store.intervals.completeConnect()
                } else {
                    store.intervals.refreshStatus()
                }
            }
            "strava" -> lifecycleScope.launch { store.strava.refreshStatus() }
        }
    }
}
