package app.northax.data.remote

import app.northax.data.ParsedPreferences
import app.northax.data.remote.dto.ActivityCreateRequest
import app.northax.data.remote.dto.ActivityDto
import app.northax.data.remote.dto.ActivityExercisesPatch
import app.northax.data.remote.dto.ActivityPriorityPatch
import app.northax.data.remote.dto.LoggedExerciseDto
import app.northax.data.remote.dto.ActivityStreamsDto
import app.northax.data.remote.dto.CyclingTargetPatch
import app.northax.data.remote.dto.DailyMetricsResponse
import app.northax.data.remote.dto.DailyReadinessResponse
import app.northax.data.remote.dto.DayOverrideRequest
import app.northax.data.remote.dto.DomainScheduleDto
import app.northax.data.remote.dto.DomainsPatch
import app.northax.data.remote.dto.ExerciseDto
import app.northax.data.remote.dto.GoalProgressDto
import app.northax.data.remote.dto.IntervalsApiKeyConnect
import app.northax.data.remote.dto.IntervalsConnectResponse
import app.northax.data.remote.dto.IntervalsStatusDto
import app.northax.data.remote.dto.IntervalsWorkoutPushRequest
import app.northax.data.remote.dto.ManualMetricsRequest
import app.northax.data.remote.dto.MetricPriorityPatch
import app.northax.data.remote.dto.MuscleSplitPatch
import app.northax.data.remote.dto.CoachMessageDto
import app.northax.data.remote.dto.PaginatedActivities
import app.northax.data.remote.dto.PlannedSessionDto
import app.northax.data.remote.dto.SchedulePatch
import app.northax.data.remote.dto.SportTargetsPatch
import app.northax.data.remote.dto.StrengthGenerateRequest
import app.northax.data.remote.dto.StrengthSessionResponse
import app.northax.data.remote.dto.SwitchSuggestionRequest
import app.northax.data.remote.dto.SwitchSuggestionsResponse
import app.northax.data.remote.dto.ThresholdsPatch
import app.northax.data.remote.dto.UpdateProfileRequest
import app.northax.data.remote.dto.UserPreferencesDto
import app.northax.data.remote.dto.WeeklyPlanResponse
import app.northax.data.toConnectionState
import app.northax.data.toDomain
import app.northax.data.toDto
import app.northax.data.toGarminActivity
import app.northax.domain.model.ActivitySourcePriority
import app.northax.domain.model.ActivityStreams
import app.northax.domain.model.AthleteThresholds
import app.northax.domain.model.CoachMessage
import app.northax.domain.model.DailyReadiness
import app.northax.domain.model.DomainSchedule
import app.northax.domain.model.GarminActivity
import app.northax.domain.model.GoalCheck
import app.northax.domain.model.IntervalsConnectionState
import app.northax.domain.model.MetricSourcePriority
import app.northax.domain.model.MuscleGroup
import app.northax.domain.model.PlannedSession
import app.northax.domain.model.SportTarget
import app.northax.domain.model.StrengthSession
import app.northax.domain.model.SwitchSuggestion
import app.northax.domain.model.TrainingDomain
import app.northax.domain.model.TrainingMetrics
import app.northax.domain.model.WeeklyMuscleGroupSplit
import app.northax.domain.model.WeeklyPlan
import java.time.LocalDate

/**
 * Domain-typed facade over [ApiClient]: every method returns the app's domain
 * models (mapped from DTOs), so the store and views speak domain types only —
 * a 1:1 port of the iOS NorthAxAPI.
 */
class NorthAxApi(private val client: ApiClient) {

    // MARK: - Profile

    suspend fun updateProfileName(name: String) {
        client.send("PATCH", "user/profile", UpdateProfileRequest(name))
    }

    // MARK: - Readiness & metrics

    suspend fun readinessToday(): DailyReadiness =
        client.get<DailyReadinessResponse>("readiness/today").toDomain()

    suspend fun metricsToday(): TrainingMetrics =
        client.get<DailyMetricsResponse>("metrics/daily").toDomain()

    /** Submit user-entered wellness values as a `manual` source; the server
     *  re-resolves the day against all sources and returns the merged metrics. */
    suspend fun submitManualMetrics(req: ManualMetricsRequest): TrainingMetrics =
        client.post<DailyMetricsResponse, ManualMetricsRequest>("metrics/manual", req).toDomain()

    // MARK: - Plan & preferences

    suspend fun plans(weeks: Int = 4): List<WeeklyPlan> =
        client.get<List<WeeklyPlanResponse>>("plan/weeks", mapOf("weeks" to weeks.toString()))
            .map { it.toDomain() }

    /** Generate the next two weeks with the AI planner. Falls back server-side
     *  to the deterministic engine. Uses a long timeout. */
    suspend fun generatePlanAI(): List<WeeklyPlan> =
        client.post<List<WeeklyPlanResponse>, Unit>("plan/generate-ai", null, timeoutSeconds = 120)
            .map { it.toDomain() }

    /** Replace one day's session with a chosen alternative. `weekStart` must
     *  be the Monday of the week containing `date`. Returns the updated week. */
    suspend fun overrideDay(weekStart: LocalDate, date: LocalDate, suggestion: SwitchSuggestion): WeeklyPlan {
        val session = PlannedSessionDto(
            domain = suggestion.domain.raw,
            title = suggestion.title,
            subtitle = suggestion.description,
            duration = suggestion.duration,
            intensityLabel = suggestion.intensityLabel,
            workout = suggestion.workout,
            exercises = suggestion.exercises?.map {
                ExerciseDto(it.name, it.muscleGroup.raw, it.sets, it.repsRange, it.rest, it.notes)
            },
        )
        return client.patch<WeeklyPlanResponse, DayOverrideRequest>(
            "plan/week/$weekStart/day/$date",
            DayOverrideRequest(session),
        ).toDomain()
    }

    suspend fun preferences(): ParsedPreferences =
        client.get<UserPreferencesDto>("preferences").toDomain()

    /** Replace the per-sport weekly schedule; the server regenerates forward weeks. */
    suspend fun updateSchedule(schedules: List<DomainSchedule>): ParsedPreferences =
        client.patch<UserPreferencesDto, SchedulePatch>(
            "preferences/schedule",
            SchedulePatch(schedules.map { DomainScheduleDto(it.domain.raw, it.weekdays.sorted()) }),
        ).toDomain()

    /** Partial merge of athlete thresholds; does NOT regenerate plans. */
    suspend fun updateThresholds(partial: AthleteThresholds): ParsedPreferences =
        client.patch<UserPreferencesDto, ThresholdsPatch>(
            "preferences/thresholds", ThresholdsPatch(partial.toDto()),
        ).toDomain()

    suspend fun updateMuscleSplit(split: WeeklyMuscleGroupSplit): ParsedPreferences =
        client.patch<UserPreferencesDto, MuscleSplitPatch>(
            "preferences/muscle-split", MuscleSplitPatch(split.toDto()),
        ).toDomain()

    suspend fun updateDomains(domains: List<TrainingDomain>): ParsedPreferences =
        client.patch<UserPreferencesDto, DomainsPatch>(
            "preferences/domains", DomainsPatch(domains.map { it.raw }),
        ).toDomain()

    /** Set the cycling structured-workout target ("hr" | "power"); regenerates plans. */
    suspend fun updateCyclingTarget(target: String): ParsedPreferences =
        client.patch<UserPreferencesDto, CyclingTargetPatch>(
            "preferences/target", CyclingTargetPatch(target),
        ).toDomain()

    /** Replace the per-sport goal targets (staged plan change; the caller
     *  follows up with [generatePlanAI]). */
    suspend fun updateSportTargets(targets: Map<TrainingDomain, SportTarget>): ParsedPreferences =
        client.patch<UserPreferencesDto, SportTargetsPatch>(
            "preferences/sport-targets",
            SportTargetsPatch(targets.entries.associate { (k, v) -> k.raw to v.toDto() }),
        ).toDomain()

    /** Latest AI goal-progress verdict per targeted sport (empty when none). */
    suspend fun goalProgress(): List<GoalCheck> =
        client.get<List<GoalProgressDto>>("goals/progress").mapNotNull { it.toDomain() }

    /** Sync the per-metric source ranking; does not regenerate plans. */
    suspend fun updateMetricPriority(priority: MetricSourcePriority): ParsedPreferences =
        client.patch<UserPreferencesDto, MetricPriorityPatch>(
            "preferences/metric-priority", MetricPriorityPatch(priority.wire),
        ).toDomain()

    /** Sync the activity-source preference used to de-duplicate cross-source
     *  workouts; does not regenerate plans. */
    suspend fun updateActivityPriority(priority: ActivitySourcePriority): ParsedPreferences =
        client.patch<UserPreferencesDto, ActivityPriorityPatch>(
            "preferences/activity-priority", ActivityPriorityPatch(priority.wire),
        ).toDomain()

    // MARK: - Coach

    suspend fun coachHistory(limit: Int = 50): List<CoachMessage> =
        client.get<List<CoachMessageDto>>("ai/coach/history", mapOf("limit" to limit.toString()))
            .map { it.toDomain() }

    suspend fun clearCoachHistory() {
        client.send("DELETE", "ai/coach/history")
    }

    // MARK: - Strength & switches

    /** Pre-fetched AI alternatives for one planned session. */
    suspend fun switchSuggestions(session: PlannedSession, date: LocalDate): List<SwitchSuggestion> {
        val body = SwitchSuggestionRequest(
            domain = session.domain.raw, title = session.title,
            duration = session.duration, intensityLabel = session.intensityLabel,
            date = date.toString(),
        )
        return client.post<SwitchSuggestionsResponse, SwitchSuggestionRequest>(
            "ai/switch-suggestions", body, timeoutSeconds = 120,
        ).suggestions.mapNotNull { it.toDomain() }
    }

    suspend fun strengthSession(muscleGroups: List<MuscleGroup>, readinessScore: Int?): StrengthSession =
        client.post<StrengthSessionResponse, StrengthGenerateRequest>(
            "ai/strength/generate",
            StrengthGenerateRequest(muscleGroups.map { it.raw }, readinessScore),
        ).toDomain()

    // MARK: - intervals.icu

    suspend fun intervalsStatus(): IntervalsConnectionState =
        client.get<IntervalsStatusDto>("intervals/status").toConnectionState()

    suspend fun intervalsAuthorizationUrl(): String =
        client.post<IntervalsConnectResponse, Unit>("intervals/connect", null).authorizationUrl

    /** Connect using a personal intervals.icu API key (HTTP Basic on the server). */
    suspend fun connectWithApiKey(athleteId: String, apiKey: String): IntervalsConnectionState =
        client.post<IntervalsStatusDto, IntervalsApiKeyConnect>(
            "intervals/connect/apikey", IntervalsApiKeyConnect(athleteId, apiKey),
        ).toConnectionState()

    suspend fun intervalsSync() {
        client.send("POST", "intervals/sync")
    }

    suspend fun intervalsDisconnect() {
        client.send("DELETE", "intervals/disconnect")
    }

    /** Time-series streams for a completed activity. Empty arrays when the
     *  integration has no streams for it. */
    suspend fun activityStreams(activityId: String): ActivityStreams =
        client.get<ActivityStreamsDto>("activities/$activityId/streams").toDomain()

    // MARK: - Strava

    suspend fun stravaStatus(): IntervalsConnectionState =
        client.get<IntervalsStatusDto>("integrations/strava/status").toConnectionState()

    /** Connect the single athlete via the server's personal refresh token (no redirect). */
    suspend fun stravaConnectPersonal(): IntervalsConnectionState =
        client.post<IntervalsStatusDto, Unit>("integrations/strava/connect/personal", null, timeoutSeconds = 30)
            .toConnectionState()

    suspend fun stravaSync() {
        client.send("POST", "integrations/strava/sync")
    }

    suspend fun stravaDisconnect() {
        client.send("DELETE", "integrations/strava/disconnect")
    }

    // MARK: - Activities

    /** Persist an in-app logged workout as a `manual` activity. */
    suspend fun createActivity(request: ActivityCreateRequest): GarminActivity =
        client.post<ActivityDto, ActivityCreateRequest>("activities", request).toGarminActivity()

    /** Rewrite the exercise log of an in-app logged (manual) strength activity. */
    suspend fun updateActivityExercises(id: String, exercises: List<LoggedExerciseDto>): GarminActivity =
        client.patch<ActivityDto, ActivityExercisesPatch>("activities/$id", ActivityExercisesPatch(exercises))
            .toGarminActivity()

    suspend fun activities(limit: Int = 20, source: String? = null): List<GarminActivity> {
        val query = buildMap {
            put("limit", limit.toString())
            source?.let { put("source", it) }
        }
        return client.get<PaginatedActivities>("activities", query).items.map { it.toGarminActivity() }
    }

    suspend fun pushWorkout(date: LocalDate, session: PlannedSession): String {
        val payload = IntervalsWorkoutPushRequest(
            date = date.toString(),
            session = PlannedSessionDto(
                domain = session.domain.raw, title = session.title,
                subtitle = session.subtitle, duration = session.duration,
                intensityLabel = session.intensityLabel, workout = session.workout,
            ),
        )
        return client.post<app.northax.data.remote.dto.IntervalsWorkoutPushResponse, IntervalsWorkoutPushRequest>(
            "intervals/workouts/push", payload,
        ).workoutId
    }
}
