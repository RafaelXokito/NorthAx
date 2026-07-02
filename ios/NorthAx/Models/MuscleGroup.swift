import SwiftUI

enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case chest      = "Chest"
    case back       = "Back"
    case shoulders  = "Shoulders"
    case biceps     = "Biceps"
    case triceps    = "Triceps"
    case quads      = "Quads"
    case hamstrings = "Hamstrings"
    case glutes     = "Glutes"
    case calves     = "Calves"
    case core       = "Core"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chest:      return "figure.strengthtraining.traditional"
        case .back:       return "figure.rowing"
        case .shoulders:  return "figure.arms.open"
        case .biceps:     return "dumbbell"
        case .triceps:    return "dumbbell.fill"
        case .quads:      return "figure.squat"
        case .hamstrings: return "figure.walk"
        case .glutes:     return "figure.step.training"
        case .calves:     return "figure.run"
        case .core:       return "figure.core.training"
        }
    }

    var color: Color {
        switch self {
        case .chest, .shoulders, .triceps:          return .axStrengthSport // push
        case .back, .biceps:                         return .axBlue    // pull
        case .quads, .hamstrings, .glutes, .calves: return .axGreen   // legs
        case .core:                                  return .axPurple  // core
        }
    }

    /// Minimum recovery time in hours before this muscle group can be trained again
    var recoveryHours: Int {
        switch self {
        case .quads, .hamstrings, .glutes: return 72
        case .chest, .back:                return 60
        case .shoulders:                   return 48
        case .biceps, .triceps:            return 48
        case .calves, .core:               return 36
        }
    }
}

// MARK: - Day split

struct DaySplit: Codable {
    var muscleGroups: [MuscleGroup]
    var isRestDay: Bool

    static var rest: DaySplit { DaySplit(muscleGroups: [], isRestDay: true) }

    var displayName: String {
        if isRestDay || muscleGroups.isEmpty { return "Rest" }
        if muscleGroups.count > 2 { return "\(muscleGroups[0].rawValue) + \(muscleGroups.count - 1) more" }
        return muscleGroups.map(\.rawValue).joined(separator: " + ")
    }
}

// MARK: - Weekly split

struct WeeklyMuscleGroupSplit: Codable {
    /// Seven entries, index 0 = Monday, 6 = Sunday
    var days: [DaySplit]

    init(days: [DaySplit]) {
        precondition(days.count == 7)
        self.days = days
    }

    func split(forCalendarWeekday weekday: Int) -> DaySplit {
        // Calendar.weekday: 1=Sun, 2=Mon … 7=Sat → map to 0=Mon … 6=Sun
        let idx = (weekday + 5) % 7
        return days[idx]
    }

    // MARK: Presets

    static var pushPullLegs: WeeklyMuscleGroupSplit {
        WeeklyMuscleGroupSplit(days: [
            DaySplit(muscleGroups: [.chest, .shoulders, .triceps], isRestDay: false), // Mon – Push
            DaySplit(muscleGroups: [.back, .biceps],                isRestDay: false), // Tue – Pull
            DaySplit(muscleGroups: [.quads, .hamstrings, .glutes, .calves], isRestDay: false), // Wed – Legs
            .rest,                                                                     // Thu
            DaySplit(muscleGroups: [.chest, .shoulders, .triceps], isRestDay: false), // Fri – Push
            DaySplit(muscleGroups: [.back, .biceps],                isRestDay: false), // Sat – Pull
            .rest                                                                      // Sun
        ])
    }

    static var upperLower: WeeklyMuscleGroupSplit {
        let upper: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps]
        let lower: [MuscleGroup] = [.quads, .hamstrings, .glutes, .calves]
        return WeeklyMuscleGroupSplit(days: [
            DaySplit(muscleGroups: upper, isRestDay: false), // Mon
            DaySplit(muscleGroups: lower, isRestDay: false), // Tue
            .rest,                                           // Wed
            DaySplit(muscleGroups: upper, isRestDay: false), // Thu
            DaySplit(muscleGroups: lower, isRestDay: false), // Fri
            .rest,                                           // Sat
            .rest                                            // Sun
        ])
    }

    static var fullBody: WeeklyMuscleGroupSplit {
        let all: [MuscleGroup] = [.chest, .back, .quads, .hamstrings, .shoulders, .core]
        return WeeklyMuscleGroupSplit(days: [
            DaySplit(muscleGroups: all, isRestDay: false),
            .rest,
            DaySplit(muscleGroups: all, isRestDay: false),
            .rest,
            DaySplit(muscleGroups: all, isRestDay: false),
            .rest,
            .rest
        ])
    }
}
