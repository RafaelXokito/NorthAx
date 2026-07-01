import Foundation

/// A data source that can report wellness metrics. `intervals` already
/// aggregates Garmin/Strava/Apple Health upstream; `healthkit` is read on-device;
/// `manual` is reserved for user-entered values (a backend zone, not yet merged
/// client-side — see docs/multi-source-metrics.md).
enum MetricSource: String, Codable, CaseIterable, Identifiable {
    case intervals, healthkit, manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .intervals: return "intervals.icu"
        case .healthkit: return "Apple Health"
        case .manual:    return "Manual entry"
        }
    }
}

/// Metrics that more than one source can report, so they need conflict
/// resolution. Training load (CTL/ATL) is intervals-only and intentionally absent.
enum MergeableMetric: String, Codable, CaseIterable, Identifiable {
    case hrv, restingHR, sleep, bodyWeight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hrv:        return "Heart Rate Variability"
        case .restingHR:  return "Resting Heart Rate"
        case .sleep:      return "Sleep"
        case .bodyWeight: return "Body Weight"
        }
    }

    /// Sources that can actually produce this metric. The UI only ranks these,
    /// and the resolver never considers a source outside this list.
    var candidateSources: [MetricSource] {
        switch self {
        case .hrv, .restingHR, .sleep: return [.intervals, .healthkit, .manual]
        case .bodyWeight:              return [.healthkit, .manual]  // intervals doesn't carry weight
        }
    }
}

/// Per-metric ordered source preference (highest first). The first source that
/// has a value for a given day wins.
struct MetricSourcePriority: Codable, Equatable {
    /// `MergeableMetric.rawValue` → ordered list of sources.
    var order: [String: [MetricSource]]

    /// Defaults to each metric's candidate order, i.e. intervals.icu wins —
    /// identical to the app's pre-existing behavior.
    static var `default`: MetricSourcePriority {
        var o: [String: [MetricSource]] = [:]
        for m in MergeableMetric.allCases { o[m.rawValue] = m.candidateSources }
        return MetricSourcePriority(order: o)
    }

    func sources(for metric: MergeableMetric) -> [MetricSource] {
        order[metric.rawValue] ?? metric.candidateSources
    }

    /// Promote `source` to the top of `metric`'s ranking, keeping the rest in order.
    mutating func setPrimary(_ source: MetricSource, for metric: MergeableMetric) {
        var list = sources(for: metric)
        list.removeAll { $0 == source }
        list.insert(source, at: 0)
        order[metric.rawValue] = list
    }

    /// `metric.rawValue -> [source.rawValue]`, for syncing to the backend.
    var wire: [String: [String]] { order.mapValues { $0.map(\.rawValue) } }
}

// MARK: - Wire form (backend `user_preferences.metric_priority`)
// In an extension so the memberwise `init(order:)` is preserved.
extension MetricSourcePriority {
    /// Rebuild from the wire form, filling any missing metric with its defaults
    /// so newly-added metrics are always present.
    init(wire: [String: [String]]) {
        var o: [String: [MetricSource]] = [:]
        for (metric, sources) in wire { o[metric] = sources.compactMap(MetricSource.init) }
        for m in MergeableMetric.allCases where o[m.rawValue] == nil { o[m.rawValue] = m.candidateSources }
        self.init(order: o)
    }
}
