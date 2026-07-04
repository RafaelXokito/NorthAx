package app.northax.data.remote

import kotlinx.serialization.Serializable

/**
 * Typed representation of the backend's error envelope:
 * `{ "error": { "code", "message", "status" } }`.
 *
 * `code` is the machine-readable string (e.g. `METRICS_NOT_FOUND`) so the UI
 * can react to specific conditions rather than parsing messages.
 */
class ApiError(
    val code: String,
    val message2: String,
    val status: Int,
) : Exception(message2) {

    val isUnauthorized: Boolean get() = status == 401
    val isNotFound: Boolean get() = status == 404

    // Known codes worth branching on in the UI.
    val isIntervalsNotConfigured: Boolean get() = code == "INTERVALS_NOT_CONFIGURED"

    val userMessage: String get() = message2

    companion object {
        /** Network/transport failure with no HTTP response (offline, timeout). */
        fun offline() = ApiError("OFFLINE", "No connection.", 0)

        /** Response could not be decoded. */
        fun decoding() = ApiError("DECODING_ERROR", "Unexpected response.", 0)
    }
}

/** Wire shape of the error envelope for decoding. */
@Serializable
data class ApiErrorEnvelope(val error: Body) {
    @Serializable
    data class Body(val code: String, val message: String, val status: Int)
}
