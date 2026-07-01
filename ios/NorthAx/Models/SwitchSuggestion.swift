import Foundation

/// An alternative session offered for a planned workout (§9). AI-generated ones
/// carry a `rationale` and (usually) a structured breakdown; deterministic
/// fallbacks have `isAI == false` and no rationale.
struct SwitchSuggestion: Identifiable {
    let id = UUID()
    var domain: TrainingDomain
    var title: String
    var duration: Int
    var intensityLabel: String
    var description: String
    var rationale: String?
    var estimatedLoad: Double?
    var workout: StructuredWorkoutDTO?
    var exercises: [ExerciseSuggestion]?
    var isAI: Bool
}
