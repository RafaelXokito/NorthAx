package app.northax.data.remote.dto

import app.northax.data.remote.ApiDate
import app.northax.data.remote.ApiInstant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Response/request DTOs mirroring the OpenAPI component schemas. Property
// names match the camelCase wire keys 1:1. Calendar-date *request* fields use
// `String` ("yyyy-MM-dd") so they aren't encoded as full datetimes.

// MARK: - Readiness

@Serializable
data class ComponentScoresDto(val hrv: Int, val sleep: Int, val load: Int, val recovery: Int)

@Serializable
data class SuggestedSessionDto(
    val domain: String,
    val title: String,
    val duration: Int,
    val intensityLabel: String,
    val intensityDescription: String,
    val aiRationale: String? = null,
)

@Serializable
data class KeyInsightDto(
    val label: String,
    val value: String,
    val unit: String,
    val trend: String,
    val explanation: String,
    val context: String,
)

@Serializable
data class AiExplanationDto(val narrative: String, val generatedAt: ApiInstant, val model: String)

@Serializable
data class DailyReadinessResponse(
    val date: ApiDate,
    val score: Int,
    val status: String,
    val verdict: String,
    val explanation: String,
    val coachingNote: String,
    val componentScores: ComponentScoresDto,
    val suggestedSession: SuggestedSessionDto,
    val keyInsights: List<KeyInsightDto>,
    val aiExplanation: AiExplanationDto? = null,
)

// MARK: - Metrics

@Serializable
data class DailyMetricsResponse(
    val date: ApiDate,
    val hrv: Double,
    val hrvBaseline: Double,
    val hrvTrend: List<Double>,
    val restingHr: Int,
    val restingHrBaseline: Int,
    val sleepDuration: Double,
    val sleepScore: Int,
    val remSleep: Double,
    val deepSleep: Double,
    val sleepDebt: Double,
    val acuteLoad: Double,
    val chronicLoad: Double,
    val todayLoad: Double,
    val weeklyLoadChange: Double,
    val bodyWeight: Double? = null,
    val vo2max: Double? = null,
    // Aligned daily series for the detail graphs (oldest→newest, up to 90 days).
    val trendDates: List<ApiDate>? = null,
    val hrvSeries: List<Double>? = null,
    val restingHrSeries: List<Double>? = null,
    val sleepSeries: List<Double>? = null,
    val tsbSeries: List<Double>? = null,
    val ctlSeries: List<Double>? = null,
    val atlSeries: List<Double>? = null,
    val vo2maxSeries: List<Double>? = null,
    val metricSources: Map<String, String>? = null, // metric -> winning source
)

// Manual wellness entry. `date` is "yyyy-MM-dd"; omitted (null) fields simply
// aren't provided by the manual source.
@Serializable
data class ManualMetricsRequest(
    val date: String,
    val hrv: Double? = null,
    val restingHr: Int? = null,
    val sleepDuration: Double? = null,
    val sleepScore: Int? = null,
    val bodyWeight: Double? = null,
)

// MARK: - Plan + structured workouts

@Serializable
data class WorkoutStepDto(
    val cue: String,
    val minutes: Int,
    val target: String, // human label, e.g. "Z2 endurance (HR)"
    val icu: String,    // intervals.icu token, e.g. "Z2 HR"
)

@Serializable
data class WorkoutBlockDto(
    @SerialName("repeat") val repeatCount: Int,
    val steps: List<WorkoutStepDto>,
)

@Serializable
data class StructuredWorkoutDto(
    val targetMode: String, // "hr" | "power" | "pace" | "none"
    val blocks: List<WorkoutBlockDto>,
)

@Serializable
data class PlannedSessionDto(
    val domain: String,
    val title: String,
    val subtitle: String? = null,
    val duration: Int,
    val intensityLabel: String,
    val workout: StructuredWorkoutDto? = null,
    val exercises: List<ExerciseDto>? = null, // strength: movement breakdown
)

@Serializable
data class PlannedDayDto(
    val date: ApiDate,
    val weekdayShort: String,
    val dayNumber: String,
    val isRest: Boolean,
    val isToday: Boolean,
    val isPast: Boolean,
    val sessions: List<PlannedSessionDto>,
)

@Serializable
data class WeeklyPlanResponse(
    val id: String? = null,
    val weekStart: ApiDate,
    val weekLabel: String,
    val isCurrentWeek: Boolean,
    val days: List<PlannedDayDto>,
    val generatedAt: ApiInstant,
)

// MARK: - Preferences

@Serializable
data class DomainScheduleDto(
    val domain: String,
    val weekdays: List<Int>, // sorted ascending, 0=Mon … 6=Sun
)

@Serializable
data class AthleteThresholdsDto(
    val ftpWatts: Int? = null,
    val thresholdHr: Int? = null,
    val maxHr: Int? = null,
    val runThresholdPaceSecPerKm: Int? = null,
    val paceUnit: String = "km",       // "km" | "mile"
    val swimThresholdPaceSecPer100m: Int? = null,
    val poolUnit: String = "pool25m",  // "pool25m" | "pool50m" | "openWater"
)

@Serializable
data class DaySplitDto(val muscleGroups: List<String>, val isRestDay: Boolean)

// `targetDate` is a "yyyy-MM-dd" string (not a full datetime).
@Serializable
data class SportTargetDto(
    val goalType: String, // "raceTime" | "powerHold" | "distanceAvgSpeed"
    val targetDate: String,
    val distanceKm: Double? = null,
    val finishTimeSec: Int? = null,
    val zone: Int? = null,
    val holdMinutes: Int? = null,
    val avgSpeedKmh: Double? = null,
)

@Serializable
data class UserPreferencesDto(
    val enabledDomains: List<String>,
    val domainSchedules: List<DomainScheduleDto>,
    val muscleGroupSplit: List<DaySplitDto>,
    val cyclingTarget: String = "hr", // "hr" | "power"
    val thresholds: AthleteThresholdsDto = AthleteThresholdsDto(),
    val metricPriority: Map<String, List<String>> = emptyMap(), // metric -> [source, ...]
    val activityPriority: List<String> = emptyList(),           // ordered activity sources
    val sportTargets: Map<String, SportTargetDto>? = null,      // optional: older backends omit it
)

@Serializable
data class ActivityPriorityPatch(val activityPriority: List<String>)

@Serializable
data class CyclingTargetPatch(val cyclingTarget: String)

@Serializable
data class MetricPriorityPatch(val metricPriority: Map<String, List<String>>)

@Serializable
data class DomainsPatch(val enabledDomains: List<String>)

@Serializable
data class SchedulePatch(val domainSchedules: List<DomainScheduleDto>)

@Serializable
data class ThresholdsPatch(val thresholds: AthleteThresholdsDto)

@Serializable
data class MuscleSplitPatch(val muscleGroupSplit: List<DaySplitDto>)

@Serializable
data class SportTargetsPatch(val sportTargets: Map<String, SportTargetDto>)

@Serializable
data class GoalProgressDto(
    val domain: String,
    val verdict: String, // "on_track" | "behind" | "ahead"
    val summary: String,
    val recommendReplan: Boolean,
    val analyzedAt: ApiInstant,
)

// MARK: - Coach

@Serializable
data class CoachMessageDto(
    val id: String,
    val role: String,
    val content: String,
    val createdAt: ApiInstant,
)

@Serializable
data class CoachMessageRequest(val content: String)

// MARK: - Strength

@Serializable
data class ExerciseDto(
    val name: String,
    val muscleGroup: String,
    val sets: Int,
    val repsRange: String,
    val rest: String,
    val notes: String? = null,
)

@Serializable
data class StrengthSessionResponse(
    val muscleGroups: List<String>,
    val title: String,
    val intensityLabel: String,
    val duration: Int,
    val rationale: String,
    val recoveryWarnings: List<String>,
    val exercises: List<ExerciseDto>,
)

@Serializable
data class StrengthGenerateRequest(
    val muscleGroups: List<String>,
    val readinessScore: Int? = null,
)

// MARK: - Switch suggestions

@Serializable
data class SwitchSuggestionRequest(
    val domain: String,
    val title: String,
    val duration: Int,
    val intensityLabel: String,
    val date: String, // "yyyy-MM-dd"
)

@Serializable
data class SwitchSuggestionDto(
    val domain: String,
    val title: String,
    val duration: Int,
    val intensityLabel: String,
    val description: String,
    val rationale: String,
    val estimatedLoad: Double? = null,
    val workout: StructuredWorkoutDto? = null,
    val exercises: List<ExerciseDto>? = null,
)

@Serializable
data class SwitchSuggestionsResponse(val suggestions: List<SwitchSuggestionDto>)

/** Replace a single day's session (used when the athlete applies a switch). */
@Serializable
data class DayOverrideRequest(val session: PlannedSessionDto?) // null → clear to a rest day

/** One Strava segment result within an activity. */
@Serializable
data class SegmentEffortDto(
    val id: String,
    val segmentId: String,
    val activityExternalId: String,
    val name: String,
    val distanceMeters: Double? = null,
    val avgGrade: Double? = null,
    val climbCategory: Int? = null,
    val elapsedSeconds: Int,
    val movingSeconds: Int? = null,
    val startDate: ApiInstant,
    val prRank: Int? = null,
    val komRank: Int? = null,
)

/** A segment's metadata plus the athlete's efforts on it, newest first. */
@Serializable
data class SegmentHistoryDto(
    val segmentId: String,
    val name: String,
    val distanceMeters: Double? = null,
    val avgGrade: Double? = null,
    val climbCategory: Int? = null,
    val efforts: List<SegmentEffortDto> = emptyList(),
)

@Serializable
data class StravaSegmentsBackfillDto(val processed: Int, val remaining: Int)

/** Time-series streams for a completed activity. */
@Serializable
data class ActivityStreamsDto(
    val activityId: String,
    val time: List<Double>,
    val heartRate: List<Double>,
    val power: List<Double>,
    val velocity: List<Double>,
    val altitude: List<Double>,
    val cadence: List<Double>,
    val latLng: List<List<Double>> = emptyList(), // default: tolerates an older backend
    val source: String,
)

// MARK: - intervals.icu

@Serializable
data class IntervalsStatusDto(
    val connected: Boolean,
    val displayName: String? = null,
    val lastSyncAt: ApiInstant? = null,
)

@Serializable
data class IntervalsConnectResponse(val authorizationUrl: String)

@Serializable
data class IntervalsApiKeyConnect(val athleteId: String, val apiKey: String)

@Serializable
data class IntervalsWorkoutPushRequest(
    val date: String, // "yyyy-MM-dd"
    val session: PlannedSessionDto,
)

@Serializable
data class IntervalsWorkoutPushResponse(
    val workoutId: String,
    val scheduledDate: ApiDate,
)

// MARK: - Activities

@Serializable
data class LoggedSetDto(val weightKg: Double? = null, val reps: Int)

@Serializable
data class LoggedExerciseDto(
    val name: String,
    val muscleGroup: String,
    val sets: List<LoggedSetDto>,
)

/** Create a `manual` activity — used to persist an in-app logged strength
 *  workout so the plan matcher marks the session done. */
@Serializable
data class ActivityCreateRequest(
    val name: String,
    val domain: String,
    val startTime: ApiInstant,
    val durationSeconds: Int,
    val strengthExercises: List<LoggedExerciseDto>? = null,
)

/** Rewrite the exercise log of an in-app logged strength activity. */
@Serializable
data class ActivityExercisesPatch(
    val strengthExercises: List<LoggedExerciseDto>,
)

@Serializable
data class ActivityDto(
    val id: String,
    val externalId: String? = null,
    val source: String,
    val name: String,
    val domain: String,
    val startTime: ApiInstant,
    val durationSeconds: Int,
    val distanceMeters: Double? = null,
    val elevationGain: Double? = null,
    val avgHeartRate: Int? = null,
    val maxHeartRate: Int? = null,
    val calories: Int? = null,
    val trainingLoad: Double? = null,
    val notes: String? = null,
    val strengthExercises: List<LoggedExerciseDto>? = null,
    val routePoints: List<List<Double>>? = null, // coarse [[lat, lng], …] for list thumbnails
    val createdAt: ApiInstant,
)

@Serializable
data class PaginatedActivities(
    val items: List<ActivityDto>,
    val total: Int,
    val limit: Int,
    val offset: Int,
    val hasMore: Boolean,
)
