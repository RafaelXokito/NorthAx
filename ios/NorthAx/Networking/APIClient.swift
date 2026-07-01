import Foundation

/// Posted when the refresh token is rejected — AuthService observes this to
/// drop the session and return the user to sign-in.
extension Notification.Name {
    static let northaxSessionExpired = Notification.Name("northax.sessionExpired")
}

/// Type-erasing wrapper so heterogeneous request bodies encode through one path.
private struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFn = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}

/// Async HTTP client for the NorthAx backend. Injects the bearer token, decodes
/// DTOs with the shared coders, maps the §11 error envelope to `APIError`, and
/// transparently refreshes + retries once on a 401 (§3.2).
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let tokens = TokenStore.shared
    private let refresher = TokenRefresher()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Typed entry points

    func get<T: Decodable>(_ path: String, query: [URLQueryItem]? = nil, authenticated: Bool = true) async throws -> T {
        try decode(await perform("GET", path, query, nil, authenticated))
    }

    func post<T: Decodable>(_ path: String, body: Encodable? = nil, authenticated: Bool = true, timeout: TimeInterval? = nil) async throws -> T {
        try decode(await perform("POST", path, nil, encode(body), authenticated, timeout: timeout))
    }

    func put<T: Decodable>(_ path: String, body: Encodable? = nil, authenticated: Bool = true) async throws -> T {
        try decode(await perform("PUT", path, nil, encode(body), authenticated))
    }

    func patch<T: Decodable>(_ path: String, body: Encodable? = nil, authenticated: Bool = true) async throws -> T {
        try decode(await perform("PATCH", path, nil, encode(body), authenticated))
    }

    /// For endpoints that return no content (204).
    @discardableResult
    func send(_ method: String, _ path: String, body: Encodable? = nil, authenticated: Bool = true) async throws -> Data {
        try await perform(method, path, nil, encode(body), authenticated)
    }

    // MARK: - Refresh (called by TokenRefresher)

    func performRefresh() async -> Bool {
        guard let refresh = tokens.refreshToken else { return false }
        do {
            let body = try JSONCoders.encoder.encode(RefreshRequest(refreshToken: refresh))
            let data = try await perform("POST", "auth/refresh", nil, body, false, allowRetry: false)
            let resp = try JSONCoders.decoder.decode(RefreshResponse.self, from: data)
            tokens.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Core

    private func encode(_ body: Encodable?) -> Data? {
        guard let body else { return nil }
        return try? JSONCoders.encoder.encode(AnyEncodable(body))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONCoders.decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding }
    }

    private func makeRequest(_ method: String, _ path: String, _ query: [URLQueryItem]?, _ bodyData: Data?, _ authenticated: Bool, _ timeout: TimeInterval?) -> URLRequest {
        let url = APIConfig.baseURL.appendingPathComponent(path)
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if let query, !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url ?? url)
        req.httpMethod = method
        if let timeout { req.timeoutInterval = timeout }
        if let bodyData {
            req.httpBody = bodyData
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token = tokens.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func perform(_ method: String, _ path: String, _ query: [URLQueryItem]?, _ bodyData: Data?, _ authenticated: Bool, allowRetry: Bool = true, timeout: TimeInterval? = nil) async throws -> Data {
        let request = makeRequest(method, path, query, bodyData, authenticated, timeout)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.decoding }

        if http.statusCode == 401, authenticated, allowRetry {
            if await refresher.refresh(using: self) {
                return try await perform(method, path, query, bodyData, authenticated, allowRetry: false, timeout: timeout)
            }
            tokens.clear()
            await MainActor.run { NotificationCenter.default.post(name: .northaxSessionExpired, object: nil) }
            throw mapError(data, status: 401)
        }

        if (200..<300).contains(http.statusCode) { return data }
        throw mapError(data, status: http.statusCode)
    }

    private func mapError(_ data: Data, status: Int) -> APIError {
        if let env = try? JSONCoders.decoder.decode(APIErrorEnvelope.self, from: data) {
            return APIError(code: env.error.code, message: env.error.message, status: env.error.status)
        }
        return APIError(code: "HTTP_\(status)", message: "Request failed (\(status)).", status: status)
    }
}

/// Serializes concurrent token refreshes into a single in-flight request so a
/// burst of 401s triggers exactly one `/auth/refresh`.
actor TokenRefresher {
    private var inFlight: Task<Bool, Never>?

    func refresh(using client: APIClient) async -> Bool {
        if let inFlight { return await inFlight.value }
        let task = Task { await client.performRefresh() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}
