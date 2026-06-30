import Foundation

// Weekday encoding: Int 0..6, 0=Monday … 6=Sunday (wire contract).
struct DomainSchedule: Codable, Identifiable, Equatable {
    var domain: TrainingDomain
    var weekdays: Set<Int>   // 0..6
    var id: String { domain.id }
    var daysPerWeek: Int { weekdays.count }
}

struct TrainingFrequency: Codable, Equatable {
    var schedules: [DomainSchedule]

    /// Distinct weekdays that have at least one session (UNION across sports).
    var totalTrainingDays: Int { Set(schedules.flatMap(\.weekdays)).count }
    /// Total sessions across the week (a weekday may host more than one sport).
    var totalSessions: Int { schedules.reduce(0) { $0 + $1.weekdays.count } }
    var restDaysPerWeek: Int { max(0, 7 - totalTrainingDays) }
    var isOverloaded: Bool { totalTrainingDays > 6 }

    func weekdays(for domain: TrainingDomain) -> Set<Int> {
        schedules.first(where: { $0.domain == domain })?.weekdays ?? []
    }

    func days(for domain: TrainingDomain) -> Int {
        weekdays(for: domain).count
    }

    mutating func setDays(_ weekdays: Set<Int>, for domain: TrainingDomain) {
        let clamped = weekdays.filter { (0...6).contains($0) }
        if let idx = schedules.firstIndex(where: { $0.domain == domain }) {
            if clamped.isEmpty {
                schedules.remove(at: idx)
            } else {
                schedules[idx].weekdays = clamped
            }
        } else if !clamped.isEmpty {
            schedules.append(DomainSchedule(domain: domain, weekdays: clamped))
        }
    }

    mutating func toggle(_ weekday: Int, for domain: TrainingDomain) {
        guard (0...6).contains(weekday) else { return }
        var days = weekdays(for: domain)
        if days.contains(weekday) { days.remove(weekday) } else { days.insert(weekday) }
        setDays(days, for: domain)
    }

    // MARK: - Defaults

    static var defaultFrequency: TrainingFrequency {
        TrainingFrequency(schedules: [
            DomainSchedule(domain: .cycling,  weekdays: [0, 2, 4]),
            DomainSchedule(domain: .strength, weekdays: [1, 5])
        ])
    }

    static var empty: TrainingFrequency {
        TrainingFrequency(schedules: [])
    }
}
