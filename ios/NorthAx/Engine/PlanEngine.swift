import Foundation

struct PlanEngine {

    // MARK: - Public entry point

    /// Generates `weeks` consecutive weekly plans starting from the Monday
    /// of the week that contains `from`.
    static func generatePlans(
        from date: Date = Date(),
        weeks: Int = 4,
        frequency: TrainingFrequency,
        muscleGroupSplit: WeeklyMuscleGroupSplit
    ) -> [WeeklyPlan] {
        let monday = mondayOf(date)
        return (0..<weeks).map { offset in
            let start = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: monday)!
            return generateWeek(start: start, frequency: frequency, split: muscleGroupSplit)
        }
    }

    // MARK: - Week generation

    /// Places one session per (sport, weekday) pair. A weekday with several
    /// sports gets several sessions, ordered by the schedules' sport order. A
    /// weekday with no sessions is a rest day.
    private static func generateWeek(
        start: Date,
        frequency: TrainingFrequency,
        split: WeeklyMuscleGroupSplit
    ) -> WeeklyPlan {
        let days: [PlannedDay] = (0..<7).map { offset in   // 0=Mon … 6=Sun
            let date    = Calendar.current.date(byAdding: .day, value: offset, to: start)!
            let weekday = Calendar.current.component(.weekday, from: date)

            // Sports scheduled on this weekday, in the schedules' declared order.
            let sessions = frequency.schedules
                .filter { $0.weekdays.contains(offset) }
                .map { makeSession(domain: $0.domain, slot: offset, weekday: weekday, split: split) }

            return PlannedDay(date: date, sessions: sessions, isRest: sessions.isEmpty)
        }

        return WeeklyPlan(weekStart: start, days: days)
    }

    // MARK: - Session building

    private static func makeSession(
        domain: TrainingDomain,
        slot: Int,          // 0=Mon … 6=Sun, used to vary session type within a week
        weekday: Int,       // Calendar.weekday (1=Sun … 7=Sat) for split lookup
        split: WeeklyMuscleGroupSplit
    ) -> PlannedSession {
        switch domain {
        case .cycling:
            // Vary between endurance / intervals / easy based on slot position
            let variants: [(title: String, subtitle: String, duration: Int, intensity: String)] = [
                ("Zone 3 Intervals",   "70–85% FTP · 5×8 min efforts",  75, "Threshold"),
                ("Aerobic Endurance",  "65–75% FTP · Steady state",      90, "Moderate"),
                ("Easy Recovery Ride", "55–65% FTP · Active recovery",   60, "Easy")
            ]
            let v = variants[slot % variants.count]
            return PlannedSession(domain: domain, title: v.title, subtitle: v.subtitle,
                                  duration: v.duration, intensityLabel: v.intensity)

        case .running:
            let variants: [(String, String, Int, String)] = [
                ("Easy Run",   "Zone 2 · Conversational pace",  45, "Easy"),
                ("Tempo Run",  "Comfortably hard · ~80% max HR", 40, "Hard"),
                ("Long Run",   "Zone 1–2 · Building endurance",  70, "Easy")
            ]
            let v = variants[slot % variants.count]
            return PlannedSession(domain: domain, title: v.0, subtitle: v.1,
                                  duration: v.2, intensityLabel: v.3)

        case .strength:
            let daySplit = split.split(forCalendarWeekday: weekday)
            let groupLabel = daySplit.isRestDay || daySplit.muscleGroups.isEmpty
                ? "Full Body"
                : daySplit.displayName
            return PlannedSession(domain: domain,
                                  title: groupLabel,
                                  subtitle: "Gym · Per your weekly split",
                                  duration: 60,
                                  intensityLabel: "Moderate")

        case .swimming:
            let variants: [(String, String, Int, String)] = [
                ("Interval Set",       "8×100m at race pace",       55, "Hard"),
                ("Technique Session",  "Drills + aerobic endurance", 45, "Moderate")
            ]
            let v = variants[slot % variants.count]
            return PlannedSession(domain: domain, title: v.0, subtitle: v.1,
                                  duration: v.2, intensityLabel: v.3)

        case .triathlon:
            return PlannedSession(domain: domain, title: "Brick Session",
                                  subtitle: "60 min bike + 20 min run",
                                  duration: 90, intensityLabel: "Moderate")

        case .mobility:
            return PlannedSession(domain: domain, title: "Mobility Flow",
                                  subtitle: "Yoga · Hip flexors, hamstrings, spine",
                                  duration: 40, intensityLabel: "Easy")

        case .recovery:
            return PlannedSession(domain: domain, title: "Active Recovery",
                                  subtitle: "Short walk or light stretching",
                                  duration: 25, intensityLabel: "Very Easy")
        }
    }

    // MARK: - Calendar helpers

    static func mondayOf(_ date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2  // Monday
        return cal.date(from: comps) ?? date
    }
}
