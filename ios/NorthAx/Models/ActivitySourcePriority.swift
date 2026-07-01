import Foundation

/// A source that can report a completed activity (§13). Raw values match the
/// backend `activities.source` column (`garmin` = imported via intervals.icu).
enum ActivitySource: String, Codable, CaseIterable, Identifiable {
    case intervals = "garmin"
    case strava
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .intervals: return "intervals.icu"
        case .strava:    return "Strava"
        case .manual:    return "Manual"
        }
    }
}

/// Ordered activity-source preference — highest priority first. When the same
/// workout is reported by more than one source, the higher-ranked one wins.
struct ActivitySourcePriority: Equatable {
    var order: [ActivitySource]

    static let `default` = ActivitySourcePriority(order: ActivitySource.allCases)

    var primary: ActivitySource { order.first ?? .intervals }

    mutating func setPrimary(_ source: ActivitySource) {
        var next = order.filter { $0 != source }
        next.insert(source, at: 0)
        order = next
    }

    var wire: [String] { order.map(\.rawValue) }

    init(order: [ActivitySource]) { self.order = order }

    /// Build from the backend list, appending any missing sources so the order is
    /// always complete (and never empty).
    init(wire: [String]) {
        var resolved = wire.compactMap { ActivitySource(rawValue: $0) }
        for source in ActivitySource.allCases where !resolved.contains(source) {
            resolved.append(source)
        }
        order = resolved.isEmpty ? ActivitySource.allCases : resolved
    }
}
