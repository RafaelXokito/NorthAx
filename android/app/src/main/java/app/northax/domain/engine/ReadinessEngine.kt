package app.northax.domain.engine

import app.northax.domain.model.DailyReadiness
import app.northax.domain.model.MetricInsight
import app.northax.domain.model.TrainingDomain
import app.northax.domain.model.TrainingMetrics
import java.util.Locale
import kotlin.math.abs

/** Offline fallback readiness calculation — a 1:1 port of the iOS engine. */
object ReadinessEngine {

    fun calculate(metrics: TrainingMetrics): DailyReadiness {
        val hrvScore = calculateHRVScore(metrics)
        val sleepScore = calculateSleepScore(metrics)
        val loadScore = calculateLoadScore(metrics)
        val recovery = (hrvScore + sleepScore + loadScore) / 3

        val total = (hrvScore * 0.35 + sleepScore * 0.35 + loadScore * 0.30).toInt()

        val status = statusFor(total)
        val session = buildSession(status)

        return DailyReadiness(
            score = total,
            status = status,
            explanation = buildExplanation(metrics),
            coachingNote = buildCoachingNote(status),
            hrvScore = hrvScore,
            sleepScore = sleepScore,
            loadScore = loadScore,
            recoveryScore = recovery,
            suggestedDomain = session.domain,
            suggestedSessionTitle = session.title,
            suggestedDuration = session.duration,
            suggestedIntensityLabel = session.intensityLabel,
            suggestedIntensityDescription = session.intensityDescription,
            keyInsights = buildInsights(metrics),
        )
    }

    // MARK: - Component scores

    private fun calculateHRVScore(m: TrainingMetrics): Int {
        // Each 1% above baseline adds ~1.5 pts from base 70; below subtracts more steeply.
        val deviation = m.hrvChange
        val score = if (deviation >= 0) (70 + deviation * 150).toInt() else (70 + deviation * 220).toInt()
        return score.coerceIn(0, 100)
    }

    private fun calculateSleepScore(m: TrainingMetrics): Int {
        val durationScore = when {
            m.sleepDuration >= 8 -> 100
            m.sleepDuration >= 7 -> 90
            m.sleepDuration >= 6 -> 65
            m.sleepDuration >= 5 -> 40
            else -> 20
        }
        return (durationScore + m.sleepScore) / 2
    }

    private fun calculateLoadScore(m: TrainingMetrics): Int {
        val tsb = m.trainingBalance
        return when {
            tsb >= 20 -> 58 // too fresh
            tsb >= 5 -> 95
            tsb >= -5 -> 100 // optimal window
            tsb >= -15 -> 82
            tsb >= -25 -> 62
            tsb >= -35 -> 42
            else -> 22
        }
    }

    // MARK: - Status

    private fun statusFor(score: Int): DailyReadiness.Status = when {
        score >= 85 -> DailyReadiness.Status.Peak
        score >= 70 -> DailyReadiness.Status.High
        score >= 55 -> DailyReadiness.Status.Moderate
        score >= 35 -> DailyReadiness.Status.Low
        else -> DailyReadiness.Status.Rest
    }

    // MARK: - Text generation

    private fun fmt1(v: Double): String = String.format(Locale.US, "%.1f", v)

    private fun buildExplanation(m: TrainingMetrics): String {
        val c = m.hrvChange
        val hrv = when {
            c > 0.05 -> "Your HRV is ${(c * 100).toInt()}% above your baseline — your autonomic nervous system has recovered well."
            c < -0.10 -> "Your HRV has dropped ${(abs(c) * 100).toInt()}% below your ${m.hrvBaseline.toInt()} ms baseline, a key signal of accumulated stress."
            else -> "Your HRV is sitting at baseline (${m.hrv.toInt()} ms), indicating normal recovery."
        }

        val sleep = when {
            m.sleepDuration >= 7.5 -> "Last night's ${fmt1(m.sleepDuration)} hours of sleep was high quality."
            m.sleepDuration >= 6.0 -> "You got ${fmt1(m.sleepDuration)} hours — adequate, but below the optimal 7.5–9 hours for full recovery."
            else -> "Only ${fmt1(m.sleepDuration)} hours of sleep is insufficient. Muscle repair and hormonal recovery are compromised."
        }

        val tsb = m.trainingBalance
        val load = when {
            abs(tsb) <= 5 -> "Your training load is perfectly balanced — enough fitness base without carrying excess fatigue."
            tsb > 5 -> "You're well-rested with ${tsb.toInt()} points of surplus fitness. This is an excellent window for quality work."
            tsb > -15 -> "You're carrying moderate fatigue (TSB ${tsb.toInt()}). This is normal mid-block — stay within your structure."
            else -> "Accumulated fatigue is high (TSB ${tsb.toInt()}). Your body needs time to absorb the recent training stress."
        }

        return "$hrv $sleep $load"
    }

    private fun buildCoachingNote(status: DailyReadiness.Status): String = when (status) {
        DailyReadiness.Status.Peak ->
            "Conditions are optimal. Push the intensity — your body is primed to respond to a quality training stimulus today."
        DailyReadiness.Status.High ->
            "Good conditions for training. Stay within your planned structure and you'll have a productive session."
        DailyReadiness.Status.Moderate ->
            "Train if your plan calls for it, but stay disciplined. Reduce effort if your body signals resistance."
        DailyReadiness.Status.Low ->
            "Light movement only. Prioritize movement quality over any fitness output today."
        DailyReadiness.Status.Rest ->
            "Rest is the training today. Forcing intensity now costs more than it earns. Let the adaptation happen."
    }

    // MARK: - Insights

    private fun buildInsights(m: TrainingMetrics): List<MetricInsight> {
        val c = m.hrvChange
        val hrvTrend = if (c > 0.03) MetricInsight.Trend.Up
        else if (c < -0.05) MetricInsight.Trend.Warning else MetricInsight.Trend.Neutral

        val sleepTrend = if (m.sleepScore >= 80) MetricInsight.Trend.Neutral
        else if (m.sleepScore < 60) MetricInsight.Trend.Warning else MetricInsight.Trend.Down

        val tsb = m.trainingBalance
        val tsbTrend = if (abs(tsb) < 10) MetricInsight.Trend.Neutral
        else if (tsb < -15) MetricInsight.Trend.Warning else MetricInsight.Trend.Down

        val hrDiff = m.restingHRChange
        val hrTrend = if (hrDiff <= 0) MetricInsight.Trend.Up
        else if (hrDiff > 5) MetricInsight.Trend.Warning else MetricInsight.Trend.Down

        return listOf(
            MetricInsight(
                label = "HRV",
                value = "${m.hrv.toInt()}",
                unit = "ms",
                trend = hrvTrend,
                explanation = if (c > 0.03) "Above baseline" else if (c < -0.05) "Below baseline" else "At baseline",
                context = when {
                    c > 0.03 -> "${(c * 100).toInt()}% above your ${m.hrvBaseline.toInt()} ms average — strong nervous system recovery."
                    c < -0.05 -> "${(abs(c) * 100).toInt()}% below your ${m.hrvBaseline.toInt()} ms average — autonomic stress is elevated."
                    else -> "Within normal range of your ${m.hrvBaseline.toInt()} ms baseline."
                },
            ),
            MetricInsight(
                label = "Sleep",
                value = fmt1(m.sleepDuration),
                unit = "hrs",
                trend = sleepTrend,
                explanation = if (m.sleepScore >= 80) "Well rested" else if (m.sleepScore < 60) "Poor sleep" else "Adequate",
                context = "Sleep score ${m.sleepScore}/100." +
                    if (m.sleepDebt < 1) " Sleep debt is minimal." else " Sleep debt: ${fmt1(m.sleepDebt)} h.",
            ),
            MetricInsight(
                label = "Load",
                value = "${if (tsb >= 0) "+" else ""}${tsb.toInt()}",
                unit = "TSB",
                trend = tsbTrend,
                explanation = if (abs(tsb) < 10) "Balanced" else if (tsb < 0) "Fatigued" else "Fresh",
                context = when {
                    abs(tsb) < 10 -> "You're in the optimal zone — sufficient fitness without excessive fatigue."
                    tsb < -15 -> "High accumulated fatigue. Recovery should be the priority this week."
                    else -> "Moderate fatigue is normal during a build block."
                },
            ),
            MetricInsight(
                label = "Resting HR",
                value = "${m.restingHR}",
                unit = "bpm",
                trend = hrTrend,
                explanation = if (hrDiff <= 0) "${abs(hrDiff)} below baseline" else "$hrDiff above baseline",
                context = if (hrDiff <= 0) "Your cardiovascular system is efficient today."
                else "Elevated resting HR signals your heart is working harder to maintain recovery.",
            ),
        )
    }

    // MARK: - Session recommendation

    private data class Suggested(
        val domain: TrainingDomain,
        val title: String,
        val duration: Int,
        val intensityLabel: String,
        val intensityDescription: String,
    )

    private fun buildSession(status: DailyReadiness.Status): Suggested = when (status) {
        DailyReadiness.Status.Peak -> Suggested(
            TrainingDomain.Cycling, "Zone 3 Intervals", 75, "Threshold",
            "70–85% FTP · Hold power steady through each interval"
        )
        DailyReadiness.Status.High -> Suggested(
            TrainingDomain.Cycling, "Aerobic Endurance", 90, "Moderate",
            "65–75% FTP · Conversational pace throughout"
        )
        DailyReadiness.Status.Moderate -> Suggested(
            TrainingDomain.Running, "Easy Run", 45, "Easy",
            "Zone 2 · Keep heart rate below 75% max HR"
        )
        DailyReadiness.Status.Low -> Suggested(
            TrainingDomain.Mobility, "Mobility & Stretching", 30, "Very Easy",
            "Focus on hip flexors, hamstrings, and thoracic spine"
        )
        DailyReadiness.Status.Rest -> Suggested(
            TrainingDomain.Recovery, "Active Recovery", 20, "Minimal",
            "Short walk or light stretching only"
        )
    }
}
