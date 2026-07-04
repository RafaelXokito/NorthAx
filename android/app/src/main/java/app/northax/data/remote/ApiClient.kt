package app.northax.data.remote

import app.northax.data.remote.dto.RefreshRequest
import app.northax.data.remote.dto.RefreshResponse
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.time.Duration
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Async HTTP client for the NorthAx backend. Injects the bearer token, decodes
 * DTOs with the shared coders, maps the error envelope to [ApiError], and
 * transparently refreshes + retries once on a 401 — a 1:1 port of the iOS
 * APIClient (including the single-flight token refresher).
 */
class ApiClient(private val tokens: TokenStore) {

    val json = JsonCoders.json
    val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(Duration.ofSeconds(15))
        .readTimeout(Duration.ofSeconds(30))
        .build()

    /** Emits when the refresh token is rejected — AuthService observes this to
     *  drop the session and return the user to sign-in. */
    private val _sessionExpired = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val sessionExpired: SharedFlow<Unit> = _sessionExpired

    // MARK: - Typed entry points

    suspend inline fun <reified T> get(
        path: String,
        query: Map<String, String> = emptyMap(),
        authenticated: Boolean = true,
    ): T = decode(perform("GET", path, query, null, authenticated))

    suspend inline fun <reified T, reified B> post(
        path: String,
        body: B? = null,
        authenticated: Boolean = true,
        timeoutSeconds: Long? = null,
    ): T = decode(perform("POST", path, emptyMap(), encode(body), authenticated, timeoutSeconds = timeoutSeconds))

    suspend inline fun <reified T, reified B> patch(
        path: String,
        body: B? = null,
        authenticated: Boolean = true,
    ): T = decode(perform("PATCH", path, emptyMap(), encode(body), authenticated))

    /** For endpoints that return no content (204). */
    suspend inline fun <reified B> send(
        method: String,
        path: String,
        body: B? = null,
        authenticated: Boolean = true,
    ): String = perform(method, path, emptyMap(), encode(body), authenticated)

    suspend fun send(method: String, path: String): String =
        perform(method, path, emptyMap(), null, true)

    // MARK: - Encoding / decoding

    inline fun <reified B> encode(body: B?): String? =
        body?.let { json.encodeToString(it) }

    inline fun <reified T> decode(data: String): T =
        try {
            json.decodeFromString<T>(data)
        } catch (e: Exception) {
            throw ApiError.decoding()
        }

    // MARK: - Core

    suspend fun perform(
        method: String,
        path: String,
        query: Map<String, String>,
        bodyJson: String?,
        authenticated: Boolean,
        allowRetry: Boolean = true,
        timeoutSeconds: Long? = null,
    ): String {
        val urlBuilder = "${ApiConfig.baseUrl}/$path".toHttpUrl().newBuilder()
        query.forEach { (k, v) -> urlBuilder.addQueryParameter(k, v) }

        val builder = Request.Builder()
            .url(urlBuilder.build())
            .method(method, bodyJson?.toRequestBody("application/json".toMediaType()))
        if (authenticated) {
            tokens.accessToken?.let { builder.header("Authorization", "Bearer $it") }
        }

        val client = timeoutSeconds?.let {
            httpClient.newBuilder()
                .readTimeout(Duration.ofSeconds(it))
                .callTimeout(Duration.ofSeconds(it))
                .build()
        } ?: httpClient

        val (code, data) = execute(client, builder.build())

        if (code == 401 && authenticated && allowRetry) {
            if (refresher.refresh()) {
                return perform(method, path, query, bodyJson, authenticated, allowRetry = false, timeoutSeconds)
            }
            tokens.clear()
            _sessionExpired.tryEmit(Unit)
            throw mapError(data, 401)
        }

        if (code in 200..299) return data
        throw mapError(data, code)
    }

    private suspend fun execute(client: OkHttpClient, request: Request): Pair<Int, String> =
        suspendCancellableCoroutine { cont ->
            val call = client.newCall(request)
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (cont.isActive) cont.resumeWithException(ApiError.offline())
                }

                override fun onResponse(call: Call, response: Response) {
                    response.use {
                        val body = it.body?.string() ?: ""
                        if (cont.isActive) cont.resume(it.code to body)
                    }
                }
            })
        }

    private fun mapError(data: String, status: Int): ApiError {
        val env = try {
            json.decodeFromString<ApiErrorEnvelope>(data)
        } catch (_: Exception) {
            null
        }
        return env?.let { ApiError(it.error.code, it.error.message, it.error.status) }
            ?: ApiError("HTTP_$status", "Request failed ($status).", status)
    }

    // MARK: - Refresh (single-flight)

    private val refresher = TokenRefresher()

    suspend fun performRefresh(): Boolean {
        val refresh = tokens.refreshToken ?: return false
        return try {
            val body = json.encodeToString(RefreshRequest(refresh))
            val data = perform("POST", "auth/refresh", emptyMap(), body, authenticated = false, allowRetry = false)
            val resp = json.decodeFromString<RefreshResponse>(data)
            tokens.save(resp.accessToken, resp.refreshToken)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Serializes concurrent token refreshes into a single in-flight request so
     * a burst of 401s triggers exactly one `/auth/refresh`.
     */
    private inner class TokenRefresher {
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        private val mutex = Mutex()
        private var inFlight: Deferred<Boolean>? = null

        suspend fun refresh(): Boolean {
            val task = mutex.withLock {
                inFlight ?: scope.async { performRefresh() }.also { inFlight = it }
            }
            val result = task.await()
            mutex.withLock { if (inFlight == task) inFlight = null }
            return result
        }
    }
}
