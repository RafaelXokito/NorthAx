import Foundation

// PlannedSession moved here from PlanView so the whole app shares one definition.
struct PlannedSession: Identifiable, Equatable {
    var id = UUID()
    var domain: TrainingDomain
    var title: String
    var subtitle: String
    var duration: Int      // minutes
    var intensityLabel: String
    var workout: StructuredWorkoutDTO? = nil   // structured steps (targets in zones)
    var exercises: [ExerciseSuggestion]? = nil // strength: movement breakdown

    /// Renderable lines for the structured workout, e.g. "5× · Work 8 min · Z4 HR".
    var workoutLines: [String] {
        guard let w = workout, w.targetMode != "none" else { return [] }
        return w.blocks.map { block in
            let prefix = block.repeat > 1 ? "\(block.repeat)× " : ""
            let body = block.steps.map { step in
                "\(step.cue) \(step.minutes) min" + (step.icu.isEmpty ? "" : " · \(step.icu)")
            }.joined(separator: ", ")
            return prefix + body
        }
    }
}

struct PlannedDay: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var sessions: [PlannedSession]   // empty + isRest == rest day
    var isRest: Bool

    var weekdayShort: String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: date)
    }

    var dayNumber: String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: date)
    }

    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var isPast: Bool  { date < Calendar.current.startOfDay(for: Date()) }
}

struct WeeklyPlan: Identifiable, Equatable {
    var id: Date { weekStart }
    var weekStart: Date
    var days: [PlannedDay]   // always 7 entries, Mon → Sun

    var trainingDays: [PlannedDay] { days.filter { !$0.isRest } }
    var restDays: [PlannedDay]     { days.filter { $0.isRest  } }

    var weekLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(f.string(from: weekStart)) – \(f.string(from: end))"
    }

    var isCurrentWeek: Bool {
        Calendar.current.isDate(weekStart, equalTo: Date(), toGranularity: .weekOfYear)
    }
}
