import Foundation

struct ExerciseSuggestion: Identifiable {
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
