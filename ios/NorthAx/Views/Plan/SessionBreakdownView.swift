import SwiftUI

/// Shared workout breakdown: the exercise list for strength, the effort graph
/// for endurance. Reused by the plan list, today's card, and switch suggestions.
struct SessionBreakdownView: View {
    @Environment(AthleteStore.self) private var store
    let domain: TrainingDomain
    let workout: StructuredWorkoutDTO?
    let exercises: [ExerciseSuggestion]?
    var cyclingTarget: String? = nil   // nil → use the store's preference

    var body: some View {
        if let exercises, !exercises.isEmpty {
            exerciseList(exercises)
        } else if let workout, workout.targetMode != "none" {
            WorkoutEffortGraphView(workout: workout, sport: domain,
                                   cyclingTarget: cyclingTarget ?? store.cyclingTarget)
        }
    }

    private func exerciseList(_ exercises: [ExerciseSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(exercises) { ex in
                HStack(alignment: .top, spacing: 10) {
                    Text(ex.muscleGroup.rawValue.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.axAccent).tracking(0.5)
                        .frame(width: 64, alignment: .leading).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ex.name).font(.caption.weight(.semibold)).foregroundStyle(.axPrimary)
                            Spacer()
                            Text(ex.setDisplay).font(.caption2.weight(.semibold)).foregroundStyle(.axSecondary)
                        }
                        Text("Rest \(ex.rest)" + (ex.notes.map { " · \($0)" } ?? ""))
                            .font(.caption2).foregroundStyle(.axTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
