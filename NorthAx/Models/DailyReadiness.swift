import Foundation

struct MetricInsight: Identifiable {
    var id = UUID()
    var label: String
    var value: String
    var unit: String
    var trend: Trend
    var explanation: String
    var context: String

    enum Trend {
        case up, down, neutral, warning

        var icon: String {
            switch self {
            case .up:      return "arrow.up.right"
            case .down:    return "arrow.down.right"
            case .neutral: return "minus"
            case .warning: return "exclamationmark.triangle"
            }
        }

        var isPositive: Bool {
            switch self {
            case .up, .neutral: return true
            case .down, .warning: return false
            }
        }
    }
}

struct DailyReadiness {
    enum Status: String {
        case peak     = "Peak"
        case high     = "High"
        case moderate = "Moderate"
        case low      = "Low"
        case rest     = "Rest Day"

        var verdict: String {
            switch self {
            case .peak:     return "Train hard today."
            case .high:     return "Good day to train."
            case .moderate: return "Train with caution."
            case .low:      return "Light activity only."
            case .rest:     return "Rest and recover."
            }
        }
    }

    var score: Int          // 0–100
    var status: Status
    var explanation: String
    var coachingNote: String

    var hrvScore: Int
    var sleepScore: Int
    var loadScore: Int
    var recoveryScore: Int

    var suggestedDomain: TrainingDomain
    var suggestedSessionTitle: String
    var suggestedDuration: Int          // minutes
    var suggestedIntensityLabel: String
    var suggestedIntensityDescription: String

    var keyInsights: [MetricInsight]
}
