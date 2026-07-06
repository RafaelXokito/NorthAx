package app.northax

import android.app.Application
import app.northax.data.AppContainer
import org.maplibre.android.MapLibre

class NorthAxApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        // MapLibre (route maps) must be initialized before any MapView inflates.
        MapLibre.getInstance(this)
    }
}
