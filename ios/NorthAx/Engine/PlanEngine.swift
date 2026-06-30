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

    private static func generateWeek(
        start: Date,
        frequency: TrainingFrequency,
        split: WeeklyMuscleGroupSplit
    ) -> WeeklyPlan {
        let totalSessions = min(frequency.totalTrainingDays, 6) // always ≥1 rest day
        let restSlots = restDayPositions(restCount: 7 - totalSessions)
        var queue = makeSessionQueue(frequency: frequency, targetCount: totalSessions)

        let days: [PlannedDay] = (0..<7).map { offset in
            let date    = Calendar.current.date(byAdding: .day, value: offset, to: start)!
            let weekday = Calendar.current.component(.weekday, from: date)

            if restSlots.contains(offset) || queue.isEmpty {
                return PlannedDay(date: date, session: nil, isRest: true)
            } else {
                let domain  = queue.removeFirst()
                let session = makeSession(domain: domain, slot: offset,
                                          weekday: weekday, split: split)
                return PlannedDay(date: date, session: session, isRest: false)
            }
        }

        return WeeklyPlan(weekStart: start, days: days)
    }

    // MARK: - Rest day placement

    /// Places rest days at positions that maximize recovery gaps.
    /// Index 0 = Monday, 6 = Sunday.
    private static func restDayPositions(restCount: Int) -> Set<Int> {
        switch restCount {
        case 0:  return []
        case 1:  return [6]                  // Sun
        case 2:  return [3, 6]               // Thu, Sun
        case 3:  return [1, 4, 6]            // Tue, Fri, Sun → Mon, Wed, Thu, Sat train
        case 4:  return [1, 3, 5, 6]         // 3-day week: Mon, Wed, Fri
        case 5:  return [1, 2, 4, 5, 6]      // 2-day week: Mon, Thu
        case 6:  return [1, 2, 3, 4, 5, 6]   // 1-day week: Mon only
        default: return Set(0..<7)
        }
    }

    // MARK: - Session queue (greedy interleaving to avoid back-to-back same sport)

    private static func makeSessionQueue(
        frequency: TrainingFrequency,
        targetCount: Int
    ) -> [TrainingDomain] {
        // Build a remaining-count table, sorted descending
        var remaining: [(domain: TrainingDomain, left: Int)] = frequency.domainFrequencies
            .filter { $0.daysPerWeek > 0 }
            .map { (domain: $0.domain, left: min($0.daysPerWeek, targetCount)) }
            .sorted { $0.left > $1.left }

        var queue:  [TrainingDomain] = []
        var last:   TrainingDomain? = nil

        while queue.count < targetCount, !remaining.isEmpty {
            // Pick highest-remaining domain, preferring one different from `last`
            let idx = pickNext(remaining: remaining, avoidDomain: last)
            queue.append(remaining[idx].domain)
            last = remaining[idx].domain
            remaining[idx].left -= 1
            remaining.removeAll { $0.left <= 0 }
        }

        return queue
    }

    private static func pickNext(
        remaining: [(domain: TrainingDomain, left: Int)],
        avoidDomain: TrainingDomain?
    ) -> Int {
        // Prefer a domain different from avoidDomain; among ties, pick highest count
        if let avoidDomain = avoidDomain,
           let alt = remaining.enumerated()
               .filter({ $0.element.domain != avoidDomain })
               .max(by: { $0.element.left < $1.element.left }) {
            return alt.offset
        }
        // Fallback: highest count regardless
        return remaining.enumerated().max(by: { $0.element.left < $1.element.left })?.offset ?? 0
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
