import Foundation

/// Backend connection configuration. The base URL differs per build:
/// DEBUG points at a local/dev server (add an ATS exception for `localhost`),
/// release points at production. Override at runtime via the
/// `NORTHAX_API_BASE_URL` environment variable / launch argument when testing
/// against a device-reachable dev backend.
enum APIConfig {
    static let baseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["NORTHAX_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        return URL(string: "http://localhost:8080/v1")!
        #else
        return URL(string: "https://api.northax.app/v1")!
        #endif
    }()

    /// Custom URL scheme used for the Garmin OAuth callback deep link.
    static let appScheme = "northax"
}
