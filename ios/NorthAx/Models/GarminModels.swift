import Foundation

// MARK: - Activity

enum GarminActivityType: String, Codable {
    case cycling         = "Cycling"
    case running         = "Running"
    case swimming        = "Swimming"
    case strengthTraining = "Strength Training"
    case hiking          = "Hiking"
    case yoga            = "Yoga"
    case other           = "Other"

    var domain: TrainingDomain {
        switch self {
        case .cycling:          return .cycling
        case .running:          return .running
        case .swimming:         return .swimming
        case .strengthTraining: return .strength
        case .yoga:             return .mobility
        default:                return .recovery
        }
    }
}

struct GarminActivity: Identifiable, Codable {
    var id: String
    var name: String
    var type: GarminActivityType
    var startTime: Date
    var duration: TimeInterval   // seconds
    var distanceMeters: Double?
    var elevationGain: Double?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var calories: Int?
    var trainingLoad: Double?    // normalized TSS equivalent

    var formattedDuration: String {
        let m = Int(duration / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
    }

    var formattedDistance: String? {
        guard let d = distanceMeters else { return nil }
        return String(format: "%.1f km", d / 1000)
    }

    var hoursAgo: Double { Date().timeIntervalSince(startTime) / 3600 }
}

// MARK: - Connection state

enum IntervalsConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(displayName: String, lastSync: Date)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayLabel: String {
        switch self {
        case .disconnected:               return "Not connected"
        case .connecting:                 return "Connecting…"
        case .connected(_, let d):        return "Synced \(relativeTime(d))"
        case .error(let msg):             return "Error: \(msg)"
        }
    }

    var connectedName: String? {
        if case .connected(let name, _) = self { return name }
        return nil
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff / 60))m ago" }
        return "\(Int(diff / 3600))h ago"
    }
}
