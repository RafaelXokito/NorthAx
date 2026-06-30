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
}

struct PlannedDayDTO: Decodable {
    var date: Date
    var weekdayShort: String
    var dayNumber: String
    var isRest: Bool
    var isToday: Bool
    var isPast: Bool
    var session: PlannedSessionDTO?
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

struct DomainFrequencyDTO: Codable {
    var domain: String
    var daysPerWeek: Int
}

struct DaySplitDTO: Codable {
    var muscleGroups: [String]
    var isRestDay: Bool
}

struct UserPreferencesDTO: Codable {
    var enabledDomains: [String]
    var domainFrequencies: [DomainFrequencyDTO]
    var muscleGroupSplit: [DaySplitDTO]
    var cyclingTarget: String = "hr"   // "hr" | "power"
}

struct CyclingTargetPatch: Encodable {
    var cyclingTarget: String
}

struct DomainsPatch: Encodable {
    var enabledDomains: [String]
}

struct FrequencyPatch: Encodable {
    var domainFrequencies: [DomainFrequencyDTO]
}

struct MuscleSplitPatch: Encodable {
    var muscleGroupSplit: [DaySplitDTO]
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

struct ExerciseDTO: Decodable {
    var name: String
    var muscleGroup: String
    var sets: Int
    var repsRange: String
    var rest: String
    var notes: String?
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
