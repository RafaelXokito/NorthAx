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

    /// Stable key for caching daily switch suggestions (§9) — survives plan
    /// reloads (unlike the random `session.id`) as long as the plan is unchanged.
    var suggestionKey: String { SessionMatch.suggestionKey(day: day, session: session) }

    static func suggestionKey(day: PlannedDay, session: PlannedSession) -> String {
        "\(dateKey.string(from: day.date))|\(session.domain.rawValue)|\(session.title)"
    }

    private static let dateKey: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}

/// One navigable week (§11): the plan (or a synthesized past week) plus its
/// matches. `isHistorical` weeks are built from imported activities only.
struct WeekData {
    let offset: Int
    let week: WeeklyPlan
    let matches: [SessionMatch]
    let isHistorical: Bool
}

/// Client-side matching of a week's planned sessions to imported workouts
/// (§7 of the plan). Match on same calendar day + same sport; when several
/// workouts fit, pick the one closest in duration to the planned session.
enum PlanMatchingEngine {
    static func matches(week: WeeklyPlan, activities: [GarminActivity], today: Date = Date()) -> [SessionMatch] {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: today)
        var out: [SessionMatch] = []
        var matchedActivityIDs: Set<GarminActivity.ID> = []
        for day in week.days where !day.isRest && !day.sessions.isEmpty {
            for session in day.sessions {
                let sameDaySameSport = activities.filter {
                    cal.isDate($0.startTime, inSameDayAs: day.date) && $0.type.domain == session.domain
                        && !matchedActivityIDs.contains($0.id)
                }
                let matched = sameDaySameSport.min {
                    abs($0.duration / 60 - Double(session.duration))
                        < abs($1.duration / 60 - Double(session.duration))
                }
                if let matched { matchedActivityIDs.insert(matched.id) }
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

        // Surface imported workouts that don't correspond to any planned session
        // (unplanned / extra sessions) as done entries, so a workout the athlete
        // did off-plan still shows up on the week instead of vanishing (§7).
        for day in week.days {
            let extras = activities.filter {
                cal.isDate($0.startTime, inSameDayAs: day.date) && !matchedActivityIDs.contains($0.id)
            }
            for a in extras {
                matchedActivityIDs.insert(a.id)
                let session = PlannedSession(
                    domain: a.type.domain, title: a.name, subtitle: "",
                    duration: Int(a.duration / 60), intensityLabel: "Completed"
                )
                out.append(SessionMatch(id: session.id, day: day, session: session,
                                        completion: .done, activity: a))
            }
        }

        // Chronological order regardless of planned/unplanned. Stable within a day
        // (original index tiebreak) so planned sessions stay ahead of extras.
        return out.enumerated()
            .sorted { ($0.element.day.date, $0.offset) < ($1.element.day.date, $1.offset) }
            .map(\.element)
    }

    /// Roll a day's session matches up to a single state for the week strip:
    /// rest → any missed → all done → otherwise planned.
    static func dayState(day: PlannedDay, matches: [SessionMatch]) -> SessionCompletion {
        let dayMatches = matches.filter { $0.day.date == day.date }
        if day.isRest || day.sessions.isEmpty {
            // A rest day still marks done if an unplanned workout was imported for it.
            return dayMatches.contains { $0.completion == .done } ? .done : .rest
        }
        if dayMatches.isEmpty { return .planned }
        if dayMatches.contains(where: { $0.completion == .missed }) { return .missed }
        if dayMatches.allSatisfy({ $0.completion == .done }) { return .done }
        return .planned
    }
}
