import Foundation

/// Domain-typed facade over `APIClient`: every method returns the app's existing
/// models (mapped from DTOs), so the store and views speak domain types only.
struct NorthAxAPI {
    static let shared = NorthAxAPI()
    private let client = APIClient.shared

    // MARK: - Profile

    func updateProfileName(_ name: String) async throws {
        _ = try await client.send("PATCH", "user/profile", body: UpdateProfileRequest(name: name))
    }

    // MARK: - Readiness & metrics

    func readinessToday() async throws -> DailyReadiness {
        let dto: DailyReadinessResponse = try await client.get("readiness/today")
        return dto.toDomain()
    }

    func metricsToday() async throws -> TrainingMetrics {
        let dto: DailyMetricsResponse = try await client.get("metrics/daily")
        return dto.toDomain()
    }

    // MARK: - Plan & preferences

    func plans(weeks: Int = 4) async throws -> [WeeklyPlan] {
        let dtos: [WeeklyPlanResponse] = try await client.get(
            "plan/weeks", query: [URLQueryItem(name: "weeks", value: String(weeks))]
        )
        return dtos.map { $0.toDomain() }
    }

    func preferences() async throws -> ParsedPreferences {
        let dto: UserPreferencesDTO = try await client.get("preferences")
        return dto.toDomain()
    }

    func updateFrequency(_ frequency: TrainingFrequency) async throws -> ParsedPreferences {
        let dto: UserPreferencesDTO = try await client.patch(
            "preferences/frequency", body: FrequencyPatch(domainFrequencies: frequency.toDTO())
        )
        return dto.toDomain()
    }

    func updateMuscleSplit(_ split: WeeklyMuscleGroupSplit) async throws -> ParsedPreferences {
        let dto: UserPreferencesDTO = try await client.patch(
            "preferences/muscle-split", body: MuscleSplitPatch(muscleGroupSplit: split.toDTO())
        )
        return dto.toDomain()
    }

    func updateDomains(_ domains: [TrainingDomain]) async throws -> ParsedPreferences {
        let dto: UserPreferencesDTO = try await client.patch(
            "preferences/domains", body: DomainsPatch(enabledDomains: domains.map(\.rawValue))
        )
        return dto.toDomain()
    }

    /// Set the cycling structured-workout target ("hr" | "power"); regenerates plans.
    func updateCyclingTarget(_ target: String) async throws -> ParsedPreferences {
        let dto: UserPreferencesDTO = try await client.patch(
            "preferences/target", body: CyclingTargetPatch(cyclingTarget: target)
        )
        return dto.toDomain()
    }

    // MARK: - Coach

    func coachHistory(limit: Int = 50) async throws -> [CoachMessage] {
        let dtos: [CoachMessageDTO] = try await client.get(
            "ai/coach/history", query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return dtos.map { $0.toDomain() }
    }

    func clearCoachHistory() async throws {
        _ = try await client.send("DELETE", "ai/coach/history")
    }

    // MARK: - Strength

    func strengthSession(muscleGroups: [MuscleGroup], readinessScore: Int?) async throws -> StrengthSession {
        let dto: StrengthSessionResponse = try await client.post(
            "ai/strength/generate",
            body: StrengthGenerateRequest(
                muscleGroups: muscleGroups.map(\.rawValue), readinessScore: readinessScore
            )
        )
        return dto.toDomain()
    }

    // MARK: - Garmin

    func intervalsStatus() async throws -> IntervalsConnectionState {
        let dto: IntervalsStatusDTO = try await client.get("intervals/status")
        return dto.toConnectionState()
    }

    func intervalsAuthorizationURL() async throws -> URL {
        let dto: IntervalsConnectResponse = try await client.post("intervals/connect")
        guard let url = URL(string: dto.authorizationUrl) else { throw APIError.decoding }
        return url
    }

    /// Connect using a personal intervals.icu API key (HTTP Basic on the server).
    func connectWithAPIKey(athleteId: String, apiKey: String) async throws -> IntervalsConnectionState {
        let dto: IntervalsStatusDTO = try await client.post(
            "intervals/connect/apikey",
            body: IntervalsApiKeyConnect(athleteId: athleteId, apiKey: apiKey)
        )
        return dto.toConnectionState()
    }

    @discardableResult
    func intervalsSync() async throws -> Bool {
        _ = try await client.send("POST", "intervals/sync")
        return true
    }

    func intervalsDisconnect() async throws {
        _ = try await client.send("DELETE", "intervals/disconnect")
    }

    func activities(limit: Int = 20) async throws -> [GarminActivity] {
        let page: PaginatedActivities = try await client.get(
            "activities", query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return page.items.map { $0.toGarminActivity() }
    }

    @discardableResult
    func pushWorkout(date: Date, session: PlannedSession) async throws -> String {
        let payload = IntervalsWorkoutPushRequest(
            date: JSONCoders.calendarDate.string(from: date),
            session: PlannedSessionDTO(
                domain: session.domain.rawValue, title: session.title,
                subtitle: session.subtitle, duration: session.duration,
                intensityLabel: session.intensityLabel, workout: session.workout
            )
        )
        let resp: IntervalsWorkoutPushResponse = try await client.post("intervals/workouts/push", body: payload)
        return resp.workoutId
    }
}
