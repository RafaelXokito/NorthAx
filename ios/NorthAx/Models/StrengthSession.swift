import Foundation

struct ExerciseSuggestion: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var muscleGroup: MuscleGroup
    var sets: Int
    var repsRange: String  // e.g. "5–7", "8–12"
    var rest: String       // e.g. "2–3 min"
    var notes: String?

    var setDisplay: String { "\(sets) × \(repsRange)" }
}

struct StrengthSession {
    var muscleGroups: [MuscleGroup]
    var title: String
    var exercises: [ExerciseSuggestion]
    var duration: Int       // minutes
    var intensityLabel: String
    var rationale: String
    var recoveryWarnings: [String]
}

// MARK: - Logged strength work (actuals, per set)

struct LoggedSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var weightKg: Double?   // nil = bodyweight
    var reps: Int

    private enum CodingKeys: String, CodingKey { case weightKg, reps }

    var display: String {
        let w = weightKg.map { $0 == $0.rounded() ? "\(Int($0)) kg" : String(format: "%.1f kg", $0) } ?? "BW"
        return "\(w) × \(reps)"
    }
}

struct LoggedExercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var muscleGroup: MuscleGroup
    var sets: [LoggedSet]

    private enum CodingKeys: String, CodingKey { case name, muscleGroup, sets }
}

/// SF Symbol for a specific movement (keyword match), falling back to the
/// muscle group's icon — the app has no bundled imagery (§ Design).
enum ExerciseIcons {
    static func symbol(for name: String, group: MuscleGroup) -> String {
        let n = name.lowercased()
        if n.contains("plank") || n.contains("crunch") || n.contains("twist")
            || n.contains("dead bug") || n.contains("leg raise") { return "figure.core.training" }
        if n.contains("pull-up") || n.contains("row") || n.contains("pulldown")
            || n.contains("face pull") { return "figure.rower" }
        if n.contains("squat") || n.contains("lunge") || n.contains("leg press")
            || n.contains("dips") { return "figure.strengthtraining.functional" }
        if n.contains("press") || n.contains("deadlift") || n.contains("thrust")
            || n.contains("good morning") { return "figure.strengthtraining.traditional" }
        if n.contains("calf") || n.contains("step") { return "figure.step.training" }
        if n.contains("curl") || n.contains("raise") || n.contains("fly")
            || n.contains("pushdown") || n.contains("kickback") { return "dumbbell" }
        return group.icon
    }
}
