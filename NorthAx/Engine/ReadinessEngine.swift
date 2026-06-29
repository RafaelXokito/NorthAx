import Foundation

struct ReadinessEngine {

    static func calculate(from metrics: TrainingMetrics) -> DailyReadiness {
        let hrvScore   = calculateHRVScore(metrics)
        let sleepScore = calculateSleepScore(metrics)
        let loadScore  = calculateLoadScore(metrics)
        let recovery   = (hrvScore + sleepScore + loadScore) / 3

        let total = Int(
            Double(hrvScore)   * 0.35 +
            Double(sleepScore) * 0.35 +
            Double(loadScore)  * 0.30
        )

        let status      = statusFor(score: total)
        let explanation = buildExplanation(metrics: metrics, status: status)
        let note        = buildCoachingNote(status: status, metrics: metrics)
        let insights    = buildInsights(metrics)
        let session     = buildSession(status: status)

        return DailyReadiness(
            score: total,
            status: status,
            explanation: explanation,
            coachingNote: note,
            hrvScore: hrvScore,
            sleepScore: sleepScore,
            loadScore: loadScore,
            recoveryScore: recovery,
            suggestedDomain: session.domain,
            suggestedSessionTitle: session.title,
            suggestedDuration: session.duration,
            suggestedIntensityLabel: session.intensityLabel,
            suggestedIntensityDescription: session.intensityDescription,
            keyInsights: insights
        )
    }

    // MARK: - Component scores

    private static func calculateHRVScore(_ m: TrainingMetrics) -> Int {
        // Each 1 % above baseline adds ~1.5 pts from base 70; below subtracts more steeply
        let deviation = m.hrvChange
        let score = deviation >= 0
            ? Int(70 + deviation * 150)
            : Int(70 + deviation * 220)
        return clamp(score)
    }

    private static func calculateSleepScore(_ m: TrainingMetrics) -> Int {
        let durationScore: Int
        switch m.sleepDuration {
        case 8...:      durationScore = 100
        case 7..<8:     durationScore = 90
        case 6..<7:     durationScore = 65
        case 5..<6:     durationScore = 40
        default:        durationScore = 20
        }
        return (durationScore + m.sleepScore) / 2
    }

    private static func calculateLoadScore(_ m: TrainingMetrics) -> Int {
        let tsb = m.trainingBalance
        switch tsb {
        case 20...:    return 58   // too fresh
        case 5..<20:   return 95
        case -5..<5:   return 100  // optimal window
        case -15..<(-5): return 82
        case -25..<(-15): return 62
        case -35..<(-25): return 42
        default:       return 22
        }
    }

    private static func clamp(_ v: Int) -> Int { max(0, min(100, v)) }

    // MARK: - Status

    private static func statusFor(score: Int) -> DailyReadiness.Status {
        switch score {
        case 85...100: return .peak
        case 70..<85:  return .high
        case 55..<70:  return .moderate
        case 35..<55:  return .low
        default:       return .rest
        }
    }

    // MARK: - Text generation

    private static func buildExplanation(metrics m: TrainingMetrics, status: DailyReadiness.Status) -> String {
        let c = m.hrvChange
        let hrv: String
        if c > 0.05 {
            hrv = "Your HRV is \(Int(c * 100))% above your baseline — your autonomic nervous system has recovered well."
        } else if c < -0.10 {
            hrv = "Your HRV has dropped \(Int(abs(c) * 100))% below your \(Int(m.hrvBaseline)) ms baseline, a key signal of accumulated stress."
        } else {
            hrv = "Your HRV is sitting at baseline (\(Int(m.hrv)) ms), indicating normal recovery."
        }

        let sleep: String
        if m.sleepDuration >= 7.5 {
            sleep = "Last night's \(String(format: "%.1f", m.sleepDuration)) hours of sleep was high quality."
        } else if m.sleepDuration >= 6.0 {
            sleep = "You got \(String(format: "%.1f", m.sleepDuration)) hours — adequate, but below the optimal 7.5–9 hours for full recovery."
        } else {
            sleep = "Only \(String(format: "%.1f", m.sleepDuration)) hours of sleep is insufficient. Muscle repair and hormonal recovery are compromised."
        }

        let tsb = m.trainingBalance
        let load: String
        if abs(tsb) <= 5 {
            load = "Your training load is perfectly balanced — enough fitness base without carrying excess fatigue."
        } else if tsb > 5 {
            load = "You're well-rested with \(Int(tsb)) points of surplus fitness. This is an excellent window for quality work."
        } else if tsb > -15 {
            load = "You're carrying moderate fatigue (TSB \(Int(tsb))). This is normal mid-block — stay within your structure."
        } else {
            load = "Accumulated fatigue is high (TSB \(Int(tsb))). Your body needs time to absorb the recent training stress."
        }

        return "\(hrv) \(sleep) \(load)"
    }

    private static func buildCoachingNote(status: DailyReadiness.Status, metrics: TrainingMetrics) -> String {
        switch status {
        case .peak:
            return "Conditions are optimal. Push the intensity — your body is primed to respond to a quality training stimulus today."
        case .high:
            return "Good conditions for training. Stay within your planned structure and you'll have a productive session."
        case .moderate:
            return "Train if your plan calls for it, but stay disciplined. Reduce effort if your body signals resistance."
        case .low:
            return "Light movement only. Prioritize movement quality over any fitness output today."
        case .rest:
            return "Rest is the training today. Forcing intensity now costs more than it earns. Let the adaptation happen."
        }
    }

    // MARK: - Insights

    private static func buildInsights(_ m: TrainingMetrics) -> [MetricInsight] {
        let c = m.hrvChange
        let hrvTrend: MetricInsight.Trend = c > 0.03 ? .up : (c < -0.05 ? .warning : .neutral)

        let sleepTrend: MetricInsight.Trend = m.sleepScore >= 80 ? .neutral : (m.sleepScore < 60 ? .warning : .down)

        let tsb = m.trainingBalance
        let tsbTrend: MetricInsight.Trend = abs(tsb) < 10 ? .neutral : (tsb < -15 ? .warning : .down)

        let hrDiff = m.restingHRChange
        let hrTrend: MetricInsight.Trend = hrDiff <= 0 ? .up : (hrDiff > 5 ? .warning : .down)

        return [
            MetricInsight(
                label: "HRV",
                value: "\(Int(m.hrv))",
                unit: "ms",
                trend: hrvTrend,
                explanation: c > 0.03 ? "Above baseline" : (c < -0.05 ? "Below baseline" : "At baseline"),
                context: c > 0.03
                    ? "\(Int(c * 100))% above your \(Int(m.hrvBaseline)) ms average — strong nervous system recovery."
                    : (c < -0.05
                        ? "\(Int(abs(c) * 100))% below your \(Int(m.hrvBaseline)) ms average — autonomic stress is elevated."
                        : "Within normal range of your \(Int(m.hrvBaseline)) ms baseline.")
            ),
            MetricInsight(
                label: "Sleep",
                value: String(format: "%.1f", m.sleepDuration),
                unit: "hrs",
                trend: sleepTrend,
                explanation: m.sleepScore >= 80 ? "Well rested" : (m.sleepScore < 60 ? "Poor sleep" : "Adequate"),
                context: "Sleep score \(m.sleepScore)/100.\(m.sleepDebt < 1 ? " Sleep debt is minimal." : " Sleep debt: \(String(format: "%.1f", m.sleepDebt)) h.")"
            ),
            MetricInsight(
                label: "Load",
                value: "\(tsb >= 0 ? "+" : "")\(Int(tsb))",
                unit: "TSB",
                trend: tsbTrend,
                explanation: abs(tsb) < 10 ? "Balanced" : (tsb < 0 ? "Fatigued" : "Fresh"),
                context: abs(tsb) < 10
                    ? "You're in the optimal zone — sufficient fitness without excessive fatigue."
                    : (tsb < -15
                        ? "High accumulated fatigue. Recovery should be the priority this week."
                        : "Moderate fatigue is normal during a build block.")
            ),
            MetricInsight(
                label: "Resting HR",
                value: "\(m.restingHR)",
                unit: "bpm",
                trend: hrTrend,
                explanation: hrDiff <= 0 ? "\(abs(hrDiff)) below baseline" : "\(hrDiff) above baseline",
                context: hrDiff <= 0
                    ? "Your cardiovascular system is efficient today."
                    : "Elevated resting HR signals your heart is working harder to maintain recovery."
            )
        ]
    }

    // MARK: - Session recommendation

    private static func buildSession(status: DailyReadiness.Status) -> (
        domain: TrainingDomain, title: String, duration: Int,
        intensityLabel: String, intensityDescription: String
    ) {
        switch status {
        case .peak:
            return (.cycling, "Zone 3 Intervals", 75, "Threshold",
                    "70–85% FTP · Hold power steady through each interval")
        case .high:
            return (.cycling, "Aerobic Endurance", 90, "Moderate",
                    "65–75% FTP · Conversational pace throughout")
        case .moderate:
            return (.running, "Easy Run", 45, "Easy",
                    "Zone 2 · Keep heart rate below 75% max HR")
        case .low:
            return (.mobility, "Mobility & Stretching", 30, "Very Easy",
                    "Focus on hip flexors, hamstrings, and thoracic spine")
        case .rest:
            return (.recovery, "Active Recovery", 20, "Minimal",
                    "Short walk or light stretching only")
        }
    }
}
