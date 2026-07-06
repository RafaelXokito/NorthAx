import Foundation

/// One Strava segment result within an activity (§13).
struct SegmentEffort: Identifiable {
    var id: String            // backend effort row UUID
    var segmentId: String
    var name: String
    var distanceMeters: Double?
    var avgGrade: Double?
    var climbCategory: Int?
    var elapsedSeconds: Int
    var movingSeconds: Int?
    var startDate: Date
    var prRank: Int?          // 1–3 personal-record rank
    var komRank: Int?         // 1–10 leaderboard placement
    var points: [[Double]]?   // segment geometry [[lat, lng], …]
    var bestElapsedSeconds: Int?   // the athlete's all-time best on this segment
    var rank: Int?                 // 1-based all-time rank of this effort on the segment

    /// "7:05" or "1:02:45".
    var formattedTime: String {
        let h = elapsedSeconds / 3600, m = (elapsedSeconds % 3600) / 60, s = elapsedSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// The all-time best as "6:45", when known and not this effort.
    var formattedBest: String? {
        guard let best = bestElapsedSeconds, best != elapsedSeconds else { return nil }
        let h = best / 3600, m = (best % 3600) / 60, s = best % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "3.2 KM · 5.4%".
    var metaLine: String {
        var parts: [String] = []
        if let d = distanceMeters { parts.append(String(format: "%.1f KM", d / 1000)) }
        if let g = avgGrade { parts.append(String(format: "%.1f%%", g)) }
        return parts.joined(separator: " · ")
    }
}

/// A segment's metadata plus the athlete's efforts on it, newest first.
struct SegmentHistory {
    var segmentId: String
    var name: String
    var distanceMeters: Double?
    var avgGrade: Double?
    var climbCategory: Int?
    var points: [[Double]]?
    var efforts: [SegmentEffort]

    var bestElapsedSeconds: Int? { efforts.map(\.elapsedSeconds).min() }
}
