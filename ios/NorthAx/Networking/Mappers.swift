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
            bodyWeight: bodyWeight,
            trendDates: trendDates ?? [],
            hrvSeries: hrvSeries ?? [],
            restingHRSeries: restingHrSeries ?? [],
            sleepSeries: sleepSeries ?? [],
            tsbSeries: tsbSeries ?? [],
            ctlSeries: ctlSeries ?? [],
            atlSeries: atlSeries ?? [],
            vo2maxSeries: vo2maxSeries ?? [],
            vo2max: vo2max,
            provenance: (metricSources ?? [:]).compactMapValues { MetricSource(rawValue: $0) }
        )
    }
}

// MARK: - Plan

extension PlannedSessionDTO {
    func toDomain() -> PlannedSession? {
        guard let d = TrainingDomain(rawValue: domain) else { return nil }
        return PlannedSession(
            domain: d, title: title, subtitle: subtitle ?? "",
            duration: duration, intensityLabel: intensityLabel, workout: workout,
            exercises: exercises?.compactMap { e in
                guard let mg = MuscleGroup(rawValue: e.muscleGroup) else { return nil }
                return ExerciseSuggestion(
                    name: e.name, muscleGroup: mg, sets: e.sets,
                    repsRange: e.repsRange, rest: e.rest, notes: e.notes
                )
            }
        )
    }
}

extension WeeklyPlanResponse {
    func toDomain() -> WeeklyPlan {
        WeeklyPlan(
            weekStart: weekStart,
            days: days.map { day in
                PlannedDay(
                    date: day.date,
                    sessions: day.sessions.compactMap { $0.toDomain() },
                    isRest: day.isRest
                )
            }
        )
    }
}

// MARK: - Preferences

struct ParsedPreferences {
    var enabledDomains: [TrainingDomain]
    var frequency: TrainingFrequency
    var split: WeeklyMuscleGroupSplit
    var cyclingTarget: String
    var thresholds: AthleteThresholds
    var metricPriority: MetricSourcePriority
    var activityPriority: ActivitySourcePriority
    var sportTargets: [TrainingDomain: SportTarget]
}

extension UserPreferencesDTO {
    func toDomain() -> ParsedPreferences {
        let domains = enabledDomains.compactMap { TrainingDomain(rawValue: $0) }
        let scheds = domainSchedules.compactMap { ds -> DomainSchedule? in
            guard let d = TrainingDomain(rawValue: ds.domain) else { return nil }
            return DomainSchedule(domain: d, weekdays: Set(ds.weekdays.filter { (0...6).contains($0) }))
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
        var targets: [TrainingDomain: SportTarget] = [:]
        for (key, dto) in sportTargets ?? [:] {
            guard let d = TrainingDomain(rawValue: key), let t = dto.toDomain() else { continue }
            targets[d] = t
        }
        return ParsedPreferences(
            enabledDomains: domains,
            frequency: TrainingFrequency(schedules: scheds),
            split: split,
            cyclingTarget: cyclingTarget,
            thresholds: thresholds.toDomain(),
            metricPriority: MetricSourcePriority(wire: metricPriority),
            activityPriority: ActivitySourcePriority(wire: activityPriority),
            sportTargets: targets
        )
    }
}

extension SportTargetDTO {
    func toDomain() -> SportTarget? {
        guard let kind = GoalType(rawValue: goalType),
              let date = JSONCoders.calendarDate.date(from: targetDate) else { return nil }
        return SportTarget(
            goalType: kind, targetDate: date, distanceKm: distanceKm,
            finishTimeSec: finishTimeSec, zone: zone,
            holdMinutes: holdMinutes, avgSpeedKmh: avgSpeedKmh
        )
    }
}

extension SportTarget {
    func toDTO() -> SportTargetDTO {
        SportTargetDTO(
            goalType: goalType.rawValue,
            targetDate: JSONCoders.calendarDate.string(from: targetDate),
            distanceKm: distanceKm, finishTimeSec: finishTimeSec, zone: zone,
            holdMinutes: holdMinutes, avgSpeedKmh: avgSpeedKmh
        )
    }
}

extension GoalProgressDTO {
    func toDomain() -> GoalCheck? {
        guard let d = TrainingDomain(rawValue: domain),
              let v = GoalCheck.Verdict(rawValue: verdict) else { return nil }
        return GoalCheck(domain: d, verdict: v, summary: summary,
                         recommendReplan: recommendReplan, analyzedAt: analyzedAt)
    }
}

extension TrainingFrequency {
    func toDTO() -> [DomainScheduleDTO] {
        schedules.map { DomainScheduleDTO(domain: $0.domain.rawValue, weekdays: $0.weekdays.sorted()) }
    }
}

extension AthleteThresholdsDTO {
    func toDomain() -> AthleteThresholds {
        AthleteThresholds(
            ftpWatts: ftpWatts,
            thresholdHr: thresholdHr,
            maxHr: maxHr,
            runThresholdPaceSecPerKm: runThresholdPaceSecPerKm,
            paceUnit: PaceUnit(rawValue: paceUnit) ?? .km,
            swimThresholdPaceSecPer100m: swimThresholdPaceSecPer100m,
            poolUnit: PoolUnit(rawValue: poolUnit) ?? .pool25m
        )
    }
}

extension AthleteThresholds {
    func toDTO() -> AthleteThresholdsDTO {
        AthleteThresholdsDTO(
            ftpWatts: ftpWatts,
            thresholdHr: thresholdHr,
            maxHr: maxHr,
            runThresholdPaceSecPerKm: runThresholdPaceSecPerKm,
            paceUnit: paceUnit.rawValue,
            swimThresholdPaceSecPer100m: swimThresholdPaceSecPer100m,
            poolUnit: poolUnit.rawValue
        )
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

// MARK: - Switch suggestions (§9)

extension SwitchSuggestionDTO {
    func toDomain() -> SwitchSuggestion? {
        guard let d = TrainingDomain(rawValue: domain) else { return nil }
        return SwitchSuggestion(
            domain: d, title: title, duration: duration, intensityLabel: intensityLabel,
            description: description, rationale: rationale, estimatedLoad: estimatedLoad,
            workout: workout,
            exercises: exercises?.compactMap { e in
                guard let mg = MuscleGroup(rawValue: e.muscleGroup) else { return nil }
                return ExerciseSuggestion(name: e.name, muscleGroup: mg, sets: e.sets,
                                          repsRange: e.repsRange, rest: e.rest, notes: e.notes)
            },
            isAI: true
        )
    }
}

extension ActivityStreamsDTO {
    func toDomain() -> ActivityStreams {
        ActivityStreams(activityId: activityId, time: time, heartRate: heartRate,
                        power: power, velocity: velocity, altitude: altitude,
                        cadence: cadence, source: source)
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
