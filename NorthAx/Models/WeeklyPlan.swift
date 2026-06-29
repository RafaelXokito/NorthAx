import Foundation

// PlannedSession moved here from PlanView so the whole app shares one definition.
struct PlannedSession: Identifiable, Equatable {
    var id = UUID()
    var domain: TrainingDomain
    var title: String
    var subtitle: String
    var duration: Int      // minutes
    var intensityLabel: String
}

struct PlannedDay: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var session: PlannedSession?
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
