import Foundation

/// One parsed event from the coach SSE stream (§8.2).
enum CoachStreamEvent {
    case delta(String)                              // incremental text
    case done(messageId: String, fullContent: String)
    case failed(APIError)                           // server emitted an error event
}

/// Streams Server-Sent Events from the coach endpoint and yields typed events.
/// Uses `URLSession.bytes` so deltas surface as they arrive.
final class SSEClient {
    static let shared = SSEClient()

    private let session: URLSession = .shared
    private let tokens = TokenStore.shared

    /// POST `body` to `path` and stream coach events. The stream finishes after
    /// `done`, or throws `APIError` on transport/HTTP failure.
    func coachStream(path: String, body: Encodable) -> AsyncThrowingStream<CoachStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = APIConfig.baseURL.appendingPathComponent(path)
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if let token = tokens.accessToken {
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    req.httpBody = try JSONCoders.encoder.encode(AnyEncodableBox(body))

                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.decoding
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw APIError(code: "HTTP_\(http.statusCode)", message: "Coach stream failed.", status: http.statusCode)
                    }

                    var eventName = "message"
                    var dataLines: [String] = []

                    func flush() {
                        guard !dataLines.isEmpty else { eventName = "message"; return }
                        let payload = dataLines.joined(separator: "\n")
                        dataLines.removeAll()
                        let name = eventName
                        eventName = "message"
                        if let event = Self.parse(name: name, payload: payload) {
                            continuation.yield(event)
                        }
                    }

                    for try await line in bytes.lines {
                        if line.isEmpty {
                            flush()                 // blank line terminates an event
                        } else if line.hasPrefix("event:") {
                            eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5).trimmingCharacters(in: .whitespaces)))
                        }
                    }
                    flush()
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: APIError.offline)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Frame parsing

    private static func parse(name: String, payload: String) -> CoachStreamEvent? {
        guard let data = payload.data(using: .utf8) else { return nil }
        switch name {
        case "delta":
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = obj["text"] as? String {
                return .delta(text)
            }
        case "done":
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let id = obj["messageId"] as? String ?? ""
                let full = obj["fullContent"] as? String ?? ""
                return .done(messageId: id, fullContent: full)
            }
        case "error":
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String
            return .failed(APIError(code: code ?? "AI_UNAVAILABLE", message: "Coach unavailable.", status: 503))
        default:
            return nil
        }
        return nil
    }
}

/// Local type-eraser (mirrors the one in APIClient; kept private per file).
private struct AnyEncodableBox: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFn = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}
