package app.northax

import app.northax.domain.engine.PlanMatchingEngine
import app.northax.domain.engine.SessionCompletion
import app.northax.domain.model.GarminActivity
import app.northax.domain.model.GarminActivityType
import app.northax.domain.model.PlannedDay
import app.northax.domain.model.PlannedSession
import app.northax.domain.model.TrainingDomain
import app.northax.domain.model.WeeklyPlan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

/** Port of the iOS PlanMatchingEngineTests — same scenarios, same expectations. */
class PlanMatchingEngineTest {

    private val monday: LocalDate = LocalDate.of(2026, 6, 29) // a Monday
    private val today: LocalDate = LocalDate.of(2026, 7, 2)   // Thursday of that week

    private fun week(vararg sessions: Pair<Int, PlannedSession>): WeeklyPlan {
        val byDay = sessions.groupBy({ it.first }, { it.second })
        val days = (0 until 7).map { offset ->
            val s = byDay[offset] ?: emptyList()
            PlannedDay(date = monday.plusDays(offset.toLong()), sessions = s, isRest = s.isEmpty())
        }
        return WeeklyPlan(weekStart = monday, days = days)
    }

    private fun session(domain: TrainingDomain, title: String = "Session", duration: Int = 60) =
        PlannedSession(domain = domain, title = title, subtitle = "", duration = duration, intensityLabel = "Moderate")

    private fun activity(
        dayOffset: Int,
        type: GarminActivityType,
        durationMinutes: Int = 60,
        id: String = "a-$dayOffset-$type-$durationMinutes",
    ) = GarminActivity(
        id = id,
        name = "Imported",
        type = type,
        startTime = monday.plusDays(dayOffset.toLong()).atTime(9, 0).atZone(ZoneId.systemDefault()).toInstant(),
        durationSeconds = durationMinutes * 60L,
    )

    @Test
    fun `same day same sport marks done`() {
        val plan = week(0 to session(TrainingDomain.Cycling))
        val matches = PlanMatchingEngine.matches(plan, listOf(activity(0, GarminActivityType.Cycling)), today)
        assertEquals(SessionCompletion.Done, matches.single().completion)
        assertNotNull(matches.single().activity)
    }

    @Test
    fun `past day without workout marks missed`() {
        val plan = week(0 to session(TrainingDomain.Cycling))
        val matches = PlanMatchingEngine.matches(plan, emptyList(), today)
        assertEquals(SessionCompletion.Missed, matches.single().completion)
    }

    @Test
    fun `future day without workout stays planned`() {
        val plan = week(5 to session(TrainingDomain.Cycling)) // Saturday
        val matches = PlanMatchingEngine.matches(plan, emptyList(), today)
        assertEquals(SessionCompletion.Planned, matches.single().completion)
    }

    @Test
    fun `same day different sport does not match`() {
        val plan = week(0 to session(TrainingDomain.Cycling))
        val matches = PlanMatchingEngine.matches(plan, listOf(activity(0, GarminActivityType.Running)), today)
        // Planned session missed; the run surfaces as an extra.
        val planned = matches.first { it.session.domain == TrainingDomain.Cycling }
        assertEquals(SessionCompletion.Missed, planned.completion)
        assertNull(planned.activity)
        val extra = matches.first { it.completion == SessionCompletion.Extra }
        assertEquals(TrainingDomain.Running, extra.session.domain)
    }

    @Test
    fun `closest duration wins when several workouts fit`() {
        val plan = week(0 to session(TrainingDomain.Cycling, duration = 90))
        val far = activity(0, GarminActivityType.Cycling, durationMinutes = 30, id = "far")
        val close = activity(0, GarminActivityType.Cycling, durationMinutes = 85, id = "close")
        val matches = PlanMatchingEngine.matches(plan, listOf(far, close), today)
        val done = matches.first { it.completion == SessionCompletion.Done }
        assertEquals("close", done.activity?.id)
    }

    @Test
    fun `unplanned workout on rest day surfaces as extra and rolls the day to done`() {
        val plan = week(0 to session(TrainingDomain.Cycling))
        val restDay = plan.days[3] // Thursday, rest
        val extraActivity = activity(3, GarminActivityType.Running)
        val matches = PlanMatchingEngine.matches(plan, listOf(extraActivity, activity(0, GarminActivityType.Cycling)), today)
        assertEquals(1, matches.count { it.completion == SessionCompletion.Extra })
        assertEquals(SessionCompletion.Done, PlanMatchingEngine.dayState(restDay, matches))
    }

    @Test
    fun `one activity matches at most one planned session`() {
        val plan = week(0 to session(TrainingDomain.Cycling), 0 to session(TrainingDomain.Cycling, "Second"))
        val matches = PlanMatchingEngine.matches(plan, listOf(activity(0, GarminActivityType.Cycling)), today)
        assertEquals(1, matches.count { it.completion == SessionCompletion.Done })
        assertEquals(1, matches.count { it.completion == SessionCompletion.Missed })
    }

    @Test
    fun `day state rolls up missed over done`() {
        val plan = week(0 to session(TrainingDomain.Cycling), 0 to session(TrainingDomain.Strength))
        val matches = PlanMatchingEngine.matches(plan, listOf(activity(0, GarminActivityType.Cycling)), today)
        assertEquals(SessionCompletion.Missed, PlanMatchingEngine.dayState(plan.days[0], matches))
    }

    @Test
    fun `today matches show extras even without a covering plan week`() {
        val todayRun = activity(3, GarminActivityType.Running, id = "run") // Thursday == today

        // No plan at all — the workout still surfaces as an extra.
        val noPlan = PlanMatchingEngine.todayMatches(null, listOf(todayRun), today)
        assertEquals(SessionCompletion.Extra, noPlan.single().completion)
        assertEquals("run", noPlan.single().activity?.id)

        // A lapsed plan week that doesn't contain today — same outcome.
        val staleMonday = monday.minusWeeks(2)
        val staleWeek = WeeklyPlan(weekStart = staleMonday, days = (0 until 7).map {
            PlannedDay(date = staleMonday.plusDays(it.toLong()), sessions = emptyList(), isRest = true)
        })
        val stale = PlanMatchingEngine.todayMatches(staleWeek, listOf(todayRun), today)
        assertEquals(SessionCompletion.Extra, stale.single().completion)

        // A week that covers today must not duplicate the extra.
        val covered = PlanMatchingEngine.todayMatches(week(3 to session(TrainingDomain.Cycling)), listOf(todayRun), today)
        assertEquals(2, covered.size)
        assertEquals(1, covered.count { it.completion == SessionCompletion.Extra })
        assertEquals(1, covered.count { it.completion == SessionCompletion.Planned })
    }

    @Test
    fun `extra matches keep a stable id across recomputations`() {
        val plan = week(0 to session(TrainingDomain.Cycling))
        val run = activity(3, GarminActivityType.Running, id = "run")
        val first = PlanMatchingEngine.matches(plan, listOf(run), today).first { it.completion == SessionCompletion.Extra }
        val second = PlanMatchingEngine.matches(plan, listOf(run), today).first { it.completion == SessionCompletion.Extra }
        assertEquals(first.id, second.id)
    }
}
