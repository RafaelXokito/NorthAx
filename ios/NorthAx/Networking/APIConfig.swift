import Foundation

/// Backend connection configuration (Raspberry Pi "rafaelpereira").
/// DEBUG uses the mDNS domain `rafaelpereira.local` — works at home, and ATS
/// permits it via `NSAllowsLocalNetworking` in Info.plist.
/// Away from home, reach the Pi over Tailscale: set `NORTHAX_API_BASE_URL` to its
/// MagicDNS name, ideally HTTPS via `tailscale serve` (a valid cert needs no ATS
/// exception), e.g. `https://rafaelpereira.<tailnet>.ts.net/v1`.
enum APIConfig {
    static let baseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["NORTHAX_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        return URL(string: "http://rafaelpereira.local:8080/v1")!
        #else
        return URL(string: "https://api.northax.app/v1")!
        #endif
    }()

    /// Custom URL scheme used for the Garmin OAuth callback deep link.
    static let appScheme = "northax"
}
