import Foundation

/// Shared JSON coders configured for the backend contract (§6): camelCase keys
/// (matched 1:1 by the DTO property names) and a date strategy that accepts
/// BOTH `YYYY-MM-DD` calendar dates and full ISO-8601 datetimes, since the API
/// mixes them (e.g. `date`/`weekStart` vs `startTime`/`createdAt`).
enum JSONCoders {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = isoDateTime.date(from: raw) ?? isoDateTimeNoFraction.date(from: raw) {
                return date
            }
            if let day = calendarDate.date(from: raw) {
                return day
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognized date: \(raw)")
            )
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(isoDateTime.string(from: date))
        }
        return e
    }()

    // MARK: - Formatters

    static let calendarDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let isoDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoDateTimeNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
