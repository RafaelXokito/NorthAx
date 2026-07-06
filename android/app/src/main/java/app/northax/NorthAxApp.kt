package app.northax

import android.app.Application
import app.northax.data.AppContainer
import java.io.File
import org.osmdroid.config.Configuration

class NorthAxApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        // osmdroid (route maps): a real user agent is an OSM tile-policy
        // requirement; tiles cache in app-private storage (no permissions).
        Configuration.getInstance().apply {
            userAgentValue = BuildConfig.APPLICATION_ID
            osmdroidBasePath = cacheDir
            osmdroidTileCache = File(cacheDir, "osm_tiles")
        }
    }
}
