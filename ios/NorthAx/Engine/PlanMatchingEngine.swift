import SwiftUI

/// Completion state of a planned session, derived by matching it against
/// workouts imported from intervals.icu / Garmin / Apple Health.
enum SessionCompletion {
    case planned   // scheduled today or in the future, not yet done
    case done      // a matching imported workout was found
    case missed    // the planned day has passed with no matching workout
    case rest      // no session scheduled

    var label: String {
        switch self {
        case .planned: return "Planned"
        case .done:    return "Done"
        case .missed:  return "Missed"
        case .rest:    return "Rest"
        }
    }

    var color: Color {
        switch self {
        case .planned: return .axAccent
        case .done:    return .axGreen
        case .missed:  return .axRed
        case .rest:    return .axTertiary
        }
    }

    var icon: String {
        switch self {
        case .planned: return "circle"
        case .done:    return "checkmark.circle.fill"
        case .missed:  return "xmark.circle"
        case .rest:    return "moon"
        }
    }
}

/// A planned session paired with its completion state and (when done) the
/// imported workout it matched.
struct SessionMatch: Identifiable {
    let id: UUID
    let day: PlannedDay
    let session: PlannedSession
    let completion: SessionCompletion
    let activity: GarminActivity?
}

/// Client-side matching of a week's planned sessions to imported workouts
/// (§7 of the plan). Match on same calendar day + same sport; when several
/// workouts fit, pick the one closest in duration to the planned session.
enum PlanMatchingEngine {
    static func matches(week: WeeklyPlan, activities: [GarminActivity], today: Date = Date()) -> [SessionMatch] {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: today)
        var out: [SessionMatch] = []
        for day in week.days where !day.isRest && !day.sessions.isEmpty {
            for session in day.sessions {
                let sameDaySameSport = activities.filter {
                    cal.isDate($0.startTime, inSameDayAs: day.date) && $0.type.domain == session.domain
                }
                let matched = sameDaySameSport.min {
                    abs($0.duration / 60 - Double(session.duration))
                        < abs($1.duration / 60 - Double(session.duration))
                }
                let completion: SessionCompletion
                if matched != nil {
                    completion = .done
                } else if cal.startOfDay(for: day.date) < startToday {
                    completion = .missed
                } else {
                    completion = .planned
                }
                out.append(SessionMatch(id: session.id, day: day, session: session,
                                        completion: completion, activity: matched))
            }
        }
        return out
    }

    /// Roll a day's session matches up to a single state for the week strip:
    /// rest → any missed → all done → otherwise planned.
    static func dayState(day: PlannedDay, matches: [SessionMatch]) -> SessionCompletion {
        if day.isRest || day.sessions.isEmpty { return .rest }
        let dayMatches = matches.filter { $0.day.date == day.date }
        if dayMatches.isEmpty { return .planned }
        if dayMatches.contains(where: { $0.completion == .missed }) { return .missed }
        if dayMatches.allSatisfy({ $0.completion == .done }) { return .done }
        return .planned
    }
}
