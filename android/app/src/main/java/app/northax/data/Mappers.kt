package app.northax.data

import app.northax.data.remote.JsonCoders
import app.northax.data.remote.dto.ActivityDto
import app.northax.data.remote.dto.ActivityStreamsDto
import app.northax.data.remote.dto.AthleteThresholdsDto
import app.northax.data.remote.dto.CoachMessageDto
import app.northax.data.remote.dto.DailyMetricsResponse
import app.northax.data.remote.dto.DailyReadinessResponse
import app.northax.data.remote.dto.DaySplitDto
import app.northax.data.remote.dto.DomainScheduleDto
import app.northax.data.remote.dto.ExerciseDto
import app.northax.data.remote.dto.GoalProgressDto
import app.northax.data.remote.dto.IntervalsStatusDto
import app.northax.data.remote.dto.LoggedExerciseDto
import app.northax.data.remote.dto.LoggedSetDto
import app.northax.data.remote.dto.PlannedSessionDto
import app.northax.data.remote.dto.SegmentEffortDto
import app.northax.data.remote.dto.SegmentHistoryDto
import app.northax.data.remote.dto.SportTargetDto
import app.northax.data.remote.dto.StrengthSessionResponse
import app.northax.data.remote.dto.SwitchSuggestionDto
import app.northax.data.remote.dto.UserPreferencesDto
import app.northax.data.remote.dto.WeeklyPlanResponse
import app.northax.domain.model.ActivitySourcePriority
import app.northax.domain.model.ActivityStreams
import app.northax.domain.model.AthleteThresholds
import app.northax.domain.model.CoachMessage
import app.northax.domain.model.DailyReadiness
import app.northax.domain.model.DaySplit
import app.northax.domain.model.DomainSchedule
import app.northax.domain.model.ExerciseSuggestion
import app.northax.domain.model.GarminActivity
import app.northax.domain.model.GarminActivityType
import app.northax.domain.model.GoalCheck
import app.northax.domain.model.GoalType
import app.northax.domain.model.IntervalsConnectionState
import app.northax.domain.model.LoggedExercise
import app.northax.domain.model.LoggedSet
import app.northax.domain.model.MetricInsight
import app.northax.domain.model.MetricSource
import app.northax.domain.model.MetricSourcePriority
import app.northax.domain.model.SegmentEffort
import app.northax.domain.model.SegmentHistory
import app.northax.domain.model.MuscleGroup
import app.northax.domain.model.PaceUnit
import app.northax.domain.model.PlannedDay
import app.northax.domain.model.PlannedSession
import app.northax.domain.model.PoolUnit
import app.northax.domain.model.SportTarget
import app.northax.domain.model.StrengthSession
import app.northax.domain.model.SwitchSuggestion
import app.northax.domain.model.TrainingDomain
import app.northax.domain.model.TrainingFrequency
import app.northax.domain.model.TrainingMetrics
import app.northax.domain.model.WeeklyMuscleGroupSplit
import app.northax.domain.model.WeeklyPlan
import java.time.Instant
import java.time.LocalDate

// Conversions between wire DTOs and the app's domain models, so views and
// engines are unchanged. Enum strings that don't resolve fall back safely.

// MARK: - Readiness

fun DailyReadinessResponse.toDomain(): DailyReadiness = DailyReadiness(
    score = score,
    status = DailyReadiness.Status.fromRaw(status) ?: DailyReadiness.Status.Moderate,
    explanation = explanation,
    coachingNote = coachingNote,
    hrvScore = componentScores.hrv,
    sleepScore = componentScores.sleep,
    loadScore = componentScores.load,
    recoveryScore = componentScores.recovery,
    suggestedDomain = TrainingDomain.fromRaw(suggestedSession.domain) ?: TrainingDomain.Recovery,
    suggestedSessionTitle = suggestedSession.title,
    suggestedDuration = suggestedSession.duration,
    suggestedIntensityLabel = suggestedSession.intensityLabel,
    suggestedIntensityDescription = suggestedSession.intensityDescription,
    keyInsights = keyInsights.map {
        MetricInsight(
            label = it.label, value = it.value, unit = it.unit,
            trend = MetricInsight.Trend.fromWire(it.trend),
            explanation = it.explanation, context = it.context,
        )
    },
    serverVerdict = verdict,
    aiNarrative = aiExplanation?.narrative,
)

// MARK: - Metrics

fun DailyMetricsResponse.toDomain(): TrainingMetrics = TrainingMetrics(
    hrv = hrv, hrvBaseline = hrvBaseline, hrvTrend = hrvTrend,
    restingHR = restingHr, restingHRBaseline = restingHrBaseline,
    sleepDuration = sleepDuration, sleepScore = sleepScore,
    remSleep = remSleep, deepSleep = deepSleep, sleepDebt = sleepDebt,
    acuteLoad = acuteLoad, chronicLoad = chronicLoad,
    todayLoad = todayLoad, weeklyLoadChange = weeklyLoadChange,
    bodyWeight = bodyWeight,
    trendDates = trendDates ?: emptyList(),
    hrvSeries = hrvSeries ?: emptyList(),
    restingHRSeries = restingHrSeries ?: emptyList(),
    sleepSeries = sleepSeries ?: emptyList(),
    tsbSeries = tsbSeries ?: emptyList(),
    ctlSeries = ctlSeries ?: emptyList(),
    atlSeries = atlSeries ?: emptyList(),
    vo2maxSeries = vo2maxSeries ?: emptyList(),
    vo2max = vo2max,
    provenance = (metricSources ?: emptyMap())
        .mapNotNull { (k, v) -> MetricSource.fromRaw(v)?.let { k to it } }
        .toMap(),
)

// MARK: - Plan

fun PlannedSessionDto.toDomain(): PlannedSession? {
    val d = TrainingDomain.fromRaw(domain) ?: return null
    return PlannedSession(
        domain = d, title = title, subtitle = subtitle ?: "",
        duration = duration, intensityLabel = intensityLabel, workout = workout,
        exercises = exercises?.mapNotNull { it.toDomain() },
    )
}

fun ExerciseDto.toDomain(): ExerciseSuggestion? {
    val mg = MuscleGroup.fromRaw(muscleGroup) ?: return null
    return ExerciseSuggestion(
        name = name, muscleGroup = mg, sets = sets,
        repsRange = repsRange, rest = rest, notes = notes,
    )
}

fun WeeklyPlanResponse.toDomain(): WeeklyPlan = WeeklyPlan(
    weekStart = weekStart,
    days = days.map { day ->
        PlannedDay(
            date = day.date,
            sessions = day.sessions.mapNotNull { it.toDomain() },
            isRest = day.isRest,
        )
    },
)

// MARK: - Preferences

data class ParsedPreferences(
    val enabledDomains: List<TrainingDomain>,
    val frequency: TrainingFrequency,
    val split: WeeklyMuscleGroupSplit,
    val cyclingTarget: String,
    val thresholds: AthleteThresholds,
    val metricPriority: MetricSourcePriority,
    val activityPriority: ActivitySourcePriority,
    val sportTargets: Map<TrainingDomain, SportTarget>,
)

fun UserPreferencesDto.toDomain(): ParsedPreferences {
    val domains = enabledDomains.mapNotNull { TrainingDomain.fromRaw(it) }
    val scheds = domainSchedules.mapNotNull { ds ->
        val d = TrainingDomain.fromRaw(ds.domain) ?: return@mapNotNull null
        DomainSchedule(d, ds.weekdays.filter { it in 0..6 }.toSet())
    }
    val split = if (muscleGroupSplit.size == 7) {
        WeeklyMuscleGroupSplit(muscleGroupSplit.map {
            DaySplit(
                muscleGroups = it.muscleGroups.mapNotNull { g -> MuscleGroup.fromRaw(g) },
                isRestDay = it.isRestDay,
            )
        })
    } else {
        WeeklyMuscleGroupSplit.pushPullLegs
    }
    val targets = mutableMapOf<TrainingDomain, SportTarget>()
    for ((key, dto) in sportTargets ?: emptyMap()) {
        val d = TrainingDomain.fromRaw(key) ?: continue
        val t = dto.toDomain() ?: continue
        targets[d] = t
    }
    return ParsedPreferences(
        enabledDomains = domains,
        frequency = TrainingFrequency(scheds),
        split = split,
        cyclingTarget = cyclingTarget,
        thresholds = thresholds.toDomain(),
        metricPriority = MetricSourcePriority.fromWire(metricPriority),
        activityPriority = ActivitySourcePriority.fromWire(activityPriority),
        sportTargets = targets,
    )
}

fun SportTargetDto.toDomain(): SportTarget? {
    val kind = GoalType.fromRaw(goalType) ?: return null
    val date = try {
        LocalDate.parse(targetDate, JsonCoders.calendarDate)
    } catch (_: Exception) {
        return null
    }
    return SportTarget(
        goalType = kind, targetDate = date, distanceKm = distanceKm,
        finishTimeSec = finishTimeSec, zone = zone,
        holdMinutes = holdMinutes, avgSpeedKmh = avgSpeedKmh,
    )
}

fun SportTarget.toDto(): SportTargetDto = SportTargetDto(
    goalType = goalType.raw,
    targetDate = targetDate.format(JsonCoders.calendarDate),
    distanceKm = distanceKm, finishTimeSec = finishTimeSec, zone = zone,
    holdMinutes = holdMinutes, avgSpeedKmh = avgSpeedKmh,
)

fun GoalProgressDto.toDomain(): GoalCheck? {
    val d = TrainingDomain.fromRaw(domain) ?: return null
    val v = GoalCheck.Verdict.fromRaw(verdict) ?: return null
    return GoalCheck(d, v, summary, recommendReplan, analyzedAt)
}

fun TrainingFrequency.toDto(): List<DomainScheduleDto> =
    schedules.map { DomainScheduleDto(it.domain.raw, it.weekdays.sorted()) }

fun AthleteThresholdsDto.toDomain(): AthleteThresholds = AthleteThresholds(
    ftpWatts = ftpWatts,
    thresholdHr = thresholdHr,
    maxHr = maxHr,
    runThresholdPaceSecPerKm = runThresholdPaceSecPerKm,
    paceUnit = PaceUnit.fromRaw(paceUnit) ?: PaceUnit.Km,
    swimThresholdPaceSecPer100m = swimThresholdPaceSecPer100m,
    poolUnit = PoolUnit.fromRaw(poolUnit) ?: PoolUnit.Pool25m,
)

fun AthleteThresholds.toDto(): AthleteThresholdsDto = AthleteThresholdsDto(
    ftpWatts = ftpWatts,
    thresholdHr = thresholdHr,
    maxHr = maxHr,
    runThresholdPaceSecPerKm = runThresholdPaceSecPerKm,
    paceUnit = paceUnit.raw,
    swimThresholdPaceSecPer100m = swimThresholdPaceSecPer100m,
    poolUnit = poolUnit.raw,
)

fun WeeklyMuscleGroupSplit.toDto(): List<DaySplitDto> =
    days.map { DaySplitDto(it.muscleGroups.map { g -> g.raw }, it.isRestDay) }

// MARK: - Coach

fun CoachMessageDto.toDomain(): CoachMessage =
    CoachMessage(content = content, isCoach = role == "coach", timestamp = createdAt)

// MARK: - Strength

fun StrengthSessionResponse.toDomain(): StrengthSession = StrengthSession(
    muscleGroups = muscleGroups.mapNotNull { MuscleGroup.fromRaw(it) },
    title = title,
    exercises = exercises.mapNotNull { it.toDomain() },
    duration = duration,
    intensityLabel = intensityLabel,
    rationale = rationale,
    recoveryWarnings = recoveryWarnings,
)

// MARK: - Switch suggestions

fun SwitchSuggestionDto.toDomain(): SwitchSuggestion? {
    val d = TrainingDomain.fromRaw(domain) ?: return null
    return SwitchSuggestion(
        domain = d, title = title, duration = duration, intensityLabel = intensityLabel,
        description = description, rationale = rationale, estimatedLoad = estimatedLoad,
        workout = workout,
        exercises = exercises?.mapNotNull { it.toDomain() },
        isAI = true,
    )
}

fun SegmentEffortDto.toDomain(): SegmentEffort = SegmentEffort(
    id = id, segmentId = segmentId, name = name,
    distanceMeters = distanceMeters, avgGrade = avgGrade, climbCategory = climbCategory,
    elapsedSeconds = elapsedSeconds, movingSeconds = movingSeconds, startDate = startDate,
    prRank = prRank, komRank = komRank, points = points,
)

fun SegmentHistoryDto.toDomain(): SegmentHistory = SegmentHistory(
    segmentId = segmentId, name = name, distanceMeters = distanceMeters,
    avgGrade = avgGrade, climbCategory = climbCategory, points = points,
    efforts = efforts.map { it.toDomain() },
)

fun ActivityStreamsDto.toDomain(): ActivityStreams = ActivityStreams(
    activityId = activityId, time = time, heartRate = heartRate,
    power = power, velocity = velocity, altitude = altitude,
    cadence = cadence, latLng = latLng, source = source,
)

// MARK: - intervals.icu

fun IntervalsStatusDto.toConnectionState(): IntervalsConnectionState =
    if (connected) IntervalsConnectionState.Connected(displayName ?: "Garmin", lastSyncAt ?: Instant.now())
    else IntervalsConnectionState.Disconnected

// MARK: - Activities

fun ActivityDto.toGarminActivity(): GarminActivity {
    val type = when (domain) {
        "Cycling" -> GarminActivityType.Cycling
        "Running" -> GarminActivityType.Running
        "Swimming" -> GarminActivityType.Swimming
        "Strength" -> GarminActivityType.StrengthTraining
        "Mobility" -> GarminActivityType.Yoga
        else -> GarminActivityType.Other
    }
    return GarminActivity(
        id = externalId ?: id, name = name, type = type,
        startTime = startTime, durationSeconds = durationSeconds.toLong(),
        distanceMeters = distanceMeters, elevationGain = elevationGain,
        avgHeartRate = avgHeartRate, maxHeartRate = maxHeartRate,
        calories = calories, trainingLoad = trainingLoad,
        strengthExercises = strengthExercises?.mapNotNull { it.toDomain() },
        source = source, routePoints = routePoints,
    )
}

fun LoggedExerciseDto.toDomain(): LoggedExercise? {
    val mg = MuscleGroup.fromRaw(muscleGroup) ?: return null
    return LoggedExercise(
        name = name, muscleGroup = mg,
        sets = sets.map { LoggedSet(weightKg = it.weightKg, reps = it.reps) },
    )
}

fun LoggedExercise.toDto(): LoggedExerciseDto = LoggedExerciseDto(
    name = name, muscleGroup = muscleGroup.raw,
    sets = sets.map { LoggedSetDto(it.weightKg, it.reps) },
)
