package app.northax

import app.northax.domain.engine.ReadinessEngine
import app.northax.domain.model.DailyReadiness
import app.northax.domain.model.TrainingMetrics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadinessEngineTest {

    @Test
    fun `fresh metrics score high`() {
        val readiness = ReadinessEngine.calculate(TrainingMetrics.mockFresh)
        assertTrue("expected >= 70, got ${readiness.score}", readiness.score >= 70)
        assertTrue(
            readiness.status == DailyReadiness.Status.High || readiness.status == DailyReadiness.Status.Peak
        )
    }

    @Test
    fun `fatigued metrics score low`() {
        val readiness = ReadinessEngine.calculate(TrainingMetrics.mockFatigued)
        assertTrue("expected < 55, got ${readiness.score}", readiness.score < 55)
    }

    @Test
    fun `score stays within bounds and insights are complete`() {
        for (metrics in listOf(TrainingMetrics.mockFresh, TrainingMetrics.mockFatigued)) {
            val readiness = ReadinessEngine.calculate(metrics)
            assertTrue(readiness.score in 0..100)
            assertEquals(4, readiness.keyInsights.size)
            assertTrue(readiness.suggestedDuration > 0)
        }
    }
}
