import Foundation

// Conversions between wire DTOs and the app's existing domain models, so views
// and engines are unchanged. Enum strings that don't resolve fall back safely.

// MARK: - Readiness

extension MetricInsight.Trend {
    init(wire: String) {
        switch wire {
        case "up": self = .up
        case "down": self = .down
        case "warning": self = .warning
        default: self = .neutral
        }
    }
}

extension DailyReadinessResponse {
    func toDomain() -> DailyReadiness {
        DailyReadiness(
            score: score,
            status: DailyReadiness.Status(rawValue: status) ?? .moderate,
            explanation: explanation,
            coachingNote: coachingNote,
            hrvScore: componentScores.hrv,
            sleepScore: componentScores.sleep,
            loadScore: componentScores.load,
            recoveryScore: componentScores.recovery,
            suggestedDomain: TrainingDomain(rawValue: suggestedSession.domain) ?? .recovery,
            suggestedSessionTitle: suggestedSession.title,
            suggestedDuration: suggestedSession.duration,
            suggestedIntensityLabel: suggestedSession.intensityLabel,
            suggestedIntensityDescription: suggestedSession.intensityDescription,
            keyInsights: keyInsights.map {
                MetricInsight(
                    label: $0.label, value: $0.value, unit: $0.unit,
                    trend: MetricInsight.Trend(wire: $0.trend),
                    explanation: $0.explanation, context: $0.context
                )
            },
            serverVerdict: verdict,
            aiNarrative: aiExplanation?.narrative
        )
    }
}

// MARK: - Metrics

extension DailyMetricsResponse {
    func toDomain() -> TrainingMetrics {
        TrainingMetrics(
            hrv: hrv, hrvBaseline: hrvBaseline, hrvTrend: hrvTrend,
            restingHR: restingHr, restingHRBaseline: restingHrBaseline,
            sleepDuration: sleepDuration, sleepScore: sleepScore,
            remSleep: remSleep, deepSleep: deepSleep, sleepDebt: sleepDebt,
            acuteLoad: acuteLoad, chronicLoad: chronicLoad,
            todayLoad: todayLoad, weeklyLoadChange: weeklyLoadChange,
            bodyWeight: bodyWeight
        )
    }
}

// MARK: - Plan

extension PlannedSessionDTO {
    func toDomain() -> PlannedSession? {
        guard let d = TrainingDomain(rawValue: domain) else { return nil }
        return PlannedSession(
            domain: d, title: title, subtitle: subtitle ?? "",
            duration: duration, intensityLabel: intensityLabel
        )
    }
}

extension WeeklyPlanResponse {
    func toDomain() -> WeeklyPlan {
        WeeklyPlan(
            weekStart: weekStart,
            days: days.map { PlannedDay(date: $0.date, session: $0.session?.toDomain(), isRest: $0.isRest) }
        )
    }
}

// MARK: - Preferences

struct ParsedPreferences {
    var enabledDomains: [TrainingDomain]
    var frequency: TrainingFrequency
    var split: WeeklyMuscleGroupSplit
}

extension UserPreferencesDTO {
    func toDomain() -> ParsedPreferences {
        let domains = enabledDomains.compactMap { TrainingDomain(rawValue: $0) }
        let freqs = domainFrequencies.compactMap { df -> DomainFrequency? in
            guard let d = TrainingDomain(rawValue: df.domain) else { return nil }
            return DomainFrequency(domain: d, daysPerWeek: df.daysPerWeek)
        }
        let split: WeeklyMuscleGroupSplit
        if muscleGroupSplit.count == 7 {
            split = WeeklyMuscleGroupSplit(days: muscleGroupSplit.map {
                DaySplit(
                    muscleGroups: $0.muscleGroups.compactMap { MuscleGroup(rawValue: $0) },
                    isRestDay: $0.isRestDay
                )
            })
        } else {
            split = .pushPullLegs
        }
        return ParsedPreferences(
            enabledDomains: domains,
            frequency: TrainingFrequency(domainFrequencies: freqs),
            split: split
        )
    }
}

extension TrainingFrequency {
    func toDTO() -> [DomainFrequencyDTO] {
        domainFrequencies.map { DomainFrequencyDTO(domain: $0.domain.rawValue, daysPerWeek: $0.daysPerWeek) }
    }
}

extension WeeklyMuscleGroupSplit {
    func toDTO() -> [DaySplitDTO] {
        days.map { DaySplitDTO(muscleGroups: $0.muscleGroups.map(\.rawValue), isRestDay: $0.isRestDay) }
    }
}

// MARK: - Coach

extension CoachMessageDTO {
    func toDomain() -> CoachMessage {
        CoachMessage(content: content, isCoach: role == "coach", timestamp: createdAt)
    }
}

// MARK: - Strength

extension StrengthSessionResponse {
    func toDomain() -> StrengthSession {
        StrengthSession(
            muscleGroups: muscleGroups.compactMap { MuscleGroup(rawValue: $0) },
            title: title,
            exercises: exercises.compactMap { e in
                guard let mg = MuscleGroup(rawValue: e.muscleGroup) else { return nil }
                return ExerciseSuggestion(
                    name: e.name, muscleGroup: mg, sets: e.sets,
                    repsRange: e.repsRange, rest: e.rest, notes: e.notes
                )
            },
            duration: duration,
            intensityLabel: intensityLabel,
            rationale: rationale,
            recoveryWarnings: recoveryWarnings
        )
    }
}

// MARK: - Garmin

extension IntervalsStatusDTO {
    func toConnectionState() -> IntervalsConnectionState {
        connected
            ? .connected(displayName: displayName ?? "Garmin", lastSync: lastSyncAt ?? Date())
            : .disconnected
    }
}

extension ActivityDTO {
    func toGarminActivity() -> GarminActivity {
        let type: GarminActivityType
        switch domain {
        case "Cycling": type = .cycling
        case "Running": type = .running
        case "Swimming": type = .swimming
        case "Strength": type = .strengthTraining
        case "Mobility": type = .yoga
        default: type = .other
        }
        return GarminActivity(
            id: externalId ?? id, name: name, type: type,
            startTime: startTime, duration: TimeInterval(durationSeconds),
            distanceMeters: distanceMeters, elevationGain: elevationGain,
            avgHeartRate: avgHeartRate, maxHeartRate: maxHeartRate,
            calories: calories, trainingLoad: trainingLoad
        )
    }
}
