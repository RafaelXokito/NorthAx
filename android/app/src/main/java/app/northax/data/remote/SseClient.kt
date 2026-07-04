package app.northax.data.remote

import app.northax.data.remote.dto.CoachMessageRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.time.Duration

/** One parsed event from the coach SSE stream. */
sealed class CoachStreamEvent {
    data class Delta(val text: String) : CoachStreamEvent()               // incremental text
    data class Done(val messageId: String, val fullContent: String) : CoachStreamEvent()
    data class Failed(val error: ApiError) : CoachStreamEvent()           // server emitted an error event
}

/**
 * Streams Server-Sent Events from the coach endpoint and yields typed events.
 * Reads the response body line by line so deltas surface as they arrive.
 */
class SseClient(private val client: ApiClient, private val tokens: TokenStore) {

    private val json = JsonCoders.json

    /** POST `body` to `path` and stream coach events. The flow finishes after
     *  `done`, or throws [ApiError] on transport/HTTP failure. */
    fun coachStream(path: String, body: CoachMessageRequest): Flow<CoachStreamEvent> = flow {
        val request = Request.Builder()
            .url("${ApiConfig.baseUrl}/$path")
            .post(json.encodeToString(CoachMessageRequest.serializer(), body)
                .toRequestBody("application/json".toMediaType()))
            .header("Accept", "text/event-stream")
            .apply { tokens.accessToken?.let { header("Authorization", "Bearer $it") } }
            .build()

        val streamingClient = client.httpClient.newBuilder()
            .readTimeout(Duration.ofMinutes(5))
            .build()

        val response = try {
            streamingClient.newCall(request).execute()
        } catch (e: IOException) {
            throw ApiError.offline()
        }

        response.use { resp ->
            if (resp.code !in 200..299) {
                throw ApiError("HTTP_${resp.code}", "Coach stream failed.", resp.code)
            }
            val source = resp.body?.source() ?: throw ApiError.decoding()

            var eventName = "message"
            val dataLines = mutableListOf<String>()

            suspend fun flush() {
                if (dataLines.isEmpty()) {
                    eventName = "message"
                    return
                }
                val payload = dataLines.joinToString("\n")
                dataLines.clear()
                val name = eventName
                eventName = "message"
                parse(name, payload)?.let { emit(it) }
            }

            while (true) {
                val line = source.readUtf8Line() ?: break
                when {
                    line.isEmpty() -> flush() // blank line terminates an event
                    line.startsWith("event:") -> eventName = line.removePrefix("event:").trim()
                    line.startsWith("data:") -> dataLines.add(line.removePrefix("data:").trim())
                }
            }
            flush()
        }
    }.flowOn(Dispatchers.IO)

    // MARK: - Frame parsing

    private fun parse(name: String, payload: String): CoachStreamEvent? {
        val obj = try {
            json.parseToJsonElement(payload).jsonObject
        } catch (_: Exception) {
            return null
        }
        return when (name) {
            "delta" -> obj["text"]?.jsonPrimitive?.content?.let { CoachStreamEvent.Delta(it) }
            "done" -> CoachStreamEvent.Done(
                messageId = obj["messageId"]?.jsonPrimitive?.content ?: "",
                fullContent = obj["fullContent"]?.jsonPrimitive?.content ?: "",
            )
            "error" -> {
                val code = obj["code"]?.jsonPrimitive?.content
                CoachStreamEvent.Failed(ApiError(code ?: "AI_UNAVAILABLE", "Coach unavailable.", 503))
            }
            else -> null
        }
    }
}
