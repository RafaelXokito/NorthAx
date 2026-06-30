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

@Observable
class AthleteStore {
    var athleteName: String = "Athlete"
    var enabledDomains: [TrainingDomain] = [.cycling, .strength]
    var muscleGroupSplit: WeeklyMuscleGroupSplit = .pushPullLegs
    var metrics: TrainingMetrics = .mockFresh
    var readiness: DailyReadiness
    var messages: [CoachMessage] = [.opening]
    var sessionOverride: SessionOverride? = nil

    // Training frequency + plan — persisted across launches
    var trainingFrequency: TrainingFrequency = AthleteStore.loadFrequency() {
        didSet {
            if trainingFrequency != oldValue {
                AthleteStore.saveFrequency(trainingFrequency)
                regeneratePlan()
            }
        }
    }
    var weeklyPlans: [WeeklyPlan] = []
    var planWasRecentlyUpdated: Bool = false
    var hasSetFrequency: Bool = UserDefaults.standard.bool(forKey: "northax.hasSetFrequency") {
        didSet { UserDefaults.standard.set(hasSetFrequency, forKey: "northax.hasSetFrequency") }
    }

    let garmin = GarminService()

    var useFatiguedScenario: Bool = false {
        didSet {
            metrics = useFatiguedScenario ? .mockFatigued : .mockFresh
            recalculate()
        }
    }

    init() {
        readiness = ReadinessEngine.calculate(from: .mockFresh)
        weeklyPlans = PlanEngine.generatePlans(
            weeks: 4,
            frequency: trainingFrequency,
            muscleGroupSplit: muscleGroupSplit
        )
    }

    // Called by ContentView when the signed-in user changes
    func configure(with user: AuthUser) {
        if !user.name.isEmpty { athleteName = user.name }
    }

    func resetForSignOut() {
        hasSetFrequency = false
        trainingFrequency = .defaultFrequency
        messages = [.opening]
        sessionOverride = nil
    }

    // MARK: - Persistence helpers

    private static func loadFrequency() -> TrainingFrequency {
        guard let data = UserDefaults.standard.data(forKey: "northax.trainingFrequency"),
              let freq = try? JSONDecoder().decode(TrainingFrequency.self, from: data) else {
            return .defaultFrequency
        }
        return freq
    }

    private static func saveFrequency(_ freq: TrainingFrequency) {
        if let data = try? JSONEncoder().encode(freq) {
            UserDefaults.standard.set(data, forKey: "northax.trainingFrequency")
        }
    }

    func recalculate() {
        readiness = ReadinessEngine.calculate(from: metrics)
    }

    // MARK: - Plan generation

    func regeneratePlan() {
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
            sessionOverride = standardOverride(for: domain)
        }
    }

    func clearSessionOverride() {
        sessionOverride = nil
    }

    private func standardOverride(for domain: TrainingDomain) -> SessionOverride {
        let score = readiness.score
        switch domain {
        case .cycling:
            if score >= 80 { return SessionOverride(domain: domain, title: "Zone 3 Intervals", duration: 75, intensityLabel: "Threshold", intensityDescription: "70–85% FTP") }
            if score >= 60 { return SessionOverride(domain: domain, title: "Aerobic Endurance", duration: 90, intensityLabel: "Moderate",  intensityDescription: "65–75% FTP") }
            return SessionOverride(domain: domain, title: "Recovery Ride",     duration: 45, intensityLabel: "Easy",      intensityDescription: "Zone 1–2")

        case .running:
            if score >= 80 { return SessionOverride(domain: domain, title: "Tempo Run",         duration: 50, intensityLabel: "Hard",      intensityDescription: "Comfortably hard pace") }
            if score >= 60 { return SessionOverride(domain: domain, title: "Easy Run",           duration: 45, intensityLabel: "Easy",      intensityDescription: "Zone 2") }
            return SessionOverride(domain: domain, title: "Recovery Jog",     duration: 30, intensityLabel: "Very Easy", intensityDescription: "Conversational pace")

        case .swimming:
            if score >= 80 { return SessionOverride(domain: domain, title: "Interval Set",       duration: 60, intensityLabel: "Hard",      intensityDescription: "8×100m at race pace") }
            return SessionOverride(domain: domain, title: "Technique Session",  duration: 45, intensityLabel: "Moderate",  intensityDescription: "Drills + aerobic")

        case .triathlon:
            return SessionOverride(domain: domain, title: "Brick Session",      duration: 90, intensityLabel: "Moderate",  intensityDescription: "60 min bike + 20 min run")

        case .mobility:
            return SessionOverride(domain: domain, title: "Yoga Flow",          duration: 40, intensityLabel: "Easy",      intensityDescription: "Hip flexors, hamstrings, thoracic spine")

        case .recovery, .strength:
            return SessionOverride(domain: domain, title: "Active Recovery",    duration: 20, intensityLabel: "Minimal",   intensityDescription: "Short walk or light stretching")
        }
    }

    // MARK: - Coaching responses

    func respond(to question: String) async {
        let response = buildResponse(for: question)
        try? await Task.sleep(for: .seconds(1.2))
        messages.append(CoachMessage(content: response, isCoach: true, timestamp: Date()))
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
        let r = readiness
        let m = metrics

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

        if q.contains("garmin") || q.contains("sync") {
            return garmin.connectionState.isConnected
                ? "Garmin is connected and syncing. Your recent activities are being used to improve load calculations and recovery estimates."
                : "Garmin isn't connected yet. Head to Settings → Garmin Connect to link your account. Once connected, your actual training history will replace the mock data."
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
