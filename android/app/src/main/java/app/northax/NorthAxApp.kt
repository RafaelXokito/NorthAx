package app.northax

import android.app.Application
import app.northax.data.AppContainer

class NorthAxApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
