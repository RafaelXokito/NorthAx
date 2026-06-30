import Foundation

/// Backend connection configuration. The base URL differs per build:
/// DEBUG points at the Raspberry Pi production server on the LAN (by IP; ATS is
/// permitted via `NSAllowsLocalNetworking` in Info.plist). Release points at the
/// public domain. Override at runtime via the `NORTHAX_API_BASE_URL` env var.
enum APIConfig {
    static let baseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["NORTHAX_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        return URL(string: "http://192.168.1.203:8080/v1")!   // Raspberry Pi (rafaelpereira)
        #else
        return URL(string: "https://api.northax.app/v1")!
        #endif
    }()

    /// Custom URL scheme used for the Garmin OAuth callback deep link.
    static let appScheme = "northax"
}
