import Foundation
import Observation

// MARK: - Session override

struct SessionOverride {
    var domain: TrainingDomain
    var title: String
    var duration: Int
    var intensityLabel: String
    var intensityDescription: String
    var strengthSession: StrengthSession?

    init(domain: TrainingDomain, title: String, duration: Int,
         intensityLabel: String, intensityDescription: String,
         strengthSession: StrengthSession? = nil) {
        self.domain = domain
        self.title = title
        self.duration = duration
        self.intensityLabel = intensityLabel
        self.intensityDescription = intensityDescription
        self.strengthSession = strengthSession
    }
}

// MARK: - Store

/// Central view-model. When a backend session exists it loads live data
/// (readiness, metrics, plan, coach, preferences) and reconciles optimistic
/// local engine output with the server; offline (or debug) it falls back to the
/// client engines and mock seed so the UI always has data.
@MainActor
@Observable
class AthleteStore {
    var athleteName: String = "Athlete"
    var enabledDomains: [TrainingDomain] = [.cycling, .strength] {
        didSet {
            guard enabledDomains != oldValue, !suppressServerSync, TokenStore.shared.hasSession else { return }
            Task { _ = try? await api.updateDomains(enabledDomains) }
        }
    }
    var muscleGroupSplit: WeeklyMuscleGroupSplit = .pushPullLegs {
        didSet {
            guard !suppressServerSync, TokenStore.shared.hasSession else { return }
            Task { await syncSplitToServer() }
        }
    }
    /// Structured-workout target for cycling: "hr" (default) or "power".
    var cyclingTarget: String = "hr" {
        didSet {
            guard cyclingTarget != oldValue, !suppressServerSync, TokenStore.shared.hasSession else { return }
            Task { await syncCyclingTargetToServer() }
        }
    }
    /// Athlete physiological thresholds. PATCHes a partial merge; does NOT
    /// regenerate plans (zones are render-time only).
    var thresholds: AthleteThresholds = AthleteThresholds() {
        didSet {
            guard thresholds != oldValue, !suppressServerSync, TokenStore.shared.hasSession else { return }
            Task { await syncThresholdsToServer() }
        }
    }
    /// Live wellness data — nil means "no data yet" (no integration connected /
    /// nothing synced). The UI shows an empty state rather than fabricated values.
    var metrics: TrainingMetrics? = nil
    var readiness: DailyReadiness? = nil
    var messages: [CoachMessage] = [.opening]
    var sessionOverride: SessionOverride? = nil
    /// Which main tab is shown. Exposed so deep-link buttons (e.g. the "Enable
    /// integrations" CTA on an empty dashboard) can jump straight to Settings.
    var selectedTab: AppTab = .dashboard

    /// True only for a "Continue as Debug User" session (no backend tokens). Gates
    /// every mock/demo path so a real signed-in user never sees fabricated values.
    private(set) var isDebugSession = false

    // Training frequency + plan — persisted across launches
    var trainingFrequency: TrainingFrequency = AthleteStore.loadFrequency() {
        didSet {
            if trainingFrequency != oldValue {
                AthleteStore.saveFrequency(trainingFrequency)
                regeneratePlan()  // optimistic local update
                if !suppressServerSync, TokenStore.shared.hasSession {
                    Task { await syncFrequencyToServer() }
                }
            }
        }
    }
    var weeklyPlans: [WeeklyPlan] = []
    var planWasRecentlyUpdated: Bool = false
    var hasSetFrequency: Bool = UserDefaults.standard.bool(forKey: "northax.hasSetFrequency") {
        didSet { UserDefaults.standard.set(hasSetFrequency, forKey: "northax.hasSetFrequency") }
    }

    let intervals = IntervalsService()
    let health = HealthKitService()

    private let api = NorthAxAPI.shared
    /// Set while applying server state so property `didSet`s don't echo back.
    private var suppressServerSync = false

#if DEBUG
    /// Debug-only demo toggle to preview the fresh/fatigued scenarios without a
    /// data source. Not compiled into release builds, so real users only ever
    /// see live data or the empty state.
    var useFatiguedScenario: Bool = false {
        didSet {
            metrics = useFatiguedScenario ? .mockFatigued : .mockFresh
            recalculate()
        }
    }
#endif

    init() {
        // Only build a local plan for a returning user who already defined their
        // frequency (offline-friendly). A new user starts with no plan and is
        // prompted to create one.
        if trainingFrequency.totalTrainingDays > 0 {
            weeklyPlans = PlanEngine.generatePlans(
                weeks: 4,
                frequency: trainingFrequency,
                muscleGroupSplit: muscleGroupSplit
            )
        }
    }

    // Called by ContentView when the signed-in user changes
    func configure(with user: AuthUser) {
        if !user.name.isEmpty { athleteName = user.name }
        if TokenStore.shared.hasSession {
            isDebugSession = false
            Task { await loadFromBackend() }
        } else {
            // No backend tokens means this is the "Continue as Debug User" bypass.
            // Seed the demo data so the UI is explorable offline. Real users always
            // have a session above and only ever see live data (or an empty state).
#if DEBUG
            isDebugSession = true
            metrics = .mockFresh
            recalculate()
            // Seed a demo plan so the debug session is explorable offline.
            let demoFrequency = trainingFrequency.totalTrainingDays > 0 ? trainingFrequency : .defaultFrequency
            weeklyPlans = PlanEngine.generatePlans(
                weeks: 4, frequency: demoFrequency, muscleGroupSplit: muscleGroupSplit
            )
#endif
        }
    }

    func resetForSignOut() {
        hasSetFrequency = false
        trainingFrequency = .empty   // no assumed plan after sign-out
        messages = [.opening]
        sessionOverride = nil
        isDebugSession = false
        metrics = nil
        readiness = nil
        weeklyPlans = []
    }

    // MARK: - Backend loading

    /// Pull live data when authenticated; no-op (engine/mock) otherwise.
    func loadFromBackend() async {
        guard TokenStore.shared.hasSession else { return }
        await loadPreferences()
        await loadMetricsAndReadiness()
        await loadPlans()
        await loadCoachHistory()
        await intervals.refreshStatus()
    }

    func loadPreferences() async {
        guard let prefs = try? await api.preferences() else { return }
        suppressServerSync = true
        if !prefs.enabledDomains.isEmpty { enabledDomains = prefs.enabledDomains }
        muscleGroupSplit = prefs.split
        trainingFrequency = prefs.frequency
        cyclingTarget = prefs.cyclingTarget
        thresholds = prefs.thresholds
        suppressServerSync = false
    }

    func loadMetricsAndReadiness() async {
        // No mock fallback: when the backend has no data, metrics/readiness stay
        // nil and the UI shows an empty state instead of fabricated numbers.
        metrics = try? await api.metricsToday()

        // HealthKit fallback (§4): Garmin/intervals data takes precedence. Only
        // when there's no server metrics AND Garmin isn't connected do we supply
        // metrics from Apple Health so readiness can still be computed.
        if metrics == nil, !intervals.connectionState.isConnected, health.readEnabled {
            metrics = await metricsFromHealthKit()
        }

        if let r = try? await api.readinessToday() {
            readiness = r
        } else {
            recalculate()  // engine result from real metrics, or nil if none
        }
    }

    /// Build `TrainingMetrics` from Apple Health readings. Returns nil unless at
    /// least one core recovery signal (RHR or HRV) is present, so we never
    /// fabricate a readiness score from nothing. Training-load fields (ATL/CTL)
    /// aren't available from HealthKit, so they default to a neutral balance.
    private func metricsFromHealthKit() async -> TrainingMetrics? {
        let rhr = await health.latestRestingHR()
        let hrv = await health.latestHRV()
        guard rhr != nil || hrv != nil else { return nil }

        let sleep = await health.lastNightSleepHours()
        let weight = await health.latestWeight()
        let hrvValue = hrv ?? 0

        return TrainingMetrics(
            hrv: hrvValue,
            hrvBaseline: hrvValue,           // single reading → treat as its own baseline
            hrvTrend: hrvValue > 0 ? [hrvValue] : [],
            restingHR: rhr ?? 0,
            restingHRBaseline: rhr ?? 0,
            sleepDuration: sleep ?? 0,
            sleepScore: sleep.map { min(100, Int($0 / 8.0 * 100)) } ?? 0,
            remSleep: 0, deepSleep: 0, sleepDebt: 0,
            acuteLoad: 0, chronicLoad: 0,    // no HealthKit load model → neutral balance
            todayLoad: 0, weeklyLoadChange: 0,
            bodyWeight: weight
        )
    }

    /// Marks today's resolved session as done. When HealthKit write is enabled,
    /// also logs it as an `HKWorkout` (§4). `start`/`end` bracket the session by
    /// its planned duration ending now.
    func markSessionDone(domain: TrainingDomain, title: String, durationMin: Int) async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .minute, value: -durationMin, to: end) ?? end
        await health.saveWorkout(domain: domain, title: title, start: start, end: end)
    }

    func loadPlans() async {
        if let plans = try? await api.plans(weeks: 4), !plans.isEmpty {
            weeklyPlans = plans
        }
    }

    func loadCoachHistory() async {
        if let history = try? await api.coachHistory(limit: 50), !history.isEmpty {
            messages = history
        }
    }

    private func syncFrequencyToServer() async {
        if let prefs = try? await api.updateSchedule(trainingFrequency.schedules) {
            suppressServerSync = true
            muscleGroupSplit = prefs.split
            suppressServerSync = false
            await loadPlans()  // server regenerated forward weeks (§7.6)
        }
    }

    private func syncThresholdsToServer() async {
        // Partial merge only — no plan regeneration (zones are render-time).
        _ = try? await api.updateThresholds(thresholds)
    }

    private func syncSplitToServer() async {
        if (try? await api.updateMuscleSplit(muscleGroupSplit)) != nil {
            await loadPlans()
        }
    }

    private func syncCyclingTargetToServer() async {
        if (try? await api.updateCyclingTarget(cyclingTarget)) != nil {
            await loadPlans()  // server rebuilt structured workouts for the new target
        }
    }

    // MARK: - Persistence helpers

    private static func loadFrequency() -> TrainingFrequency {
        guard let data = UserDefaults.standard.data(forKey: "northax.trainingFrequency"),
              let freq = try? JSONDecoder().decode(TrainingFrequency.self, from: data) else {
            // No saved frequency means the user hasn't defined a plan — start
            // empty so the Plan tab prompts them to create one rather than
            // assuming a default schedule.
            return .empty
        }
        return freq
    }

    private static func saveFrequency(_ freq: TrainingFrequency) {
        if let data = try? JSONEncoder().encode(freq) {
            UserDefaults.standard.set(data, forKey: "northax.trainingFrequency")
        }
    }

    func recalculate() {
        readiness = metrics.map { ReadinessEngine.calculate(from: $0) }
    }

    // MARK: - Plan generation

    func regeneratePlan() {
        // No training days defined yet → no plan. The Plan tab shows a
        // "create a plan" prompt rather than an assumed schedule.
        guard trainingFrequency.totalTrainingDays > 0 else {
            weeklyPlans = []
            planWasRecentlyUpdated = false
            return
        }
        weeklyPlans = PlanEngine.generatePlans(
            weeks: 4,
            frequency: trainingFrequency,
            muscleGroupSplit: muscleGroupSplit
        )
        planWasRecentlyUpdated = true
        // Auto-clear the banner after a few seconds
        Task {
            try? await Task.sleep(for: .seconds(4))
            planWasRecentlyUpdated = false
        }
    }

    // MARK: - Activity switch

    func switchSession(to domain: TrainingDomain, strengthSession: StrengthSession?) {
        if domain == .strength, let session = strengthSession {
            let desc = session.muscleGroups.prefix(3).map(\.rawValue).joined(separator: ", ")
            sessionOverride = SessionOverride(
                domain: .strength,
                title: session.title,
                duration: session.duration,
                intensityLabel: session.intensityLabel,
                intensityDescription: "\(session.intensityLabel) · \(desc)",
                strengthSession: session
            )
        } else {
            sessionOverride = switchSuggestion(for: domain)
        }
    }

    func clearSessionOverride() {
        sessionOverride = nil
    }

    /// Backend-generated strength session (§8.4) with engine fallback. Used by
    /// the activity switcher when the user picks a strength session.
    func generateStrengthSession(for muscleGroups: [MuscleGroup]) async -> StrengthSession? {
        if TokenStore.shared.hasSession {
            if let session = try? await api.strengthSession(
                muscleGroups: muscleGroups, readinessScore: readiness?.score
            ) {
                return session
            }
        }
        return nil  // caller falls back to StrengthEngine
    }

    // MARK: - Training-load model (TSS-like: hours × IF² × 100)

    /// Relative intensity factor for an intensity label (fraction of threshold).
    static func intensityFactor(_ label: String) -> Double {
        switch label.lowercased() {
        case "very easy", "minimal", "recovery": return 0.55
        case "easy":                              return 0.65
        case "moderate":                          return 0.75
        case "tempo":                             return 0.85
        case "hard", "threshold":                 return 0.95
        case "vo2", "vo2max", "max":              return 1.05
        default:                                  return 0.75
        }
    }

    func sessionLoad(durationMin: Int, intensity: String) -> Double {
        let f = Self.intensityFactor(intensity)
        return Double(durationMin) / 60.0 * f * f * 100.0
    }

    /// The training load prescribed for today (the deterministic suggestion).
    var prescribedLoad: Double {
        guard let readiness else { return 0 }
        return sessionLoad(durationMin: readiness.suggestedDuration, intensity: readiness.suggestedIntensityLabel)
    }

    /// Minutes needed at `intensity` to match `target` load, clamped to a sane range.
    private func durationForLoad(_ target: Double, intensity: String, _ range: ClosedRange<Int>) -> Int {
        let f = Self.intensityFactor(intensity)
        let mins = target / (f * f * 100.0) * 60.0
        return min(range.upperBound, max(range.lowerBound, Int(mins.rounded())))
    }

    /// A switch alternative whose training load matches today's prescribed load
    /// as closely as the sport allows (recovery/mobility stay short by design).
    /// Shared by the store (when applied) and the switcher view (for display).
    func switchSuggestion(for domain: TrainingDomain) -> SessionOverride {
        let target = prescribedLoad
        let score = readiness?.score ?? 0
        func matched(_ title: String, _ intensity: String, _ desc: String, _ range: ClosedRange<Int>) -> SessionOverride {
            let dur = durationForLoad(target, intensity: intensity, range)
            return SessionOverride(domain: domain, title: title, duration: dur,
                                   intensityLabel: intensity, intensityDescription: desc)
        }
        switch domain {
        case .cycling:
            if score >= 80 { return matched("Zone 3 Intervals", "Threshold", "70–85% FTP", 30...150) }
            if score >= 60 { return matched("Aerobic Endurance", "Moderate", "65–75% FTP", 30...180) }
            return matched("Recovery Ride", "Easy", "Zone 1–2", 30...120)

        case .running:
            if score >= 80 { return matched("Tempo Run", "Hard", "Comfortably hard pace", 20...75) }
            if score >= 60 { return matched("Easy Run", "Easy", "Zone 2", 20...100) }
            return matched("Recovery Jog", "Very Easy", "Conversational pace", 20...75)

        case .swimming:
            if score >= 80 { return matched("Interval Set", "Hard", "8×100m at race pace", 20...75) }
            if score >= 60 { return matched("Technique Session", "Moderate", "Drills + aerobic", 20...75) }
            return matched("Easy Swim", "Easy", "Continuous aerobic", 20...60)

        case .triathlon:
            return matched("Brick Session", "Moderate", "Bike + run", 45...150)

        case .mobility:
            // Recovery-oriented: kept short rather than load-matched.
            return SessionOverride(domain: domain, title: "Yoga Flow", duration: 40,
                                   intensityLabel: "Easy", intensityDescription: "Hip flexors, hamstrings, thoracic spine")

        case .recovery, .strength:
            return SessionOverride(domain: domain, title: "Active Recovery", duration: 20,
                                   intensityLabel: "Minimal", intensityDescription: "Short walk or light stretching")
        }
    }

    // MARK: - Coaching responses

    /// Stream a coach reply over SSE when authenticated (§8.2); fall back to the
    /// local templated response offline. The caller has already appended the
    /// user's message to `messages`.
    func respond(to question: String) async {
        guard TokenStore.shared.hasSession else {
            let response = buildResponse(for: question)
            try? await Task.sleep(for: .seconds(0.8))
            messages.append(CoachMessage(content: response, isCoach: true, timestamp: Date()))
            return
        }

        messages.append(CoachMessage(content: "", isCoach: true, timestamp: Date()))
        let index = messages.count - 1
        let stream = SSEClient.shared.coachStream(
            path: "ai/coach/message", body: CoachMessageRequest(content: question)
        )
        do {
            for try await event in stream {
                switch event {
                case .delta(let text):
                    messages[index].content += text
                case .done(_, let full):
                    if !full.isEmpty { messages[index].content = full }
                case .failed:
                    if messages[index].content.isEmpty {
                        messages[index].content = "The coach is unavailable right now. Please try again."
                    }
                }
            }
        } catch {
            if messages[index].content.isEmpty {
                messages[index].content = buildResponse(for: question)
            }
        }
    }

    private func intensityLabelFor(_ readiness: DailyReadiness) -> String {
        switch readiness.status {
        case .peak, .high: return "heavy"
        case .moderate:    return "moderate"
        case .low, .rest:  return "light"
        }
    }

    private func buildResponse(for question: String) -> String {
        let q = question.lowercased()
        guard let r = readiness, let m = metrics else {
            return "I don't have your training data yet. Connect a data source in Settings → Integrations and I'll give you guidance based on your real HRV, sleep, and training load."
        }

        if q.contains("train") || q.contains("session") || q.contains("today") {
            if r.score >= 70 {
                return "Based on your data, you're in good shape to train. Readiness is \(r.score)/100 — \(r.status.rawValue.lowercased()) zone.\n\nI'd go ahead with the \(r.suggestedSessionTitle). Your HRV is performing well and your training load is balanced, so you can push the intensity without significant risk."
            } else {
                return "Looking at your numbers, I'd recommend against hard training today. Readiness is \(r.score)/100 — your body is showing signs of stress.\n\nThe most productive thing you can do is rest or keep activity very light. The adaptations from yesterday's training happen during recovery, not during the next hard session."
            }
        }

        if q.contains("recovery") || q.contains("low") || q.contains("tired") || q.contains("fatigue") {
            var reasons: [String] = []
            if m.hrvChange < -0.08 { reasons.append("HRV is \(Int(abs(m.hrvChange) * 100))% below baseline") }
            if m.sleepDuration < 7  { reasons.append("only \(String(format: "%.1f", m.sleepDuration)) hours of sleep") }
            if m.trainingBalance < -15 { reasons.append("a spike in recent training load") }

            if reasons.isEmpty { return "Your recovery is actually looking reasonable. HRV, sleep quality, and training load are all within normal range." }
            return "Recovery is compromised primarily because of \(reasons.joined(separator: ", and ")).\n\nThese signals combine to indicate accumulated stress. Prioritising sleep, hydration, and nutrition over the next 24–48 hours will have more impact on your performance than any workout."
        }

        if q.contains("overtrain") {
            if m.trainingBalance < -20 || m.hrvChange < -0.15 {
                return "There are early warning signs. Acute load has spiked and your HRV trend is declining — this pattern is associated with functional overreaching.\n\nIt's not overtraining yet, but continuing at this pace without adequate recovery will get you there. Reduce intensity for 3–5 days."
            }
            return "Based on current metrics, you're not showing signs of overtraining. HRV is stable and training load is within a sustainable range.\n\nKey warning signs: persistent HRV depression, elevated resting HR, declining performance, chronic fatigue."
        }

        if q.contains("improv") || q.contains("progress") || q.contains("plateau") {
            return "Progression is happening, though it's rarely linear. Your chronic training load has been building steadily — the foundation of long-term performance.\n\nThe biggest lever right now is sleep consistency. Athletes who prioritise 8+ hours of quality sleep adapt faster than those who train more but sleep less."
        }

        if q.contains("focus") || q.contains("habit") || q.contains("biggest") {
            return "The single habit that would produce the biggest improvement right now is sleep consistency.\n\nYour training structure is solid, but sleep has been variable. Even one additional hour of quality sleep per night would measurably improve HRV, shorten recovery, and increase the training volume you can absorb."
        }

        if q.contains("load") || q.contains("tsb") || q.contains("atl") || q.contains("ctl") {
            let tsb = m.trainingBalance
            let sign = tsb >= 0 ? "+" : ""
            return "Your Training Stress Balance (TSB) is currently \(sign)\(Int(tsb)).\n\nTSB = Fitness (CTL) minus Fatigue (ATL). Positive means fresh; negative means carrying fatigue. The optimal performance window is roughly −10 to +5.\n\nAt \(Int(tsb)), you're \(abs(tsb) < 10 ? "in a great training window" : (tsb < 0 ? "carrying meaningful fatigue" : "quite fresh — consider adding some load"))."
        }

        if q.contains("garmin") || q.contains("intervals") || q.contains("sync") {
            return intervals.connectionState.isConnected
                ? "intervals.icu is connected and syncing. Your Garmin activities and wellness are being used to improve load calculations and recovery estimates."
                : "intervals.icu isn't connected yet. Head to Settings → Connect to link your account (it brings in your Garmin data). Once connected, your real training history replaces the sample data."
        }

        if q.contains("gym") || q.contains("muscle") || q.contains("strength") || q.contains("lift") {
            let weekday = Calendar.current.component(.weekday, from: Date())
            let split   = muscleGroupSplit.split(forCalendarWeekday: weekday)
            if split.isRestDay || split.muscleGroups.isEmpty {
                return "According to your weekly split, today is a rest day for strength work. If you want to hit the gym anyway, tap 'Switch Activity' on the dashboard — I'll generate an appropriate session based on your recovery status."
            }
            let groups = split.muscleGroups.map(\.rawValue).joined(separator: ", ")
            return "Today's split in your plan is: \(groups).\n\nWith readiness at \(r.score)/100, I'd programme this as a \(intensityLabelFor(r)) session. Tap 'Switch Activity' on the dashboard to see the full exercise list."
        }

        return "Good question. With a readiness score of \(r.score)/100, I'd recommend \(r.score >= 70 ? "executing today's session with intention — your body is ready" : "keeping today light and prioritising recovery").\n\nIs there a specific metric you'd like to understand better?"
    }
}
