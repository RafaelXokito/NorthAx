import Foundation

enum GoalType: String, Codable {
    case raceTime          // Running: distance + finish time
    case powerHold         // Cycling: hold a power zone for a duration
    case distanceAvgSpeed  // Cycling: distance at an average speed
}

/// One structured goal per sport, fed to the AI planner and the post-sync
/// progress analysis. Flat struct + `goalType` discriminator, matching the
/// AthleteThresholds style.
struct SportTarget: Codable, Equatable {
    var goalType: GoalType
    var targetDate: Date
    var distanceKm: Double?      // raceTime, distanceAvgSpeed
    var finishTimeSec: Int?      // raceTime
    var zone: Int?               // powerHold (1-5)
    var holdMinutes: Int?        // powerHold
    var avgSpeedKmh: Double?     // distanceAvgSpeed
}

/// Latest AI goal-progress verdict for one targeted sport.
struct GoalCheck: Identifiable, Equatable {
    enum Verdict: String {
        case onTrack = "on_track"
        case behind
        case ahead
    }

    var domain: TrainingDomain
    var verdict: Verdict
    var summary: String
    var recommendReplan: Bool
    var analyzedAt: Date

    var id: TrainingDomain { domain }
}
