import Foundation

// Converts coach-emitted zone tokens (Z1..Z5) into concrete numeric ranges
// using the athlete's thresholds. Pure / no SwiftUI. The graph uses this to
// draw a real numeric Y-axis; when the needed threshold is missing every
// function returns nil and the graph falls back to zone-only rendering.

enum ZoneMode { case hr, power, pace }

/// Numeric bounds for a zone. Units depend on mode: bpm (hr), watts (power),
/// seconds-per-unit (pace, where LOWER = faster). A nil bound is open-ended.
struct ZoneRange {
    let lower: Double?
    let upper: Double?
}

enum ZoneMath {

    // % of FTP. Z5 is open-topped; cap display at 120%.
    private static let powerBounds: [Int: (Double, Double?)] = [
        1: (0.40, 0.55), 2: (0.56, 0.75), 3: (0.76, 0.90),
        4: (0.91, 1.05), 5: (1.06, 1.20),
    ]
    // % of LTHR. Z5 open-topped; cap ~110%.
    private static let hrBounds: [Int: (Double, Double?)] = [
        1: (0.65, 0.81), 2: (0.81, 0.89), 3: (0.90, 0.93),
        4: (0.94, 0.99), 5: (1.00, 1.10),
    ]
    // % of threshold SPEED (pace is inverse). Z5 open-topped; cap ~108%.
    private static let paceSpeedBounds: [Int: (Double, Double?)] = [
        1: (0.78, 0.84), 2: (0.84, 0.91), 3: (0.91, 0.96),
        4: (0.96, 1.02), 5: (1.02, 1.08),
    ]

    /// Numeric range for a zone, or nil if the relevant threshold is absent.
    static func range(zone: Int, mode: ZoneMode, sport: TrainingDomain,
                      thresholds: AthleteThresholds) -> ZoneRange? {
        guard (1...5).contains(zone) else { return nil }
        switch mode {
        case .power:
            guard let ftp = thresholds.ftpWatts, let b = powerBounds[zone] else { return nil }
            return ZoneRange(lower: Double(ftp) * b.0, upper: b.1.map { Double(ftp) * $0 })
        case .hr:
            guard let lthr = lthr(thresholds), let b = hrBounds[zone] else { return nil }
            return ZoneRange(lower: lthr * b.0, upper: b.1.map { lthr * $0 })
        case .pace:
            guard let thr = thresholdPaceSeconds(sport: sport, thresholds: thresholds),
                  let b = paceSpeedBounds[zone] else { return nil }
            // Higher speed factor => faster => fewer seconds. Lower seconds bound
            // corresponds to the FASTER (upper) speed factor.
            let lowerSec = b.1.map { Double(thr) / $0 }       // fastest end (may be open)
            let upperSec = Double(thr) / b.0                   // slowest end
            return ZoneRange(lower: lowerSec, upper: upperSec)
        }
    }

    /// Representative value for plotting the segment height.
    static func midpoint(zone: Int, mode: ZoneMode, sport: TrainingDomain,
                         thresholds: AthleteThresholds) -> Double? {
        guard let r = range(zone: zone, mode: mode, sport: sport, thresholds: thresholds)
        else { return nil }
        switch (r.lower, r.upper) {
        case let (l?, u?): return (l + u) / 2
        case let (l?, nil): return l       // open-topped: anchor at the floor
        case let (nil, u?): return u
        default: return nil
        }
    }

    /// Human-readable range string with units.
    static func format(_ range: ZoneRange, mode: ZoneMode,
                       sport: TrainingDomain = .running,
                       paceUnit: PaceUnit = .km) -> String {
        switch mode {
        case .hr:
            return "\(intStr(range.lower))–\(intStr(range.upper)) bpm"
        case .power:
            return "\(intStr(range.lower))–\(intStr(range.upper)) W"
        case .pace:
            let suffix = sport == .swimming ? "/100m" : (paceUnit == .mile ? "/mi" : "/km")
            // Faster (lower seconds) shown first.
            return "\(paceStr(range.lower))–\(paceStr(range.upper))\(suffix)"
        }
    }

    // MARK: - Helpers

    /// LTHR: prefer measured threshold HR, else estimate from max HR (≈0.92·max).
    private static func lthr(_ t: AthleteThresholds) -> Double? {
        if let hr = t.thresholdHr { return Double(hr) }
        if let mx = t.maxHr { return Double(mx) * 0.92 }
        return nil
    }

    private static func thresholdPaceSeconds(sport: TrainingDomain,
                                             thresholds: AthleteThresholds) -> Int? {
        sport == .swimming ? thresholds.swimThresholdPaceSecPer100m
                           : thresholds.runThresholdPaceSecPerKm
    }

    private static func intStr(_ v: Double?) -> String {
        guard let v else { return "–" }
        return String(Int(v.rounded()))
    }

    private static func paceStr(_ seconds: Double?) -> String {
        guard let seconds else { return "–" }
        let s = Int(seconds.rounded())
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
