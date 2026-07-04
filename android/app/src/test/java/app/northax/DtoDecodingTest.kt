package app.northax

import app.northax.data.remote.ApiErrorEnvelope
import app.northax.data.remote.JsonCoders
import app.northax.data.remote.dto.ActivityCreateRequest
import app.northax.data.remote.dto.DailyReadinessResponse
import app.northax.data.remote.dto.WeeklyPlanResponse
import app.northax.data.toDomain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate

/** Wire-contract sanity: camelCase keys, mixed date formats, error envelope. */
class DtoDecodingTest {

    private val json = JsonCoders.json

    @Test
    fun `readiness response decodes with mixed date formats`() {
        val payload = """
            {
              "date": "2026-07-04",
              "score": 72,
              "status": "High",
              "verdict": "Good day to train.",
              "explanation": "…",
              "coachingNote": "…",
              "componentScores": {"hrv": 75, "sleep": 80, "load": 65, "recovery": 70},
              "suggestedSession": {
                "domain": "Cycling", "title": "Threshold Work", "duration": 75,
                "intensityLabel": "Hard", "intensityDescription": "Sustainable effort"
              },
              "keyInsights": [],
              "aiExplanation": {
                "narrative": "You're well-recovered.",
                "generatedAt": "2026-07-04T10:30:00.123456+00:00",
                "model": "hermes"
              },
              "someFutureField": true
            }
        """.trimIndent()
        val dto = json.decodeFromString<DailyReadinessResponse>(payload)
        assertEquals(LocalDate.of(2026, 7, 4), dto.date)
        assertEquals(72, dto.score)
        val domain = dto.toDomain()
        assertEquals("You're well-recovered.", domain.aiNarrative)
        assertEquals(75, domain.suggestedDuration)
    }

    @Test
    fun `weekly plan decodes and maps sessions`() {
        val payload = """
            {
              "weekStart": "2026-06-29",
              "weekLabel": "Jun 29 – Jul 5",
              "isCurrentWeek": true,
              "generatedAt": "2026-06-29T06:00:00+00:00",
              "days": [
                {
                  "date": "2026-06-29", "weekdayShort": "Mon", "dayNumber": "29",
                  "isRest": false, "isToday": false, "isPast": true,
                  "sessions": [{
                    "domain": "Cycling", "title": "Z2 Endurance", "subtitle": null,
                    "duration": 90, "intensityLabel": "Easy",
                    "workout": {"targetMode": "hr", "blocks": [
                      {"repeat": 1, "steps": [{"cue": "Warm up", "minutes": 10, "target": "Z1", "icu": "Z1 HR"}]}
                    ]}
                  }]
                }
              ]
            }
        """.trimIndent()
        val week = json.decodeFromString<WeeklyPlanResponse>(payload).toDomain()
        assertEquals(LocalDate.of(2026, 6, 29), week.weekStart)
        assertEquals(1, week.days.size)
        val s = week.days[0].sessions.single()
        assertEquals("Z2 Endurance", s.title)
        assertEquals(1, s.workout?.blocks?.size)
    }

    @Test
    fun `error envelope decodes`() {
        val env = json.decodeFromString<ApiErrorEnvelope>(
            """{"error": {"code": "METRICS_NOT_FOUND", "message": "No metrics.", "status": 404}}"""
        )
        assertEquals("METRICS_NOT_FOUND", env.error.code)
        assertEquals(404, env.error.status)
    }

    @Test
    fun `activity create request encodes calendar-safe payload`() {
        val encoded = json.encodeToString(
            ActivityCreateRequest.serializer(),
            ActivityCreateRequest(
                name = "Strength Workout",
                domain = "Strength",
                startTime = Instant.parse("2026-07-04T18:00:00Z"),
                durationSeconds = 3600,
            ),
        )
        assertTrue(encoded.contains("\"startTime\":\"2026-07-04T18:00:00Z\""))
        assertTrue(encoded.contains("\"durationSeconds\":3600"))
    }
}
