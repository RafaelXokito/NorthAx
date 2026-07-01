import Foundation

/// Downsampled time-series for a completed activity (§10). Arrays are
/// index-aligned with `time` (seconds from start); any absent metric is empty.
struct ActivityStreams {
    var activityId: String
    var time: [Double]
    var heartRate: [Double]
    var power: [Double]
    var velocity: [Double]   // m/s
    var altitude: [Double]
    var cadence: [Double]
    var source: String

    var hasData: Bool {
        !heartRate.isEmpty || !power.isEmpty || !velocity.isEmpty
            || !altitude.isEmpty || !cadence.isEmpty
    }

    /// Speed in km/h (from m/s) — intuitive for a review chart (higher = faster).
    var speedKmh: [Double] { velocity.map { $0 * 3.6 } }

    var durationSeconds: Double { time.last ?? 0 }
}
