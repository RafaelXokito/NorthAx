import Foundation

/// Typed representation of the backend's error envelope (§11):
/// `{ "error": { "code", "message", "status" } }`.
///
/// `code` is the machine-readable string (e.g. `METRICS_NOT_FOUND`) so the UI
/// can react to specific conditions rather than parsing messages.
struct APIError: Error, Equatable {
    var code: String
    var message: String
    var status: Int

    /// Network/transport failure with no HTTP response (offline, timeout).
    static let offline = APIError(code: "OFFLINE", message: "No connection.", status: 0)
    /// Response could not be decoded.
    static let decoding = APIError(code: "DECODING_ERROR", message: "Unexpected response.", status: 0)

    var isUnauthorized: Bool { status == 401 }
    var isNotFound: Bool { status == 404 }

    // Known codes worth branching on in the UI.
    var isTokenExpired: Bool { code == "AUTH_TOKEN_EXPIRED" }
    var isTokenRevoked: Bool { code == "AUTH_TOKEN_REVOKED" }
    var isMetricsMissing: Bool { code == "METRICS_NOT_FOUND" }
    var isIntervalsNotConnected: Bool { code == "INTERVALS_NOT_CONNECTED" }
    var isAIUnavailable: Bool { code == "AI_UNAVAILABLE" }

    var userMessage: String { message }
}

/// Wire shape of the error envelope for decoding.
struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
        let status: Int
    }
    let error: Body
}
