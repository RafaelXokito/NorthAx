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

    // MARK: - Mock data

    static var mockActivities: [GarminActivity] {
        let cal = Calendar.current
        let now = Date()
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now)! }
        return [
            GarminActivity(id: "1", name: "Morning Ride", type: .cycling,
                           startTime: daysAgo(1), duration: 4500,
                           distanceMeters: 32_000, elevationGain: 380,
                           avgHeartRate: 142, maxHeartRate: 168, calories: 820, trainingLoad: 72),
            GarminActivity(id: "2", name: "Easy Run", type: .running,
                           startTime: daysAgo(3), duration: 2700,
                           distanceMeters: 8_500, elevationGain: 95,
                           avgHeartRate: 138, maxHeartRate: 155, calories: 480, trainingLoad: 45),
            GarminActivity(id: "3", name: "Strength Session", type: .strengthTraining,
                           startTime: daysAgo(4), duration: 3600,
                           distanceMeters: nil, elevationGain: nil,
                           avgHeartRate: 118, maxHeartRate: 148, calories: 420, trainingLoad: 38),
            GarminActivity(id: "4", name: "Zone 3 Intervals", type: .cycling,
                           startTime: daysAgo(5), duration: 5400,
                           distanceMeters: 45_000, elevationGain: 520,
                           avgHeartRate: 158, maxHeartRate: 178, calories: 1180, trainingLoad: 98),
            GarminActivity(id: "5", name: "Recovery Ride", type: .cycling,
                           startTime: daysAgo(7), duration: 3600,
                           distanceMeters: 28_000, elevationGain: 120,
                           avgHeartRate: 128, maxHeartRate: 145, calories: 640, trainingLoad: 42)
        ]
    }
}

// MARK: - Connection state

enum GarminConnectionState: Equatable {
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
