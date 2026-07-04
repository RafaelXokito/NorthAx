import Foundation

struct StrengthEngine {

    // MARK: - Public entry point

    static func generateSession(
        muscleGroups: [MuscleGroup],
        readiness: DailyReadiness,
        recentActivities: [GarminActivity]
    ) -> StrengthSession {
        let intensity = intensityFor(readiness: readiness)
        let warnings  = buildRecoveryWarnings(for: muscleGroups, recentActivities: recentActivities)
        let exercises = buildExercises(for: muscleGroups, intensity: intensity)
        let duration  = estimateDuration(exercises: exercises)
        let title     = buildTitle(for: muscleGroups)
        let rationale = buildRationale(muscleGroups: muscleGroups, readiness: readiness,
                                        intensity: intensity, warningCount: warnings.count)

        return StrengthSession(
            muscleGroups: muscleGroups,
            title: title,
            exercises: exercises,
            duration: duration,
            intensityLabel: intensity.label,
            rationale: rationale,
            recoveryWarnings: warnings
        )
    }

    // MARK: - Intensity levels

    enum Intensity {
        case heavy, moderate, light

        var label: String {
            switch self {
            case .heavy:    return "Heavy"
            case .moderate: return "Moderate"
            case .light:    return "Light"
            }
        }

        var primarySets: Int  { switch self { case .heavy: return 4; case .moderate: return 3; case .light: return 2 } }
        var accessorySets: Int { Swift.max(2, primarySets - 1) }

        var primaryReps: String   { switch self { case .heavy: return "5–7"; case .moderate: return "8–12"; case .light: return "15–20" } }
        var accessoryReps: String { switch self { case .heavy: return "8–12"; case .moderate: return "10–15"; case .light: return "15–20" } }
        var primaryRest: String   { switch self { case .heavy: return "2–3 min"; case .moderate: return "90 sec"; case .light: return "60 sec" } }
        var accessoryRest: String { switch self { case .heavy: return "90 sec"; case .moderate: return "60 sec"; case .light: return "45 sec" } }
    }

    private static func intensityFor(readiness: DailyReadiness) -> Intensity {
        switch readiness.status {
        case .peak, .high:     return .heavy
        case .moderate:        return .moderate
        case .low, .rest:      return .light
        }
    }

    // MARK: - Exercise database

    private static let db: [MuscleGroup: [(name: String, isCompound: Bool, note: String?)]] = [
        .chest: [
            ("Barbell Bench Press",      true,  "Control the descent, full range"),
            ("Incline Dumbbell Press",   true,  nil),
            ("Cable Chest Fly",          false, "Squeeze at midpoint"),
            ("Dips",                     false, nil)
        ],
        .back: [
            ("Pull-Ups",                 true,  "Drive elbows down, not hands"),
            ("Barbell Row",              true,  "Chest stays up, hinge at hips"),
            ("Seated Cable Row",         false, nil),
            ("Lat Pulldown",             false, nil)
        ],
        .shoulders: [
            ("Overhead Press",           true,  "Full lockout at top"),
            ("Lateral Raise",            false, "Lead with elbow, not wrist"),
            ("Face Pull",                false, "External rotation at end range"),
            ("Arnold Press",             false, nil)
        ],
        .biceps: [
            ("Barbell Curl",             true,  nil),
            ("Hammer Curl",              false, nil),
            ("Incline Dumbbell Curl",    false, "Stretch at bottom")
        ],
        .triceps: [
            ("Skull Crushers",           true,  "Keep elbows fixed"),
            ("Close-Grip Bench Press",   true,  nil),
            ("Cable Pushdown",           false, nil)
        ],
        .quads: [
            ("Back Squat",               true,  "Break parallel if mobility allows"),
            ("Leg Press",                false, nil),
            ("Hack Squat",               false, nil),
            ("Walking Lunge",            false, nil)
        ],
        .hamstrings: [
            ("Romanian Deadlift",        true,  "Maintain neutral spine throughout"),
            ("Leg Curl",                 false, nil),
            ("Nordic Curl",              false, "Progress slowly — high injury risk if rushed"),
            ("Good Morning",             false, nil)
        ],
        .glutes: [
            ("Hip Thrust",               true,  "Full hip extension at top"),
            ("Bulgarian Split Squat",    true,  nil),
            ("Cable Kickback",           false, nil)
        ],
        .calves: [
            ("Standing Calf Raise",      true,  "Full stretch at bottom"),
            ("Seated Calf Raise",        false, nil)
        ],
        .core: [
            ("Dead Bug",                 true,  "Lower back stays flat throughout"),
            ("Plank",                    false, nil),
            ("Russian Twist",            false, nil),
            ("Hanging Leg Raise",        false, nil),
            ("Cable Crunch",             false, nil)
        ]
    ]

    /// Movement names for one muscle group — the pick list for the live logger.
    static func movements(for group: MuscleGroup) -> [String] {
        (db[group] ?? []).map(\.name)
    }

    private static func buildExercises(for muscleGroups: [MuscleGroup], intensity: Intensity) -> [ExerciseSuggestion] {
        let exercisesPerGroup = muscleGroups.count <= 2 ? 3 : 2
        var result: [ExerciseSuggestion] = []

        for group in muscleGroups {
            let movements = db[group] ?? []
            let selected  = movements.prefix(exercisesPerGroup)

            for (i, movement) in selected.enumerated() {
                let isFirst  = i == 0
                let sets     = isFirst ? intensity.primarySets   : intensity.accessorySets
                let reps     = isFirst ? intensity.primaryReps   : intensity.accessoryReps
                let rest     = isFirst ? intensity.primaryRest   : intensity.accessoryRest
                let note     = isFirst ? movement.note : nil
                result.append(ExerciseSuggestion(
                    name: movement.name, muscleGroup: group,
                    sets: sets, repsRange: reps, rest: rest, notes: note
                ))
            }
        }
        return result
    }

    private static func estimateDuration(exercises: [ExerciseSuggestion]) -> Int {
        let totalSets = exercises.reduce(0) { $0 + $1.sets }
        return min(90, max(30, 10 + totalSets * 3)) // 10 min warmup + ~3 min/set
    }

    private static func buildTitle(for muscleGroups: [MuscleGroup]) -> String {
        switch muscleGroups.count {
        case 0: return "Gym Session"
        case 1: return "\(muscleGroups[0].rawValue) Day"
        case 2: return "\(muscleGroups[0].rawValue) + \(muscleGroups[1].rawValue)"
        default:
            // Classify as Push / Pull / Legs / Full Body
            let hasPush = muscleGroups.contains(where: { [.chest, .shoulders, .triceps].contains($0) })
            let hasPull = muscleGroups.contains(where: { [.back, .biceps].contains($0) })
            let hasLegs = muscleGroups.contains(where: { [.quads, .hamstrings, .glutes, .calves].contains($0) })
            if hasPush && !hasPull && !hasLegs { return "Push Day" }
            if !hasPush && hasPull && !hasLegs { return "Pull Day" }
            if !hasPush && !hasPull && hasLegs { return "Leg Day" }
            return "Full Body"
        }
    }

    // MARK: - Recovery warnings

    private static func buildRecoveryWarnings(
        for muscleGroups: [MuscleGroup],
        recentActivities: [GarminActivity]
    ) -> [String] {
        let lastStrength = recentActivities
            .filter { $0.type == .strengthTraining }
            .min(by: { $0.startTime > $1.startTime })

        guard let last = lastStrength else { return [] }
        let hoursAgo = last.hoursAgo

        return muscleGroups.compactMap { group in
            guard hoursAgo < Double(group.recoveryHours) else { return nil }
            let remaining = Int(Double(group.recoveryHours) - hoursAgo)
            return "\(group.rawValue) trained \(Int(hoursAgo))h ago — ~\(remaining)h until fully recovered. Reduce volume on these movements."
        }
    }

    // MARK: - Rationale

    private static func buildRationale(
        muscleGroups: [MuscleGroup],
        readiness: DailyReadiness,
        intensity: Intensity,
        warningCount: Int
    ) -> String {
        let groups = muscleGroups.prefix(3).map(\.rawValue).joined(separator: ", ")

        var text: String
        switch readiness.status {
        case .peak:
            text = "Readiness is at \(readiness.score)/100 — an ideal window for heavy work. The \(groups) session is loaded for strength adaptation: compound lifts first, heavier weights, longer rest intervals."
        case .high:
            text = "Readiness at \(readiness.score)/100 supports solid strength work. Stick to your working weights and focus on controlled reps — no reason to max out today, but no reason to hold back either."
        case .moderate:
            text = "With readiness at \(readiness.score)/100, the session is dialled back to moderate intensity. Prioritise technique and mind-muscle connection. The volume is enough to maintain strength without adding recovery debt."
        case .low, .rest:
            text = "Readiness is low (\(readiness.score)/100). If you train at all, keep loads very light — this is maintenance work only. Mobility or a walk may be a better investment of today's energy."
        }

        if warningCount > 0 {
            text += " Recovery warnings are noted above — treat those muscle groups with care."
        }
        return text
    }
}
