package app.northax.data

import android.content.Context
import app.northax.data.local.LocalPrefs
import app.northax.data.remote.ApiClient
import app.northax.data.remote.NorthAxApi
import app.northax.data.remote.SseClient
import app.northax.data.remote.TokenStore

/** Manual dependency container — one instance per process, owned by the Application. */
class AppContainer(context: Context) {
    val tokens = TokenStore(context)
    val prefs = LocalPrefs(context)
    val apiClient = ApiClient(tokens)
    val api = NorthAxApi(apiClient)
    val sse = SseClient(apiClient, tokens)
}
