import Foundation
import Security

/// Persists the access + refresh JWT pair in the Keychain (not UserDefaults).
/// Access TTL 15 min, refresh 60 days (spec §3.2). Thread-safe via a serial queue.
final class TokenStore {
    static let shared = TokenStore()

    private let service = "app.northax.tokens"
    private let accessAccount = "accessToken"
    private let refreshAccount = "refreshToken"
    private let queue = DispatchQueue(label: "app.northax.tokenstore")

    private init() {}

    var accessToken: String? { read(accessAccount) }
    var refreshToken: String? { read(refreshAccount) }
    var hasSession: Bool { refreshToken != nil }

    func save(accessToken: String, refreshToken: String) {
        queue.sync {
            write(accessToken, account: accessAccount)
            write(refreshToken, account: refreshAccount)
        }
    }

    func updateAccess(_ token: String) {
        queue.sync { write(token, account: accessAccount) }
    }

    func clear() {
        queue.sync {
            delete(accessAccount)
            delete(refreshAccount)
        }
    }

    // MARK: - Keychain primitives

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        var query = baseQuery(account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
