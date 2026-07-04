package app.northax.domain.engine

import app.northax.domain.model.PlannedDay
import app.northax.domain.model.PlannedSession
import app.northax.domain.model.TrainingDomain
import app.northax.domain.model.TrainingFrequency
import app.northax.domain.model.WeeklyMuscleGroupSplit
import app.northax.domain.model.WeeklyPlan
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

/** Deterministic local plan generator — offline/debug fallback (iOS PlanEngine). */
object PlanEngine {

    /** Generates `weeks` consecutive weekly plans starting from the Monday of
     *  the week that contains `from`. */
    fun generatePlans(
        from: LocalDate = LocalDate.now(),
        weeks: Int = 4,
        frequency: TrainingFrequency,
        muscleGroupSplit: WeeklyMuscleGroupSplit,
    ): List<WeeklyPlan> {
        val monday = mondayOf(from)
        return (0 until weeks).map { offset ->
            generateWeek(monday.plusWeeks(offset.toLong()), frequency, muscleGroupSplit)
        }
    }

    /** Places one session per (sport, weekday) pair. A weekday with several
     *  sports gets several sessions; a weekday with no sessions is a rest day. */
    private fun generateWeek(
        start: LocalDate,
        frequency: TrainingFrequency,
        split: WeeklyMuscleGroupSplit,
    ): WeeklyPlan {
        val days = (0 until 7).map { offset -> // 0=Mon … 6=Sun
            val date = start.plusDays(offset.toLong())
            val sessions = frequency.schedules
                .filter { offset in it.weekdays }
                .map { makeSession(it.domain, offset, date.dayOfWeek, split) }
            PlannedDay(date = date, sessions = sessions, isRest = sessions.isEmpty())
        }
        return WeeklyPlan(weekStart = start, days = days)
    }

    private fun makeSession(
        domain: TrainingDomain,
        slot: Int, // 0=Mon … 6=Sun, used to vary session type within a week
        weekday: DayOfWeek,
        split: WeeklyMuscleGroupSplit,
    ): PlannedSession = when (domain) {
        TrainingDomain.Cycling -> {
            val variants = listOf(
                Variant("Zone 3 Intervals", "70–85% FTP · 5×8 min efforts", 75, "Threshold"),
                Variant("Aerobic Endurance", "65–75% FTP · Steady state", 90, "Moderate"),
                Variant("Easy Recovery Ride", "55–65% FTP · Active recovery", 60, "Easy"),
            )
            variants[slot % variants.size].toSession(domain)
        }

        TrainingDomain.Running -> {
            val variants = listOf(
                Variant("Easy Run", "Zone 2 · Conversational pace", 45, "Easy"),
                Variant("Tempo Run", "Comfortably hard · ~80% max HR", 40, "Hard"),
                Variant("Long Run", "Zone 1–2 · Building endurance", 70, "Easy"),
            )
            variants[slot % variants.size].toSession(domain)
        }

        TrainingDomain.Strength -> {
            val daySplit = split.splitForIsoWeekday(weekday.value)
            val groupLabel = if (daySplit.isRestDay || daySplit.muscleGroups.isEmpty()) "Full Body"
            else daySplit.displayName
            PlannedSession(
                domain = domain, title = groupLabel,
                subtitle = "Gym · Per your weekly split",
                duration = 60, intensityLabel = "Moderate",
            )
        }

        TrainingDomain.Swimming -> {
            val variants = listOf(
                Variant("Interval Set", "8×100m at race pace", 55, "Hard"),
                Variant("Technique Session", "Drills + aerobic endurance", 45, "Moderate"),
            )
            variants[slot % variants.size].toSession(domain)
        }

        TrainingDomain.Triathlon -> PlannedSession(
            domain = domain, title = "Brick Session",
            subtitle = "60 min bike + 20 min run",
            duration = 90, intensityLabel = "Moderate",
        )

        TrainingDomain.Mobility -> PlannedSession(
            domain = domain, title = "Mobility Flow",
            subtitle = "Yoga · Hip flexors, hamstrings, spine",
            duration = 40, intensityLabel = "Easy",
        )

        TrainingDomain.Recovery -> PlannedSession(
            domain = domain, title = "Active Recovery",
            subtitle = "Short walk or light stretching",
            duration = 25, intensityLabel = "Very Easy",
        )
    }

    private data class Variant(val title: String, val subtitle: String, val duration: Int, val intensity: String) {
        fun toSession(domain: TrainingDomain) = PlannedSession(
            domain = domain, title = title, subtitle = subtitle,
            duration = duration, intensityLabel = intensity,
        )
    }

    fun mondayOf(date: LocalDate): LocalDate =
        date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
}
