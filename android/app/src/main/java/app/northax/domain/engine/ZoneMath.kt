package app.northax.domain.engine

import app.northax.domain.model.AthleteThresholds
import app.northax.domain.model.PaceUnit
import app.northax.domain.model.TrainingDomain
import kotlin.math.roundToInt

// Converts coach-emitted zone tokens (Z1..Z5) into concrete numeric ranges
// using the athlete's thresholds. Pure / no UI. The graph uses this to draw a
// real numeric Y-axis; when the needed threshold is missing every function
// returns null and the graph falls back to zone-only rendering.

enum class ZoneMode { Hr, Power, Pace }

/**
 * Numeric bounds for a zone. Units depend on mode: bpm (hr), watts (power),
 * seconds-per-unit (pace, where LOWER = faster). A null bound is open-ended.
 */
data class ZoneRange(val lower: Double?, val upper: Double?)

object ZoneMath {

    // % of FTP. Z5 is open-topped; cap display at 120%.
    private val powerBounds: Map<Int, Pair<Double, Double?>> = mapOf(
        1 to (0.40 to 0.55), 2 to (0.56 to 0.75), 3 to (0.76 to 0.90),
        4 to (0.91 to 1.05), 5 to (1.06 to 1.20),
    )

    // % of LTHR. Z5 open-topped; cap ~110%.
    private val hrBounds: Map<Int, Pair<Double, Double?>> = mapOf(
        1 to (0.65 to 0.81), 2 to (0.81 to 0.89), 3 to (0.90 to 0.93),
        4 to (0.94 to 0.99), 5 to (1.00 to 1.10),
    )

    // % of threshold SPEED (pace is inverse). Z5 open-topped; cap ~108%.
    private val paceSpeedBounds: Map<Int, Pair<Double, Double?>> = mapOf(
        1 to (0.78 to 0.84), 2 to (0.84 to 0.91), 3 to (0.91 to 0.96),
        4 to (0.96 to 1.02), 5 to (1.02 to 1.08),
    )

    /** Numeric range for a zone, or null if the relevant threshold is absent. */
    fun range(zone: Int, mode: ZoneMode, sport: TrainingDomain, thresholds: AthleteThresholds): ZoneRange? {
        if (zone !in 1..5) return null
        return when (mode) {
            ZoneMode.Power -> {
                val ftp = thresholds.ftpWatts ?: return null
                val b = powerBounds[zone] ?: return null
                ZoneRange(ftp * b.first, b.second?.let { ftp * it })
            }
            ZoneMode.Hr -> {
                val lthr = lthr(thresholds) ?: return null
                val b = hrBounds[zone] ?: return null
                ZoneRange(lthr * b.first, b.second?.let { lthr * it })
            }
            ZoneMode.Pace -> {
                val thr = thresholdPaceSeconds(sport, thresholds) ?: return null
                val b = paceSpeedBounds[zone] ?: return null
                // Higher speed factor => faster => fewer seconds. Lower seconds
                // bound corresponds to the FASTER (upper) speed factor.
                val lowerSec = b.second?.let { thr / it } // fastest end (may be open)
                val upperSec = thr / b.first              // slowest end
                ZoneRange(lowerSec, upperSec)
            }
        }
    }

    /** Representative value for plotting the segment height. */
    fun midpoint(zone: Int, mode: ZoneMode, sport: TrainingDomain, thresholds: AthleteThresholds): Double? {
        val r = range(zone, mode, sport, thresholds) ?: return null
        return when {
            r.lower != null && r.upper != null -> (r.lower + r.upper) / 2
            r.lower != null -> r.lower // open-topped: anchor at the floor
            r.upper != null -> r.upper
            else -> null
        }
    }

    /** Human-readable range string with units. */
    fun format(
        range: ZoneRange,
        mode: ZoneMode,
        sport: TrainingDomain = TrainingDomain.Running,
        paceUnit: PaceUnit = PaceUnit.Km,
    ): String = when (mode) {
        ZoneMode.Hr -> "${intStr(range.lower)}–${intStr(range.upper)} bpm"
        ZoneMode.Power -> "${intStr(range.lower)}–${intStr(range.upper)} W"
        ZoneMode.Pace -> {
            val suffix = if (sport == TrainingDomain.Swimming) "/100m"
            else if (paceUnit == PaceUnit.Mile) "/mi" else "/km"
            // Faster (lower seconds) shown first.
            "${paceStr(range.lower)}–${paceStr(range.upper)}$suffix"
        }
    }

    // MARK: - Helpers

    /** LTHR: prefer measured threshold HR, else estimate from max HR (≈0.92·max). */
    private fun lthr(t: AthleteThresholds): Double? {
        t.thresholdHr?.let { return it.toDouble() }
        t.maxHr?.let { return it * 0.92 }
        return null
    }

    private fun thresholdPaceSeconds(sport: TrainingDomain, thresholds: AthleteThresholds): Double? =
        (if (sport == TrainingDomain.Swimming) thresholds.swimThresholdPaceSecPer100m
        else thresholds.runThresholdPaceSecPerKm)?.toDouble()

    private fun intStr(v: Double?): String = v?.roundToInt()?.toString() ?: "–"

    private fun paceStr(seconds: Double?): String {
        val s = seconds?.roundToInt() ?: return "–"
        return "${s / 60}:" + "%02d".format(s % 60)
    }
}
