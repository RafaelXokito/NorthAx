import Foundation

// Response/request DTOs mirroring the OpenAPI component schemas (§6). Property
// names match the camelCase wire keys 1:1. Calendar-date *request* fields use
// `String` ("yyyy-MM-dd") so they aren't encoded as full datetimes.

// MARK: - Readiness (§6.4)

struct ComponentScoresDTO: Decodable {
    var hrv: Int
    var sleep: Int
    var load: Int
    var recovery: Int
}

struct SuggestedSessionDTO: Decodable {
    var domain: String
    var title: String
    var duration: Int
    var intensityLabel: String
    var intensityDescription: String
    var aiRationale: String?
}

struct KeyInsightDTO: Decodable {
    var label: String
    var value: String
    var unit: String
    var trend: String
    var explanation: String
    var context: String
}

struct AiExplanationDTO: Decodable {
    var narrative: String
    var generatedAt: Date
    var model: String
}

struct DailyReadinessResponse: Decodable {
    var date: Date
    var score: Int
    var status: String
    var verdict: String
    var explanation: String
    var coachingNote: String
    var componentScores: ComponentScoresDTO
    var suggestedSession: SuggestedSessionDTO
    var keyInsights: [KeyInsightDTO]
    var aiExplanation: AiExplanationDTO?
}

// MARK: - Metrics (§6.3)

struct DailyMetricsResponse: Decodable {
    var date: Date
    var hrv: Double
    var hrvBaseline: Double
    var hrvTrend: [Double]
    var restingHr: Int
    var restingHrBaseline: Int
    var sleepDuration: Double
    var sleepScore: Int
    var remSleep: Double
    var deepSleep: Double
    var sleepDebt: Double
    var acuteLoad: Double
    var chronicLoad: Double
    var todayLoad: Double
    var weeklyLoadChange: Double
    var bodyWeight: Double?
    var vo2max: Double?
    // Aligned daily series for the detail graphs (oldest→newest, up to 90 days).
    // Only the by-date GET endpoints populate these; optional for compatibility.
    var trendDates: [Date]?
    var hrvSeries: [Double]?
    var restingHrSeries: [Double]?
    var sleepSeries: [Double]?
    var tsbSeries: [Double]?
    var ctlSeries: [Double]?
    var atlSeries: [Double]?
    var vo2maxSeries: [Double]?
    var metricSources: [String: String]?   // metric -> winning source (provenance)
}

// MARK: - Plan (§6.7) + structured workouts

struct WorkoutStepDTO: Codable, Equatable {
    var cue: String
    var minutes: Int
    var target: String   // human label, e.g. "Z2 endurance (HR)"
    var icu: String      // intervals.icu token, e.g. "Z2 HR"
}

struct WorkoutBlockDTO: Codable, Equatable {
    var `repeat`: Int
    var steps: [WorkoutStepDTO]
}

struct StructuredWorkoutDTO: Codable, Equatable {
    var targetMode: String   // "hr" | "power" | "pace" | "none"
    var blocks: [WorkoutBlockDTO]
}

struct PlannedSessionDTO: Codable {
    var domain: String
    var title: String
    var subtitle: String?
    var duration: Int
    var intensityLabel: String
    var workout: StructuredWorkoutDTO?
    var exercises: [ExerciseDTO]? = nil   // strength: movement breakdown
}

struct PlannedDayDTO: Decodable {
    var date: Date
    var weekdayShort: String
    var dayNumber: String
    var isRest: Bool
    var isToday: Bool
    var isPast: Bool
    var sessions: [PlannedSessionDTO]
}

struct WeeklyPlanResponse: Decodable {
    var id: String?
    var weekStart: Date
    var weekLabel: String
    var isCurrentWeek: Bool
    var days: [PlannedDayDTO]
    var generatedAt: Date
}

// MARK: - Preferences (§6.5)

struct DomainScheduleDTO: Codable {
    var domain: String
    var weekdays: [Int]   // sorted ascending, 0=Mon … 6=Sun
}

struct AthleteThresholdsDTO: Codable {
    var ftpWatts: Int?
    var thresholdHr: Int?
    var maxHr: Int?
    var runThresholdPaceSecPerKm: Int?
    var paceUnit: String = "km"          // "km" | "mile"
    var swimThresholdPaceSecPer100m: Int?
    var poolUnit: String = "pool25m"     // "pool25m" | "pool50m" | "openWater"
}

struct DaySplitDTO: Codable {
    var muscleGroups: [String]
    var isRestDay: Bool
}

// `targetDate` is a "yyyy-MM-dd" string (not a full datetime), like
// ManualMetricsRequest.date — the encoder would emit an ISO datetime otherwise.
struct SportTargetDTO: Codable {
    var goalType: String       // "raceTime" | "powerHold" | "distanceAvgSpeed"
    var targetDate: String
    var distanceKm: Double?
    var finishTimeSec: Int?
    var zone: Int?
    var holdMinutes: Int?
    var avgSpeedKmh: Double?
}

struct UserPreferencesDTO: Codable {
    var enabledDomains: [String]
    var domainSchedules: [DomainScheduleDTO]
    var muscleGroupSplit: [DaySplitDTO]
    var cyclingTarget: String = "hr"   // "hr" | "power"
    var thresholds: AthleteThresholdsDTO = AthleteThresholdsDTO()
    var metricPriority: [String: [String]] = [:]   // metric -> [source, ...]
    var activityPriority: [String] = []            // §13 — ordered activity sources
    var sportTargets: [String: SportTargetDTO]?    // optional: older backends omit it
}

struct ActivityPriorityPatch: Encodable {
    var activityPriority: [String]
}

struct CyclingTargetPatch: Encodable {
    var cyclingTarget: String
}

struct MetricPriorityPatch: Encodable {
    var metricPriority: [String: [String]]
}

// Manual wellness entry. `date` is a "yyyy-MM-dd" string (not a full datetime);
// omitted (nil) fields simply aren't provided by the manual source.
struct ManualMetricsRequest: Encodable {
    var date: String
    var hrv: Double?
    var restingHr: Int?
    var sleepDuration: Double?
    var sleepScore: Int?
    var bodyWeight: Double?
}

struct DomainsPatch: Encodable {
    var enabledDomains: [String]
}

struct SchedulePatch: Encodable {
    var domainSchedules: [DomainScheduleDTO]
}

struct ThresholdsPatch: Encodable {
    var thresholds: AthleteThresholdsDTO
}

struct MuscleSplitPatch: Encodable {
    var muscleGroupSplit: [DaySplitDTO]
}

struct SportTargetsPatch: Encodable {
    var sportTargets: [String: SportTargetDTO]   // full replace; omit a domain to clear it
}

struct GoalProgressDTO: Decodable {
    var domain: String
    var verdict: String          // "on_track" | "behind" | "ahead"
    var summary: String
    var recommendReplan: Bool
    var analyzedAt: Date
}

// MARK: - Coach (§6.8, §6.9)

struct CoachMessageDTO: Decodable {
    var id: String
    var role: String
    var content: String
    var createdAt: Date
}

struct CoachMessageRequest: Encodable {
    var content: String
}

// MARK: - Strength (§6.10)

struct ExerciseDTO: Codable {
    var name: String
    var muscleGroup: String
    var sets: Int
    var repsRange: String
    var rest: String
    var notes: String?
}

// MARK: - Switch suggestions (§9)

struct SwitchSuggestionRequest: Encodable {
    var domain: String
    var title: String
    var duration: Int
    var intensityLabel: String
    var date: String   // "yyyy-MM-dd"
}

struct SwitchSuggestionDTO: Decodable {
    var domain: String
    var title: String
    var duration: Int
    var intensityLabel: String
    var description: String
    var rationale: String
    var estimatedLoad: Double?
    var workout: StructuredWorkoutDTO?
    var exercises: [ExerciseDTO]?
}

struct SwitchSuggestionsResponse: Decodable {
    var suggestions: [SwitchSuggestionDTO]
}

/// Replace a single day's session (used when the athlete applies a switch, §9).
struct DayOverrideRequest: Encodable {
    var session: PlannedSessionDTO?   // nil → clear to a rest day
}

/// Time-series streams for a completed activity (§10).
struct ActivityStreamsDTO: Decodable {
    var activityId: String
    var time: [Double]
    var heartRate: [Double]
    var power: [Double]
    var velocity: [Double]
    var altitude: [Double]
    var cadence: [Double]
    var source: String
}

struct StrengthSessionResponse: Decodable {
    var muscleGroups: [String]
    var title: String
    var intensityLabel: String
    var duration: Int
    var rationale: String
    var recoveryWarnings: [String]
    var exercises: [ExerciseDTO]
}

struct StrengthGenerateRequest: Encodable {
    var muscleGroups: [String]
    var readinessScore: Int?
}

// MARK: - Garmin (§6.11, §9.4)

struct IntervalsStatusDTO: Decodable {
    var connected: Bool
    var displayName: String?
    var lastSyncAt: Date?
}

struct IntervalsConnectResponse: Decodable {
    var authorizationUrl: String
}

struct IntervalsApiKeyConnect: Encodable {
    var athleteId: String
    var apiKey: String
}

struct IntervalsWorkoutPushRequest: Encodable {
    var date: String              // "yyyy-MM-dd"
    var session: PlannedSessionDTO
}

struct IntervalsWorkoutPushResponse: Decodable {
    var workoutId: String
    var scheduledDate: Date
}

// MARK: - Activities (§6.6)

struct ActivityDTO: Decodable {
    var id: String
    var externalId: String?
    var source: String
    var name: String
    var domain: String
    var startTime: Date
    var durationSeconds: Int
    var distanceMeters: Double?
    var elevationGain: Double?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var calories: Int?
    var trainingLoad: Double?
    var notes: String?
    var createdAt: Date
}

struct PaginatedActivities: Decodable {
    var items: [ActivityDTO]
    var total: Int
    var limit: Int
    var offset: Int
    var hasMore: Bool
}
