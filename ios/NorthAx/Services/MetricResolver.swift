import Foundation

/// Same-day raw readings from HealthKit. Each `nil` means "not available", so the
/// resolver can tell a real reading apart from a missing one.
struct HealthKitReadings {
    var hrv: Double?
    var restingHR: Int?
    var sleepHours: Double?
    var weight: Double?

    var isEmpty: Bool { hrv == nil && restingHR == nil && sleepHours == nil && weight == nil }
}

/// Merges intervals-derived backend metrics with on-device HealthKit readings,
/// per the user's per-metric source priority (see docs/multi-source-metrics.md).
enum MetricResolver {

    /// Returns the resolved metrics (with `provenance` filled in) or `nil` when no
    /// source has any data. `base` is the backend object when present (it alone
    /// carries training load, baselines, and trends); otherwise a HealthKit-built
    /// fallback. HealthKit can only override *today's raw reading* of a mergeable
    /// metric — derived fields always come from `base`.
    static func resolve(
        backend: TrainingMetrics?,
        healthKit: HealthKitReadings?,
        priority: MetricSourcePriority,
        fallback: TrainingMetrics?
    ) -> TrainingMetrics? {
        guard var base = backend ?? fallback else { return nil }
        let hk = healthKit
        var provenance: [String: MetricSource] = [:]

        /// The server value's real source (intervals or manual) for a metric, or
        /// nil when the backend didn't supply that metric. From backend provenance
        /// so a server value that was itself manually entered competes as `manual`.
        func serverSource(_ m: MergeableMetric) -> MetricSource? {
            guard let b = backend else { return nil }
            switch m {
            case .hrv, .restingHR, .sleep: break         // always present on a backend row
            case .bodyWeight: if b.bodyWeight == nil { return nil }
            }
            return b.provenance[m.rawValue] ?? .intervals
        }

        /// Winner between the server value and HealthKit, ranked by the user's
        /// priority for this metric.
        func pick(_ m: MergeableMetric, hkHasValue: Bool) -> MetricSource? {
            let order = priority.sources(for: m)
            func rank(_ s: MetricSource) -> Int { order.firstIndex(of: s) ?? Int.max }
            var best: MetricSource? = hkHasValue ? .healthkit : nil
            if let srv = serverSource(m), best == nil || rank(srv) < rank(best!) { best = srv }
            return best
        }

        if let s = pick(.hrv, hkHasValue: hk?.hrv != nil) {
            if s == .healthkit, let v = hk?.hrv { base.hrv = v }
            provenance[MergeableMetric.hrv.rawValue] = s
        }

        if let s = pick(.restingHR, hkHasValue: hk?.restingHR != nil) {
            if s == .healthkit, let v = hk?.restingHR { base.restingHR = v }
            provenance[MergeableMetric.restingHR.rawValue] = s
        }

        if let s = pick(.sleep, hkHasValue: hk?.sleepHours != nil) {
            if s == .healthkit, let v = hk?.sleepHours {
                base.sleepDuration = v
                base.sleepScore = min(100, Int(v / 8.0 * 100))
            }
            provenance[MergeableMetric.sleep.rawValue] = s
        }

        if let s = pick(.bodyWeight, hkHasValue: hk?.weight != nil) {
            if s == .healthkit, let v = hk?.weight { base.bodyWeight = v }
            provenance[MergeableMetric.bodyWeight.rawValue] = s
        }

        base.provenance = provenance
        return base
    }
}
